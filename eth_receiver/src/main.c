/******************************************************************************
 * Copyright (C) 2026. All Rights Reserved.
 *
 * Project: Star Tracker PS - AX7010 Zynq-7000
 * Component: eth_receiver
 * File: main.c
 *
 * Description:
 *   Main entry point for the Ethernet UDP Receiver with State Echo.
 *   Initializes the Zynq hardware platform, lwIP networking stack,
 *   Gigabit Ethernet MAC (GEM0), and enters the non-blocking polling loop.
 ******************************************************************************/

#include <stdio.h>
#include "xil_printf.h"
#include "xparameters.h"
#include "netif/xadapter.h"
#include "platform.h"
#include "lwip/init.h"
#include "lwip/inet.h"
#include "lwip/netif.h"
#include "udp_receiver.h"

#ifndef XPAR_XEMACPS_0_BASEADDR
#define XPAR_XEMACPS_0_BASEADDR 0xe000b000
#endif

/* Global network interface instance */
static struct netif g_netif;

/* Hardware MAC address assigned to this board */
static unsigned char g_mac_addr[] = { 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };

/**
 * @brief  Helper to print an IP address in standard dotted-decimal notation.
 */
static void print_ip(const char *label, const ip_addr_t *ip)
{
    xil_printf("%s%d.%d.%d.%d\r\n", label,
               ip4_addr1(ip), ip4_addr2(ip),
               ip4_addr3(ip), ip4_addr4(ip));
}

int main(void)
{
    ip_addr_t ip_addr, netmask, gw_addr;

    /* 1. Initialize caches and UART */
    init_platform();

    xil_printf("\r\n");
    xil_printf("====================================================\r\n");
    xil_printf("  Star Tracker PS - Ethernet UDP Receiver & Echo    \r\n");
    xil_printf("  Target: ALINX AX7010 (Zynq-7000 XC7Z010)          \r\n");
    xil_printf("====================================================\r\n\r\n");

    /* 2. Initialize the lwIP network stack */
    xil_printf("[INIT] Initializing lwIP stack...\r\n");
    lwip_init();

    /* 3. Configure static IP address parameters */
    if (!inet_aton(DEFAULT_IP_ADDRESS, &ip_addr)) {
        xil_printf("[ERROR] Invalid default IP address format!\r\n");
    }
    if (!inet_aton(DEFAULT_IP_MASK, &netmask)) {
        xil_printf("[ERROR] Invalid subnet mask format!\r\n");
    }
    if (!inet_aton(DEFAULT_GW_ADDRESS, &gw_addr)) {
        xil_printf("[ERROR] Invalid gateway address format!\r\n");
    }

    /* 4. Add the GEM0 Ethernet MAC interface to lwIP */
    xil_printf("[INIT] Binding GEM0 Ethernet MAC (0x%08X)...\r\n",
               (unsigned int)XPAR_XEMACPS_0_BASEADDR);

    if (!xemac_add(&g_netif, &ip_addr, &netmask, &gw_addr,
                   g_mac_addr, XPAR_XEMACPS_0_BASEADDR)) {
        xil_printf("[FATAL] Error adding network interface to lwIP!\r\n");
        return -1;
    }

    /* Set as default network interface and bring link up */
    netif_set_default(&g_netif);
    netif_set_up(&g_netif);

    xil_printf("[INIT] Network interface successfully started:\r\n");
    print_ip("  Board IP Address : ", &g_netif.ip_addr);
    print_ip("  Subnet Mask      : ", &g_netif.netmask);
    print_ip("  Gateway Address  : ", &g_netif.gw);
    xil_printf("  Board MAC Address: %02X:%02X:%02X:%02X:%02X:%02X\r\n\r\n",
               g_mac_addr[0], g_mac_addr[1], g_mac_addr[2],
               g_mac_addr[3], g_mac_addr[4], g_mac_addr[5]);

    /* 5. Initialize UDP Receiver Socket and Callback */
    if (udp_receiver_init() != 0) {
        xil_printf("[FATAL] Failed to bind UDP receiver on port %d!\r\n", UDP_LISTEN_PORT);
        return -1;
    }

    xil_printf(">> System is ACTIVE and ready.\r\n");
    xil_printf(">> Send UDP packets to %s:%d from your host.\r\n",
               DEFAULT_IP_ADDRESS, UDP_LISTEN_PORT);
    xil_printf(">> The board will print each packet and echo its state back.\r\n\r\n");

    /* 6. Main Polling Loop */
    while (1) {
        /*
         * In lwIP RAW mode without an RTOS, xemacif_input() MUST be called
         * repeatedly to poll the GEM DMA RX descriptors and pass incoming
         * Ethernet frames up through the IP and UDP layers to our callback.
         */
        xemacif_input(&g_netif);
    }

    /* Clean up (never reached) */
    cleanup_platform();
    return 0;
}
