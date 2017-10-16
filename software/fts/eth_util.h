/*
 * eth_util.h
 *
 *  Created on: Aug 27, 2017
 *      Author: zaqc
 */

#ifndef ETH_UTIL_H_
#define ETH_UTIL_H_
//----------------------------------------------------------------------------

#include <stdlib.h>
#include <alt_types.h>
#include <altera_avalon_sgdma.h>
#include <altera_avalon_sgdma_descriptor.h>
#include <altera_avalon_sgdma_regs.h>
//----------------------------------------------------------------------------

#define UDP_HEADER_SIZE		(42 + 2)

#define	DSCOPE_HDR_SIZE		(128)			// u32 pkt_cntr + u32 wheel_cntr + u32 l_status + u32 r_status + u8 reserved[112]
#define HDR_SIZE			(UDP_HEADER_SIZE + DSCOPE_HDR_SIZE)
//----------------------------------------------------------------------------


extern unsigned char g_BroadcastMAC[6];

extern unsigned char g_PacketTypeARP[2];
extern unsigned char g_PacketTypeUDP[2];

extern unsigned char g_HType[2]; // Ethernet
extern unsigned char g_PType[2]; // IPv4
extern unsigned char g_HLen; // Hardware Address Length (MAC_LENGTH == 6)
extern unsigned char g_PLen; // Protocol Address Length (IP_ADDR_LEN == 4)
extern unsigned char g_OpArpReq[2]; // ARP Request
extern unsigned char g_OpArpResp[2]; // ARP Response
extern unsigned char g_SrcMAC[6]; // Self MAC Address
extern unsigned char g_DstMAC[6]; // Address: Pegatron_31:24:85 (0c:54:a5:31:24:85) eth0
extern unsigned char g_SrcIP[4];
extern unsigned char g_DstIP[4];

extern unsigned char g_SrcPort[2];
extern unsigned char g_DstPort[2];

#define	u16_btol(a)		((((a) << 8) & 0xFF00) | (((a) >> 8) & 0xFF))

extern alt_sgdma_dev *sgdma_tx_dev;
extern alt_sgdma_dev *sgdma_rx_dev;

extern alt_sgdma_descriptor *rx_descriptor;
extern alt_sgdma_descriptor *rx_descriptor_end;

extern alt_sgdma_descriptor *tx_descriptor_1;
extern alt_sgdma_descriptor *tx_descriptor_2;
extern alt_sgdma_descriptor *tx_descriptor_3;
extern alt_sgdma_descriptor *tx_descriptor_4;
extern alt_sgdma_descriptor *tx_descriptor_5;
extern alt_sgdma_descriptor *tx_descriptor_end;

extern alt_sgdma_descriptor *tx_desc_arp;
extern alt_sgdma_descriptor *tx_desc_arp_end;

extern alt_sgdma_descriptor *tx_desc_keyb;
extern alt_sgdma_descriptor *tx_desc_keyb_end;


extern volatile alt_u8 *rx_frame;

extern volatile alt_u8 *tx_frame_1;
extern volatile alt_u8 *tx_frame_2;
extern volatile alt_u8 *tx_frame_3;

extern volatile alt_u8 *tx_frame_arp;

extern volatile alt_u8 *tx_frame_keyb;

extern void rx_ethernet_isr(void *context);

void eth_init(void);
void udp_gen(void);

alt_u16 gen_udp_header(alt_u8 *ptr, alt_u16 pkt_id, alt_u16 pkt_offset, alt_u16 pkt_len, alt_u8 frag, alt_u16 udp_data_len, int keyb_port);
alt_u16 gen_arp_resp(alt_u8 *ptr, alt_u8 *dst_mac, alt_u8 *dst_ip);

#endif /* ETH_UTIL_H_ */
