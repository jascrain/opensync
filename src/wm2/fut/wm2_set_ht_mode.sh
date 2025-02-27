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
default_channel_change_timeout=60

usage()
{
cat << usage_string
wm2/wm2_set_ht_mode.sh [-h] arguments
Description:
    - Script tries to set chosen HT MODE. If interface is not UP it brings up the interface, and tries to set HT MODE to desired value.
Arguments:
    -h  show this help message
    \$1  (if_name)       : Wifi_Radio_Config::if_name     : (string)(required)
    \$2  (vif_if_name)   : Wifi_VIF_Config::if_name       : (string)(required)
    \$3  (vif_radio_idx) : Wifi_VIF_Config::vif_radio_idx : (int)(required)
    \$4  (ssid)          : Wifi_VIF_Config::ssid          : (string)(required)
    \$5  (security)      : Wifi_VIF_Config::security      : (string)(required)
    \$6  (channel)       : Wifi_Radio_Config::channel     : (int)(required)
    \$7  (ht_mode)       : Wifi_Radio_Config::ht_mode     : (string)(required)
    \$8  (hw_mode)       : Wifi_Radio_Config::hw_mode     : (string)(required)
    \$9  (mode)          : Wifi_VIF_Config::mode          : (string)(required)
Testcase procedure:
    - On DEVICE: Run: ./${manager_setup_file} (see ${manager_setup_file} -h)
                 Run: ./wm2/wm2_set_ht_mode.sh <IF-NAME> <VIF-IF-NAME> <VIF-RADIO-IDX> <SSID> <SECURITY> <CHANNEL> <HT-MODE> <HW-MODE> <MODE>
Script usage example:
    ./wm2/wm2_set_ht_mode.sh wifi1 home-ap-l50 2 FUTssid '["map",[["encryption","WPA-PSK"],["key","FUTpsk"],["mode","2"]]]' 36 HT20 11ac ap
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

NARGS=9
[ $# -lt ${NARGS} ] && usage && raise "Requires '${NARGS}' input argument(s)" -l "wm2/wm2_set_ht_mode.sh" -arg
if_name=${1}
vif_if_name=${2}
vif_radio_idx=${3}
ssid=${4}
security=${5}
channel=${6}
ht_mode=${7}
hw_mode=${8}
mode=${9}
channel_change_timeout=${10:-${default_channel_change_timeout}}

trap '
    fut_info_dump_line
    print_tables Wifi_Radio_Config Wifi_Radio_State
    print_tables Wifi_VIF_Config Wifi_VIF_State
    check_restore_ovsdb_server
    fut_info_dump_line
' EXIT SIGINT SIGTERM

log_title "wm2/wm2_set_ht_mode.sh: WM2 test - Testing Wifi_Radio_Config field ht_mode - '${ht_mode}'"

# Testcase:
# Configure radio, create VIF and apply channel and ht_mode
# This needs to be done simultaneously for the driver to bring up an active AP
log "wm2/wm2_set_ht_mode.sh: Configuring Wifi_Radio_Config, creating interface in Wifi_VIF_Config."
log "wm2/wm2_set_ht_mode.sh: Waiting for ${channel_change_timeout}s for settings {ht_mode:$ht_mode}"
create_radio_vif_interface \
    -channel "$channel" \
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
        log "wm2/wm2_set_ht_mode.sh: create_radio_vif_interface {$if_name, $ht_mode} - Interface created - Success" ||
        raise "FAIL: create_radio_vif_interface {$if_name, $ht_mode} - Failed to create interface" -l "wm2/wm2_set_ht_mode.sh" -ds

wait_ovsdb_entry Wifi_Radio_State -w if_name "$if_name" -is ht_mode "$ht_mode" &&
    log "wm2/wm2_set_ht_mode.sh: wait_ovsdb_entry - Wifi_Radio_Config reflected to Wifi_Radio_State::ht_mode is $ht_mode - Success" ||
    raise "FAIL: wait_ovsdb_entry - Failed to reflect Wifi_Radio_Config to Wifi_Radio_State::ht_mode is not $ht_mode" -l "wm2/wm2_set_ht_mode.sh" -tc

log "wm2/wm2_set_ht_mode.sh: Checking ht_mode at system level - LEVEL2"
check_ht_mode_at_os_level "$ht_mode" "$vif_if_name" "$channel" &&
    log "wm2/wm2_set_ht_mode.sh: LEVEL2 - check_ht_mode_at_os_level - ht_mode $ht_mode set at system level - Success" ||
    raise "FAIL: LEVEL2 - check_ht_mode_at_os_level - ht_mode  $ht_mode not set at system level" -l "wm2/wm2_set_ht_mode.sh" -tc

pass
