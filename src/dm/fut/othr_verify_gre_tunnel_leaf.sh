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

#!/bin/bhaul_mtu

# FUT environment loading
# shellcheck disable=SC1091
source /tmp/fut-base/shell/config/default_shell.sh
[ -e "/tmp/fut-base/fut_set_env.sh" ] && source /tmp/fut-base/fut_set_env.sh
source "${FUT_TOPDIR}/shell/lib/unit_lib.sh"
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

# Setup test environment for CM tests.
usage()
{
cat << usage_string
othr/othr_verify_gre_tunnel_leaf.sh [-h] arguments
Description:
    - Script verifies GRE tunnel on LEAF device
Arguments:
    -h : show this help message
    \$1 (upstream_router_ip) : Router IP address to check        : (string)(optional) : (default:192.168.200.1)
    \$2 (internet_check_ip)  : Internet IP address to check      : (string)(optional) : (default:1.1.1.1)
    \$3 (n_ping)             : Number of ping packets            : (string)(optional) : (default:5)
Script usage example:
    ./othr/othr_verify_gre_tunnel_leaf.sh bhaul-sta-l50 br-home
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


# Input arguments common to GW and LEAF, optional:
upstream_router_ip=${1:-"192.168.200.1"}
internet_check_ip=${2:-"1.1.1.1"}
n_ping=${3:-"5"}

# LEAF validation step #2
# Enforce router connectivity, check-only internet connectivity
log "othr/othr_verify_gre_tunnel_leaf.sh: Check that LEAF has WAN connectivity via GRE tunnel"
wait_for_function_response 0 "ping -c${n_ping} ${upstream_router_ip}" &&
    log "othr/othr_verify_gre_tunnel_leaf.sh: Can ping router ${upstream_router_ip} - Success" ||
    raise "FAIL: Can not ping router ${upstream_router_ip}" -tc

wait_for_function_response 0 "ping -c${n_ping} ${internet_check_ip}" &&
    log "othr/othr_verify_gre_tunnel_leaf.sh: Can ping internet ${internet_check_ip} - Success" ||
    log -wrn "othr/othr_verify_gre_tunnel_leaf.sh: Can not ping internet ${internet_check_ip}"

pass
