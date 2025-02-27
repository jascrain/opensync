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
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

usage()
{
cat << usage_string
fsm/fsm_create_tap_interface.sh [-h] arguments
Description:
    - Script creates and configures tap interface as a part of fsm plugin configuration.

Arguments:
    -h  show this help message
    \$1 (lan_bridge_if) : used as bridge interface name         : (string)(required)
    \$2 (postfix)       : used as postfix on tap interface name : (string)(required)
    \$3 (of_port)       : used as Openflow port                 : (int)(required)

Script usage example:
    ./fsm/fsm_create_tap_interface.sh br-home tdns 3001
    ./fsm/fsm_create_tap_interface.sh br-home thttp 4001
    ./fsm/fsm_create_tap_interface.sh br-home tupnp 5001
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
ovs-vsctl show
check_restore_ovsdb_server
fut_info_dump_line
' EXIT SIGINT SIGTERM

# INPUT ARGUMENTS:
NARGS=3
[ $# -ne ${NARGS} ] && raise "Requires exactly '${NARGS}' input argument(s)" -arg
# Input arguments specific to GW, required:
lan_bridge_if=${1}
tap_name_postfix=${2}
of_port=${3}

# Construct from input arguments
tap_if="${lan_bridge_if}.${tap_name_postfix}"

log_title "fsm/fsm_create_tap_interface.sh: FSM test - Create tap interface - $tap_if"

# Generate tap interface
log "fsm/fsm_create_tap_interface.sh: Generate tap interface '$tap_if'"
wait_for_function_response 0 "add_tap_interface $lan_bridge_if $tap_if $of_port" &&
    log "fsm/fsm_create_tap_interface.sh: add_tap_interface - interfce '$tap_if' created on '$lan_bridge_if'- Success" ||
    raise "FAIL: add_tap_interface - interface '$tap_if' not created" -l "fsm/fsm_create_tap_interface.sh" -tc

# Bring up tap interface DNS
wait_for_function_response 0 "tap_up_cmd $tap_if" &&
    log "fsm/fsm_create_tap_interface.sh: tap_up_cmd - interface '$tap_if' brought up - Success" ||
    raise "FAIL: tap_up_cmd - interface '$tap_if' not brought up" -l "fsm/fsm_create_tap_interface.sh" -tc

# Set no flood to interface DNS
wait_for_function_response 0 "gen_no_flood_cmd $lan_bridge_if $tap_if" &&
    log "fsm/fsm_create_tap_interface.sh: gen_no_flood_cmd - set interface '$tap_if' to 'no flood' - Success" ||
    raise "FAIL: gen_no_flood_cmd - interface '$tap_if' not set to 'no flood'" -l "fsm/fsm_create_tap_interface.sh" -tc

# Check if applied to system (LEVEL2)
wait_for_function_response 0 "check_if_port_in_bridge $tap_if $lan_bridge_if" &&
    log "fsm/fsm_create_tap_interface.sh: check_if_port_in_bridge - LEVEL2 - port '$tap_if' added to '$lan_bridge_if' - Success" ||
    raise "FAIL: check_if_port_in_bridge - LEVEL2 - port '$tap_if' not added to $lan_bridge_if" -l "fsm/fsm_create_tap_interface.sh" -tc

# Show ovs switch config
ovs-vsctl show

# Delete port from bridge
wait_for_function_response 0 "remove_port_from_bridge $lan_bridge_if $tap_if" &&
    log "fsm/fsm_create_tap_interface.sh: remove_port_from_bridge - port '$tap_if' removed from '$lan_bridge_if' - Success" ||
    raise "FAIL: remove_port_from_bridge - port '$tap_if' not removed from '$lan_bridge_if'" -l "fsm/fsm_create_tap_interface.sh" -tc

pass
