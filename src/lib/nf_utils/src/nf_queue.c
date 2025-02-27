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

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <arpa/inet.h>
#include <errno.h>
#include <net/if.h>
#include <libmnl/libmnl.h>
#include <linux/if_link.h>
#include <linux/rtnetlink.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <linux/netfilter.h>
#include <linux/netfilter/nfnetlink.h>
#include <linux/netfilter/nfnetlink_queue.h>
#include <linux/netfilter/nfnetlink_conntrack.h>
#include <linux/netfilter/nf_conntrack_common.h>

#include "log.h"
#include "neigh_table.h"
#include "nf_utils.h"
#include "os_types.h"
#include "memutil.h"

static struct nf_queue_context
nfq_context =
{
    .initialized = false,
};

struct nf_queue_context *
nf_queue_get_context(void)
{
    return &nfq_context;
}

static const char *
nf_ct_mark_str(uint8_t mark)
{
    static char buf[256];

    if (mark == CT_MARK_INSPECT)
    {
        sprintf(buf, "%d %s", mark, "Inspect");
    }
    else
    {
        sprintf(buf, "%d %s", mark, (mark == CT_MARK_DROP ? "Drop" : "Allow"));
    }

    return buf;
}

static int
nf_queue_parse_attr_cb(const struct nlattr *attr, void *data)
{
    struct nfq_pkt_info *pi = (struct nfq_pkt_info *)data;
    struct nfqnl_msg_packet_hdr *ph;
    int type = mnl_attr_get_type(attr);
    int rc;

    /* skip unsupported attribute in user-space */
    if (mnl_attr_type_valid(attr, NFQA_MAX) < 0)
        return MNL_CB_OK;

    switch(type)
    {
    case NFQA_MARK:
        break;
    case NFQA_IFINDEX_INDEV:
        rc = mnl_attr_validate(attr, MNL_TYPE_U32);
        if (rc < 0)
        {
            LOGE("%s: mnl_attr_validate failed", __func__);
            return MNL_CB_ERROR;
        }
        pi->rx_vidx = ntohl(mnl_attr_get_u32(attr));
        break;
    case NFQA_IFINDEX_OUTDEV:
        rc = mnl_attr_validate(attr, MNL_TYPE_U32);
        if (rc < 0)
        {
            LOGE("%s: mnl_attr_validate failed", __func__);
            return MNL_CB_ERROR;
        }
        pi->tx_vidx = ntohl(mnl_attr_get_u32(attr));
        break;
    case NFQA_IFINDEX_PHYSINDEV:
        rc = mnl_attr_validate(attr, MNL_TYPE_U32);
        if (rc < 0)
        {
            LOGE("%s: mnl_attr_validate failed", __func__);
            return MNL_CB_ERROR;
        }
        pi->rx_pidx = ntohl(mnl_attr_get_u32(attr));
        break;
    case NFQA_IFINDEX_PHYSOUTDEV:
        rc = mnl_attr_validate(attr, MNL_TYPE_U32);
        if (rc < 0)
        {
            LOGE("%s: mnl_attr_validate failed", __func__);
            return MNL_CB_ERROR;
        }
        pi->tx_pidx = ntohl(mnl_attr_get_u32(attr));
        break;
    case NFQA_TIMESTAMP:
        rc = mnl_attr_validate2(attr, MNL_TYPE_UNSPEC,
                                sizeof(struct nfqnl_msg_packet_timestamp));
        if (rc < 0)
        {
            LOGE("%s: mnl_attr_validate2 failed", __func__);
            return MNL_CB_ERROR;
        }
        break;
    case NFQA_HWADDR:
        rc = mnl_attr_validate2(attr, MNL_TYPE_UNSPEC,
                                sizeof(struct nfqnl_msg_packet_hw));
        if (rc < 0)
        {
            LOGE("%s: mnl_attr_validate2 failed", __func__);
            return MNL_CB_ERROR;
        }
        pi->hw_addr = mnl_attr_get_payload(attr);
        break;
    case NFQA_PAYLOAD:
        pi->payload = mnl_attr_get_payload(attr);
        pi->payload_len = mnl_attr_get_payload_len(attr);
        break;
    case NFQA_PACKET_HDR:
        ph = mnl_attr_get_payload(attr);
        pi->packet_id = ntohl(ph->packet_id);
        pi->hw_protocol = ntohs(ph->hw_protocol);
        break;
    }

    return MNL_CB_OK;
}


static int
nf_queue_cb(const struct nlmsghdr *nlh, void *data)
{
    struct nfqueue_ctxt *nfq;
    struct nfq_pkt_info *pkt_info;
    int ret;

    nfq = (struct nfqueue_ctxt *)data;
    pkt_info = &nfq->pkt_info;
    ret = mnl_attr_parse(nlh, sizeof(struct nfgenmsg), nf_queue_parse_attr_cb, pkt_info);
    if (ret == MNL_CB_ERROR) return MNL_CB_ERROR;

    /* Default mark is Inspect */
    pkt_info->flow_mark = CT_MARK_INSPECT;
    pkt_info->queue_num = nfq->queue_num;

    if (nfq->nfq_cb) nfq->nfq_cb(pkt_info, nfq->user_data);

    return MNL_CB_OK;
}


static struct nlmsghdr *
nf_queue_set_nlh_request(char *buf, uint8_t type, uint32_t queue_num)
{
    struct nlmsghdr *nlh;
    struct nfgenmsg *nfg;

    if (!buf) return NULL;

    nlh = mnl_nlmsg_put_header(buf);
    nlh->nlmsg_type = (NFNL_SUBSYS_QUEUE << 8) | type;
    nlh->nlmsg_flags = NLM_F_REQUEST;

    nfg = mnl_nlmsg_put_extra_header(nlh, sizeof(*nfg));
    nfg->nfgen_family = AF_UNSPEC;
    nfg->version = NFNETLINK_V0;
    nfg->res_id = htons(queue_num);

    return nlh;
}


static void
nf_queue_send_nlh_request(struct nlmsghdr *nlh, uint8_t cfg_type,
                          void *cmd_opts, struct nfqueue_ctxt *nfq)
{
    struct nf_queue_context *ctxt;
    uint32_t *queue_maxlen;
    int ret;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return;

    switch (cfg_type)
    {
    case NFQA_CFG_CMD:
        mnl_attr_put(nlh, NFQA_CFG_CMD,
                     sizeof(struct nfqnl_msg_config_cmd), cmd_opts);
        break;

    case NFQA_CFG_PARAMS:
        mnl_attr_put(nlh, NFQA_CFG_PARAMS,
                     sizeof(struct nfqnl_msg_config_params), cmd_opts);

        /* Set flag NFQA_CFG_F_FAIL_OPEN for accepting packets by kernel when queue full*/
        mnl_attr_put_u32(nlh, NFQA_CFG_FLAGS, htonl(NFQA_CFG_F_FAIL_OPEN));
        mnl_attr_put_u32(nlh, NFQA_CFG_MASK, htonl(NFQA_CFG_F_FAIL_OPEN));

        /* Avoid receiving fragmented packets to the QUEUE*/
        mnl_attr_put_u32(nlh, NFQA_CFG_FLAGS, htonl(NFQA_CFG_F_GSO));
        mnl_attr_put_u32(nlh, NFQA_CFG_MASK, htonl(NFQA_CFG_F_GSO));

        /* Get/Set conntrack info through NFQUEUE.*/
        mnl_attr_put_u32(nlh, NFQA_CFG_FLAGS, htonl(NFQA_CFG_F_CONNTRACK));
        mnl_attr_put_u32(nlh, NFQA_CFG_MASK, htonl(NFQA_CFG_F_CONNTRACK));

        break;

    case NFQA_CFG_QUEUE_MAXLEN:
        queue_maxlen = (uint32_t *)cmd_opts;
        mnl_attr_put_u32(nlh, NFQA_CFG_QUEUE_MAXLEN, htonl(*queue_maxlen));
        break;

     default:
        break;
    }

    ret = mnl_socket_sendto(nfq->nfq_mnl, nlh, nlh->nlmsg_len);
    if (ret == -1)
    {
        LOGE("%s: Failed to send nfq command type:[%d] ",__func__,cfg_type);
    }

    return;
}

static void
nf_queue_send_verdict(struct nfqnl_msg_verdict_hdr *vhdr,
                      uint32_t queue_num)
{
    struct nf_queue_context *ctxt;
    struct nfqueue_ctxt nfq_lkp;
    struct nfqueue_ctxt *nfq;
    struct nfq_pkt_info *pkt_info;
    struct nlattr *nest;
    int ret;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return;

    memset(&nfq_lkp, 0, sizeof(struct nfqueue_ctxt));
    nfq_lkp.queue_num = queue_num;
    nfq = ds_tree_find(&ctxt->nfq_tree, &nfq_lkp);
    if (nfq == NULL) return;

    pkt_info = &nfq->pkt_info;


    /*
    * We always pass verdict as accept,
    * however we just mark the conntrack entry
    * either to 2 or 3.This will make sure that the conntrack
    * entry is active and OVS can take
    * the appropriate action.
    */
    vhdr->verdict = htonl(NF_ACCEPT);

    mnl_attr_put(nfq->nlh, NFQA_VERDICT_HDR, sizeof(struct nfqnl_msg_verdict_hdr), vhdr);

    LOGT("%s(): conntrack mark set to %s", __func__, nf_ct_mark_str(pkt_info->flow_mark));
    nest = mnl_attr_nest_start(nfq->nlh, NFQA_CT);
    mnl_attr_put_u32(nfq->nlh, CTA_MARK, htonl(pkt_info->flow_mark));
    mnl_attr_nest_end(nfq->nlh, nest);

    ret = mnl_socket_sendto(nfq->nfq_mnl, nfq->nlh, nfq->nlh->nlmsg_len);
    if (ret == -1)
    {
        LOGE("%s: Failed to send verdict for packet_id[%d]",__func__,ntohl(vhdr->id));
    }
    return;
}

/**
 * @brief ev callback to nfq events
 */
static void
nf_queue_read_mnl_cbk(EV_P_ ev_io *ev, int revents)
{
    struct nf_queue_context *ctxt;
    struct nfq_pkt_info *pkt_info;
    struct nfqnl_msg_verdict_hdr vhdr;
    struct nfqueue_ctxt *nfq;
    char rcv_buf[0xFFFF];
    int portid = 0;
    int ret = 0;

    if (EV_ERROR & revents)
    {
        LOGE("%s: Invalid mnl socket event", __func__);
        return;
    }

    nfq = ev->data;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return;

    memset(&nfq->send_buf, 0, sizeof(nfq->send_buf));

    nfq->nlh = NULL;
    pkt_info = &nfq->pkt_info;

    ret = mnl_socket_recvfrom(nfq->nfq_mnl, rcv_buf, sizeof(rcv_buf));
    if (ret == -1)
    {
        LOGE("%s: mnl_socket_recvfrom failed: %s", __func__, strerror(errno));
        return;
    }

    nfq->nlh = nf_queue_set_nlh_request(nfq->send_buf, NFQNL_MSG_VERDICT, nfq->queue_num);

    portid = mnl_socket_get_portid(nfq->nfq_mnl);
    ret = mnl_cb_run(rcv_buf, ret, 0, portid, nf_queue_cb, nfq);
    if (ret == -1)
    {
        LOGE("%s: mnl_cb_run failed [%u]", __func__, errno);
        return;
    }

    /* TODO: Sending Batch verdict is efficient */
    memset(&vhdr, 0, sizeof(struct nfqnl_msg_verdict_hdr));
    vhdr.id = htonl(pkt_info->packet_id);

    nf_queue_send_verdict(&vhdr, nfq->queue_num);

    return;
}

bool
nf_queue_open(struct nfq_settings *nfq_set)
{
    struct nf_queue_context *ctxt;
    char buf[MNL_SOCKET_BUFFER_SIZE];
    struct mnl_socket *nl;
    struct nlmsghdr *nlh;
    struct nfqnl_msg_config_cmd cmd;
    struct nfqnl_msg_config_params params;
    struct nfqueue_ctxt *nfq;
    int ret;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return false;

    nfq = CALLOC(1, sizeof(struct nfqueue_ctxt));
    if (nfq == NULL)
    {
        LOGE("%s: Couldn't allocate memory for nfqueue entry", __func__);
        return false;
    }

    nfq->loop = nfq_set->loop;
    nfq->nfq_cb = nfq_set->nfq_cb;
    nfq->queue_num = nfq_set->queue_num;
    nfq->user_data = nfq_set->data;

    LOGI("%s: Starting nfqueue[%d] ", __func__, nfq->queue_num);

    nl = mnl_socket_open(NETLINK_NETFILTER);
    if (nl == NULL)
    {
        LOGE("%s: mnl_socket_open failed", __func__);
        goto err_free_nfq;
    }

    ret = mnl_socket_bind(nl, 0, MNL_SOCKET_AUTOPID);
    if (ret != 0)
    {
        LOGE("%s: mnl_socket_bind failed", __func__);
        goto err_mnl_sock;
    }
    nfq->nfq_mnl = nl;

    nlh = nf_queue_set_nlh_request(buf, NFQNL_MSG_CONFIG, nfq->queue_num);

    /* Bind for packets.*/
    memset(&cmd, 0, sizeof(struct nfqnl_msg_config_cmd));
    cmd.command = NFQNL_CFG_CMD_BIND;
    cmd.pf = htons(AF_INET);
    nf_queue_send_nlh_request(nlh, NFQA_CFG_CMD, &cmd, nfq);

    nlh = nf_queue_set_nlh_request(buf, NFQNL_MSG_CONFIG, nfq->queue_num);
    /* Set config params. */
    memset(&params, 0, sizeof(struct nfqnl_msg_config_params));
    params.copy_range = htonl(0xFFFF);
    params.copy_mode = NFQNL_COPY_PACKET;
    nf_queue_send_nlh_request(nlh, NFQA_CFG_PARAMS, &params, nfq);

    nfq->nfq_fd = mnl_socket_get_fd(nfq->nfq_mnl);
    ev_io_init(&nfq->nfq_io_mnl, nf_queue_read_mnl_cbk, nfq->nfq_fd, EV_READ);

    nfq->nfq_io_mnl.data = (void *)nfq;

    ev_io_start(nfq->loop, &nfq->nfq_io_mnl);

    ds_tree_insert(&ctxt->nfq_tree, nfq, nfq);

    return true;

err_mnl_sock:
    mnl_socket_close(nl);

err_free_nfq:
    FREE(nfq);

    return false;
}


/**
 * @brief set max socket buffer size of netlink.
 *
 * @param sock_buff_sz
 * @return 0 if the nfqueue initialization successful, -1 otherwise
 */
bool
nf_queue_set_nlsock_buffsz(uint32_t queue_num, uint32_t sock_buff_sz)
{
    struct nf_queue_context *ctxt;
    struct nfqueue_ctxt nfq_lkp;
    struct nfqueue_ctxt *nfq;
    int ret;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return false;

    memset(&nfq_lkp, 0, sizeof(struct nfqueue_ctxt));
    nfq_lkp.queue_num = queue_num;
    nfq = ds_tree_find(&ctxt->nfq_tree, &nfq_lkp);
    if (nfq == NULL) return false;

    ret = setsockopt(nfq->nfq_fd, SOL_SOCKET,
                     SO_RCVBUFFORCE, &sock_buff_sz,
                     sizeof(sock_buff_sz));
    if (ret == -1)
    {
        LOGE("%s: Failed to set nfq socket buff size to %u: error[%s]",
              __func__, sock_buff_sz, strerror(errno));
        return false;
    }

    return true;
}


/**
 * @brief set max length of nfqueues.
 *
 * @param queue length
 * @return 0 if the nfqueue initialization successful, -1 otherwise
 */
bool
nf_queue_set_queue_maxlen(uint32_t queue_num, uint32_t queue_maxlen)
{
    struct nf_queue_context *ctxt;
    struct nfqueue_ctxt nfq_lkp;
    struct nfqueue_ctxt *nfq;
    struct nlmsghdr *nlh;
    char buf[MNL_SOCKET_BUFFER_SIZE];

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return false;

    memset(&nfq_lkp, 0, sizeof(struct nfqueue_ctxt));
    nfq_lkp.queue_num = queue_num;
    nfq = ds_tree_find(&ctxt->nfq_tree, &nfq_lkp);
    if (nfq == NULL) return false;

    nlh = nf_queue_set_nlh_request(buf, NFQNL_MSG_CONFIG, nfq->queue_num);
    nf_queue_send_nlh_request(nlh, NFQA_CFG_QUEUE_MAXLEN, &queue_maxlen, nfq);

    return true;
}

static int
nfq_cmp(const void *_a, const void *_b)
{
    const struct nfqueue_ctxt *a = (const struct nfqueue_ctxt *)_a;
    const struct nfqueue_ctxt *b = (const struct nfqueue_ctxt *)_b;

    return (a->queue_num - b->queue_num);
}

/**
 * @brief initialize nfqueues
 *
 * @param struct nfq_settings.
 * @return 0 if the nfqueue initialization successful, -1 otherwise
 */
bool
nf_queue_init()
{
    struct nf_queue_context *ctxt;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized) return true;

    ds_tree_init(&ctxt->nfq_tree, nfq_cmp,
                 struct nfqueue_ctxt, nfq_tnode);

    ctxt->initialized = true;
    return true;
}

void nf_queue_close(uint32_t queue_num)
{
    char buf[MNL_SOCKET_BUFFER_SIZE];
    struct nf_queue_context *ctxt;
    struct nfqnl_msg_config_cmd cmd;
    struct nfqueue_ctxt nfq_lkp;
    struct nlmsghdr *nlh;
    struct nfqueue_ctxt *nfq;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return;

    memset(&nfq_lkp, 0, sizeof(struct nfqueue_ctxt));
    nfq_lkp.queue_num = queue_num;
    nfq = ds_tree_find(&ctxt->nfq_tree, &nfq_lkp);
    if (nfq == NULL) return;

    if (nfq->nfq_mnl == NULL) return;

    nlh = nf_queue_set_nlh_request(buf, NFQNL_MSG_CONFIG, nfq->queue_num);

    /* UnBind for packets.*/
    memset(&cmd, 0, sizeof(struct nfqnl_msg_config_cmd));
    cmd.command = NFQNL_CFG_CMD_UNBIND;
    cmd.pf = htons(AF_INET);
    nf_queue_send_nlh_request(nlh, NFQA_CFG_CMD, &cmd, nfq);

    if (ev_is_active(&nfq->nfq_io_mnl))
    {
        ev_io_stop(nfq->loop, &nfq->nfq_io_mnl);
    }

    mnl_socket_close(nfq->nfq_mnl);
    ds_tree_remove(&ctxt->nfq_tree, nfq);
    FREE(nfq);

    return;
}

/**
 *
 * @brief free allocated nfqueue resources
 */
void
nf_queue_exit(void)
{
    struct nf_queue_context *ctxt;
    struct nfqueue_ctxt *nfq_entry, *nfq_next;
    ds_tree_t *tree;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return;

    tree = &ctxt->nfq_tree;
    nfq_entry = ds_tree_head(tree);
    while (nfq_entry != NULL)
    {
        nfq_next = ds_tree_next(tree, nfq_entry);
        LOGI("%s : closing nfqueue[%d]", __func__, nfq_entry->queue_num);
        nf_queue_close(nfq_entry->queue_num);

        nfq_entry = nfq_next;
    }

    ctxt->initialized = false;

    return;
}


/**
 *
 * @brief  Set mark for given pktid.
 * mark 1 - INSPECT,
 * mark 2 - ALLOW
 * mark 3 - BLOCK
 */
bool
nf_queue_set_ct_mark(uint32_t packet_id, int mark, uint32_t queue_num)
{
    struct nf_queue_context  *ctxt;
    struct nfq_pkt_info *pkt_info;
    struct nfqueue_ctxt nfq_lkp;
    struct nfqueue_ctxt *nfq;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return false;

    memset(&nfq_lkp, 0, sizeof(struct nfqueue_ctxt));
    nfq_lkp.queue_num = queue_num;
    nfq = ds_tree_find(&ctxt->nfq_tree, &nfq_lkp);
    if (nfq == NULL) return false;

    pkt_info = &nfq->pkt_info;
    if (pkt_info->packet_id != packet_id) return false;

    pkt_info->flow_mark = mark;

    LOGD("%s: Setting flow_mark for packet_id[%d] of queue[%d] to %d",
         __func__, packet_id, queue_num, pkt_info->flow_mark);

    return true;
}


/**
 *
 * @brief update payload for given pktid.
 */
bool
nf_queue_update_payload(uint32_t packet_id, uint32_t queue_num)
{
    struct nf_queue_context  *ctxt;
    struct nfq_pkt_info *pkt_info;
    struct nfqueue_ctxt nfq_lkp;
    struct nfqueue_ctxt *nfq;

    ctxt = nf_queue_get_context();
    if (ctxt->initialized == false) return false;

    memset(&nfq_lkp, 0, sizeof(struct nfqueue_ctxt));
    nfq_lkp.queue_num = queue_num;
    nfq = ds_tree_find(&ctxt->nfq_tree, &nfq_lkp);
    if (nfq == NULL) return false;

    pkt_info = &nfq->pkt_info;
    if (pkt_info->packet_id != packet_id) return false;

    mnl_attr_put(nfq->nlh, NFQA_PAYLOAD, pkt_info->payload_len, pkt_info->payload);

    LOGD("%s: updated payload for packet_id[%d] of queue[%d]",
         __func__, packet_id, queue_num);
    return true;
}

int nf_queue_set_dpi_mark(struct net_header_parser *net_hdr, int mark)
{
    nf_queue_set_ct_mark(net_hdr->packet_id, mark, net_hdr->nfq_queue_num);
    return 0;
}
