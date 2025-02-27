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

#include <arpa/inet.h>
#include <stdlib.h>
#include <stddef.h>
#include <time.h>

#include "const.h"
#include "ds_tree.h"
#include "log.h"
#include "fsm_demo_dpi_plugin.h"
#include "assert.h"
#include "json_util.h"
#include "ovsdb.h"
#include "ovsdb_cache.h"
#include "ovsdb_table.h"
#include "schema.h"
#include "net_header_parse.h"
#include "network_metadata_report.h"
#include "qm_conn.h"
#include "fsm_dpi_utils.h"
#include "memutil.h"

static struct fsm_demo_plugin_cache
cache_mgr =
{
    .initialized = false,
};


struct fsm_demo_plugin_cache *
fsm_demo_get_mgr(void)
{
    return &cache_mgr;
}

// Blocked IP list - mail.yahoo.com
#define BLOCKED_IP_ADDR "69.147.88.8"

/**
 * @brief compare device sessions
 * @param a device session
 * @param b device session
 *
 * Compare device sessions based on their device IDs (MAC address)
 */
static int
fsm_demo_dev_id_cmp(const void *a, const void *b)
{
    const os_macaddr_t *dev_id_a = a;
    const os_macaddr_t *dev_id_b = b;

    return memcmp(dev_id_a->addr,
                  dev_id_b->addr,
                  sizeof(dev_id_a->addr));
}


/**
 * @brief compare sessions
 *
 * @param a session pointer
 * @param b session pointer
 * @return 0 if sessions matches
 */
static int
fsm_demo_session_cmp(const void *a, const void *b)
{
    uintptr_t p_a = (uintptr_t)a;
    uintptr_t p_b = (uintptr_t)b;

    if (p_a ==  p_b) return 0;
    if (p_a < p_b) return -1;
    return 1;
}

/**
 * @brief allocate a network stats aggregator
 *
 * Flow stats will be reported periodically through mqtt
 */
struct net_md_aggregator *
fsm_demo_alloc_aggr(struct fsm_demo_session *f_session)
{
    struct net_md_aggregator_set aggr_set;
    struct net_md_aggregator *aggr;
    struct fsm_session *session;
    struct node_info info;

    memset(&aggr_set, 0, sizeof(aggr_set));
    session = f_session->session;
    info.node_id = session->node_id;
    info.location_id = session->location_id;
    aggr_set.info = &info;
    aggr_set.num_windows = 1;
    aggr_set.acc_ttl = 600;
    aggr_set.report_type = NET_MD_REPORT_RELATIVE;
    aggr_set.report_filter = NULL;
    aggr_set.send_report = net_md_send_report;
    aggr = net_md_allocate_aggregator(&aggr_set);

    return aggr;
}


/**
 * @brief session initialization entry point
 *
 * Initializes the plugin specific fields of the session,
 * like the packet parsing handler and the periodic routines called
 * by fsm.
 * @param session pointer provided by fsm
 */
int
fsm_demo_dpi_plugin_init(struct fsm_session *session)
{
    struct fsm_demo_plugin_cache *mgr;
    struct fsm_parser_ops *parser_ops;
    struct fsm_demo_session *fsm_demo_session;
    bool rc;

    if (session == NULL) return -1;

    mgr = fsm_demo_get_mgr();

    /* Initialize the manager on first call */
    if (!mgr->initialized)
    {
        ds_tree_init(&mgr->fsm_sessions, fsm_demo_session_cmp,
                     struct fsm_demo_session, session_node);
        mgr->initialized = true;
    }

    /* Look up the fsm demo session */
    fsm_demo_session = fsm_demo_lookup_session(session);
    if (fsm_demo_session == NULL)
    {
        LOGE("%s: could not allocate fsm_demo parser", __func__);
        return -1;
    }

    /* Bail if the session is already initialized */
    if (fsm_demo_session->initialized) return 0;

    /* Set the fsm session */
    session->ops.periodic = fsm_demo_plugin_periodic;
    session->ops.exit = fsm_demo_plugin_exit;
    session->handler_ctxt = fsm_demo_session;

    /* Set the plugin specific ops */
    parser_ops = &session->p_ops->parser_ops;
    parser_ops->handler = fsm_demo_plugin_handler;

    /* Wrap up the session initialization */
    fsm_demo_session->session = session;

    /* Allocate flow samples aggregator */
    fsm_demo_session->aggr = fsm_demo_alloc_aggr(fsm_demo_session);
    if (fsm_demo_session->aggr == NULL) goto err_alloc_aggr;

    rc = net_md_activate_window(fsm_demo_session->aggr);
    if (!rc)
    {
        LOGE("%s: failed to activate aggregator", __func__);
        goto err_alloc_aggr;
    }
    ds_tree_init(&fsm_demo_session->session_devices, fsm_demo_dev_id_cmp,
                 struct fsm_demo_device, device_node);
    fsm_demo_session->initialized = true;
    LOGD("%s: added session %s", __func__, session->name);

    return 0;

err_alloc_aggr:
    fsm_demo_free_session(fsm_demo_session);
    return -1;
}

/**
 * @brief session exit point
 *
 * Frees up resources used by the session.
 * @param session pointer provided by fsm
 */
void
fsm_demo_plugin_exit(struct fsm_session *session)
{
    struct fsm_demo_plugin_cache *mgr;

    mgr = fsm_demo_get_mgr();
    if (!mgr->initialized) return;

    fsm_demo_delete_session(session);
    return;
}


/**
 * @brief session packet processing entry point
 *
 * packet processing handler.
 * @param args the fsm session
 * @param h the pcap capture header
 * @param bytes a pointer to the captured packet
 */
void
fsm_demo_plugin_handler(struct fsm_session *session,
                        struct net_header_parser *net_parser)
{
    struct fsm_demo_session *f_session;
    struct fsm_demo_parser *parser;
    size_t len;

    f_session = (struct fsm_demo_session *)session->handler_ctxt;
    parser = &f_session->parser;
    parser->net_parser = net_parser;

    len = fsm_demo_parse_message(parser);
    if (len == 0) return;

    fsm_demo_process_message(f_session);

    return;
}


/**
 * @brief parses the received message
 *
 * @param parser the parsed data container
 * @return the size of the parsed message, or 0 on parsing error.
 */
size_t
fsm_demo_parse_message(struct fsm_demo_parser *parser)
{
    struct net_header_parser *net_parser;
    size_t len;

    if (parser == NULL) return 0;

    /* Parse network header */
    net_parser = parser->net_parser;
    parser->parsed = net_parser->parsed;
    parser->data = net_parser->data;

    /* Adjust payload length to remove potential ethernet padding */
    parser->data_len = net_parser->packet_len - net_parser->parsed;

    /* Parse the message content */
    len = fsm_demo_parse_content(parser);

    return len;
}


/**
 * @brief parses the received message content
 *
 * @param parser the parsed data container
 * @return the size of the parsed message content, or 0 on parsing error.
 */
size_t
fsm_demo_parse_content(struct fsm_demo_parser *parser)
{
    /*
     * Place holder to process the packet content after the network header
     */
    return parser->parsed;
}

void
fsm_demo_alloc_flow_tag(struct flow_tags *tag, char *flow_proto)
{
    tag->vendor = strdup("Plume");
    if (tag->vendor == NULL) return;

    tag->app_name = strdup("Plume App");
    if (tag->app_name == NULL) goto err_free_vendor;

    tag->nelems = 2;
    tag->tags = CALLOC(tag->nelems, sizeof(tag->tags));
    tag->tags[0] = strdup(flow_proto);
    if (tag->tags[0] == NULL) goto err_free_tag_tags;

    tag->tags[1] = strdup("Plume Tag1");
    if (tag->tags[1] == NULL) goto err_free_tag_tags_0;

    return;

err_free_tag_tags_0:
    FREE(tag->tags[0]);

err_free_tag_tags:
    FREE(tag->tags);

err_free_app_name:
    FREE(tag->app_name);

err_free_vendor:
    FREE(tag->vendor);

}


void fsm_demo_app_detector(struct net_header_parser *net_parser, struct net_md_flow_key *key)
{
    char *flow_stream = NULL;

    if (key->ipprotocol == IPPROTO_UDP)
        flow_stream = "UDP Flow";
    else if (key->ipprotocol == IPPROTO_TCP)
        flow_stream = "TCP Flow";
    else
       flow_stream = "Not identified flow";

    fsm_demo_alloc_flow_tag(&net_parser->tags, flow_stream);
    // Application is detected ino need furthur packets
    net_parser->flow_action = FLOW_PASSTHROUGH;
}

void fsm_demo_flow_analyser(struct net_header_parser *net_parser, struct net_md_flow_key *key)
{
    struct in_addr addr;
    int ret;

    // For demo purpose one IP is used for Blacklisting.
    ret = inet_pton(AF_INET, BLOCKED_IP_ADDR, &addr.s_addr);
    if (ret <= 0)
    {
        net_parser->tags.nelems = 0;
        return;
    }
    /*
     * All new IP flows will be inspected/tapped using the ovs-conntrack
     * rules that are configured in pod using script - create_fsm_demo_dpi.sh
     * Check the destination ip of flow
     * against blocked ip. If true block the flow.
     * If false don't inspect the furthur packets
     * in the flow, just passthrough it (i.e. not tapped).
     */
    if ((*((uint32_t *)key->src_ip) == addr.s_addr) ||
       (*((uint32_t *)key->dst_ip) == addr.s_addr))
    {
        LOGD("*************Blocked IP Matches *****************");
        /*
         * Restrict Internet access based on BLOCKED_IP_ADDR
         * BLOCKED_IP_ADDR is created as static - mail.yahoo.com
         * When a wireless client tries to access BLOCKED_IP_ADDR
         * for e.g. "curl mail.yahoo.com" it will get blocked
         * FSM_DPI_API supports three states as follows:-
         * FSM_DPI_INSPECT - All new ip flow  will be inspected and tapped.
         * FSM_DPI_PASSTHRU - Used to bypass inspection of a 5tuple flow.
         * FSM_DPI_DROP - Used to block the traffic of a 5tuple flow.
         * In the example access to mail.yahoo.com is blocked.
         */
        net_parser->flow_action = FLOW_DROP;
        net_parser->tags.nelems = 0;
    }
    else
    {
        LOGD("IP Flow having good reputation detecting the application");
        fsm_demo_app_detector(net_parser, key);
    }
}

/**
 * @brief process the parsed message
 *
 * Prepare a key to lookup the flow stats info, and update the flow stats.
 * @param f_session the demo session pointing to the parsed message
 */
void
fsm_demo_process_message(struct fsm_demo_session *f_session)
{
    struct net_header_parser *net_parser;
    struct net_md_stats_accumulator *acc;
    struct fsm_demo_parser *parser;
    struct flow_counters counters;
    struct fsm_session *session;
    struct flow_tags **key_tags;
    struct eth_header *eth_hdr;
    struct net_md_flow_key key;
    struct flow_key *fkey;
    struct flow_tags *tag;
    char *report;

    parser = &f_session->parser;
    net_parser = parser->net_parser;
    eth_hdr = &net_parser->eth_header;

    session = f_session->session;
    report = demo_jencode_demo_event(session);
    session->ops.send_report(session, report);

    memset(&key, 0, sizeof(key));
    key.smac = eth_hdr->srcmac;
    key.dmac = eth_hdr->dstmac;
    key.vlan_id = eth_hdr->vlan_id;
    key.ethertype = eth_hdr->ethertype;

    /* Only care about ipv4 traffic in the context of this demo */
    key.ip_version = net_parser->ip_version;
    if (key.ip_version != 4) return;

    if (key.ip_version == 4)
    {
        struct iphdr * iphdr;

        iphdr = net_header_get_ipv4_hdr(net_parser);
        key.src_ip = (uint8_t *)(&iphdr->saddr);
        key.dst_ip = (uint8_t *)(&iphdr->daddr);
    }
    key.ipprotocol = net_parser->ip_protocol;
    if (key.ipprotocol == IPPROTO_UDP)
    {
        struct udphdr *udphdr;

        udphdr = net_parser->ip_pld.udphdr;
        key.sport = udphdr->source;
        key.dport = udphdr->dest;
    }
    else if (key.ipprotocol == IPPROTO_TCP)
    {
        struct tcphdr *tcphdr;

        tcphdr = net_parser->ip_pld.tcphdr;
        key.sport = tcphdr->source;
        key.dport = tcphdr->dest;
    }
    /* Demo application detector */
    fsm_demo_flow_analyser(net_parser, &key);
    switch (net_parser->flow_action)
    {
        case FLOW_INSPECT:
            // Already we are in INSPECT state do nothing
            LOGD("%s:"
                 "Need more packets either to determine IP flow reputation"
                 "or app detection",
                 __func__);
        break;

        case FLOW_PASSTHROUGH:
            fsm_set_dpi_mark(net_parser, FSM_DPI_PASSTHRU);
            LOGD("%s: Application is detected", __func__);
        break;

        case FLOW_DROP:
            fsm_set_dpi_mark(net_parser, FSM_DPI_DROP);
            LOGD("%s: IP flow is blocked", __func__);
        break;

        case FLOW_NA:
        default:
            LOGE("%s: Unknown flow action", __func__);
            return;
        break;
    }

    memset(&counters, 0, sizeof(counters));
    counters.packets_count = 1;
    counters.bytes_count = net_parser->packet_len;

    /* Add the stats sample */
    net_md_add_sample(f_session->aggr, &key, &counters);

    /* Add a flow tag */
    acc = net_md_lookup_acc(f_session->aggr, &key);
    if (acc == NULL) return;

    /* Access the flow report key */
    fkey = acc->fkey;
    if (fkey == NULL) return;

    /* Free the existing flow tag for demo simplicity */
    free_flow_key_tags(fkey);

    /* Update the flow tags */
    if (net_parser->tags.nelems > 0)
    {
        // Application is detected and app tag is present


        /* Allocate one key tag container */
        key_tags = CALLOC(1, sizeof(*key_tags));

        /* Allocate the one flow tag container the key will carry */
        tag = CALLOC(1, sizeof(*tag));

        // net_parser.tags contains detected application tags
        *tag = net_parser->tags;
        (*key_tags) = tag;
        fkey->tags = key_tags;
        fkey->num_tags = 1;
    }
    else
    {
        // No app tags present - application is still in INSPECT state
        fkey->tags = NULL;
        fkey->num_tags = 0;
    }

    return;
err_free_key_tags:
    FREE(key_tags);
}


/**
 * @brief session packet periodic processing entry point
 *
 * Periodically called by the fsm manager
 * Sends a flow stats report.
 * @param session the fsm session
 */
void
fsm_demo_plugin_periodic(struct fsm_session *session)
{
    struct fsm_demo_session *f_session;
    struct net_md_aggregator *aggr;
    struct flow_window **windows;
    struct flow_window *window;
    struct flow_report *report;

    if (session->topic == NULL) return;

    f_session = session->handler_ctxt;
    aggr = f_session->aggr;
    report = aggr->report;

    /* Close the flows observation window */
    net_md_close_active_window(aggr);

    /* Check if the report is worth sending - ie did it get any flow stats ? */
    windows = report->flow_windows;
    window = *windows;

    if (window->num_stats != 0) net_md_send_report(aggr, session->topic);
    else net_md_reset_aggregator(aggr);

    /* Activate the observation window */
    net_md_activate_window(aggr);
}


/**
 * @brief looks up a session
 *
 * Looks up a session, and allocates it if not found.
 * @param session the session to lookup
 * @return the found/allocated session, or NULL if the allocation failed
 */
struct fsm_demo_session *
fsm_demo_lookup_session(struct fsm_session *session)
{
    struct fsm_demo_plugin_cache *mgr;
    struct fsm_demo_session *f_session;
    ds_tree_t *sessions;

    mgr = fsm_demo_get_mgr();
    sessions = &mgr->fsm_sessions;

    f_session = ds_tree_find(sessions, session);
    if (f_session != NULL) return f_session;

    LOGD("%s: Adding new session %s", __func__, session->name);
    f_session = CALLOC(1, sizeof(struct fsm_demo_session));

    ds_tree_insert(sessions, f_session, session);

    return f_session;
}

/**
 * @brief looks up a device in the device cache
 *
 * @param f_session the fsm demo session
 * @return the device context if found, NULL otherwise
 */
struct fsm_demo_device *
fsm_demo_lookup_device(struct fsm_demo_session *f_session)
{
    struct fsm_demo_parser *parser;
    struct net_header_parser *net_parser;
    struct eth_header *eth;
    struct fsm_demo_device *fdev;
    ds_tree_t *tree;

    if (f_session == NULL) return NULL;

    parser = &f_session->parser;
    net_parser = parser->net_parser;
    eth = &net_parser->eth_header;
    tree = &f_session->session_devices;
    fdev = ds_tree_find(tree, eth->srcmac);

    return fdev;
}


/**
 * @brief looks up or allocate a device for the fsm demo session's device cache
 *
 * @param f_session the fsm demo session
 * @return the device context if found or allocated, NULL otherwise
 */
struct fsm_demo_device *
fsm_demo_get_device(struct fsm_demo_session *f_session)
{
    struct fsm_demo_device *fdev;
    struct fsm_demo_parser *parser;
    struct net_header_parser *net_parser;
    struct eth_header *eth;
    ds_tree_t *tree;

    if (f_session == NULL) return NULL;

    fdev = fsm_demo_lookup_device(f_session);
    if (fdev != NULL) return fdev;

    /* No match, allocate a new entry */
    parser = &f_session->parser;
    net_parser = parser->net_parser;
    eth = &net_parser->eth_header;
    fdev = CALLOC(1, sizeof(*fdev));

    memcpy(&fdev->device_mac, eth->srcmac, sizeof(os_macaddr_t));

    tree = &f_session->session_devices;
    ds_tree_insert(tree, fdev, &fdev->device_mac);

    return fdev;
}


/**
 * @brief frees a fsm demo device
 *
 * @param hdev the fsm demo device to delete
 */
void
fsm_demo_free_device(struct fsm_demo_device *fdev)
{
    FREE(fdev);
}


/**
 * @brief Frees a fsm demo session
 *
 * @param f_session the fsm demo session to delete
 */
void
fsm_demo_free_session(struct fsm_demo_session *f_session)
{
    struct fsm_demo_device *fdev, *remove;
    ds_tree_t *tree;

    tree = &f_session->session_devices;
    fdev = ds_tree_head(tree);
    while (fdev != NULL)
    {
        remove = fdev;
        fdev = ds_tree_next(tree, fdev);
        ds_tree_remove(tree, remove);
        fsm_demo_free_device(remove);
    }

    net_md_free_aggregator(f_session->aggr);
    FREE(f_session->aggr);
    FREE(f_session);
}


/**
 * @brief deletes a session
 *
 * @param session the fsm session keying the http session to delete
 */
void
fsm_demo_delete_session(struct fsm_session *session)
{
    struct fsm_demo_plugin_cache *mgr;
    struct fsm_demo_session *f_session;
    ds_tree_t *sessions;

    mgr = fsm_demo_get_mgr();
    sessions = &mgr->fsm_sessions;

    f_session = ds_tree_find(sessions, session);
    if (f_session == NULL) return;

    LOGD("%s: removing session %s", __func__, session->name);
    ds_tree_remove(sessions, f_session);
    fsm_demo_free_session(f_session);

    return;
}

/**
 * @brief get current time in cloud accepted format
 *
 * Formats the current time in the cloud accepted format:
 * yyyy-mm-ddTHH:MM:SS.mmmZ.
 * @params time_str input string which will store the timestamp
 * @params size: input string size
 */
static void
demo_json_mqtt_curtime(char *time_str, size_t size)
{
    struct timeval tv;
    struct tm *tm ;
    char tstr[50];

    gettimeofday(&tv, NULL);
    tm = gmtime(&tv.tv_sec);
    strftime(tstr, sizeof(tstr), "%FT%T", tm);
    snprintf(time_str, size, "%s.%03dZ", tstr, (int)(tv.tv_usec / 1000));
}


/**
 * @brief encode a demo report in json format
 *
 * Returns a pointer to a string string json encoded information.
 * The caller needs to free the pointer through a json_free() call.
 * @param session fsm session storing the header information
 * @param to_report http user agent information to report
 */
char *
demo_jencode_demo_event(struct fsm_session *session)
{
    json_t *json_report, *body_envelope, *body;
    char *json_msg = NULL;
    bool ready;

    ready = demo_jcheck_header_info(session);
    if (ready == false) return NULL;

    json_report  = json_object();
    body_envelope = json_array();
    body = json_object();

    /* Encode header */
    demo_jencode_header(session, json_report);

    /* Encode body */
    json_object_set_new(body, "whatHappened", json_string("processed a packet"));

    /* Encode body envelope */
    json_array_append_new(body_envelope, body);
    json_object_set_new(json_report, "demoEvents", body_envelope);

    /* Convert json object in a compact string */
    json_msg = json_dumps(json_report, JSON_COMPACT);
    json_decref(json_report);

    return json_msg;
}


/**
 * @brief checks that a session has all the info to report through mqtt
 *
 * Validates that mqtt topics and location/node ids have been set
 * @param session fsm session storing the header information
 */
bool
demo_jcheck_header_info(struct fsm_session *session)
{
    if (session->topic == NULL) return false;
    if (session->location_id == NULL) return false;
    if (session->node_id == NULL) return false;

    return true;
}

/**
 * @brief encode the header section of a message
 *
 * Fills up the header section of a json formatted mqtt report
 * @param json_report json object getting filled
 * @param session fsm session storing the header information
 */
void
demo_jencode_header(struct fsm_session *session, json_t *json_report)
{
    char *version = "X.X.X";
    char *str = NULL;
    char time_str[128] = { 0 };

    /* Encode mqtt headers section */
    str = session->location_id;
    json_object_set_new(json_report, "locationId", json_string(str));
    str = session->node_id;
    json_object_set_new(json_report, "nodeId", json_string(str));

    /* Encode version */
    json_object_set_new(json_report, "version", json_string(version));

    /* Encode report time */
    demo_json_mqtt_curtime(time_str, sizeof(time_str));
    json_object_set_new(json_report, "reportedAt", json_string(time_str));
}
