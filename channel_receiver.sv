module channel_receiver(
	input							rst_n,
	input							clk,
	
	input							ch_clk,
	input							ch_data,
	
	output						dma_sop,
	output						dma_eop,
	output		[31:0]		dma_data,
	output						dma_vld,
	input							dma_rdy,
	
	input			[7:0]			i_avalon_addr,
	input							i_avalon_rd,
	output		[31:0]		o_avalon_rd_data
);

//channal 0
receiver_dd drsv0(
	.res_n(rst_n),
	.d_rs(ch_data),
	.clk_rs(ch_clk),
	.dout(recv_data),
	.validout(recv_valid) //data_valid[0])
);

wire			[35:0]		recv_data;		//received data
wire	 						recv_valid;		//data valid

ch_fifo ch_fifo_unit(
	.aclr(~rst_n),
	
	.wrclk(ch_clk),
	.data(recv_data),
	.wrreq(recv_valid & ~fifo_full),
	.wrfull(fifo_full),
	
	.rdclk(clk),
	.q(fifo_data),
	.rdreq(fifo_rdy),
	.rdempty(fifo_empty)
);

wire							fifo_full;
wire			[35:0]		fifo_data;
wire							fifo_rdy;
wire							fifo_empty;

plque plque_unit(
	.rst_n(rst_n),
	.clk(clk),
	
	.i_in_data(fifo_data),
	.i_in_vld(~fifo_empty),
	.o_in_rdy(fifo_rdy),
	
	.o_out_data(dma_data),
	.o_out_vld(dma_vld),
	.i_out_rdy(dma_rdy),
	.o_sop(dma_sop),
	.o_eop(dma_eop),
	
	.i_mm_addr(i_avalon_addr),
	.i_mm_rd(i_avalon_rd),
	.o_mm_rd_data(o_avalon_rd_data)
);

endmodule
