#!/bin/sh

# Copyright (c) 2015, Plume Design Inc. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    1. Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#    2. Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#    3. Neither the name of the Plume Design Inc. nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL Plume Design Inc. BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# FUT environment loading
# shellcheck disable=SC1091
source /tmp/fut-base/shell/config/default_shell.sh
[ -e "/tmp/fut-base/fut_set_env.sh" ] && source /tmp/fut-base/fut_set_env.sh
source "${FUT_TOPDIR}/shell/lib/fsm_lib.sh"
source "${FUT_TOPDIR}/shell/lib/nm2_lib.sh"
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

manager_setup_file="fsm/fsm_setup.sh"
create_rad_vif_if_file="tools/device/create_radio_vif_interface.sh"
create_inet_file="tools/device/create_inet_interface.sh"
add_bridge_port_file="tools/device/add_bridge_port.sh"
configure_lan_bridge_for_wan_connectivity_file="tools/device/configure_lan_bridge_for_wan_connectivity.sh"
# Default of_port must be unique between fsm tests for valid testing
of_port_default=10003
usage() {
    cat << usage_string
fsm/fsm_configure_test_ndp_plugin.sh [-h] arguments
Description:
    - Script configures interfaces FSM settings for NDP blocking rules
    - Requires 'ping6' tool be present on the system
Arguments:
    -h  show this help message
    \$1 (lan_bridge_if)    : Interface name used for LAN bridge        : (string)(required)
    \$2 (of_port)          : FSM out/of port                           : (int)(optional)     : (default:${of_port_default})
Testcase procedure:
    - On DEVICE: Run: ./${manager_setup_file} (see ${manager_setup_file} -h)
            Create Radio/VIF interface
                Run: ./${create_rad_vif_if_file} (see ${create_rad_vif_if_file} -h)
            Create Inet entry for VIF interface
                Run: ./${create_inet_file} (see ${create_inet_file} -h)
            Create Inet entry for home bridge interface (br-home)
                Run: ./${create_inet_file} (see ${create_inet_file} -h)
            Add bridge port to VIF interface onto home bridge
                Run: ./${add_bridge_port_file} (see ${add_bridge_port_file} -h)
            Configure WAN bridge settings
                Run: ./${configure_lan_bridge_for_wan_connectivity_file} (see ${configure_lan_bridge_for_wan_connectivity_file} -h)
            Update Inet entry for home bridge interface for dhcpd (br-home)
                Run: ./${create_inet_file} (see ${create_inet_file} -h)
            Test FSM for NDP plugin test
                Run: ./fsm/fsm_configure_test_ndp_plugin.sh <LAN-BRIDGE-IF>
Script usage example:
    ./fsm/fsm_configure_test_ndp_plugin.sh br-home
    ./fsm/fsm_configure_test_ndp_plugin.sh br-home 3002
usage_string
}
if [ -n "${1}" ]; then
    case "${1}" in
    help | \
    --help | \
    -h)
        usage && exit 1
        ;;
    *)
        ;;
    esac
fi

trap '
fut_info_dump_line
print_tables Wifi_Associated_Clients
print_tables Openflow_Config Openflow_State
print_tables Flow_Service_Manager_Config FSM_Policy
print_tables IPv6_Neighbors
check_restore_ovsdb_server
fut_info_dump_line
' EXIT SIGINT SIGTERM

# INPUT ARGUMENTS:
NARGS=1
[ $# -lt ${NARGS} ] && raise "Requires at least '${NARGS}' input argument(s)" -arg
# Input arguments specific to GW, required:
lan_bridge_if=${1}
of_port=${2:-${of_port_default}}

client_mac=$(get_ovsdb_entry_value Wifi_Associated_Clients mac)
if [ -z "${client_mac}" ]; then
    raise "Couldn't acquire Client mac address from Wifi_Associated_Clients, is client connected?" -l "fsm/fsm_configure_test_ndp_plugin.sh"
fi
# Use first MAC from Wifi_Associated_Clients
client_mac="${client_mac%%,*}"
tap_ndp_if="${lan_bridge_if}.tndp"

log_title "fsm/fsm_configure_test_ndp_plugin.sh: FSM test - Configure ndp plugin"

log "fsm/fsm_configure_test_ndp_plugin.sh: Configuring TAP interfaces required for FSM testing"
add_bridge_port "${lan_bridge_if}" "${tap_ndp_if}"
set_ovs_vsctl_interface_option "${tap_ndp_if}" "type" "internal"
set_ovs_vsctl_interface_option "${tap_ndp_if}" "ofport_request" "${of_port}"
create_inet_entry \
    -if_name "${tap_ndp_if}" \
    -if_type "tap" \
    -ip_assign_scheme "none" \
    -dhcp_sniff "false" \
    -network true \
    -enabled true &&
        log "fsm/fsm_configure_test_ndp_plugin.sh: Interface ${tap_ndp_if} created - Success" ||
        raise "FAIL: Failed to create interface ${tap_ndp_if}" -l "fsm/fsm_configure_test_ndp_plugin.sh" -ds

log "fsm/fsm_configure_test_ndp_plugin.sh: Cleaning FSM OVSDB Config tables"
empty_ovsdb_table Openflow_Config
empty_ovsdb_table Flow_Service_Manager_Config
empty_ovsdb_table FSM_Policy

# Insert egress rule to Openflow_Config
insert_ovsdb_entry Openflow_Config \
    -i token "dev_flow_ndp_out" \
    -i table 0 \
    -i rule "dl_dst=${client_mac},ipv6,nw_proto=58" \
    -i priority 200 \
    -i bridge "${lan_bridge_if}" \
    -i action "normal,output:${of_port}" &&
        log "fsm/fsm_configure_test_ndp_plugin.sh: Egress rule inserted - Success" ||
        raise "FAIL: Failed to insert_ovsdb_entry" -l "fsm/fsm_configure_test_ndp_plugin.sh" -oe

# Insert ingress rule to Openflow_Config
insert_ovsdb_entry Openflow_Config \
    -i token "dev_flow_ndp_in" \
    -i table 0 \
    -i rule "dl_src=${client_mac},ipv6,nw_proto=58" \
    -i priority 200 \
    -i bridge "${lan_bridge_if}" \
    -i action "normal,output:${of_port}" &&
        log "fsm/fsm_configure_test_ndp_plugin.sh: Ingress rule inserted - Success" ||
        raise "FAIL: Failed to insert_ovsdb_entry" -l "fsm/fsm_configure_test_ndp_plugin.sh" -oe

insert_ovsdb_entry Flow_Service_Manager_Config \
    -i if_name "${tap_ndp_if}" \
    -i handler "dev_ndp" \
    -i plugin '/usr/opensync/lib/libfsm_ndp.so' \
    -i other_config '["map",[["dso_init","ndp_plugin_init"]]]' &&
        log "fsm/fsm_configure_test_ndp_plugin.sh: Flow_Service_Manager_Config entry added - Success" ||
        raise "FAIL: Failed to insert Flow_Service_Manager_Config entry" -l "fsm/fsm_configure_test_ndp_plugin.sh" -oe

log "fsm/fsm_configure_test_ndp_plugin.sh: ping6 clients"
wait_for_function_response 0 "ping6 -c2 -I ${tap_ndp_if} ff02::1" 5 &&
    log "fsm/fsm_configure_test_ndp_plugin.sh: ping6 clients - Success" ||
    log -wrn "fsm/fsm_configure_test_ndp_plugin.sh: Failed to ping6 clients"

wait_for_function_response 0 "${OVSH} s IPv6_Neighbors hwaddr | grep '${client_mac}'" 30 &&
    log "fsm/fsm_configure_test_ndp_plugin.sh: Client added into IPv6_Neighbors table - Success" ||
    raise "FAIL: Client not added into IPv6_Neighbors table" -l "fsm/fsm_configure_test_ndp_plugin.sh" -oe

print_tables IPv6_Neighbors

pass
