/*
 * recv_data.c
 *
 *  Created on: Sep 9, 2017
 *      Author: zaqc
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include "system.h"
#include "altera_avalon_sgdma.h"
#include "altera_avalon_sgdma_regs.h"
#include "altera_avalon_sgdma_descriptor.h"

#include "altera_avalon_fifo.h"
#include "altera_avalon_fifo_regs.h"
#include "altera_avalon_fifo_util.h"

#include "altera_avalon_tse.h"
#include <sys/alt_irq.h>
#include <sys/alt_cache.h>

#include "eth_util.h"

alt_sgdma_descriptor *l_dscope_desc;
alt_sgdma_descriptor *l_dscope_desc_end;
alt_sgdma_dev *l_dscope_dev;

alt_sgdma_descriptor *r_dscope_desc;
alt_sgdma_descriptor *r_dscope_desc_end;
alt_sgdma_dev *r_dscope_dev;

typedef struct {
	alt_u32 pkt_counter;
	alt_u32 wheel_counter;
	alt_u32 sys_tick;
	alt_u32 ls_status;
	alt_u32 ls_ch_cntr_1;
	alt_u32 ls_ch_cntr_2;
	alt_u32 ls_ch_cntr_3;
	alt_u32 ls_ch_cntr_4;
	alt_u32 rs_status;
	alt_u32 rs_ch_cntr_1;
	alt_u32 rs_ch_cntr_2;
	alt_u32 rs_ch_cntr_3;
	alt_u32 rs_ch_cntr_4;
} frame_header;

typedef struct {
	volatile void *hdr;
	volatile void *ls_frame1;
	volatile void *ls_frame2;
	volatile void *rs_frame1;
	volatile void *rs_frame2;
} udp_ds_frame;

volatile udp_ds_frame *data_1;
volatile udp_ds_frame *data_2;

volatile udp_ds_frame *get_data_ptr;
volatile udp_ds_frame *send_data_ptr;

#define	ALT_MM_SLAVE_READ_STATUS		4

// ===========================================================================
// US Frame Format (send by 5 blocks of UDP)
// ===========================================================================
// FRAME_1
// alt_u32 Packet Counter
// alt_u32 Tick Counter (from wheel)
// alt_u32 DScope_status_left
// alt_u32 DScope_status_right
// FRAME_2
// alt_u8 ch_counter[16] (left side)
// alt_u8 1024 (left side data)
// FRAME_3
// alt_u8 768 (left side data)
// alt_u32 l_side_cntr
// FRAME_4
// alt_u8 ch_counter[16] (right side)
// alt_u8 1024 (right side data)
// FRAME_5
// alt_u8 768 (right side data)
// alt_u32 r_side_cntr
// ===========================================================================

volatile int ls_state = 0;
volatile int rs_state = 0;
volatile alt_u32 l_status = 0;
volatile alt_u32 r_status = 0;
int pkt_counter = 1;

extern alt_u32 sys_tick;
extern alt_u32 ext_tick_present;
extern alt_u32 ext_sync_cntr;

//extern volatile int uart_data_present;
//extern volatile unsigned char uart_data[4];

extern volatile alt_u32 internal_sync;

void dscope_recv_0_handler(void *context) {
	frame_header *hdr;
	alt_u32 status;

	status = IORD(ALT_MM_SLAVE_0_BASE, ALT_MM_SLAVE_READ_STATUS);

	if (ls_state == 1 || (status & 0x4000) == 0) {
		if ((status & 0x01) == 0x00)
			ls_state = 2; //(status & 0x4000) == 0 ? 2 : 4;
		else
			ls_state = 0;
		l_status = status;
	} else if (ls_state == 3 || (status & 0x4000) != 0) {
		hdr = (frame_header *) (get_data_ptr->hdr + UDP_HEADER_SIZE);
		hdr->ls_ch_cntr_1 = IORD(ALT_MM_SLAVE_0_BASE, 0); // read ch counters
		hdr->ls_ch_cntr_2 = IORD(ALT_MM_SLAVE_0_BASE, 1);
		hdr->ls_ch_cntr_3 = IORD(ALT_MM_SLAVE_0_BASE, 2);
		hdr->ls_ch_cntr_4 = IORD(ALT_MM_SLAVE_0_BASE, 3);
		l_status = status;

		ls_state = 4;
	}
}
//----------------------------------------------------------------------------

void dscope_recv_1_handler(void *context) {
	frame_header *hdr;
	alt_u32 status;

	status = IORD(ALT_MM_SLAVE_1_BASE, ALT_MM_SLAVE_READ_STATUS);

	if (rs_state == 1 || (status & 0x4000) == 0) {
		if ((status & 0x01) == 0x00)
			rs_state = 2; //(status & 0x4000) == 0 ? 2 : 4;
		else
			rs_state = 0;
		r_status = status;
	} else if (ls_state == 3 || (status & 0x4000) != 0) {
		hdr = (frame_header *) (get_data_ptr->hdr + UDP_HEADER_SIZE);
		hdr->rs_ch_cntr_1 = IORD(ALT_MM_SLAVE_1_BASE, 0); // read ch counters
		hdr->rs_ch_cntr_2 = IORD(ALT_MM_SLAVE_1_BASE, 1);
		hdr->rs_ch_cntr_3 = IORD(ALT_MM_SLAVE_1_BASE, 2);
		hdr->rs_ch_cntr_4 = IORD(ALT_MM_SLAVE_1_BASE, 3);
		r_status = status;

		rs_state = 4;
	}
}
//----------------------------------------------------------------------------

void init_dscope_desc(void) {
	void *tmp_desc;
	tmp_desc = (void *) alt_uncached_malloc(
			ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE * 6);
	while (((alt_u32) tmp_desc) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE != 0)
		tmp_desc++;

	memset(tmp_desc, 0, ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE * 4);

	l_dscope_desc = (alt_sgdma_descriptor*) tmp_desc;
	tmp_desc += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;

	l_dscope_desc_end = (alt_sgdma_descriptor*) tmp_desc;
	tmp_desc += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;

	l_dscope_desc_end->control = 0;

	r_dscope_desc = (alt_sgdma_descriptor*) tmp_desc;
	tmp_desc += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;

	r_dscope_desc_end = (alt_sgdma_descriptor*) tmp_desc;

	r_dscope_desc_end->control = 0;
}

void init_recv_data(void) {
	send_data_ptr = NULL;

	l_dscope_dev = alt_avalon_sgdma_open(SGDMA_DATA_0_NAME);
	if (l_dscope_dev == NULL) {
		printf("could not open sg_dma DScope(left)\n");
		return;
	}

	r_dscope_dev = alt_avalon_sgdma_open(SGDMA_DATA_1_NAME);
	if (l_dscope_dev == NULL) {
		printf("could not open sg_dma DScope(right)\n");
		return;
	}

	init_dscope_desc();

	data_1 = alt_uncached_malloc(sizeof(udp_ds_frame));
	if (data_1 == NULL) {
		printf("could not allocate buffer for left side\n");
		return;
	}

	data_1->hdr = alt_uncached_malloc(HDR_SIZE);
	data_1->ls_frame1 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	data_1->ls_frame2 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	data_1->rs_frame1 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	data_1->rs_frame2 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	if (data_1->hdr == NULL || data_1->ls_frame1 == NULL
			|| data_1->ls_frame2 == NULL || data_1->rs_frame1 == NULL
			|| data_1->rs_frame2 == NULL) {
		printf("could not allocate buffer for left side\n");
		return;
	}

	data_2 = alt_uncached_malloc(sizeof(udp_ds_frame));
	if (data_1 == NULL) {
		printf("could not allocate buffer for left side\n");
		return;
	}

	data_2->hdr = alt_uncached_malloc(HDR_SIZE);
	data_2->ls_frame1 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	data_2->ls_frame2 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	data_2->rs_frame1 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	data_2->rs_frame2 = alt_uncached_malloc(UDP_HEADER_SIZE + 1024);
	if (data_2->hdr == NULL || data_2->ls_frame1 == NULL
			|| data_2->ls_frame2 == NULL || data_2->rs_frame1 == NULL
			|| data_2->rs_frame2 == NULL) {
		printf("could not allocate buffer for left side\n");
		return;
	}

	get_data_ptr = data_1;

	// Enable IRQ for DScope Receiver (left side)
	alt_avalon_sgdma_register_callback(l_dscope_dev, &dscope_recv_0_handler,
			(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK
					| ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK),
			NULL);

	// Enable IRQ for DScope Receiver (right side)
	alt_avalon_sgdma_register_callback(r_dscope_dev, &dscope_recv_1_handler,
			(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK
					| ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK),
			NULL);

	alt_dcache_flush_all();

//	alt_avalon_sgdma_construct_stream_to_mem_desc(l_dscope_desc, l_dscope_desc_end,
//			(alt_u32*) (get_data_ptr->ls_frame1 + UDP_HEADER_SIZE), 0, 0);
//	alt_avalon_sgdma_do_async_transfer(l_dscope_dev, l_dscope_desc);

	unsigned int cmd = ((15 << 12) | (14 << 8)) << 16;
	altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE, FIFO_CMD_0_IN_CSR_BASE,
			cmd);
	altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE, FIFO_CMD_1_IN_CSR_BASE,
			cmd);
}

// int wait_cntr = 0;
int pkt_id = 0;

alt_u32 prev_sys_tick = 0;
alt_u32 send_pkt_counter = 0;
alt_u32 send_tick_count = 0;
alt_u32 ext_sync_count = 0;

alt_u32 lto = 0;
alt_u32 rto = 0;

void recv_data(void) {
	int i;
	frame_header *hdr;
	int get_data_rdy = 0;
	int lss = 0;
	int rss = 0;
//	int keyb_send = 0;
	alt_irq_context irq_context = alt_irq_disable_all(); // Disable IRQ ===>>>
//	if (0 != uart_data_present) {
//		uart_data_present = 0;
//		keyb_send = 1;
//	}
	if (ls_state == 4 && rs_state == 4) {
		get_data_rdy = 1;
		lto = 0;
		rto = 0;
	} else {
		if (ls_state == 4) {
			if (rto == 0)
				rto = sys_tick;
			else if (rto + 5 < sys_tick)
				get_data_rdy = 1;
		}
		if (rs_state == 4) {
			if (lto == 0)
				lto = sys_tick;
			else if (lto + 5 < sys_tick)
				get_data_rdy = 1;
		}
	}

	if (ls_state == 0) {
		ls_state = 1;
		lss = 1;
	} else if (ls_state == 2) {
		ls_state = 3;
		lss = 2;
	}

	if (rs_state == 0) {
		rs_state = 1;
		rss = 1;
	} else if (rs_state == 2) {
		rs_state = 3;
		rss = 2;
	}
	alt_irq_enable_all(irq_context); // <<<=== Enable IRQ

	// Receive DMA restart for LEFT Side
	if (lss == 1) {
		while (alt_avalon_sgdma_check_descriptor_status(l_dscope_desc) != 0)
			__asm("NOP");
		alt_avalon_sgdma_construct_stream_to_mem_desc(l_dscope_desc,
				l_dscope_desc_end,
				(alt_u32*) (get_data_ptr->ls_frame1 + UDP_HEADER_SIZE), 0, 0);
		alt_avalon_sgdma_do_async_transfer(l_dscope_dev, l_dscope_desc);
	} else if (lss == 2) {
		while (alt_avalon_sgdma_check_descriptor_status(l_dscope_desc) != 0)
			__asm("NOP");
		alt_avalon_sgdma_construct_stream_to_mem_desc(l_dscope_desc,
				l_dscope_desc_end,
				(alt_u32*) (get_data_ptr->ls_frame2 + UDP_HEADER_SIZE), 0, 0);
		alt_avalon_sgdma_do_async_transfer(l_dscope_dev, l_dscope_desc);
	}

	// Receive DMA restart for RIGHT Side
	if (rss == 1) {
		while (alt_avalon_sgdma_check_descriptor_status(r_dscope_desc) != 0)
			__asm("NOP");
		alt_avalon_sgdma_construct_stream_to_mem_desc(r_dscope_desc,
				r_dscope_desc_end,
				(alt_u32*) (get_data_ptr->rs_frame1 + UDP_HEADER_SIZE), 0, 0);
		alt_avalon_sgdma_do_async_transfer(r_dscope_dev, r_dscope_desc);
	} else if (rss == 2) {
		while (alt_avalon_sgdma_check_descriptor_status(r_dscope_desc) != 0)
			__asm("NOP");
		alt_avalon_sgdma_construct_stream_to_mem_desc(r_dscope_desc,
				r_dscope_desc_end,
				(alt_u32*) (get_data_ptr->rs_frame2 + UDP_HEADER_SIZE), 0, 0);
		alt_avalon_sgdma_do_async_transfer(r_dscope_dev, r_dscope_desc);
	}

//	wait_cntr++;

	for (i = 0; i < 10; i++)
		__asm("NOP");

	if (get_data_rdy) {
		// waiting Ethernet TX descriptors
		if (NULL != send_data_ptr) {
			while (alt_avalon_sgdma_check_descriptor_status(tx_descriptor_1)
					!= 0
					|| alt_avalon_sgdma_check_descriptor_status(tx_descriptor_2)
							!= 0
					|| alt_avalon_sgdma_check_descriptor_status(tx_descriptor_3)
							!= 0
					|| alt_avalon_sgdma_check_descriptor_status(tx_descriptor_4)
							!= 0
					|| alt_avalon_sgdma_check_descriptor_status(tx_descriptor_5)
							!= 0)
				__asm("NOP");
		}

		hdr = (frame_header *) (get_data_ptr->hdr + UDP_HEADER_SIZE);

		irq_context = alt_irq_disable_all(); // Disable IRQ ===>>>
		hdr->pkt_counter = pkt_counter++;
		hdr->ls_status = l_status; // safe operation
		hdr->rs_status = r_status;
		hdr->sys_tick = sys_tick;
		hdr->wheel_counter = ext_sync_cntr;
		alt_irq_enable_all(irq_context); // <<<=== Enable IRQ

//		alt_u32 status1 = hdr->ls_status;
//		alt_u32 status2 = hdr->rs_status;
//
//		printf(" [%i %i] ", (int) ((status1 >> 2) & 0x3FF),
//				(int) (status1 & 0x03));
//
//		printf(" [%i %i] ", (int) ((status2 >> 2) & 0x3FF),
//				(int) (status2 & 0x03));
//
//		//printf(" wait_counter=%i ", wait_cntr);
//		//wait_cntr = 0;
//
//		for (i = 0; i < 4; i++) {
//			alt_u32 ch_cntr1;
//			alt_u32 ch_cntr2;
//			if (i == 0) {
//				ch_cntr1 = hdr->ls_ch_cntr_1;
//				ch_cntr2 = hdr->rs_ch_cntr_1;
//			} else if (i == 1) {
//				ch_cntr1 = hdr->ls_ch_cntr_2;
//				ch_cntr2 = hdr->rs_ch_cntr_2;
//			} else if (i == 2) {
//				ch_cntr1 = hdr->ls_ch_cntr_3;
//				ch_cntr2 = hdr->rs_ch_cntr_3;
//			} else if (i == 3) {
//				ch_cntr1 = hdr->ls_ch_cntr_4;
//				ch_cntr2 = hdr->rs_ch_cntr_4;
//			}
//
//			unsigned int j;
//			for (j = 0; j < 4; j++) {
//				unsigned char ch_len1 = (unsigned char) ((ch_cntr1
//						>> (8 * (3 - j))) & 0xFF);
//				unsigned char ch_len2 = (unsigned char) ((ch_cntr2
//						>> (8 * (3 - j))) & 0xFF);
//				printf("%i_%i ", (int) ch_len1, (int) ch_len2);
//			}
//		}
//		printf("\n");

		send_data_ptr = get_data_ptr;

		if (get_data_ptr == data_1)
			get_data_ptr = data_2;
		else
			get_data_ptr = data_1;

		pkt_id++;
		int pkt_size = 128 + 1024 + 768 + 8 + 1024 + 768 + 8;
		int fragmetn_offset = 0;
		gen_udp_header((alt_u8*) send_data_ptr->hdr, pkt_id, fragmetn_offset,
				128, 1, pkt_size, 0);
		fragmetn_offset += 128;
		gen_udp_header((alt_u8*) send_data_ptr->ls_frame1, pkt_id,
				fragmetn_offset, 1024, 1, pkt_size, 0);
		fragmetn_offset += 1024;
		gen_udp_header((alt_u8*) send_data_ptr->ls_frame2, pkt_id,
				fragmetn_offset, 768 + 8, 1, pkt_size, 0);
		fragmetn_offset += (768 + 8);
		gen_udp_header((alt_u8*) send_data_ptr->rs_frame1, pkt_id,
				fragmetn_offset, 1024, 1, pkt_size, 0);
		fragmetn_offset += 1024;
		gen_udp_header((alt_u8*) send_data_ptr->rs_frame2, pkt_id,
				fragmetn_offset, 768 + 8, 0, pkt_size, 0);

		alt_dcache_flush_all();

		alt_u8 led = 0;
		led |= ((*(unsigned char *) (get_data_ptr->ls_frame2 + UDP_HEADER_SIZE
				+ 770)) << 4) & 0xF0;
		led |= ((*(unsigned char *) (get_data_ptr->rs_frame2 + UDP_HEADER_SIZE
				+ 770))) & 0x0F;
		IOWR(PIO_LED_BASE, 0, ~led);

		alt_avalon_sgdma_construct_mem_to_stream_desc(tx_descriptor_1,
				tx_descriptor_2, (alt_u32*) send_data_ptr->hdr, HDR_SIZE, 0, 1,
				1, 0);
		alt_avalon_sgdma_do_async_transfer(sgdma_tx_dev, tx_descriptor_1);

		alt_avalon_sgdma_construct_mem_to_stream_desc(tx_descriptor_2,
				tx_descriptor_3, (alt_u32*) send_data_ptr->ls_frame1,
				UDP_HEADER_SIZE + 1024, 0, 1, 1, 0);
		alt_avalon_sgdma_do_async_transfer(sgdma_tx_dev, tx_descriptor_2);

		alt_avalon_sgdma_construct_mem_to_stream_desc(tx_descriptor_3,
				tx_descriptor_4, (alt_u32*) send_data_ptr->ls_frame2,
				UDP_HEADER_SIZE + 768 + 8, 0, 1, 1, 0);
		alt_avalon_sgdma_do_async_transfer(sgdma_tx_dev, tx_descriptor_3);

		alt_avalon_sgdma_construct_mem_to_stream_desc(tx_descriptor_4,
				tx_descriptor_5, (alt_u32*) send_data_ptr->rs_frame1,
				UDP_HEADER_SIZE + 1024, 0, 1, 1, 0);
		alt_avalon_sgdma_do_async_transfer(sgdma_tx_dev, tx_descriptor_4);

		alt_avalon_sgdma_construct_mem_to_stream_desc(tx_descriptor_5,
				tx_descriptor_end, (alt_u32*) send_data_ptr->rs_frame2,
				UDP_HEADER_SIZE + 768 + 8, 0, 1, 1, 0);
		alt_avalon_sgdma_do_async_transfer(sgdma_tx_dev, tx_descriptor_5);

		memset((void *) get_data_ptr->hdr + UDP_HEADER_SIZE, 0,
				DSCOPE_HDR_SIZE);

		irq_context = alt_irq_disable_all();
		if (ls_state == 4)
			ls_state = 0;
		if (rs_state == 4)
			rs_state = 0;

		l_status &= 0x3;
		r_status &= 0x3;

		alt_irq_enable_all(irq_context);

		get_data_rdy = 0;

		send_pkt_counter++;
	}

	// Send Sync Command to both DScope side
	int tick_present = 0;
	irq_context = alt_irq_disable_all();
	if (ext_tick_present == 1) {
		ext_tick_present = 0;
		if (internal_sync == 0)
			tick_present = 1;
	}

	if (prev_sys_tick != sys_tick) {
		if (internal_sync != 0)
			tick_present = 1;
		prev_sys_tick = sys_tick;
	}

	if (send_tick_count + 1000 <= sys_tick) {
		// printf("fc = %i es = %i \n", (int)send_pkt_counter, (int)ext_sync_count);
		send_pkt_counter = 0;
		ext_sync_count = 0;
		send_tick_count = sys_tick;
	}

	if (tick_present) {
		ext_sync_count++;
		unsigned int cmd = ((15 << 12) | (14 << 8)) << 16;
		altera_avalon_fifo_write_fifo(FIFO_CMD_0_IN_BASE,
				FIFO_CMD_0_IN_CSR_BASE, cmd);
		altera_avalon_fifo_write_fifo(FIFO_CMD_1_IN_BASE,
				FIFO_CMD_1_IN_CSR_BASE, cmd);
	}
	alt_irq_enable_all(irq_context);
}
