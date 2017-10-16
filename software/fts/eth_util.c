/*
 * eth_util.c
 *
 *  Created on: Aug 27, 2017
 *      Author: zaqc
 */

#include "system.h"

#include <altera_avalon_sgdma.h>
#include <altera_avalon_sgdma_descriptor.h>
#include <altera_avalon_sgdma_regs.h>

#include <altera_avalon_tse.h>

#include "sys/alt_stdio.h"
#include "sys/alt_irq.h"
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <alt_types.h>
#include <sys/alt_cache.h>
#include <string.h>

#include "eth_util.h"
//----------------------------------------------------------------------------

// Allocate descriptors in the descriptor_memory (onchip memory)
alt_sgdma_descriptor *rx_descriptor;
alt_sgdma_descriptor *rx_descriptor_end;

alt_sgdma_descriptor *tx_descriptor_1;
alt_sgdma_descriptor *tx_descriptor_2;
alt_sgdma_descriptor *tx_descriptor_3;
alt_sgdma_descriptor *tx_descriptor_4;
alt_sgdma_descriptor *tx_descriptor_5;
alt_sgdma_descriptor *tx_descriptor_end;

alt_sgdma_descriptor *tx_desc_arp;
alt_sgdma_descriptor *tx_desc_arp_end;

alt_sgdma_descriptor *tx_desc_keyb;
alt_sgdma_descriptor *tx_desc_keyb_end;

volatile void *temp_ptr_save_rx, *temp_ptr_save_tx;
//----------------------------------------------------------------------------

void alloc_desc(void) {
	volatile void * temp_ptr;

	//------------------------------------------------------------------------
	// DMA TX Desc[4]
	//------------------------------------------------------------------------
	temp_ptr_save_tx = temp_ptr = alt_uncached_malloc(
			14 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if (temp_ptr == NULL) {
		printf("Failed to allocate memory for the transmit descriptors\n");
		return;
	}
	memset((void *)temp_ptr, 0, 14 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);

	while ((((alt_u32) temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0) {
		temp_ptr++; // slide the pointer until 32 byte boundary is found
	}
	tx_descriptor_1 = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_descriptor_2 = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_descriptor_3 = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_descriptor_4 = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_descriptor_5 = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_descriptor_end = (alt_sgdma_descriptor *) temp_ptr;

	tx_descriptor_end->control = 0;

	//------------------------------------------------------------------------

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_desc_arp = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_desc_arp_end = (alt_sgdma_descriptor *) temp_ptr;

	tx_desc_arp_end->control = 0;

	//------------------------------------------------------------------------

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_desc_keyb = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	tx_desc_keyb_end = (alt_sgdma_descriptor *) temp_ptr;

	tx_desc_keyb_end->control = 0;

	//------------------------------------------------------------------------

	//------------------------------------------------------------------------
	// DMA RX Desc[2]
	//------------------------------------------------------------------------
	temp_ptr_save_rx = temp_ptr = alt_uncached_malloc(
			4 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if (temp_ptr == NULL) {
		printf("Failed to allocate memory for the transmit descriptors\n");
		return;
	}
	memset((void *)temp_ptr, 0, 4 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	while ((((alt_u32) temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0) {
		temp_ptr++; // slide the pointer until 32 byte boundary is found
	}
	rx_descriptor = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	rx_descriptor_end = (alt_sgdma_descriptor *) temp_ptr;

	rx_descriptor_end->control = 0;
}
//----------------------------------------------------------------------------

// Create sgdma transmit and receive devices
alt_sgdma_dev *sgdma_tx_dev;
alt_sgdma_dev *sgdma_rx_dev;

volatile alt_u8 *rx_frame;

volatile alt_u8 *tx_frame_1;
volatile alt_u8 *tx_frame_2;
volatile alt_u8 *tx_frame_3;

volatile alt_u8 *tx_frame_arp;

volatile alt_u8 *tx_frame_keyb;

#define	ETH_TSE_BASE	ETH_TSE_0_BASE

void eth_init(void) {
	sgdma_tx_dev = alt_avalon_sgdma_open(SGDMA_TX_NAME);
	if (sgdma_tx_dev == NULL) {
		printf("could not open sg_dma transmit device\n");
		return;
	}

	// Open the sgdma receive device
	sgdma_rx_dev = alt_avalon_sgdma_open(SGDMA_RX_NAME);
	if (sgdma_rx_dev == NULL) {
		printf("could not open sg_dma receive device\n");
		return;
	}
	rx_frame = alt_uncached_malloc(2048);
	if (NULL == rx_frame) {
		printf("Can't allocate memory for RX buffer...\n");
		return;
	}

	tx_frame_arp = alt_uncached_malloc(128);
	if (NULL == tx_frame_arp) {
		printf("Can't allocate memory for ARP_RESP buffer...\n");
		return;
	}

	tx_frame_keyb = alt_uncached_malloc(128);
	if (NULL == tx_frame_keyb) {
		printf("Can't allocate memory for ARP_RESP buffer...\n");
		return;
	}

	alloc_desc();

	alt_dcache_flush_all();

	// enable 1Gbit disable Ethernet RX TX
	IOWR(ETH_TSE_BASE, 0x02, 0x08);

	// Initialize the MAC address
	IOWR(ETH_TSE_BASE, 3, 0x11362200);
	IOWR(ETH_TSE_BASE, 4, 0x00000F02);

	// Specify the addresses of the PHY devices to be accessed through MDIO interface
	IOWR(ETH_TSE_BASE, 0x0F, 0x10);
	//IOWR(ETH_TSE_BASE, 0x10, 0x10);

	// Write to register 20 of the PHY chip for Ethernet port 0 to set up line loopback
	IOWR(ETH_TSE_BASE, 0x94, 0x4000);

	// Write to register 16 of the PHY chip for Ethernet port 1 to enable automatic crossover for all modes
	IOWR(ETH_TSE_BASE, 0x90, IORD(ETH_TSE_BASE, 0x90) | 0x0060);

	// Write to register 20 of the PHY chip for Ethernet port 2 to set up delay for input/output clk
	IOWR(ETH_TSE_BASE, 0x94, IORD(ETH_TSE_BASE, 0x94) | 0x0082);

	// Software reset the PHY chip and wait
	IOWR(ETH_TSE_BASE, 0x80, IORD(ETH_TSE_BASE, 0x80) | 0x8000);
	while (IORD(ETH_TSE_BASE, 0x80) & 0x8000)
		__asm("NOP");

	// Enable read and write transfers, gigabit Ethernet operation, and CRC forwarding
	IOWR(ETH_TSE_BASE, 2, IORD(ETH_TSE_BASE, 2) | 0x00000003);
}
//----------------------------------------------------------------------------

unsigned char g_BroadcastMAC[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

unsigned char g_PacketTypeARP[2] = { 0x08, 0x06 };
unsigned char g_PacketTypeUDP[2] = { 0x08, 0x00 };

unsigned char g_HType[2] = { 0x00, 0x01 }; // Ethernet
unsigned char g_PType[2] = { 0x08, 0x00 }; // IPv4
unsigned char g_HLen = 0x06; // Hardware Address Length (MAC_LENGTH == 6)
unsigned char g_PLen = 0x04; // Protocol Address Length (IP_ADDR_LEN == 4)
unsigned char g_OpArpReq[2] = { 0x00, 0x01 }; // ARP Request
unsigned char g_OpArpResp[2] = { 0x00, 0x02 }; // ARP Response

unsigned char g_SrcMAC[6] = { 0x00, 0x22, 0x36, 0x11, 0x02, 0x0F }; // Self MAC Address

//unsigned char g_DstMAC[6] = { 0x0c, 0x54, 0xa5, 0x31, 0x24, 0x85 }; // Address: Pegatron_31:24:85 (0c:54:a5:31:24:85) eth0

//unsigned char g_DstMAC[6] = { 0x0c, 0x54, 0xa5, 0x31, 0x24, 0x86 }; // Address: Pegatron_31:24:85 (0c:54:a5:31:24:85) eth1
//unsigned char g_DstMAC[6] = { 0xb8, 0x6b, 0x23, 0x70, 0x3f, 0x14 }; // Melan Toshiba IP:192.168.1.211

//
//unsigned char g_DstMAC[6] = { 0x00, 0x1e, 0x06, 0x34, 0x27, 0x52 }; // ODROID-C2 IP:192.168.1.158
//unsigned char g_DstMAC[6] = { 0x00, 0x1e, 0x06, 0x33, 0x54, 0xC4 }; // ODROID-C2 IP:192.168.1.158 (work)
//unsigned char g_DstMAC[6] = { 0x0c, 0x54, 0xa5, 0x31, 0x24, 0x86 }; // Melan HP IP:192.168.1.11
unsigned char g_DstMAC[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }; // Broadcast

unsigned char g_SrcIP[4] = { 192, 168, 1, 100 };
//unsigned char g_DstIP[4] = { 192, 168, 1, 11 };
//unsigned char g_DstIP[4] = { 192, 168, 1, 158 };
unsigned char g_DstIP[4] = { 192, 168, 1, 255 }; // Broadcast

//unsigned char g_SrcIP[4] = { 10, 0, 0, 100 };
//unsigned char g_DstIP[4] = { 10, 0, 0, 2 };

//unsigned char g_DstIP[4] = { 192, 168, 1, 180 };
//unsigned char g_DstIP[4] = { 192, 168, 1, 211 };

unsigned char g_SrcPort[2] = { 0x21, 0x79 };
unsigned char g_DstPort[2] = { 0x51, 0x52 };
unsigned char g_KeybDstPort[2] = { 0x51, 0x53 };

alt_u16 gen_udp_header(alt_u8 *ptr, alt_u16 pkt_id, alt_u16 pkt_offset,
		alt_u16 pkt_len, alt_u8 frag, alt_u16 udp_data_len, int keyb_port) {
	alt_u16 hdr_len = 42;
	ptr += 2;
	memcpy(ptr, g_DstMAC, 6);
	memcpy(&ptr[6], g_SrcMAC, 6);
	memcpy(&ptr[12], g_PacketTypeUDP, 2);

	ptr[14] = 0x45; // 4 - for IPv4, size = 5 in 32bit word's
	ptr[15] = 0x00; // ip_DSCP_ECN ?

	alt_u16 tmp = u16_btol(pkt_len + 28); // (IPv4_HDR==20 + UDP_HDR==8) 28 == 0x1C// 16'h002E size of UDP packet
	memcpy(&ptr[16], &tmp, 2);

	// 18-19=packet_id, 20, 21= flags[3bit] + offset[13]
	tmp = u16_btol(pkt_id);
	memcpy(&ptr[18], &tmp, 2);

	tmp = u16_btol(pkt_offset >> 3);
	tmp |= (((alt_u16) frag) << 5) & 0x00E0;
	memcpy(&ptr[20], &tmp, 2);

	ptr[22] = 0xC8; //ip_pkt_TTL;
	ptr[23] = 17; // UDP Packet pkt_type = 17
	ptr[24] = 0; // CRC = 0
	ptr[25] = 0;

	memcpy(&ptr[26], g_SrcIP, 4);
	memcpy(&ptr[30], g_DstIP, 4);
	memcpy(&ptr[34], g_SrcPort, 2);
	if (keyb_port)
		memcpy(&ptr[36], g_KeybDstPort, 2);
	else
		memcpy(&ptr[36], g_DstPort, 2);
	tmp = u16_btol(udp_data_len + 8); // UDP_Data_Size + UDP_Header_Size(src_port[2] + dst_port[2] + data_len[2] + udp_crc[2])
	memcpy(&ptr[38], &tmp, 2);
	tmp = 0;
	memcpy(&ptr[40], &tmp, 2); // don't use

	alt_u32 tmp_CRC = 0;
	int i;
	for (i = 0; i < 10; i++) {
		alt_u16 v = (((alt_u16) ptr[14 + i * 2]) << 8)
				+ (alt_u16) ptr[15 + i * 2];
		tmp_CRC += v;
	}

	tmp = (~u16_btol(((tmp_CRC & 0xFFFF) + ((tmp_CRC >> 16) & 0xFFFF))))
			& 0xFFFF;
	memcpy(&ptr[24], &tmp, 2);

	return hdr_len;
}
//----------------------------------------------------------------------------

alt_u16 gen_arp_resp(alt_u8 *arp_ptr, alt_u8 *dst_mac, alt_u8 *dst_ip) {
	unsigned char *ptr = (unsigned char *) arp_ptr + 2;
	memset(ptr, 0, 64);

	memcpy(ptr, dst_mac, 6);
	ptr += 6;
	memcpy(ptr, g_SrcMAC, 6);
	ptr += 6;
	memcpy(ptr, g_PacketTypeARP, 2);
	ptr += 2;

	memcpy(ptr, g_HType, 2);
	ptr += 2;
	memcpy(ptr, g_PType, 2);
	ptr += 2;
	*ptr = g_HLen;
	ptr++;
	*ptr = g_PLen;
	ptr++;
	memcpy(ptr, g_OpArpResp, 2);
	ptr += 2;
	memcpy(ptr, g_SrcMAC, 6);
	ptr += 6;
	memcpy(ptr, g_SrcIP, 4);
	ptr += 4;
	memcpy(ptr, dst_mac, 6);
	ptr += 6;
	memcpy(ptr, dst_ip, 4);
	ptr += 4;

	return ptr - arp_ptr;
}
//----------------------------------------------------------------------------

alt_u16 gen_arp_req(alt_u8 *arp_ptr, alt_u8 *dst_mac, alt_u8 *dst_ip) {
	unsigned char *ptr = (unsigned char *) arp_ptr;
	memset(ptr, 0, 64);

	memcpy(ptr, g_BroadcastMAC, 6);
	ptr += 6;
	memcpy(ptr, g_SrcMAC, 6);
	ptr += 6;
	memcpy(ptr, g_PacketTypeARP, 2);
	ptr += 2;

	memcpy(ptr, g_HType, 2);
	ptr += 2;
	memcpy(ptr, g_PType, 2);
	ptr += 2;
	*ptr = g_HLen;
	ptr++;
	*ptr = g_PLen;
	ptr++;
	memcpy(ptr, g_OpArpReq, 2);
	ptr += 2;
	memcpy(ptr, g_SrcMAC, 6);
	ptr += 6;
	memcpy(ptr, g_SrcIP, 4);
	ptr += 4;
	memset(ptr, 0x00, 6);
	ptr += 6;
	memcpy(ptr, g_DstIP, 4);
	ptr += 4;

	return ptr - arp_ptr;
}
//----------------------------------------------------------------------------

/*
int udp_data_len = 1024;

void udp_gen(void) {
	alt_u8 *ptr = (alt_u8 *) tx_frame_1;
	memset(ptr, 0, 1520);
	//ptr += 2; // align 32

	memcpy(ptr, g_DstMAC, 6);
	memcpy(&ptr[6], g_SrcMAC, 6);
	memcpy(&ptr[12], g_PacketTypeUDP, 2);

	ptr[14] = 0x45; // 4 - for IPv4, size = 5 in 32bit word's
	ptr[15] = 0x00; // ip_DSCP_ECN ?

	alt_u16 tmp = u16_btol(udp_data_len + 0x1C); // (IPv4_HDR==20 + UDP_HDR==8) 28 == 0x1C// 16'h002E size of UDP packet
	memcpy(&ptr[16], &tmp, 2);

	// 17-18=packet_id, 24, 25= flags[3bit] + offset[13]

	ptr[22] = 0xC8; //ip_pkt_TTL;
	ptr[23] = 17; // UDP Packet pkt_type = 17
	ptr[24] = 0; //CRC = 0
	ptr[25] = 0;

	memcpy(&ptr[26], g_SrcIP, 4);
	memcpy(&ptr[30], g_DstIP, 4);
	memcpy(&ptr[34], g_SrcPort, 2);
	memcpy(&ptr[36], g_DstPort, 2);
	tmp = u16_btol(udp_data_len + 8); // UDP_Data_Size + UDP_Header_Size(src_port[2] + dst_port[2] + data_len[2] + udp_crc[2])
	memcpy(&ptr[38], &tmp, 2);
	tmp = 0;
	memcpy(&ptr[40], &tmp, 2); // don't use

	alt_u32 tmp_CRC = 0;
	int i;
	for (i = 0; i < 10; i++) {
		alt_u16 v = (((alt_u16) ptr[14 + i * 2]) << 8) + ptr[15 + i * 2];
		tmp_CRC += v;
	}

	tmp = (~u16_btol(((tmp_CRC & 0xFFFF) + ((tmp_CRC >> 16) & 0xFFFF))))
			& 0xFFFF;
	memcpy(&ptr[24], &tmp, 2);
}
*/
//----------------------------------------------------------------------------

