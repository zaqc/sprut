/*
 * "Hello World" example.
 *
 * This example prints 'Hello from Nios II' to the STDOUT stream. It runs on
 * the Nios II 'standard', 'full_featured', 'fast', and 'low_cost' example
 * designs. It runs with or without the MicroC/OS-II RTOS and requires a STDOUT
 * device in your system's hardware.
 * The memory footprint of this hosted application is ~69 kbytes by default
 * using the standard reference design.
 *
 * For a reduced footprint version of this template, and an explanation of how
 * to reduce the memory footprint for a given application, see the
 * "small_hello_world" template.
 *
 */

#include <stdio.h>
#include <unistd.h>

#include <altera_avalon_pio_regs.h>
#include "system.h"

#include "altera_avalon_pio_regs.h"
#include "altera_avalon_fifo.h"
#include "altera_avalon_fifo_regs.h"
#include "altera_avalon_fifo_util.h"
#include "altera_avalon_uart.h"
#include "altera_avalon_uart_fd.h"
#include "altera_avalon_uart_regs.h"

#include <altera_avalon_timer.h>
#include <sys/alt_alarm.h>
#include <alt_types.h>
#include <sys/alt_cache.h>
#include <sys/alt_irq.h>
#include <altera_nios2_qsys_irq.h>

#include "eth_util.h"
//----------------------------------------------------------------------------

static alt_alarm tick_alarm;

volatile int sys_tick = 0;
unsigned int light_nn = 0x01;
volatile int direct = 0;
//----------------------------------------------------------------------------

alt_u32 sys_tick_callback(void *context) {
	sys_tick++;

	if ((sys_tick % 2410) == 0)
		direct = 1 - direct;

	if ((sys_tick % 100) == 0) {
		//IOWR(PIO_LED_BASE, 0, light_nn);
		if (direct == 1) {
			light_nn <<= 1;
			light_nn |= ((~(light_nn >> 8)) & 0x01);
		} else {
			light_nn >>= 1;
			light_nn |= ((~(light_nn << 8)) & 0x100);
		}
	}

	return 1;
}
//----------------------------------------------------------------------------

alt_u32 ext_tick_present = 0;
alt_u32 ext_sync_cntr = 0;

void ext_sync_irq_handler(void *context) {
	//alt_irq_context irq_context = alt_irq_disable_all();
	ext_tick_present = 1;

	alt_u32 edge =
			(alt_u32) IOADDR_ALTERA_AVALON_PIO_EDGE_CAP(PIO_EXT_SYNC_BASE);
	IOWR_ALTERA_AVALON_PIO_EDGE_CAP(PIO_EXT_SYNC_BASE, 0);
	(void) edge;

	ext_sync_cntr = IORD(PIO_EXT_SYNC_BASE, 0);
	// IOWR(PIO_LED_BASE, 0, ext_sync_cntr);
	//alt_irq_enable_all(irq_context);
}
//----------------------------------------------------------------------------

void put_kq_data(void *data, int len);
int get_kq_data(void);

int uart_hdr_cntr = 0;
int uart_data_cntr = 0;

volatile int uart_data_present = 0;
volatile unsigned char uart_data[4];

void uart_keyb_irq(void *context) {
	unsigned int status, chr;

	//alt_irq_context irq_context = alt_irq_disable_all();

	/* get serial status */
	status = IORD(UART_KEYB_BASE, 2);

	if (status & ALTERA_AVALON_UART_STATUS_TRDY_MSK) {
		int iChr = get_kq_data();
		if (iChr >= 0)
			IOWR_ALTERA_AVALON_UART_TXDATA(UART_KEYB_BASE, iChr & 0xFF);
		else
			IOWR_ALTERA_AVALON_UART_CONTROL(UART_KEYB_BASE,
					ALTERA_AVALON_UART_CONTROL_RRDY_MSK);
	}

	/* character Rx */
	if (status & 0x0080) {
		chr = IORD(UART_KEYB_BASE, 0);

		if (uart_hdr_cntr < 4) {
			if (chr == 0x55) {
				uart_hdr_cntr++;
			} else {
				uart_hdr_cntr = 0;
			}
		} else {
			if (uart_data[uart_data_cntr] != chr) {
				uart_data[uart_data_cntr] = chr;
				//printf("%i ", (int) chr);
			}
			uart_data_cntr++;
			if (uart_data_cntr >= 4) {
				uart_data_cntr = 0;
				uart_hdr_cntr = 0;
				uart_data_present = 1;
			}
		}
	}

	IOWR_ALTERA_AVALON_UART_STATUS(UART_KEYB_BASE, 0);

	//alt_irq_enable_all(irq_context);
}
//----------------------------------------------------------------------------

int cmpbuf(alt_u8 *aBuf1, alt_u8 *aBuf2, int aLen) {
	int i;
	for (i = 0; i < aLen; i++) {
		if (*aBuf1 != *aBuf2)
			return 0;
		aBuf1++;
		aBuf2++;
	}
	return 1;
}
//----------------------------------------------------------------------------

volatile alt_u8 arp_req_mac[6];
volatile alt_u8 arp_req_ip[4];
volatile alt_u8 arp_req_present = 0;

volatile alt_u32 cmd_data;
volatile alt_u32 cmd_side;
volatile alt_u8 cmd_req_present = 0;

alt_u8 g_CmdPreamble[4] = { 0x55, 0x55, 0x55, 0xD5 };
alt_u8 g_CmdLeftSide[4] = { 0xFF, 0x00, 0x12, 0xDE };
alt_u8 g_CmdRightSide[4] = { 0xFF, 0x00, 0xF0, 0x72 };
alt_u8 g_CmdBothSide[4] = { 0xFF, 0x00, 0xFE, 0x55 };

volatile alt_u32 internal_sync = 0;

void decode_packet(void) {
	int plen = rx_descriptor->actual_bytes_transferred;
	(void) plen;

	unsigned char *ptr = (unsigned char *) rx_frame + 2;

	if (cmpbuf(ptr, g_SrcMAC, 6)) {
		if (cmpbuf(&ptr[12], g_PacketTypeARP, 2)) {
			if (cmpbuf(&ptr[38], g_SrcIP, 4)) {
				alt_u16 operation = (((alt_u16) ptr[20]) << 8) | ptr[21];
				//printf("selfMAC ARP... op=%i\n", (int) operation);
				//alt_irq_context irq_context = alt_irq_disable_all();
				if (operation == 0x0001) {
					memcpy((void*) arp_req_mac, &ptr[22], 6);
					memcpy((void*) arp_req_ip, &ptr[28], 4);
					arp_req_present = 1;
				} else if (operation == 0x0002) {
					memcpy((void*) arp_req_mac, &ptr[22], 6);
					memcpy((void*) arp_req_ip, &ptr[28], 4);
					arp_req_present = 2;
				}
				//alt_irq_enable_all(irq_context);
			}
		} else if (cmpbuf(&ptr[12], g_PacketTypeUDP, 2)) {
			if (cmpbuf(&ptr[30], g_SrcIP, 4)) {
				if (ptr[36] == 0x56 && ptr[37] == 0x78) {
					//alt_irq_context irq_context = alt_irq_disable_all();
					alt_u32 pr;
					memcpy((void *) &pr, &ptr[42], 4);
					if (cmpbuf(&ptr[42], g_CmdPreamble, 4)) {
						memcpy((void *) &cmd_side, &ptr[46], 4);
						memcpy((void *) &cmd_data, &ptr[50], 4);

						cmd_data = ((cmd_data << 24) & 0xFF000000)
								| ((cmd_data << 8) & 0x00FF0000)
								| ((cmd_data >> 8) & 0xFF00)
								| ((cmd_data >> 24) & 0xFF);

						if (cmpbuf(&ptr[46], g_CmdLeftSide, 4)) {
							altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE,
									FIFO_CMD_0_IN_CSR_BASE, cmd_data);
							altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE,
									FIFO_CMD_0_IN_CSR_BASE, cmd_data);
						} else if (cmpbuf(&ptr[46], g_CmdRightSide, 4)) {
							altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE,
									FIFO_CMD_1_IN_CSR_BASE, cmd_data);
							altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE,
									FIFO_CMD_1_IN_CSR_BASE, cmd_data);
						} else if (cmpbuf(&ptr[46], g_CmdBothSide, 4)) {
							altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE,
									FIFO_CMD_0_IN_CSR_BASE, cmd_data);
							altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE,
									FIFO_CMD_0_IN_CSR_BASE, cmd_data);
							altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE,
									FIFO_CMD_1_IN_CSR_BASE, cmd_data);
							altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE,
									FIFO_CMD_1_IN_CSR_BASE, cmd_data);
						} else if (cmd_side == 0x04) {
							if ((cmd_data >> 16) == 0x0001) {
								internal_sync =
										((cmd_data & 0xFFFF) != 0) ? 1 : 0;
							}
						}
					}
					//alt_irq_enable_all(irq_context);
				} else if (ptr[36] == 0x57 && ptr[37] == 0x79) {
					//alt_irq_context irq_context = alt_irq_disable_all();
					int len = (ptr[39] | (((int) ptr[38]) << 8)) - 8;
					//printf("%i ", len);
					if (len > 0 && len < 128)
						put_kq_data(&ptr[42], len);
					//alt_irq_enable_all(irq_context);
				}
			}
		}
	} else if (cmpbuf(ptr, g_BroadcastMAC, 6)) {
		if (cmpbuf(&ptr[12], g_PacketTypeARP, 2)) {
			if (cmpbuf(&ptr[38], g_SrcIP, 4)) {
				alt_u16 operation = (((alt_u16) ptr[20]) << 8) | ptr[21];
				//printf("Broadcast ARP... op=%i\n", (int) operation);

				//alt_irq_context irq_context = alt_irq_disable_all();
				if (operation == 0x0001) {
					memcpy((void*) arp_req_mac, &ptr[22], 6);
					memcpy((void*) arp_req_ip, &ptr[28], 4);
					arp_req_present = 1;
				} else if (operation == 0x0002) {
					memcpy((void*) arp_req_mac, &ptr[22], 6);
					memcpy((void*) arp_req_ip, &ptr[28], 4);
					arp_req_present = 2;
				}
				//alt_irq_enable_all(irq_context);
			}
		}
	}
}
//----------------------------------------------------------------------------

volatile int rx_eth_flag = 0;
void rx_ethernet_isr(void *context) {
	rx_eth_flag = 1;
}
//----------------------------------------------------------------------------

#define KQ_SIZE				1024

volatile unsigned char *kq;
volatile int kq_put = 0;
volatile int kq_get = 0;
volatile int kq_len = 0;

void put_kq_data(void *data, int len) {
	if (kq_len + len < KQ_SIZE) {
		int cl = (kq_put + len);
		if (cl < KQ_SIZE) {
			memcpy((void *) &kq[kq_put], data, len);
			kq_put += len;
		} else {
			int ts = KQ_SIZE - kq_put;
			memcpy((void *) &kq[kq_put], data, ts);
			memcpy((void *) kq, data + ts, len - ts);
			kq_put = len - ts;
		}

		if (kq_len == 0) {
			kq_len += len;

			IOWR_ALTERA_AVALON_UART_CONTROL(UART_KEYB_BASE,
					ALTERA_AVALON_UART_CONTROL_RRDY_MSK | ALTERA_AVALON_UART_CONTROL_TRDY_MSK);
		} else
			kq_len += len;
	}
}
//-------------------------------------------------------------------------------

int get_kq_data(void) {
	int iChr = -1;
	if (0 != kq_len) {
		iChr = kq[kq_get];
		kq_get++;
		if (kq_get >= KQ_SIZE)
			kq_get = 0;
		kq_len--;
	}
	return iChr;
}
//-------------------------------------------------------------------------------

void init_recv_data(void);
void recv_data(void);
extern int pkt_id;
//-------------------------------------------------------------------------------

int main() {
//-------------------------------------------------------------------------------
//	Keyboard queue
//-------------------------------------------------------------------------------
//	while (1) {
//		unsigned int cmd = ((15 << 12) | (13 << 8)) << 16;
//		altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE,
//				FIFO_CMD_0_IN_CSR_BASE, cmd);
//		usleep(1000000);
//		cmd = (((15 << 12) | (13 << 8)) << 16) | 1;
//		altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE,
//				FIFO_CMD_0_IN_CSR_BASE, cmd);
//		usleep(1000000);
//	}

	int i;
	for(i = 0; i < 255; i++) {
		IOWR(PIO_LED_BASE, 0, i);
		usleep(1000);
	}

	unsigned int cmd = ((15 << 12) | (15 << 8)) << 16;
	altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE, FIFO_CMD_0_IN_CSR_BASE,
			cmd);
	altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE, FIFO_CMD_0_IN_CSR_BASE,
			cmd);
	usleep(1000000);
	altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE, FIFO_CMD_0_IN_CSR_BASE,
			cmd);
	altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE, FIFO_CMD_0_IN_CSR_BASE,
			cmd);
	usleep(1000000);

//-------------------------------------------------------------------------------
//	Keyboard queue
//-------------------------------------------------------------------------------
	//int i;

	kq = alt_uncached_malloc(KQ_SIZE);
	if (kq == NULL) {
		printf("Can't allocate memory for Keyboard Queue...\n");
		return -1;
	}

	g_SrcIP[0] = 192;
	g_SrcIP[1] = 168;
	g_SrcIP[2] = 1;
	g_SrcIP[3] = 100;

	g_DstIP[0] = 192;
	g_DstIP[1] = 168;
	g_DstIP[2] = 1;
	g_DstIP[3] = 255;

//-------------------------------------------------------------------------------
//	Alarm (TIMER 1ms)
//-------------------------------------------------------------------------------
	alt_alarm_start(&tick_alarm, 500, &sys_tick_callback, NULL);

//-------------------------------------------------------------------------------
//	ExtSync
//-------------------------------------------------------------------------------
	alt_ic_isr_register(PIO_EXT_SYNC_IRQ_INTERRUPT_CONTROLLER_ID,
			PIO_EXT_SYNC_IRQ, ext_sync_irq_handler, NULL, 0);
	IOWR_ALTERA_AVALON_PIO_EDGE_CAP(PIO_EXT_SYNC_BASE, 0);
	IOWR_ALTERA_AVALON_PIO_IRQ_MASK(PIO_EXT_SYNC_BASE, 0x1);

//-------------------------------------------------------------------------------
//	Keyboard
//-------------------------------------------------------------------------------
	IOWR_ALTERA_AVALON_UART_CONTROL(UART_KEYB_BASE, 0);
	IOWR_ALTERA_AVALON_UART_DIVISOR(UART_KEYB_BASE, 75000000 / 9600);

	IORD_ALTERA_AVALON_UART_RXDATA(UART_KEYB_BASE);
	IORD_ALTERA_AVALON_UART_RXDATA(UART_KEYB_BASE);

	IOWR_ALTERA_AVALON_UART_STATUS(UART_KEYB_BASE, 0x00);
	alt_ic_isr_register(UART_KEYB_IRQ_INTERRUPT_CONTROLLER_ID, UART_KEYB_IRQ,
			&uart_keyb_irq, NULL, 0);
	IOWR_ALTERA_AVALON_UART_CONTROL(UART_KEYB_BASE,
			ALTERA_AVALON_UART_CONTROL_RRDY_MSK);
	// | ALTERA_AVALON_UART_CONTROL_TRDY_MSK);

//-------------------------------------------------------------------------------
//	Initialize Ethernet & DSCope Receiver
//-------------------------------------------------------------------------------

	eth_init();

	init_recv_data();

//-------------------------------------------------------------------------------
//	Ethernet receive
//-------------------------------------------------------------------------------
	while (alt_avalon_sgdma_check_descriptor_status(rx_descriptor) != 0)
		__asm("NOP");

	alt_avalon_sgdma_register_callback(sgdma_rx_dev,
			(alt_avalon_sgdma_callback) rx_ethernet_isr,
			(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK
					| ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK),
			NULL);

	alt_avalon_sgdma_construct_stream_to_mem_desc(rx_descriptor,
			rx_descriptor_end, (alt_u32*) rx_frame, 0, 0);
	alt_avalon_sgdma_do_async_transfer(sgdma_rx_dev, rx_descriptor);

//-------------------------------------------------------------------------------

	while (1) {
		alt_irq_context irq_context = alt_irq_disable_all();
		alt_u8 req_present = 0;
		alt_u8 req_mac[6];
		alt_u8 req_ip[4];
		if (arp_req_present != 0) {
			memcpy(req_mac, (void*) arp_req_mac, 6);
			memcpy(req_ip, (void*) arp_req_ip, 4);
			req_present = arp_req_present;
			arp_req_present = 0;
		}
		alt_u32 keyb_present = 0;
		alt_u8 keyb_data[4];
		if (uart_data_present != 0) {
			uart_data_present = 0;
			keyb_present = 1;
			memcpy(keyb_data, (void *) uart_data, 4);
		}
		int rx_eth = 0;
		if (rx_eth_flag) {
			rx_eth_flag = 0;
			rx_eth = 1;
		}
		alt_irq_enable_all(irq_context);

		if (rx_eth) {
			while (alt_avalon_sgdma_check_descriptor_status(rx_descriptor) != 0)
				__asm("NOP");

			decode_packet();
			//printf("Eth recv.. ");

			alt_avalon_sgdma_construct_stream_to_mem_desc(rx_descriptor,
					rx_descriptor_end, (alt_u32*) rx_frame, 0, 0);
			alt_avalon_sgdma_do_async_transfer(sgdma_rx_dev, rx_descriptor);
		}

		if (req_present == 1) {
			while (alt_avalon_sgdma_check_descriptor_status(tx_desc_arp) != 0)
				__asm("NOP");

			gen_arp_resp((alt_u8*) tx_frame_arp, req_mac, req_ip);

			alt_dcache_flush_all();

			alt_avalon_sgdma_construct_mem_to_stream_desc(tx_desc_arp,
					tx_desc_arp_end, (alt_u32*) tx_frame_arp, 44, 0, 1, 1, 0);

			alt_avalon_sgdma_do_async_transfer(sgdma_tx_dev, tx_desc_arp);
		} else if (req_present == 2) {
			//memcpy(g_DstMAC, req_mac, 6);
		}

		if (keyb_present == 1) {
			while (alt_avalon_sgdma_check_descriptor_status(tx_desc_keyb) != 0)
				__asm("NOP");

			memcpy((void *) (tx_frame_keyb + UDP_HEADER_SIZE), keyb_data, 4);
			gen_udp_header((void *) tx_frame_keyb, pkt_id++, 0, 20, 0, 20, 1);

			alt_dcache_flush_all();

			alt_avalon_sgdma_construct_mem_to_stream_desc(tx_desc_keyb,
					tx_desc_keyb_end, (alt_u32*) tx_frame_keyb,
					20 + UDP_HEADER_SIZE, 0, 1, 1, 0);

			alt_avalon_sgdma_do_async_transfer(sgdma_tx_dev, tx_desc_keyb);
		}

		recv_data();
	}

	return 0;
}
