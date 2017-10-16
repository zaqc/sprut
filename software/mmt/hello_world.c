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

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

#include "system.h"
#include "altera_avalon_sgdma.h"
#include "altera_avalon_sgdma_descriptor.h"
#include "altera_avalon_sgdma_regs.h"
//----------------------------------------------------------------------------

alt_sgdma_dev *sgdma_data_dev;
alt_sgdma_descriptor *dma_descriptor;
alt_sgdma_descriptor *dma_descriptor_end;
unsigned char *dma_data;
//----------------------------------------------------------------------------

#define	ALT_MM_SLAVE_BASE	0x22000

void data_dma_ethernet_isr(void *context) {
	while (alt_avalon_sgdma_check_descriptor_status(dma_descriptor) != 0)
		__asm("NOP");

	//decode_packet();
	printf("dma bt=%i ", dma_descriptor->actual_bytes_transferred);

	int i;
	for(i = 0; i < 15; i++) {
		//IOWR(ALT_MM_SLAVE_BASE, 0, i + 10);
		int v = IORD(ALT_MM_SLAVE_BASE, i * 2);
		printf("%i ", v);
	}

	alt_avalon_sgdma_construct_stream_to_mem_desc(dma_descriptor,
			dma_descriptor_end, (alt_u32*) dma_data, 0, 0);
	alt_avalon_sgdma_do_async_transfer(sgdma_data_dev, dma_descriptor);
}
//----------------------------------------------------------------------------

int main() {

	volatile int n = 0;
	while(1) {
		IOWR(PIO_0_BASE, 0, n++);
		usleep(1000000);
	}

	// allocate buffer for DMA data
	dma_data = malloc(2048);

	// open DMA handler
	sgdma_data_dev = alt_avalon_sgdma_open(SGDMA_DATA_NAME);
	if (sgdma_data_dev == NULL) {
		printf("could not open sg_dma transmit device\n");
		return -1;
	}

	// Initialize DMA descriptors
	void *temp_ptr = malloc(4 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);
	if (temp_ptr == NULL) {
		printf("Failed to allocate memory for the transmit descriptors\n");
		return -1;
	}
	memset(temp_ptr, 0, 4 * ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE);

	while ((((alt_u32) temp_ptr) % ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE) != 0) {
		temp_ptr++; // slide the pointer until 32 byte boundary is found
	}
	dma_descriptor = (alt_sgdma_descriptor *) temp_ptr;

	temp_ptr += ALTERA_AVALON_SGDMA_DESCRIPTOR_SIZE;
	dma_descriptor_end = (alt_sgdma_descriptor *) temp_ptr;

	dma_descriptor_end->control = 0;

	// Initialize DMA IRQ handler & start receiving data
//	while (alt_avalon_sgdma_check_descriptor_status(dma_descriptor) != 0)
//		__asm("NOP");

	alt_avalon_sgdma_register_callback(sgdma_data_dev,
			(alt_avalon_sgdma_callback) data_dma_ethernet_isr,
			(ALTERA_AVALON_SGDMA_CONTROL_IE_GLOBAL_MSK
					| ALTERA_AVALON_SGDMA_CONTROL_IE_CHAIN_COMPLETED_MSK),
			NULL);

	alt_avalon_sgdma_construct_stream_to_mem_desc(dma_descriptor,
			dma_descriptor_end, (alt_u32*) dma_data, 0, 0);

	alt_avalon_sgdma_do_async_transfer(sgdma_data_dev, dma_descriptor);

	printf("Hello from Nios II!\n");

	while (1) {
		__asm("NOP");
		unsigned int cmd = ((15 << 12) | (14 << 8)) << 16;
		altera_avalon_fifo_write_fifo(FIFO_CMD1_IN_BASE,
				FIFO_CMD1_IN_CSR_BASE, cmd);
		usleep(1000000);
	}

	return 0;
}
//----------------------------------------------------------------------------
