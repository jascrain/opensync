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

UNIT_NAME := fut_dm

UNIT_DISABLE := n

# Template type:
UNIT_TYPE := FUT
# Output directory
UNIT_DIR := shell/tests/dm

# BRV specific FUTs
UNIT_FILE := brv_setup.sh
UNIT_FILE += brv_busybox_builtins.sh
UNIT_FILE += brv_is_script_on_system.sh
UNIT_FILE += brv_is_tool_on_system.sh
UNIT_FILE += brv_ovs_check_version.sh

# DM specific FUTs
UNIT_FILE += dm_setup.sh
UNIT_FILE += dm_verify_awlan_node_params.sh
UNIT_FILE += dm_verify_count_reboot_status.sh
UNIT_FILE += dm_verify_counter_inc_reboot_status.sh
UNIT_FILE += dm_verify_device_mode_awlan_node.sh
UNIT_FILE += dm_verify_enable_node_services.sh
UNIT_FILE += dm_verify_node_services.sh
UNIT_FILE += dm_verify_reboot_file_exists.sh
UNIT_FILE += dm_verify_reboot_reason.sh

# ONBRD specific FUTs
UNIT_FILE += onbrd_setup.sh
UNIT_FILE += onbrd_cleanup.sh
UNIT_FILE += onbrd_set_and_verify_bridge_mode.sh
UNIT_FILE += onbrd_verify_client_certificate_files.sh
UNIT_FILE += onbrd_verify_client_tls_connection.sh
UNIT_FILE += onbrd_verify_dhcp_dry_run_success.sh
UNIT_FILE += onbrd_verify_dut_system_time_accuracy.sh
UNIT_FILE += onbrd_verify_fw_version_awlan_node.sh
UNIT_FILE += onbrd_verify_home_vaps_on_home_bridge.sh
UNIT_FILE += onbrd_verify_home_vaps_on_radios.sh
UNIT_FILE += onbrd_verify_manager_hostname_resolved.sh
UNIT_FILE += onbrd_verify_model_awlan_node.sh
UNIT_FILE += onbrd_verify_number_of_radios.sh
UNIT_FILE += onbrd_verify_onbrd_vaps_on_radios.sh
UNIT_FILE += onbrd_verify_redirector_address_awlan_node.sh
UNIT_FILE += onbrd_verify_router_mode.sh
UNIT_FILE += onbrd_verify_wan_iface_mac_addr.sh
UNIT_FILE += onbrd_verify_wan_ip_address.sh

# OTHR specific FUTs
UNIT_FILE += othr_setup.sh
UNIT_FILE += othr_cleanup.sh
UNIT_FILE += othr_connect_wifi_client_to_ap_freeze.sh
UNIT_FILE += othr_connect_wifi_client_to_ap_unfreeze.sh
UNIT_FILE += othr_verify_eth_client_connection.sh
UNIT_FILE += othr_verify_eth_lan_iface_wifi_master_state.sh
UNIT_FILE += othr_verify_eth_wan_iface_wifi_master_state.sh
UNIT_FILE += othr_verify_gre_iface_wifi_master_state.sh
UNIT_FILE += othr_verify_gre_tunnel_gw.sh
UNIT_FILE += othr_verify_gre_tunnel_gw_cleanup.sh
UNIT_FILE += othr_verify_gre_tunnel_leaf.sh
UNIT_FILE += othr_verify_lan_bridge_iface_wifi_master_state.sh
UNIT_FILE += othr_verify_ookla_speedtest.sh
UNIT_FILE += othr_verify_vif_iface_wifi_master_state.sh
UNIT_FILE += othr_verify_wan_bridge_iface_wifi_master_state.sh
UNIT_FILE += othr_verify_wifi_client_not_associated.sh
