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
source "${FUT_TOPDIR}/shell/lib/sm_lib.sh"
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

manager_setup_file="sm/sm_setup.sh"
radio_vif_create_path="tools/device/create_radio_vif_interface.sh"
usage()
{
cat << usage_string
sm/sm_inspect_survey_report.sh [-h] arguments
Description:
    - Script configures SM survey reporting and inspects the logs, fails otherwise
Arguments:
    -h  show this help message
    \$1 (radio_type)         : used as radio_type in Wifi_Stats_Config table         : (string)(required)
    \$2 (channel)            : used as channel in Wifi_Stats_Config table            : (string)(required)
    \$3 (survey_type)        : used as survey_type in Wifi_Stats_Config table        : (string)(required)
    \$4 (reporting_interval) : used as reporting_interval in Wifi_Stats_Config table : (string)(required)
    \$5 (sampling_interval)  : used as sampling_interval in Wifi_Stats_Config table  : (string)(required)
    \$6 (report_type)        : used as report_type in Wifi_Stats_Config table        : (string)(required)
    \$7 (survey_interval)    : used as survey_interval_ms in Wifi_Stats_Config table : (string)(required)
Testcase procedure:
    - On DEVICE: Run: ./${manager_setup_file} (see ${manager_setup_file} -h)
                 Create required Radio-VIF interface settings (see ${radio_vif_create_path} -h)
                 Run: ./sm/sm_inspect_survey_report.sh <RADIO-TYPE> <CHANNEL> <SURVEY-TYPE> <REPORTING-INTERVAL> <SAMPLING-INTERVAL> <REPORT-TYPE>
Script usage example:
   ./sm/sm_inspect_survey_report.sh 2.4G 6 on-chan 10 5 raw
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
NARGS=6
[ $# -lt ${NARGS} ] && usage && raise "Requires at least '${NARGS}' input argument(s)" -l "sm/sm_inspect_survey_report.sh" -arg
sm_radio_type=${1}
sm_channel=${2}
sm_survey_type=${3}
sm_reporting_interval=${4}
sm_sampling_interval=${5}
sm_report_type=${6}
sm_survey_interval=${7}


log_title "sm/sm_inspect_survey_report.sh: SM test - Inspect survey report for $sm_radio_type"

log "sm/sm_inspect_survey_report.sh: Inspecting survey report on $sm_radio_type $sm_survey_type channel $sm_channel"
inspect_survey_report \
    "$sm_radio_type" \
    "$sm_channel" \
    "$sm_survey_type" \
    "$sm_reporting_interval" \
    "$sm_sampling_interval" \
    "$sm_report_type" \
    "$sm_survey_interval" ||
        raise "FAIL: inspect_survey_report - $sm_survey_type logs not found for radio $sm_radio_type" -l "sm/sm_inspect_survey_report.sh" -tc

pass
