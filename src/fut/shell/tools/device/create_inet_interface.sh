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
tools/device/create_inet_interface.sh [-h] arguments
Description:
    - Create/updates Inet interface and validate it in State table
Arguments:
    -h  show this help message
    -if_name              : Wifi_Inet_Config::if_name                                            : (string)(required)
    -enabled              : Wifi_Inet_Config::enabled                                            : (string)(optional)
    -network              : Wifi_Inet_Config::network                                            : (string)(optional)
    -if_type              : Wifi_Inet_Config::if_type                                            : (string)(optional)
    -inet_addr            : Wifi_Inet_Config::inet_addr                                          : (string)(optional)
    -netmask              : Wifi_Inet_Config::netmask                                            : (string)(optional)
    -dns                  : Wifi_Inet_Config::dns                                                : (string)(optional)
    -gateway              : Wifi_Inet_Config::gateway                                            : (string)(optional)
    -broadcast            : Wifi_Inet_Config::broadcast                                          : (string)(optional)
    -ip_assign_scheme     : Wifi_Inet_Config::ip_assign_scheme                                   : (string)(optional)
    -mtu                  : Wifi_Inet_Config::mtu                                                : (string)(optional)
    -NAT                  : Wifi_Inet_Config::NAT                                                : (string)(optional)
    -upnp_mode            : Wifi_Inet_Config::upnp_mode                                          : (string)(optional)
    -dhcpd                : Wifi_Inet_Config::dhcpd                                              : (string)(optional)
    -gre_ifname           : Wifi_Inet_Config::gre_ifname                                         : (string)(optional)
    -gre_remote_inet_addr : Wifi_Inet_Config::gre_remote_inet_addr                               : (string)(optional)
    -gre_local_inet_addr  : Wifi_Inet_Config::gre_local_inet_addr                                : (string)(optional)
    -broadcast_n          : Used to generate Wifi_Inet_Config::broadcast,dhcpd,inet_addr,netmask : (string)(optional)
    -inet_addr_n          : Used to generate Wifi_Inet_Config::broadcast,dhcpd,inet_addr,netmask : (string)(optional)
    -subnet               : Used to generate Wifi_Inet_Config::broadcast,dhcpd,inet_addr,netmask : (string)(optional)
Script usage example:
   ./tools/device/create_inet_interface.sh -if_name eth0 -NAT false -mtu 1600
   ./tools/device/create_inet_interface.sh -if_name eth1 -netmask 255.50.255.255.1
   ./tools/device/create_inet_interface.sh -if_name wifi0 -enabled false -network false
usage_string
}

trap '
fut_ec=$?
fut_info_dump_line
if [ $fut_ec -ne 0 ]; then 
    print_tables Wifi_Inet_Config Wifi_Inet_State Wifi_Master_State
    check_restore_ovsdb_server
fi
fut_info_dump_line
exit $fut_ec
' EXIT SIGINT SIGTERM

NARGS=1
[ $# -lt ${NARGS} ] && usage && raise "Requires at least '${NARGS}' input argument(s)" -l "tools/device/create_inet_interface.sh" -arg

log "tools/device/$(basename "$0"): Creating Inet entry"
create_inet_entry "$@" &&
    log "tools/device/$(basename "$0"): create_inet_entry - Success" ||
    raise "create_inet_entry - Failed" -l "tools/device/$(basename "$0")" -tc

exit 0
