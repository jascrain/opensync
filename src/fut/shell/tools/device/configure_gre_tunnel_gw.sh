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
source "${FUT_TOPDIR}/shell/lib/nm2_lib.sh"
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

usage()
{
cat << usage_string
tools/device/configure_gre_tunnel_gw.sh [-h] arguments
Description:
    - Script configures GRE (pgd) interface for associated LEAF device.
Pre-requirements:
    - Configured bhaul-ap on DUT device
    - Configured bhaul-sta on LEAF device
    - LEAF device associated to DUT
Arguments:
    -h : show this help message
    \$1 (bhaul_ap_if_name) : used for bhaul ap interface name : (string)(required)
    \$2 (leaf_radio_mac)   : used for LEAF radio mac          : (string)(required)
    \$3 (gre_mtu)          : used for GRE MTU                 : (string)(required)
    \$4 (lan_bridge)       : used for LAN bridge name         : (string)(required)
Testcase procedure (FUT scripts call only)(example):
    # Initial DUT and REF setup
    # On DUT: ./fut-base/shell//tests/dm/othr_setup.sh wifi0 wifi1 wifi2
    # On REF: ./fut-base/shell//tests/dm/othr_setup.sh wifi0 wifi1 wifi2
    # On REF: ./fut-base/shell//tools/device/ovsdb/get_radio_mac_from_ovsdb.sh  if_name==wifi0
    # On REF: ./fut-base/shell//tools/device/ovsdb/remove_ovsdb_entry.sh  Wifi_Credential_Config -w ssid fut-5515.bhaul
    # On REF: ./fut-base/shell//tools/device/ovsdb/insert_ovsdb_entry.sh  Wifi_Credential_Config -i onboard_type gre -i ssid fut-5515.bhaul \
        -i security '["map",[["encryption","WPA-PSK"],["key","FutTestPSK"],["mode","2"]]]'
    # On REF: ./fut-base/shell//tools/device/ovsdb/get_ovsdb_entry_value.sh  Wifi_Credential_Config _uuid ssid fut-5515.bhaul true
    # On DUT: ./fut-base/shell//tools/device/check_wan_connectivity.sh

    # Configure DUT bhaul-ap
    # On DUT: ./fut-base/shell//tools/device/vif_clean.sh 180
    # On DUT: ./fut-base/shell//tools/device/create_inet_interface.sh  -if_name br-home -if_type bridge -enabled true -network true -NAT false -ip_assign_scheme dhcp
    # On DUT: ./fut-base/shell//tools/device/configure_lan_bridge_for_wan_connectivity.sh  eth0 br-wan br-home 1500
    # On DUT: ./fut-base/shell//tools/device/create_radio_vif_interface.sh  -if_name wifi0 -vif_if_name bhaul-ap-24 -vif_radio_idx 1 \
        -channel 6 -ht_mode HT40 -hw_mode 11n -enabled true -mac_list '["set",["60:b4:f7:f0:0e:b6"]]'
        -mac_list_type whitelist -mode ap -security '["map",[["encryption","WPA-PSK"],["key","FutTestPSK"],["mode","2"]]]'
        -ssid fut-5515.bhaul -ssid_broadcast disabled
    # On DUT: ./fut-base/shell//tools/device/create_inet_interface.sh  -if_name bhaul-ap-24 -if_type vif -broadcast_n 255 \
        -inet_addr_n 129 -subnet 169.254.6 -netmask 255.255.255.128 -ip_assign_scheme static
        -mtu 1600 -NAT false -enabled true -network true

    # Configure REF bhaul-sta
    # On REF: ./fut-base/shell//tools/device/create_vif_interface.sh  -if_name bhaul-sta-24 \
        -credential_configs '["set",[["uuid","b2e198a8-895c-4f49-8fc9-aa3401f5b056"]]]'
        -ssid fut-5515.bhaul -enabled true

    # Verify GRE tunnel on DUT and REF
    # On DUT: ./fut-base/shell//tests/dm/othr_verify_gre_tunnel_gw.sh  bhaul-ap-24 60:b4:f7:f0:0e:b6 1562 br-home
    # On REF: ./fut-base/shell//tests/dm/othr_verify_gre_tunnel_leaf.sh  bhaul-sta-24 br-home
Script usage example:
    ./othr/configure_gre_tunnel_gw.sh bhaul-ap-50 60:b4:f7:f2:f3:15 1562 br-home
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
print_tables DHCP_leased_IP
ovs-vsctl show
check_restore_ovsdb_server
fut_info_dump_line
' EXIT SIGINT SIGTERM

NARGS=4
[ $# -ne ${NARGS} ] && usage && raise "Requires exactly '${NARGS}' input argument(s)" -l "othr/configure_gre_tunnel_gw.sh" -arg
bhaul_ap_if_name=${1}
leaf_radio_mac=${2}
gre_mtu=${3}
lan_bridge=${4}

bhaul_ip_assign_scheme="none"
associate_retry_count="6"
associate_retry_sleep="10"

log "tools/device/configure_gre_tunnel_gw.sh: Waiting for LEAF backhaul STA to associate to GW backhaul AP"
fnc_str="get_ovsdb_entry_value DHCP_leased_IP inet_addr -w hwaddr ${leaf_radio_mac} -r"
check_ec_code=0
wait_for_function_output "notempty" "${fnc_str}" "${associate_retry_count}" "${associate_retry_sleep}" || check_ec_code=$?
print_tables DHCP_leased_IP || true

if [ $check_ec_code -eq 0 ]; then
    leaf_sta_inet_addr=$($fnc_str) &&
        log "tools/device/configure_gre_tunnel_gw.sh: LEAF ${leaf_sta_inet_addr} associated - Success" ||
        raise "FAIL #1: LEAF ${leaf_sta_inet_addr} not associated"  -l "tools/device/configure_gre_tunnel_gw.sh" -ds
else
    raise "FAIL #2: LEAF ${leaf_sta_inet_addr} not associated" -l "tools/device/configure_gre_tunnel_gw.sh" -ds
fi
gre_name="pgd$(echo "${leaf_sta_inet_addr//./-}" | cut -d'-' -f3-4)"
ap_inet_addr=$(get_ovsdb_entry_value Wifi_Inet_Config inet_addr -w if_name "${bhaul_ap_if_name}" -r)

# TESTCASE:
log "tools/device/configure_gre_tunnel_gw.sh: Create GW GRE parent interface"
create_inet_entry \
    -if_name "${gre_name}" \
    -if_type "gre" \
    -gre_ifname "${bhaul_ap_if_name}" \
    -gre_local_inet_addr "${ap_inet_addr// /}" \
    -gre_remote_inet_addr "${leaf_sta_inet_addr}" \
    -ip_assign_scheme "${bhaul_ip_assign_scheme}" \
    -mtu "${gre_mtu}" \
    -network true \
    -enabled true &&
        log "tools/device/configure_gre_tunnel_gw.sh: Interface ${gre_name} created - Success" ||
        raise "FAIL: Failed to create interface ${gre_name}" -l "tools/device/configure_gre_tunnel_gw.sh" -ds

wait_for_function_exit_code 0 "check_vif_interface_state_is_up ${gre_name}" "${associate_retry_count}" "${associate_retry_sleep}" &&
    log -deb "tools/device/configure_gre_tunnel_gw.sh: Interface ${gre_name} is up on system" ||
    raise "FAIL: Interface ${gre_name} is not up on system" -l "tools/device/configure_gre_tunnel_gw.sh" -ds

log "tools/device/configure_gre_tunnel_gw.sh: Put GW GRE interface into LAN bridge"
add_bridge_port "${lan_bridge}" "${gre_name}"

pass
