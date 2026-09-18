/******************************************************************************
 * Copyright (C) 2026. All Rights Reserved.
 *
 * Project: Star Tracker PS - AX7010 Zynq-7000
 * Component: eth_receiver
 * File: udp_receiver.h
 *
 * Description:
 *   Header file for the UDP Receiver and State Echo module using the
 *   lwIP RAW API on Zynq-7000 standalone baremetal.
 ******************************************************************************/

#ifndef __UDP_RECEIVER_H__
#define __UDP_RECEIVER_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include "lwip/ip_addr.h"
#include "lwip/udp.h"
#include "lwip/netif.h"
#include "xil_printf.h"

/* ========================================================================== */
/* Network Default Configurations                                             */
/* ========================================================================== */
#define DEFAULT_IP_ADDRESS      "192.168.1.10"
#define DEFAULT_IP_MASK         "255.255.255.0"
#define DEFAULT_GW_ADDRESS      "192.168.1.1"
#define UDP_LISTEN_PORT         8080

/* Maximum length of outgoing status echo reply message */
#define UDP_ECHO_BUF_MAX        256

/* ========================================================================== */
/* Application State Definitions                                              */
/* ========================================================================== */
typedef enum {
    APP_STATE_INIT = 0,         /* Hardware and lwIP stack initializing */
    APP_STATE_IDLE,             /* Listening on UDP port, waiting for packets */
    APP_STATE_ACTIVE,           /* Processing packet and transmitting reply */
    APP_STATE_ERROR             /* Memory allocation or socket binding error */
} app_state_t;

/* State and metrics tracking structure */
typedef struct {
    app_state_t state;          /* Current state of the application */
    uint32_t rx_packet_count;   /* Total valid UDP datagrams received */
    uint32_t tx_packet_count;   /* Total UDP state echo responses sent */
    uint32_t last_rx_len;       /* Length (bytes) of most recent payload */
    uint32_t total_bytes_rx;    /* Total payload bytes accumulated */
} app_status_t;

/* ========================================================================== */
/* Public API Functions                                                       */
/* ========================================================================== */

/**
 * @brief  Initialize the UDP protocol control block (PCB), bind to the
 *         listening port, and register the asynchronous receive callback.
 * @return 0 on success, negative error code on failure.
 */
int udp_receiver_init(void);

/**
 * @brief  Retrieve a pointer to the live application status tracker.
 * @return Pointer to app_status_t instance.
 */
app_status_t* udp_receiver_get_status(void);

/**
 * @brief  Helper to print the current application state to the UART console.
 */
void udp_receiver_print_status(void);

#ifdef __cplusplus
}
#endif

#endif /* __UDP_RECEIVER_H__ */
