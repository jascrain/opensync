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
usage()
{
cat << usage_string
wm2/wm2_set_radio_thermal_tx_chainmask.sh [-h] arguments
Description:
    - Script tries to set chosen THERMAL TX CHAINMASK. If interface is not UP it brings up the interface, and tries to set
      THERMAL TX CHAINMASK to desired value. Recomended values: 1, 3, 7, 15. Choose non-default values.
      THERMAL TX CHAINMASK is related to TX CHAINMASK - the device will combine the two chainmasks by performing
      AND operation on each bit of the chainmask. Test will enforce thermal_tx_chainmask < tx_chainmask.
Arguments:
    -h  show this help message
    \$1  (if_name)              : Wifi_Radio_Config::if_name              : (string)(required)
    \$2  (vif_if_name)          : Wifi_VIF_Config::if_name                : (string)(required)
    \$3  (vif_radio_idx)        : Wifi_VIF_Config::vif_radio_idx          : (int)(required)
    \$4  (ssid)                 : Wifi_VIF_Config::ssid                   : (string)(required)
    \$5  (security)             : Wifi_VIF_Config::security               : (string)(required)
    \$6  (channel)              : Wifi_Radio_Config::channel              : (int)(required)
    \$7  (ht_mode)              : Wifi_Radio_Config::ht_mode              : (string)(required)
    \$8  (hw_mode)              : Wifi_Radio_Config::hw_mode              : (string)(required)
    \$9  (mode)                 : Wifi_VIF_Config::mode                   : (string)(required)
    \$10 (tx_chainmask)         : Wifi_Radio_Config::tx_chainmask         : (int)(required)
    \$11 (thermal_tx_chainmask) : Wifi_Radio_Config::thermal_tx_chainmask : (int)(required)
Testcase procedure:
    - On DEVICE: Run: ./${manager_setup_file} (see ${manager_setup_file} -h)
                 Run: ./wm2/wm2_set_radio_thermal_tx_chainmask.sh <IF-NAME> <VIF-IF-NAME> <VIF-RADIO-IDX> <SSID> <SECURITY> <CHANNEL> <HT-MODE> <HW-MODE> <MODE> <TX_CHAINMASK> <THERMAL_TX_CHAINMASK>
Script usage example:
    ./wm2/wm2_set_radio_thermal_tx_chainmask.sh wifi1 home-ap-l50 2 FUTssid '["map",[["encryption","WPA-PSK"],["key","FUTpsk"],["mode","2"]]]' 36 HT20 11ac ap 15 7

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

NARGS=11
[ $# -lt ${NARGS} ] && usage && raise "Requires at least '${NARGS}' input argument(s)" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -arg
if_name=${1}
vif_if_name=${2}
vif_radio_idx=${3}
ssid=${4}
security=${5}
channel=${6}
ht_mode=${7}
hw_mode=${8}
mode=${9}
tx_chainmask=${10}
thermal_tx_chainmask=${11}

trap '
    fut_info_dump_line
    print_tables Wifi_Radio_Config Wifi_Radio_State
    print_tables Wifi_VIF_Config Wifi_VIF_State
    check_restore_ovsdb_server
    fut_info_dump_line
' EXIT SIGINT SIGTERM

log_title "wm2/wm2_set_radio_thermal_tx_chainmask.sh: WM2 test - Testing Wifi_Radio_Config field thermal_tx_chainmask"

log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Enforce thermal_tx_chainmask < tx_chainmask "
if [ "$thermal_tx_chainmask" -gt "$tx_chainmask" ]; then
    raise "Value of thermal_tx_chainmask '$thermal_tx_chainmask' must be smaller than tx_chainmask '$tx_chainmask'" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -arg
else
    value_to_check=$thermal_tx_chainmask
fi

log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Checking if Radio/VIF states are valid for test"
check_radio_vif_state \
    -if_name "$if_name" \
    -vif_if_name "$vif_if_name" \
    -vif_radio_idx "$vif_radio_idx" \
    -ssid "$ssid" \
    -channel "$channel" \
    -security "$security" \
    -hw_mode "$hw_mode" \
    -mode "$mode" &&
        log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Radio/VIF states are valid" ||
            (
                log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Cleaning VIF_Config"
                vif_clean
                log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Radio/VIF states are not valid, creating interface..."
                create_radio_vif_interface \
                    -vif_radio_idx "$vif_radio_idx" \
                    -channel_mode manual \
                    -if_name "$if_name" \
                    -ssid "$ssid" \
                    -security "$security" \
                    -enabled true \
                    -channel "$channel" \
                    -ht_mode "$ht_mode" \
                    -hw_mode "$hw_mode" \
                    -mode "$mode" \
                    -vif_if_name "$vif_if_name" \
                    -disable_cac &&
                        log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: create_radio_vif_interface - Interface $if_name created - Success"
            ) ||
        raise "FAIL: create_radio_vif_interface - Interface $if_name not created" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -ds

log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Changing tx_chainmask to $tx_chainmask"
update_ovsdb_entry Wifi_Radio_Config -w if_name "$if_name" -u tx_chainmask "$tx_chainmask" &&
    log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: update_ovsdb_entry - Wifi_Radio_Config::tx_chainmask is $tx_chainmask - Success" ||
    raise "FAIL: update_ovsdb_entry - Wifi_Radio_Config::tx_chainmask is not $tx_chainmask" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -oe

wait_ovsdb_entry Wifi_Radio_State -w if_name "$if_name" -is tx_chainmask "$tx_chainmask" &&
    log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: wait_ovsdb_entry - Wifi_Radio_Config reflected to Wifi_Radio_State::tx_chainmask is $tx_chainmask - Success" ||
    raise "FAIL: wait_ovsdb_entry - Failed to reflect Wifi_Radio_Config to Wifi_Radio_State::tx_chainmask is not $tx_chainmask" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -ds

log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Checking TX CHAINMASK $tx_chainmask at system level - LEVEL2"
check_tx_chainmask_at_os_level "$tx_chainmask" "$if_name" &&
    log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: LEVEL2 - check_tx_chainmask_at_os_level - TX CHAINMASK $tx_chainmask set at system level - Success" ||
    raise "FAIL: LEVEL2 - check_tx_chainmask_at_os_level - TX CHAINMASK $tx_chainmask not set at system level" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -ds

log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Changing thermal_tx_chainmask to $thermal_tx_chainmask"
update_ovsdb_entry Wifi_Radio_Config -w if_name "$if_name" -u thermal_tx_chainmask "$thermal_tx_chainmask" &&
    log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: update_ovsdb_entry - Wifi_Radio_Config::thermal_tx_chainmask is $thermal_tx_chainmask - Success" ||
    raise "FAIL: update_ovsdb_entry - Failed to update Wifi_Radio_Config::thermal_tx_chainmask is not $thermal_tx_chainmask" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -oe

log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Check if tx_chainmask changed to $value_to_check"
wait_ovsdb_entry Wifi_Radio_State -w if_name "$if_name" -is tx_chainmask "$value_to_check" &&
    log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: wait_ovsdb_entry - Wifi_Radio_Config reflected to Wifi_Radio_State::tx_chainmask is $value_to_check - Success" ||
    raise "FAIL: wait_ovsdb_entry - Failed to reflect Wifi_Radio_Config to Wifi_Radio_State::tx_chainmask is not $value_to_check" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -tc

log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: Checking TX CHAINMASK $value_to_check at system level - LEVEL2"
check_tx_chainmask_at_os_level "$value_to_check" "$if_name" &&
    log "wm2/wm2_set_radio_thermal_tx_chainmask.sh: LEVEL2 - check_tx_chainmask_at_os_level - TX CHAINMASK $value_to_check set at system level - Success" ||
    raise "FAIL: LEVEL2 - check_tx_chainmask_at_os_level - TX CHAINMASK $value_to_check is not set at system" -l "wm2/wm2_set_radio_thermal_tx_chainmask.sh" -tc

pass
