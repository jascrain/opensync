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


# It is important for this particular testcase, to capture current time ASAP
time_now=$(date -u +"%s")

# FUT environment loading
# shellcheck disable=SC1091
source /tmp/fut-base/shell/config/default_shell.sh
# shellcheck disable=SC1091
[ -e "/tmp/fut-base/fut_set_env.sh" ] && source /tmp/fut-base/fut_set_env.sh
source "${FUT_TOPDIR}/shell/lib/onbrd_lib.sh"
[ -e "${PLATFORM_OVERRIDE_FILE}" ] && source "${PLATFORM_OVERRIDE_FILE}" || raise "${PLATFORM_OVERRIDE_FILE}" -ofm
[ -e "${MODEL_OVERRIDE_FILE}" ] && source "${MODEL_OVERRIDE_FILE}" || raise "${MODEL_OVERRIDE_FILE}" -ofm

manager_setup_file="onbrd/onbrd_setup.sh"
usage()
{
cat << usage_string
onbrd/onbrd_verify_dut_system_time_accuracy.sh [-h] arguments
Description:
    - Validate device time is within real time threshold
    - It is important to compare timestamps to the same time zone: UTC is used internally!
Arguments:
    -h  show this help message
    \$1 (time_ref)      : format: seconds since epoch. Used to compare system time.    : (int)(required)
    \$2 (time_accuracy) : format: seconds. Allowed time deviation from reference time. : (int)(required)
Testcase procedure:
    - On DEVICE: Run: ./${manager_setup_file} (see ${manager_setup_file} -h)
                 Run: ./onbrd/onbrd_verify_dut_system_time_accuracy.sh <ACCURACY> <REFERENCE-TIME>
Script usage example:
   ./onbrd/onbrd_verify_dut_system_time_accuracy.sh 2 $(date --utc +\"%s\")
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
NARGS=2
[ $# -lt ${NARGS} ] && usage && raise "Requires at least '${NARGS}' input argument(s)" -l "onbrd/onbrd_verify_dut_system_time_accuracy.sh" -arg

log_title "onbrd/onbrd_verify_dut_system_time_accuracy.sh: ONBRD test - Verify DUT system time is within threshold of the reference"

time_ref=$1
time_accuracy=$2

# Timestamps in human readable format
time_ref_str=$(date -D @"${time_ref}")
time_now_str=$(date -D @"${time_now}")

time_ref_timestamp=$(date -D "${time_ref_str}" +%s)
time_now_timestamp=$(date -D "${time_now_str}" +%s)

# Calculate time difference and ensure absolute value
time_diff=$(( time_ref_timestamp - time_now_timestamp ))
if [ $time_diff -lt 0 ]; then
    time_diff=$(( -time_diff ))
fi

log "onbrd/onbrd_verify_dut_system_time_accuracy.sh: Checking time ${time_now_str} against reference ${time_ref_str}"
if [ $time_diff -le "$time_accuracy" ]; then
    log "onbrd/onbrd_verify_dut_system_time_accuracy.sh: Time difference ${time_diff}s is within ${time_accuracy}s - Success"
else
    log -err "onbrd/onbrd_verify_dut_system_time_accuracy.sh:\nDevice time: ${time_now_str} -> ${time_now_timestamp}\nReference time: ${time_ref_str} -> ${time_ref_timestamp}"
    raise "FAIL: Time difference ${time_diff}s is NOT within ${time_accuracy}s" -l "onbrd/onbrd_verify_dut_system_time_accuracy.sh" -tc
fi

pass
