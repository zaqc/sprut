module send_udp_block(
	input							rst_n,
	input							i_tx_clk,

	output						o_tx_en,
	output		[7:0]			o_tx_data,

	input			[10:0]		i_data_len,

	input							i_enable,
	output						o_ready,

	output		[7:0]			o_dbg_crc32_data,
	output						o_dbg_crc32_flag,
	output		[31:0]		o_dbg_crc32	
);

ram_block ram_block_unit(
	
);

// ===========================================================================
// CRC 32
// ===========================================================================
/*
reg		[0:0]			calc_crc_flag;

always @ (posedge clk or negedge rst_n) begin
	if(1'b0 == rst_n)
		calc_crc_flag <= 1'b0;
	else
		if(new_state != state) begin
			if(new_state == SEND_HEADER)
				calc_crc_flag <= 1'b1;
			else 
				if(new_state == WAIT_FOR_CRC32)
					calc_crc_flag <= 1'b0;
		end
end

wire		[31:0]		crc32;

tx_calc_crc32 tx_calc_crc32_unit(
	.rst_n(rst_n),
	.clk(clk),
	.i_calc(calc_crc_flag),
	.i_vl(tmp_tx_en),
	.i_data(tmp_tx_data),
	.o_crc32(crc32)
);

assign o_dbg_crc32_data = tmp_tx_data;
assign o_dbg_crc32_flag = calc_crc_flag;
assign o_dbg_crc32 = crc32;
*/
endmodule
