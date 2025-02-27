#!/usr/bin/env bash

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


current_dir=$(dirname "$(realpath "$BASH_SOURCE")")
fut_topdir="$(realpath "$current_dir"/../../..)"

# FUT environment loading
source "${fut_topdir}"/config/default_shell.sh
# Ignore errors for fut_set_env.sh sourcing
[ -e "/tmp/fut-base/fut_set_env.sh" ] && source /tmp/fut-base/fut_set_env.sh &> /dev/null
source "$fut_topdir/lib/rpi_lib.sh"

usage()
{
cat << EOF
tools/server/cm/manipulate_cloud_ip_addresses.sh [-h] ip_address type
Options:
    -h  show this help message
Arguments:
    hostname=$1         --   hostname of the redirector                 -   (string)(required)
    controller_ip=$2    --   IP address of the cloud controller         -   (string)(required)
    type=$3             --   type of action to perform: block/unblock   -   (string)(required)
Usage:
   tools/server/cm/manipulate_cloud_ip_addresses.sh "www.redirector.com" "12.34.45.56" "block"
   tools/server/cm/manipulate_cloud_ip_addresses.sh "www.redirector.com" "12.34.45.56" "unblock"
EOF
exit 1
}

if [ -n "${1}" ]; then
    case "${1}" in
        help | \
        --help | \
        -h)
            usage
            ;;
    esac
fi

NARGS=3
[ $# -ne ${NARGS} ] && raise "Requires exactly '${NARGS}' input argument(s)" -l "tools/server/cm/manipulate_cloud_ip_addresses.sh" -arg

hostname=${1}
controller_ip=${2}
type=${3}

log "tools/server/cm/manipulate_cloud_ip_addresses.sh: Manipulate/${type} the cloud controller and redirector IPs"

ip_list=$(getent ahosts $hostname | grep -w "STREAM" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
for ip in $ip_list
do
    manipulate_cloud_controller_traffic $ip $type &&
        log "cm/manipulate_cloud_ip_addresses.sh: IP address '$ip' ${type}-ed - Success" ||
        raise "FAIL: failed to $type IP $ip" -l "cm/manipulate_cloud_ip_addresses.sh" -tc
done

manipulate_cloud_controller_traffic $controller_ip $type &&
    log "cm/manipulate_cloud_ip_addresses.sh: IP address '$controller_ip' ${type}-ed - Success" ||
    raise "FAIL: failed to $type IP $controller_ip" -l "cm/manipulate_cloud_ip_addresses.sh" -tc
