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
source "${FUT_TOPDIR}/shell/lib/othr_lib.sh"
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

manager_setup_file="dm/othr_setup.sh"

usage()
{
cat << usage_string
othr/othr_verify_eth_wan_iface_wifi_master_state.sh [-h] arguments
Description:
    - Verify Wifi_Master_State table exists and has eth wan interface populated.
Arguments:
    -h  show this help message
    \$1 (eth_wan_interface)     : eth_wan_interface to be checked : (string)(required)
Testcase procedure:
    - On DEVICE: Run: ./${manager_setup_file} (see ${manager_setup_file} -h)
                 Run: ./othr/othr_verify_eth_wan_iface_wifi_master_state.sh <ETH_WAN_INTERFACE>
Script usage example:
   ./othr/othr_verify_eth_wan_iface_wifi_master_state.sh eth0
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
print_tables Wifi_Master_State
check_restore_ovsdb_server
fut_info_dump_line
' EXIT SIGINT SIGTERM

NARGS=1
[ $# -ne ${NARGS} ] && usage && raise "Requires '${NARGS}' input argument(s)" -l "othr/othr_verify_eth_wan_iface_wifi_master_state.sh" -arg

eth_wan_interface=${1}

log_title "othr/othr_verify_eth_wan_iface_wifi_master_state.sh: ONBRD test - Verify Wifi_Master_State table exists and has eth wan interface '$eth_wan_interface' populated"

${OVSH} s Wifi_Master_State
if [ $? -eq 0 ]; then
    log "othr/othr_verify_eth_wan_iface_wifi_master_state.sh: Wifi_Master_State table exists"
else
    raise "FAIL: Wifi_Master_State table does not exist" -l "othr/othr_verify_eth_wan_iface_wifi_master_state.sh" -tc
fi

check_ovsdb_entry Wifi_Master_State -w if_name $eth_wan_interface
if [ $? -eq 0 ]; then
    log "othr/othr_verify_eth_wan_iface_wifi_master_state.sh: Wifi_Master_State populated with eth wan interface '$eth_wan_interface' - Success"
else
    raise "FAIL: Wifi_Master_State not populated with eth wan interface '$eth_wan_interface'" -l "othr/othr_verify_eth_wan_iface_wifi_master_state.sh" -tc
fi

pass
