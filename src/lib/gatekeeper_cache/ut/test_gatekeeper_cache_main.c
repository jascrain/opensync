/*
Copyright (c) 2015, Plume Design Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
   1. Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
   2. Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
   3. Neither the name of the Plume Design Inc. nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Plume Design Inc. BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <libgen.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

#include "gatekeeper_cache.h"
#include "log.h"
#include "memutil.h"
#include "network_metadata_utils.h"
#include "sockaddr_storage.h"
#include "target.h"
#include "unity.h"

#include "test_gatekeeper_cache.h"
#include "unit_test_utils.h"

const char *test_name = "gk_cache_tests";

size_t OVER_MAX_CACHE_ENTRIES;

struct sample_attribute_entries *test_attr_entries;
struct sample_flow_entries *test_flow_entries;

struct gk_attr_cache_interface *entry1, *entry2, *entry3, *entry4;
struct gk_attr_cache_interface *entry5, *entry6, *entry7, *entry8;
struct gk_attr_cache_interface *entry9;
struct gkc_ip_flow_interface *flow_entry1, *flow_entry2, *flow_entry3, *flow_entry4;
struct gkc_ip_flow_interface *flow_entry5, *flow_entry6, *flow_entry7, *flow_entry8;

char *g_genmac_filename = "./data/genmac.txt";

void
populate_sample_attribute_entries(void)
{
    FILE *fp;
    char line[1024];
    size_t i = 0;

    fp = fopen(g_genmac_filename, "r");
    if (fp == NULL)
    {
        printf("fopen failed !!\n");
        return;
    }

    while (fgets(line, 100, fp))
    {
        if (i >= OVER_MAX_CACHE_ENTRIES) return;

        sscanf(line, "%s %d %s ", test_attr_entries[i].mac_str, &test_attr_entries[i].attribute_type,
               test_attr_entries[i].attr_name);
        i++;
    }
}

void
populate_sample_flow_entries(void)
{
    size_t i;

    for (i = 0; i < OVER_MAX_CACHE_ENTRIES; i++)
    {
        strcpy(test_flow_entries[i].mac_str, test_attr_entries[i].mac_str);
        strcpy(test_flow_entries[i].src_ip_addr, "1.1.1.1");
        strcpy(test_flow_entries[i].dst_ip_addr, "2.2.2.2");
        test_flow_entries[i].ip_version = 4;
        test_flow_entries[i].src_port = 443;
        test_flow_entries[i].dst_port = 8888;
        test_flow_entries[i].protocol = 16;
        test_flow_entries[i].direction = GKC_FLOW_DIRECTION_INBOUND;
        test_flow_entries[i].action = FSM_ALLOW;
    }
}

static void
create_default_attr_entries(void)
{
    entry1 = CALLOC(1, sizeof(*entry1));
    entry1->action = 1;
    entry1->device_mac = str2os_mac("AA:AA:AA:AA:AA:01");
    entry1->attribute_type = GK_CACHE_REQ_TYPE_FQDN;
    entry1->cache_ttl = 1000;
    entry1->action = FSM_BLOCK;
    entry1->attr_name = strdup("www.test.com");

    entry2 = CALLOC(1, sizeof(*entry2));
    entry2->action = 1;
    entry2->device_mac = str2os_mac("AA:AA:AA:AA:AA:02");
    entry2->attribute_type = GK_CACHE_REQ_TYPE_FQDN;
    entry2->cache_ttl = 1000;
    entry2->action = FSM_ALLOW;
    entry2->attr_name = strdup("www.entr2.com");

    entry3 = CALLOC(1, sizeof(*entry3));
    entry3->action = 1;
    entry3->device_mac = str2os_mac("AA:AA:AA:AA:AA:03");
    entry3->attribute_type = GK_CACHE_REQ_TYPE_FQDN;
    entry3->cache_ttl = 1000;
    entry3->action = FSM_ALLOW;
    entry3->attr_name = strdup("www.entr3.com");

    entry4 = CALLOC(1, sizeof(*entry4));
    entry4->action = 1;
    entry4->device_mac = str2os_mac("AA:AA:AA:AA:AA:04");
    entry4->attribute_type = GK_CACHE_REQ_TYPE_URL;
    entry4->cache_ttl = 1000;
    entry4->action = FSM_BLOCK;
    entry4->attr_name = strdup("https://www.google.com");

    entry5 = CALLOC(1, sizeof(*entry5));
    entry5->action = 1;
    entry5->device_mac = str2os_mac("AA:AA:AA:AA:AA:04");
    entry5->attribute_type = GK_CACHE_REQ_TYPE_APP;
    entry5->cache_ttl = 1000;
    entry5->action = FSM_BLOCK;
    entry5->attr_name = strdup("testapp");

    entry6 = CALLOC(1, sizeof(*entry6));
    entry6->action = 1;
    entry6->device_mac = str2os_mac("AA:AA:AA:AA:AA:06");
    entry6->attribute_type = GK_CACHE_REQ_TYPE_FQDN;
    entry6->cache_ttl = 1000;
    entry6->action = FSM_ALLOW;
    entry6->attr_name = strdup("www.entr6.com");
    entry6->network_id = "home--1";

    entry7 = CALLOC(1, sizeof(*entry7));
    entry7->action = 1;
    entry7->device_mac = str2os_mac("AA:AA:AA:AA:AA:06");
    entry7->attribute_type = GK_CACHE_REQ_TYPE_APP;
    entry7->cache_ttl = 1000;
    entry7->action = FSM_BLOCK;
    entry7->attr_name = strdup("testapp1");
    entry7->network_id = "home--2";

    entry8 = CALLOC(1, sizeof(*entry8));
    entry8->action = 1;
    entry8->device_mac = str2os_mac("AA:AA:AA:AA:AA:06");
    entry8->attribute_type = GK_CACHE_REQ_TYPE_URL;
    entry8->cache_ttl = 1000;
    entry8->action = FSM_ALLOW;
    entry8->attr_name = strdup("https://www.google.com");
    entry8->network_id = "home--3";

    entry9 = CALLOC(1, sizeof(*entry5));
    entry9->action = 1;
    entry9->device_mac = str2os_mac("AA:AA:AA:AA:AA:04");
    entry9->attribute_type = GK_CACHE_REQ_TYPE_IPV4;
    entry9->cache_ttl = 1000;
    entry9->action = FSM_BLOCK;
    entry9->ip_addr = sockaddr_storage_create(AF_INET, "127.0.0.1");
    entry9->direction = NET_MD_ACC_INBOUND_DIR;
}

static void
create_default_flow_entries(void)
{
    flow_entry1 = CALLOC(1, sizeof(*flow_entry1));
    flow_entry1->device_mac = str2os_mac("AA:AA:AA:AA:AA:01");
    flow_entry1->direction = GKC_FLOW_DIRECTION_INBOUND;
    flow_entry1->src_port = 80;
    flow_entry1->dst_port = 8002;
    flow_entry1->ip_version = 4;
    flow_entry1->protocol = 16;
    flow_entry1->cache_ttl = 1000;
    flow_entry1->action = FSM_BLOCK;
    flow_entry1->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "1.1.1.1", flow_entry1->src_ip_addr);
    flow_entry1->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "10.2.4.3", flow_entry1->dst_ip_addr);

    flow_entry2 = CALLOC(1, sizeof(*flow_entry2));
    flow_entry2->device_mac = str2os_mac("AA:AA:AA:AA:AA:02");
    flow_entry2->direction = GKC_FLOW_DIRECTION_INBOUND;
    flow_entry2->src_port = 443;
    flow_entry2->dst_port = 8888;
    flow_entry2->ip_version = 4;
    flow_entry2->protocol = 16;
    flow_entry2->cache_ttl = 1000;
    flow_entry2->action = FSM_BLOCK;
    flow_entry2->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "2.2.2.2", flow_entry2->src_ip_addr);
    flow_entry2->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "10.2.2.2", flow_entry2->dst_ip_addr);

    flow_entry3 = CALLOC(1, sizeof(*flow_entry3));
    flow_entry3->device_mac = str2os_mac("AA:AA:AA:AA:AA:02");
    flow_entry3->direction = GKC_FLOW_DIRECTION_INBOUND;
    flow_entry3->src_port = 22;
    flow_entry3->dst_port = 3333;
    flow_entry3->ip_version = 6;
    flow_entry3->protocol = 16;
    flow_entry3->cache_ttl = 1000;
    flow_entry3->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET6, "0:0:0:0:0:FFFF:204.152.189.116", flow_entry3->src_ip_addr);
    flow_entry3->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET6, "1:0:0:0:0:0:0:8", flow_entry3->dst_ip_addr);

    flow_entry4 = CALLOC(1, sizeof(*flow_entry4));
    flow_entry4->device_mac = CALLOC(1, sizeof(*flow_entry4->device_mac));
    flow_entry4->device_mac->addr[0] = 0xaa;
    flow_entry4->device_mac->addr[1] = 0xaa;
    flow_entry4->device_mac->addr[2] = 0xaa;
    flow_entry4->device_mac->addr[3] = 0xaa;
    flow_entry4->device_mac->addr[4] = 0xaa;
    flow_entry4->device_mac->addr[5] = 0x03;
    flow_entry4->direction = GKC_FLOW_DIRECTION_OUTBOUND;
    flow_entry4->src_port = 16;
    flow_entry4->dst_port = 444;
    flow_entry4->action = FSM_BLOCK;
    flow_entry4->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "1.1.1.1", flow_entry4->src_ip_addr);
    flow_entry4->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "10.2.4.3", flow_entry4->dst_ip_addr);

    flow_entry5 = CALLOC(1, sizeof(*flow_entry3));
    flow_entry5->device_mac = str2os_mac("AA:AA:AA:AA:AA:05");
    flow_entry5->direction = GKC_FLOW_DIRECTION_INBOUND;
    flow_entry5->src_port = 22;
    flow_entry5->dst_port = 3333;
    flow_entry5->ip_version = 4;
    flow_entry5->protocol = 16;
    flow_entry5->cache_ttl = 1000;
    flow_entry5->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "2.2.2.2", flow_entry5->dst_ip_addr);
    flow_entry5->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "10.2.2.1", flow_entry5->src_ip_addr);

    flow_entry6 = CALLOC(1, sizeof(*flow_entry6));
    flow_entry6->device_mac = str2os_mac("AA:AA:AA:AA:AA:06");
    flow_entry6->direction = GKC_FLOW_DIRECTION_INBOUND;
    flow_entry6->src_port = 22;
    flow_entry6->dst_port = 3333;
    flow_entry6->ip_version = 4;
    flow_entry6->protocol = 16;
    flow_entry6->cache_ttl = 1000;
    flow_entry6->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "2.2.2.2", flow_entry6->dst_ip_addr);
    flow_entry6->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "10.2.2.1", flow_entry6->src_ip_addr);
    flow_entry6->network_id = "home--1";

    flow_entry7 = CALLOC(1, sizeof(*flow_entry7));
    flow_entry7->device_mac = str2os_mac("AA:AA:AA:AA:AA:07");
    flow_entry7->direction = GKC_FLOW_DIRECTION_OUTBOUND;
    flow_entry7->src_port = 22;
    flow_entry7->dst_port = 3333;
    flow_entry7->ip_version = 4;
    flow_entry7->protocol = 16;
    flow_entry7->cache_ttl = 1000;
    flow_entry7->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "2.2.2.2", flow_entry7->dst_ip_addr);
    flow_entry7->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "10.2.2.1", flow_entry7->src_ip_addr);
    flow_entry7->network_id = "home--2";

    flow_entry8 = CALLOC(1, sizeof(*flow_entry8));
    flow_entry8->device_mac = str2os_mac("AA:AA:AA:AA:AA:08");
    flow_entry8->direction = GKC_FLOW_DIRECTION_INBOUND;
    flow_entry8->src_port = 22;
    flow_entry8->dst_port = 3333;
    flow_entry8->ip_version = 4;
    flow_entry8->protocol = 16;
    flow_entry8->cache_ttl = 1000;
    flow_entry8->dst_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "2.2.2.2", flow_entry8->dst_ip_addr);
    flow_entry8->src_ip_addr = CALLOC(1, sizeof(struct in6_addr));
    inet_pton(AF_INET, "10.2.2.1", flow_entry8->src_ip_addr);
    flow_entry8->network_id = "home--3";
}

void
gatekeeper_cache_setUp(void)
{
    OVER_MAX_CACHE_ENTRIES = gk_cache_get_size() + 1;
    test_attr_entries = CALLOC(OVER_MAX_CACHE_ENTRIES, sizeof(*test_attr_entries));
    test_flow_entries = CALLOC(OVER_MAX_CACHE_ENTRIES, sizeof(*test_flow_entries));

    create_default_attr_entries();
    create_default_flow_entries();
    gk_cache_init();
    populate_sample_attribute_entries();
    populate_sample_flow_entries();
}

void
free_flow_interface(struct gkc_ip_flow_interface *entry)
{
    if (!entry) return;

    FREE(entry->device_mac);
    FREE(entry->src_ip_addr);
    FREE(entry->dst_ip_addr);
    FREE(entry);
}

void
del_default_flow_entries(void)
{
    free_flow_interface(flow_entry1);
    free_flow_interface(flow_entry2);
    free_flow_interface(flow_entry3);
    free_flow_interface(flow_entry4);
    free_flow_interface(flow_entry5);
    free_flow_interface(flow_entry6);
    free_flow_interface(flow_entry7);
    free_flow_interface(flow_entry8);
}

void
free_cache_interface(struct gk_attr_cache_interface *entry)
{
    if (!entry) return;

    FREE(entry->device_mac);
    FREE(entry->attr_name);
    FREE(entry->fqdn_redirect);
    FREE(entry->ip_addr);
    FREE(entry);
}

void
del_default_attr_entries(void)
{
    free_cache_interface(entry1);
    free_cache_interface(entry2);
    free_cache_interface(entry3);
    free_cache_interface(entry4);
    free_cache_interface(entry5);
    free_cache_interface(entry6);
    free_cache_interface(entry7);
    free_cache_interface(entry8);
    free_cache_interface(entry9);
}

void
gatekeeper_cache_tearDown(void)
{
    gk_cache_cleanup();
    del_default_attr_entries();
    del_default_flow_entries();
    FREE(test_attr_entries);
    FREE(test_flow_entries);
}

int
main(int argc, char *argv[])
{
    int ret;

    (void)argc;
    (void)argv;

    ut_init(test_name, NULL, NULL);

    ut_setUp_tearDown(test_name, gatekeeper_cache_setUp, gatekeeper_cache_tearDown);

    /*
     * This is a requirement: Do NOT proceed if the file is missing.
     * File presence will not be tested any further.
     */
    chdir(dirname(argv[0]));
    ret = access(g_genmac_filename, F_OK);
    if (ret != 0)
    {
        LOGW("In %s requires %s", basename(__FILE__), g_genmac_filename);
        exit(1);
    }

    run_gk_cache();
    run_gk_cache_cmp();
    run_gk_cache_flush();

    return ut_fini();
}
