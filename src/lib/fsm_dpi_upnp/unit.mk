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

###############################################################################
#
# fsm dpi UPnP client plugin library
#
###############################################################################
UNIT_NAME := fsm_dpi_upnp

UNIT_DISABLE := $(if $(CONFIG_FSM_DPI_UPNP), n, y)

# If compiled with clang, assume a native unit test target
# and build a static library
ifneq (, $(findstring clang, $(CC)))
    UNIT_TYPE := LIB
else
    UNIT_TYPE := SHLIB
    UNIT_DIR := lib
endif

UNIT_SRC := src/fsm_dpi_upnp.c
UNIT_SRC += src/upnp_portmap.c
UNIT_SRC += src/upnp_portmap_pb.c
UNIT_SRC += src/upnp_report_aggregator.c

UNIT_CFLAGS := -I$(UNIT_PATH)/inc

# This is REQUIRED so we can find libfsm_dpi_client.so
UNIT_LDFLAGS += -Wl,-rpath=$(INSTALL_PREFIX)/$(UNIT_DIR)
UNIT_LDFLAGS += -lminiupnpc

UNIT_EXPORT_CFLAGS := $(UNIT_CFLAGS)
UNIT_EXPORT_LDFLAGS := -ljansson -lminiupnpc

UNIT_DEPS += src/lib/fsm_dpi_client
UNIT_DEPS += src/lib/fsm_policy
UNIT_DEPS += src/lib/fsm_utils
UNIT_DEPS += src/lib/log
UNIT_DEPS += src/lib/neigh_table
UNIT_DEPS += src/lib/network_metadata
UNIT_DEPS += src/lib/policy_tags
UNIT_DEPS += src/lib/protobuf
UNIT_DEPS += src/lib/ovsdb
