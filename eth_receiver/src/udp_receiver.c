/******************************************************************************
 * Copyright (C) 2026. All Rights Reserved.
 *
 * Project: Star Tracker PS - AX7010 Zynq-7000
 * Component: eth_receiver
 * File: udp_receiver.c
 *
 * Description:
 *   Core UDP Receiver and State Echo implementation using lwIP RAW API.
 *   Receives datagrams on UDP_LISTEN_PORT, updates live program state,
 *   prints received content over UART, and transmits a state response
 *   packet back to the sender IP and port.
 ******************************************************************************/

#include "udp_receiver.h"
#include <stdio.h>
#include <string.h>
#include "lwip/err.h"
#include "lwip/pbuf.h"
#include "lwip/inet.h"
#include "xparameters.h"
#include "xllfifo.h"

#ifndef XPAR_AXI_FIFO_MM_S_0_BASEADDR
#ifdef XPAR_XLLFIFO_0_BASEADDR
#define XPAR_AXI_FIFO_MM_S_0_BASEADDR XPAR_XLLFIFO_0_BASEADDR
#else
#define XPAR_AXI_FIFO_MM_S_0_BASEADDR 0x43C00000
#endif
#endif

static XLlFifo g_fifo_inst;
static int g_fifo_ready = 0;

/* Static application state tracker */
static app_status_t g_app_status = {
    .state = APP_STATE_INIT,
    .rx_packet_count = 0,
    .tx_packet_count = 0,
    .last_rx_len = 0,
    .total_bytes_rx = 0
};

/* Global UDP Protocol Control Block */
static struct udp_pcb *g_udp_pcb = NULL;

/**
 * @brief  Helper to convert application state enum to string representation.
 */
static const char* app_state_to_str(app_state_t state)
{
    switch (state) {
        case APP_STATE_INIT:   return "INIT";
        case APP_STATE_IDLE:   return "IDLE_LISTENING";
        case APP_STATE_ACTIVE: return "ACTIVE_PROCESSING";
        case APP_STATE_ERROR:  return "ERROR";
        default:               return "UNKNOWN";
    }
}

/**
 * @brief  Initializes the AXI4-Stream FIFO hardware core using the standard xllfifo driver.
 */
static void init_axi_fifo(void)
{
    XLlFifo_Config *config;
    int status;

#ifdef SDT
    config = XLlFfio_LookupConfig(XPAR_AXI_FIFO_MM_S_0_BASEADDR);
#else
    config = XLlFfio_LookupConfig(0);
#endif

    if (config == NULL) {
        xil_printf("[FIFO] LookupConfig failed, initializing directly at 0x%08lX...\r\n",
                   (unsigned long)XPAR_AXI_FIFO_MM_S_0_BASEADDR);
        XLlFifo_Initialize(&g_fifo_inst, XPAR_AXI_FIFO_MM_S_0_BASEADDR);
    } else {
        status = XLlFifo_CfgInitialize(&g_fifo_inst, config, config->BaseAddress);
        if (status != XST_SUCCESS) {
            xil_printf("[FIFO] ERROR: XLlFifo_CfgInitialize failed (%d)\r\n", status);
            return;
        }
    }

    /* Clear any pending interrupts and reset FIFO channels */
    XLlFifo_IntClear(&g_fifo_inst, 0xFFFFFFFF);
    XLlFifo_Reset(&g_fifo_inst);
    g_fifo_ready = 1;
    xil_printf("[FIFO] AXI4-Stream FIFO initialized via xllfifo driver (Base: 0x%08x)\r\n",
               (unsigned int)g_fifo_inst.BaseAddress);
}

/**
 * @brief  Writes an incoming UDP pbuf payload into the AXI4-Stream FIFO using the driver API.
 */
/* Static frame tracking variables */
static int g_frame_lines = 0;
static int g_frame_count = 0;

/**
 * @brief  Writes an incoming UDP pbuf payload into the AXI4-Stream FIFO using the driver API.
 */
/**
 * @brief  Writes an incoming UDP pbuf payload into the AXI4-Stream FIFO using the driver API.
 */
static void axi_fifo_write_pbuf(struct pbuf *p)
{
    if (!g_fifo_ready || !p || p->tot_len == 0) {
        return;
    }

    /*
     * Note: Do NOT call XLlFifo_TxReset here. A hardware FIFO reset clears
     * the internal registers and drops the incoming 4-byte sync header!
     */

    /*
     * XLlFifo_TxVacancy() returns vacancy count in 32-bit words (not bytes).
     * Convert packet byte length into 32-bit words needed.
     */
    u32 words_needed = (p->tot_len + 3) / 4;
    u32 timeout = 50000;

    /*
     * Bounded wait for FIFO vacancy (~150 us max).
     * At 25 MHz pixel clock, one scanline (320 words) drains in ~57 us.
     */
    while ((XLlFifo_TxVacancy(&g_fifo_inst) < words_needed) && --timeout) {
    }

    if (timeout == 0) {
        /*
         * Dropped packet: do not spin forever in lwIP callback.
         * Returning allows udp_packet_callback to call pbuf_free(p),
         * keeping the GEM DMA RX descriptor ring healthy and unexhausted.
         */
        return;
    }

    /* Stream each pbuf segment into the transmit FIFO */
    struct pbuf *q;
    for (q = p; q != NULL; q = q->next) {
        XLlFifo_Write(&g_fifo_inst, q->payload, q->len);
    }

    /* Begin hardware transmission of the packet */
    XLlFifo_TxSetLen(&g_fifo_inst, p->tot_len);
}

/**
 * @brief  Asynchronous callback invoked by lwIP whenever a UDP packet
 *         is received matching our bound UDP port.
 */
static void udp_packet_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                                const ip_addr_t *addr, u16_t port)
{
    (void)arg;

    /* 1. Sanity check: Ensure packet buffer is valid */
    if (p == NULL) {
        return;
    }

    /* 2. Transition state to ACTIVE */
    g_app_status.state = APP_STATE_ACTIVE;
    g_app_status.rx_packet_count++;
    g_app_status.last_rx_len = p->tot_len;
    g_app_status.total_bytes_rx += p->tot_len;

    /* 3. Stream packet payload directly to AXI4-Stream FIFO */
    axi_fifo_write_pbuf(p);

    /* 4. Safe, non-blocking UART logging */
    if (p->tot_len == 4) {
        g_frame_lines = 0;
        g_frame_count++;
        xil_printf("\r\n========================================\r\n");
        xil_printf("[FRAME #%d START] Sync Header from %d.%d.%d.%d:%d\r\n",
                   g_frame_count,
                   (int)ip4_addr1(addr), (int)ip4_addr2(addr),
                   (int)ip4_addr3(addr), (int)ip4_addr4(addr),
                   (int)port);
        xil_printf("========================================\r\n");
    } else {
        g_frame_lines++;
        if ((g_frame_lines % 120) == 0) {
            xil_printf("[UDP RX] Frame #%d Line %d/480 (%d KB total)\r\n",
                       g_frame_count,
                       g_frame_lines,
                       (int)(g_app_status.total_bytes_rx / 1024));
        }
        if (g_frame_lines == 480) {
            xil_printf("[FRAME #%d DONE] 480/480 scanlines streamed to PL -> Display updated!\r\n",
                       g_frame_count);
        }
    }

    /* 5. Reply with Echo only on Frame Header to keep network fast */
    if (p->tot_len == 4) {
        char echo_buf[64];
        int echo_len = snprintf(echo_buf, sizeof(echo_buf),
                                "[FRAME_ACK] Frame Sync OK | TotalPkts: %d\r\n",
                                (int)g_app_status.rx_packet_count);
        if (echo_len > 0) {
            struct pbuf *p_reply = pbuf_alloc(PBUF_TRANSPORT, (u16_t)echo_len, PBUF_RAM);
            if (p_reply != NULL) {
                memcpy(p_reply->payload, echo_buf, echo_len);
                udp_sendto(pcb, p_reply, addr, port);
                pbuf_free(p_reply);
            }
        }
    }

    /* 6. CRITICAL: Free incoming packet buffer to prevent memory exhaustion */
    pbuf_free(p);

    /* 7. Return state to IDLE listening */
    g_app_status.state = APP_STATE_IDLE;
}

/**
 * @brief  Initializes the UDP listener socket on UDP_LISTEN_PORT.
 */
int udp_receiver_init(void)
{
    err_t err;

    g_app_status.state = APP_STATE_INIT;

    /* Create new UDP Protocol Control Block (PCB) */
    g_udp_pcb = udp_new();
    if (g_udp_pcb == NULL) {
        xil_printf("[UDP Receiver] ERROR: Failed to allocate UDP PCB (Out of memory)\r\n");
        g_app_status.state = APP_STATE_ERROR;
        return -1;
    }

    /* Bind PCB to all local IP addresses and the specified UDP port */
    err = udp_bind(g_udp_pcb, IP_ADDR_ANY, UDP_LISTEN_PORT);
    if (err != ERR_OK) {
        xil_printf("[UDP Receiver] ERROR: Unable to bind to port %u (err = %d)\r\n",
                   (unsigned int)UDP_LISTEN_PORT, err);
        udp_remove(g_udp_pcb);
        g_udp_pcb = NULL;
        g_app_status.state = APP_STATE_ERROR;
        return -2;
    }

    /* Register callback function for incoming packets */
    udp_recv(g_udp_pcb, udp_packet_callback, NULL);

    /* Initialize AXI4-Stream FIFO for streaming to PL */
    init_axi_fifo();

    g_app_status.state = APP_STATE_IDLE;
    xil_printf("[UDP Receiver] Listening on port %u (Callback Registered). State: IDLE\r\n",
               (unsigned int)UDP_LISTEN_PORT);

    return 0;
}

/**
 * @brief  Returns the current state tracker pointer.
 */
app_status_t* udp_receiver_get_status(void)
{
    return &g_app_status;
}

/**
 * @brief  Prints a summary of current metrics to UART.
 */
void udp_receiver_print_status(void)
{
    xil_printf("[STATUS] State: %s | RxPkts: %d | TxEchoPkts: %d | TotalBytes: %d\r\n",
               app_state_to_str(g_app_status.state),
               (int)g_app_status.rx_packet_count,
               (int)g_app_status.tx_packet_count,
               (int)g_app_status.total_bytes_rx);
}
