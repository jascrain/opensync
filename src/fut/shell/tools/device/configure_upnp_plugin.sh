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

# Default of_port must be unique between fsm tests for valid testing
of_port_default=10005
usage() {
    cat << usage_string
tools/device/configure_upnp_plugin.sh [-h] arguments
Description:
    - Script configures interfaces FSM settings for UPNP plugin testing
Arguments:
    -h  show this help message
    \$1 (lan_bridge_if)    : Interface name used for LAN bridge        : (string)(required)
    \$2 (fsm_plugin)       : Path to FSM plugin under test             : (string)(required)
    \$3 (of_port)          : FSM out/of port                           : (int)(optional)     : (default:${of_port_default})
Script usage example:
    ./tools/device/configure_upnp_plugin.sh br-home /usr/opensync/lib/libfsm_upnp.so
    ./tools/device/configure_upnp_plugin.sh br-home /usr/opensync/lib/libfsm_upnp.so 5002
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
print_tables Wifi_Inet_Config Wifi_Inet_State
print_tables Wifi_VIF_Config Wifi_VIF_State
print_tables Wifi_Radio_Config Wifi_Radio_State
print_tables Openflow_Config Openflow_State
print_tables Flow_Service_Manager_Config
print_tables FSM_Policy
print_tables Wifi_Master_State
print_tables Object_Store_State
ovs-vsctl show
check_restore_ovsdb_server
fut_info_dump_line
' EXIT SIGINT SIGTERM

# INPUT ARGUMENTS:
NARGS=2
[ $# -lt ${NARGS} ] && raise "Requires at least '${NARGS}' input argument(s)" -arg
# Input arguments specific to GW, required:
lan_bridge_if=${1}
fsm_plugin=${2}
of_port=${3:-${of_port_default}}

client_mac=$(get_ovsdb_entry_value Wifi_Associated_Clients mac)
if [ -z "${client_mac}" ]; then
    raise "FAIL: Could not acquire Client MAC address from Wifi_Associated_Clients, is client connected?" -l "tools/device/configure_upnp_plugin.sh"
fi
# Use first MAC from Wifi_Associated_Clients
client_mac="${client_mac%%,*}"
tap_upnp_if="${lan_bridge_if}.tupnp"

log_title "tools/device/configure_upnp_plugin.sh: FSM test - Configure UPnP plugin"

log "tools/device/configure_upnp_plugin.sh: Configuring TAP interfaces required for FSM testing"
add_bridge_port "${lan_bridge_if}" "${tap_upnp_if}"
set_ovs_vsctl_interface_option "${tap_upnp_if}" "type" "internal"
set_ovs_vsctl_interface_option "${tap_upnp_if}" "ofport_request" "${of_port}"
create_inet_entry \
    -if_name "${tap_upnp_if}" \
    -if_type "tap" \
    -ip_assign_scheme "none" \
    -dhcp_sniff "false" \
    -network true \
    -enabled true &&
        log "tools/device/configure_upnp_plugin.sh: Interface ${tap_upnp_if} created - Success" ||
        raise "FAIL: Failed to create interface ${tap_upnp_if}" -l "tools/device/configure_upnp_plugin.sh" -ds

log "tools/device/configure_upnp_plugin.sh: Cleaning FSM OVSDB Config tables"
empty_ovsdb_table Openflow_Config
empty_ovsdb_table Flow_Service_Manager_Config
empty_ovsdb_table FSM_Policy

# Insert rule to Openflow_Config
insert_ovsdb_entry Openflow_Config \
    -i token "dev_flow_upnp_out" \
    -i table 0 \
    -i rule "dl_src=${client_mac},udp,udp_dst=1900" \
    -i priority 200 \
    -i bridge "${lan_bridge_if}" \
    -i action "normal,output:${of_port}" &&
        log "tools/device/configure_upnp_plugin.sh: insert_ovsdb_entry - Ingress rule inserted to Openflow_Config - Success" ||
        raise "FAIL: insert_ovsdb_entry - Failed to insert ingress rule to Openflow_Config" -l "tools/device/configure_upnp_plugin.sh" -oe

mqtt_value="dev-test/dev_upnp/$(get_node_id)/$(get_location_id)"
insert_ovsdb_entry Flow_Service_Manager_Config \
    -i if_name "${tap_upnp_if}" \
    -i handler "dev_upnp" \
    -i pkt_capt_filter 'udp' \
    -i plugin "${fsm_plugin}" \
    -i other_config '["map",[["mqtt_v","'"${mqtt_value}"'"],["dso_init","upnp_plugin_init"]]]' &&
        log "tools/device/configure_upnp_plugin.sh: insert_ovsdb_entry - MQTT config inserted to Flow_Service_Manager_Config - Success" ||
        raise "FAIL: insert_ovsdb_entry - Failed to insert MQTT config to Flow_Service_Manager_Config" -l "tools/device/configure_upnp_plugin.sh" -oe
