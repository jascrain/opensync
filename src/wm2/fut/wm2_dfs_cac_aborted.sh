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
source "${FUT_TOPDIR}/shell/lib/wm2_lib.sh"
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

manager_setup_file="wm2/wm2_setup.sh"
# Wait for channel to change, not necessarily become usable (CAC for DFS)
channel_change_timeout=60

usage()
{
cat << usage_string
wm2/wm2_dfs_cac_aborted.sh [-h] arguments
Testcase info:
    Setup:
        - If channels provided in testcase config are not both in the 'nop_finished' or
        'available' state, the script would find alternative channels and execute
        with new channels. Actual used channels would be reported inside log_title.
    Problem statement (example):
        - Start on DFS channel_a and wait for CAC to complete before channel is usable
        - Radar is detected while channel_a CAC is in progress (cac = 1-10 min)
        - Driver should switch to channel_b immediately, and not wait for CAC to finish
    Script tests the following:
      - CAC must be aborted on channel_a, if channel change is requested while CAC is in progress.
      - Correct transition to "cac_started" on channel_a
      - Correct transition to "nop_finished" on channel_a after transition to channel_b
    Simplified test steps (example):
        - Ensure <CHANNEL_A> and <CHANNEL_B> are allowed
        - Verify if <CHANNEL_A> is in nop_finished state
        - Switch <CHANNEL_A> to new channel if not in "nop_finished" state
        - Verify if <CHANNEL_B> is in nop_finished state
        - Switch <CHANNEL_B> to new channel if not in "nop_finished" state
        - Configure radio, create VIF and apply <CHANNEL_A>
        - Verify if <CHANNEL_A> is applied
        - Verify if <CHANNEL_A> has started CAC
        - Change to <CHANNEL_B> while CAC is in progress
        - Verify if <CHANNEL_B> is applied
        - Verify if <CHANNEL_A> has stopped CAC and entered NOP_FINISHED
        - Verify if <CHANNEL_B> has started CAC
Arguments:
    -h  show this help message
    \$1  (if_name)          : Wifi_Radio_Config::if_name        : (string)(required)
    \$2  (vif_if_name)      : Wifi_VIF_Config::if_name          : (string)(required)
    \$3  (vif_radio_idx)    : Wifi_VIF_Config::vif_radio_idx    : (int)(required)
    \$4  (ssid)             : Wifi_VIF_Config::ssid             : (string)(required)
    \$5  (security)         : Wifi_VIF_Config::security         : (string)(required)
    \$6  (channel_a)        : Wifi_Radio_Config::channel        : (int)(required)
    \$7  (channel_b)        : Wifi_Radio_Config::channel        : (int)(required)
    \$8  (ht_mode)          : Wifi_Radio_Config::ht_mode        : (string)(required)
    \$9  (hw_mode)          : Wifi_Radio_Config::hw_mode        : (string)(required)
    \$10 (mode)             : Wifi_VIF_Config::mode             : (string)(required)
Testcase procedure:
    - On DEVICE: Run: ./${manager_setup_file} (see ${manager_setup_file} -h)
                 Run: ./wm2/wm2_dfs_cac_aborted.sh <IF_NAME> <VIF_IF_NAME> <VIF-RADIO-IDX> <SSID> <SECURITY> <CHANNEL_A> <CHANNEL_B> <HT_MODE> <HW_MODE> <MODE>
Script usage example:
    ./wm2/wm2_dfs_cac_aborted.sh wifi2 home-ap-u50 2 FUTssid '["map",[["encryption","WPA-PSK"],["key","FUTpsk"],["mode","2"]]]' 120 104 HT20 11ac ap
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

NARGS=10
[ $# -lt ${NARGS} ] && usage && raise "Requires '${NARGS}' input argument(s)" -l "wm2/wm2_dfs_cac_aborted.sh" -arg
if_name=${1}
vif_if_name=${2}
vif_radio_idx=${3}
ssid=${4}
security=${5}
channel_a=${6}
channel_b=${7}
ht_mode=${8}
hw_mode=${9}
mode=${10}

trap '
    fut_info_dump_line
    print_tables Wifi_Radio_Config Wifi_Radio_State
    check_restore_ovsdb_server
    fut_info_dump_line
' EXIT SIGINT SIGTERM

###############################################################################
# DESCRIPTION:
#   Function echoes first of the available channels on the radio that is usable
#   (NOP_FINISHED) for the test, but will not echo the channel provided as an
#   argument, since that channel would already be determined as usable.
#   Raises exception if no usable channel is found.
# INPUT PARAMETER(S):
#   $1  Channel (int, required)
# RETURNS:
#   0   Channel found.
#   See DESCRIPTION.
# USAGE EXAMPLE(S):
#   get_usable_channel 36
###############################################################################
get_usable_channel()
{
    local NARGS=1
    [ $# -ne ${NARGS} ] &&
        raise "get_usable_channel: Requires ${NARGS} input argument(s), $# given" -arg
    other_chan_in_use=${1}

    # Wifi_Radio_State::allowed channels list must not be empty!
    get_chan_list=$(get_ovsdb_entry_value Wifi_Radio_State allowed_channels -w if_name "$if_name" -r)
    list_of_chans=$(echo "${get_chan_list}" | cut -d '[' -f3 | cut -d ']' -f1 | sed "s/,/ /g")
    [ -z "$list_of_chans" ] &&
        raise "FAIL: Wifi_Radio_State::allowed_channels not populated" -l "wm2/wm2_dfs_cac_aborted.sh" -ds

    # Get the first channel in list that has state NOP_FINISHED and
    # is not the one provided in the argument.
    for channel in ${list_of_chans}; do
        [ "$channel" -eq "$other_chan_in_use" ] && continue
        check_is_nop_finished "$channel" "$if_name" >/dev/null 2>&1
        if [ $? = 0 ]; then
            echo "$channel" && return 0
        fi
    done

    raise "FAIL: No channels on radio $if_name are available for CAC abort test" -l "wm2/wm2_dfs_cac_aborted.sh" -s
}

# Sanity check - are channels even allowed on the radio
check_is_channel_allowed "$channel_a" "$if_name" &&
    log "wm2/wm2_dfs_cac_aborted.sh:check_is_channel_allowed - channel $channel_a is allowed on radio $if_name" ||
    raise "Channel $channel_a is not allowed on radio $if_name" -l "wm2/wm2_dfs_cac_aborted.sh" -ds
check_is_channel_allowed "$channel_b" "$if_name" &&
    log "wm2/wm2_dfs_cac_aborted.sh:check_is_channel_allowed - channel $channel_b is allowed on radio $if_name" ||
    raise "Channel $channel_b is not allowed on radio $if_name" -l "wm2/wm2_dfs_cac_aborted.sh" -ds

# Verify configured channel_a is in nop_finished state for the test. If not, switch to new channel.
chan_state=$(get_radio_channel_state "$channel_a" "$if_name")
if [ "$chan_state" = "nop_finished" ]; then
    log "wm2/wm2_dfs_cac_aborted.sh: Channel $channel_a on $if_name is usable for CAC abort test."
else
    log "wm2/wm2_dfs_cac_aborted.sh: Channel $channel_a in '$chan_state' state, expected \"nop_finished\". Searching for alternative channel."
    new_channel_a=$(get_usable_channel "$channel_b")
    if [ $? = 0 ]; then
        log "wm2/wm2_dfs_cac_aborted.sh: Alternative channel '$new_channel_a' found"
        channel_a=$new_channel_a
    else
        raise "FAIL: Could not find alternative channel for CAC abort test" -l "wm2/wm2_dfs_cac_aborted.sh" -s
    fi
fi

# Verify configured channel_b is in nop_finished state for the test. If not, switch to new channel.
chan_state=$(get_radio_channel_state "$channel_b" "$if_name")
if [ "$chan_state" = "nop_finished" ]; then
    log "wm2/wm2_dfs_cac_aborted.sh: Channel $channel_b on $if_name is usable for CAC abort test."
else
    log "wm2/wm2_dfs_cac_aborted.sh: Channel $channel_b in '$chan_state' state, expected \"nop_finished\". Searching for alternative channel."
    new_channel_b=$(get_usable_channel "$channel_a")
    if [ $? = 0 ]; then
        log "wm2/wm2_dfs_cac_aborted.sh: Alternative channel '$new_channel_b' found"
        channel_b=$new_channel_b
    else
        raise "FAIL: Could not find alternative channel for CAC abort test" -l "wm2/wm2_dfs_cac_aborted.sh" -s
    fi
fi

log_title "wm2/wm2_dfs_cac_aborted.sh: WM2 test - DFC CAC Aborted - Using: '${channel_a}'->'${channel_b}'"

# Testcase:
# Configure radio, create VIF and apply channel
# This needs to be done simultaneously for the driver to bring up an active AP
# Function only checks if the channel is set in Wifi_Radio_State, not if it is
# available for immediate use, so CAC could be in progress. This is desired.
log "wm2/wm2_dfs_cac_aborted.sh: Configuring Wifi_Radio_Config, creating interface in Wifi_VIF_Config."
log "wm2/wm2_dfs_cac_aborted.sh: Waiting for ${channel_change_timeout}s for settings {channel:$channel_a}"
create_radio_vif_interface \
    -channel "$channel_a" \
    -channel_mode manual \
    -enabled true \
    -ht_mode "$ht_mode" \
    -hw_mode "$hw_mode" \
    -if_name "$if_name" \
    -mode "$mode" \
    -security "$security" \
    -ssid "$ssid" \
    -vif_if_name "$vif_if_name" \
    -vif_radio_idx "$vif_radio_idx" \
    -timeout ${channel_change_timeout} \
    -disable_cac &&
        log "wm2/wm2_dfs_cac_aborted.sh: create_radio_vif_interface {$if_name, $channel_a} - Success" ||
        raise "FAIL: create_radio_vif_interface {$if_name, $channel_a} - Interface not created" -l "wm2/wm2_dfs_cac_aborted.sh" -tc

wait_ovsdb_entry Wifi_Radio_State -w if_name "$if_name" -is channel "$channel_a" &&
    log "wm2/wm2_dfs_cac_aborted.sh: wait_ovsdb_entry - Wifi_Radio_Config reflected to Wifi_Radio_State::channel is $channel_a - Success" ||
    raise "FAIL: wait_ovsdb_entry - Failed to reflect Wifi_Radio_Config to Wifi_Radio_State::channel is not $channel_a" -l "wm2/wm2_dfs_cac_aborted.sh" -tc

wait_for_function_response 0 "check_is_cac_started $channel_a $if_name" &&
    log "wm2/wm2_dfs_cac_aborted.sh: wait_for_function_response - channel $channel_a - CAC STARTED - Success" ||
    raise "FAIL: wait_for_function_response - channel $channel_a - CAC NOT STARTED" -l "wm2/wm2_dfs_cac_aborted.sh" -tc

log "wm2/wm2_dfs_cac_aborted.sh: Do not wait for CAC to finish, changing channel to $channel_b"
update_ovsdb_entry Wifi_Radio_Config -w if_name "$if_name" -u channel "$channel_b" &&
    log "wm2/wm2_dfs_cac_aborted.sh: update_ovsdb_entry - Wifi_Radio_Config::channel is $channel_b - Success" ||
    raise "FAIL: update_ovsdb_entry - Failed to update Wifi_Radio_Config::channel is not $channel_b" -l "wm2/wm2_dfs_cac_aborted.sh" -tc

wait_ovsdb_entry Wifi_Radio_State -w if_name "$if_name" -is channel "$channel_b" &&
    log "wm2/wm2_dfs_cac_aborted.sh: wait_ovsdb_entry - Wifi_Radio_Config reflected to Wifi_Radio_State::channel is $channel_b - Success" ||
    raise "FAIL: wait_ovsdb_entry - Failed to reflect Wifi_Radio_Config to Wifi_Radio_State::channel is not $channel_b" -l "wm2/wm2_dfs_cac_aborted.sh" -tc

wait_for_function_response 0 "check_is_nop_finished $channel_a $if_name" &&
    log "wm2/wm2_dfs_cac_aborted.sh: wait_for_function_response - channel $channel_a - NOP FINISHED - Success" ||
    raise "FAIL: wait_for_function_response - channel $channel_a - NOP NOT FINISHED" -l "wm2/wm2_dfs_cac_aborted.sh" -tc

wait_for_function_response 0 "check_is_cac_started $channel_b $if_name" &&
    log "wm2/wm2_dfs_cac_aborted.sh: wait_for_function_response - channel $channel_b - CAC STARTED - Success" ||
    raise "FAIL: wait_for_function_response - channel $channel_b - CAC NOT STARTED" -l "wm2/wm2_dfs_cac_aborted.sh" -tc

pass
