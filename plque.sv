module plque(
	input						rst_n,
	input						clk,
	
	input		[35:0]		i_in_data,
	input						i_in_vld,
	output					o_in_rdy,
	
	output					o_sop,
	output					o_eop,
	output	[31:0]		o_out_data,
	output					o_out_vld,
	input						i_out_rdy,
	
	input		[7:0]			i_mm_addr,
	input						i_mm_rd,
	output	[31:0]		o_mm_rd_data
);

reg			[35:0]		pl_data;
reg			[0:0]			pl_vld;

reg			[0:0]			pl_empty;

reg			[0:0]			pl_sop;
reg			[0:0]			pl_eop;

reg			[35:0]		prev_data;

reg			[7:0]			ch_data_len[0:15];

reg			[7:0]			read_addr;

wire							sop_flag;
assign sop_flag = &prev_data[35:32] & ~&i_in_data[35:32];

wire							eop_flag;
assign eop_flag = ~&prev_data[35:32] & &i_in_data[35:32];

wire							in_data_latch_flag;
assign in_data_latch_flag = i_in_vld & (pl_empty | i_out_rdy);



//----------------------------------------------------------------------------
// out data to NIOS
//----------------------------------------------------------------------------

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		read_addr <= 8'd0;
	else
		if(i_mm_rd)
			read_addr <= i_mm_addr;
			
always_comb
	case(read_addr[2:0])
		3'd0: o_mm_rd_data = {ch_data_len[4'd3], ch_data_len[4'd2], ch_data_len[4'd1], ch_data_len[4'd0]};
		3'd1: o_mm_rd_data = {ch_data_len[4'd7], ch_data_len[4'd6], ch_data_len[4'd5], ch_data_len[4'd4]};
		3'd2: o_mm_rd_data = {ch_data_len[4'd11], ch_data_len[4'd10], ch_data_len[4'd9], ch_data_len[4'd8]};
		3'd3: o_mm_rd_data = {ch_data_len[4'd15], ch_data_len[4'd14], ch_data_len[4'd13], ch_data_len[4'd12]};
		3'd4: o_mm_rd_data = {17'd0, eop_status, status_data_len, ch_order_error_flag, ds_cntr_error};
		3'd5: o_mm_rd_data = {ch_counter};
		default: o_mm_rd_data = {{24{1'b0}}, read_addr};
	endcase

//----------------------------------------------------------------------------
// processing DScope status
//----------------------------------------------------------------------------

reg			[0:0]				eop_status;
always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		eop_status <= 1'b0;
	else
		if(in_data_latch_flag)
			if(eop_flag)
				eop_status <= 1'b1;
			else
				if(sop_flag)
					eop_status <= 1'b0;

//----------------------------------------------------------------------------

reg			[0:0]				prev_mm_rd;
always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		prev_mm_rd <= 1'b0;
	else
		prev_mm_rd <= i_mm_rd;

reg			[0:0]				data_present;
always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		data_present <= 1'b0;
	else
		if(~prev_mm_rd & i_mm_rd & (i_mm_addr[2:0] == 3'd4))
			data_present <= 1'b0;
		else
			if(in_data_latch_flag)
				data_present <= 1'b1;

reg			[11:0]			status_data_len;
always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		status_data_len <= 12'd0;
	else
		if(~prev_mm_rd & i_mm_rd & (i_mm_addr[2:0] == 3'd4)) 
			status_data_len <= (data_present == 1'b1) ?  recv_data_len : 12'd0;

reg			[11:0]			recv_data_len;
always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		recv_data_len <= 12'd0;
	else
		if(in_data_latch_flag)
			if(sop_flag)
				recv_data_len <= 12'd1;
			else
				if(~&recv_data_len)
					recv_data_len  <= recv_data_len  + 12'd1;

//----------------------------------------------------------------------------

reg			[0:0]				ds_cntr_error;
reg			[31:0]			ch_counter;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		ch_counter <= 32'd0;
	else
		if(in_data_latch_flag & eop_flag) 
			ch_counter <= i_in_data[31:0];

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		ds_cntr_error <= 1'b0;
	else
		if(in_data_latch_flag & eop_flag)
			if((ch_counter + 32'd1) != i_in_data[31:0])
				ds_cntr_error <= 1'b1;
			else
				ds_cntr_error <= 1'b0;
	
//----------------------------------------------------------------------------
// calc data count for each channel
//----------------------------------------------------------------------------

reg			[3:0]				prev_ch_num;
reg			[0:0]				ch_order_error_flag;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		prev_ch_num <= 4'd0;
	else
		if(in_data_latch_flag)
			prev_ch_num <= i_in_data[35:32];

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		ch_order_error_flag <= 1'b0;
	else
		if(in_data_latch_flag) begin
			if(sop_flag)
				ch_order_error_flag <= 1'b0;
			else
				if(|i_in_data[35:32] & ~&i_in_data[35:32] & (prev_ch_num != i_in_data[35:32]))
					if((ch_data_len[prev_ch_num] != 8'd32) || ((prev_ch_num + 4'd1) != i_in_data[35:32]))
						ch_order_error_flag <= 1'b1;
		end

//----------------------------------------------------------------------------

always_ff @  (posedge clk or negedge rst_n)
	if(~rst_n)
		for(int i = 0; i <= 15; i++)
			ch_data_len[i] <= 8'd0;
	else
		if(in_data_latch_flag) begin
			if(sop_flag) begin				
				for(int i = 4'd0; i <= 4'd15; i++)
					ch_data_len[i] <= (i_in_data[35:32] == i[3:0]) ? 8'd1 : 8'd0;
			end
			else
				ch_data_len[i_in_data[35:32]] <= ch_data_len[i_in_data[35:32]] + 8'd1;
		end

//----------------------------------------------------------------------------

always_ff @  (posedge clk or negedge rst_n)
	if(~rst_n)
		prev_data <= 36'd0;
	else
		if(in_data_latch_flag)
			prev_data <= i_in_data;

reg			[11:0]		word_cntr;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n) begin
		pl_sop <= 1'b0;
		pl_eop <= 1'b0;
		word_cntr <= 12'd0;
	end
	else begin
		if(i_in_vld) begin
			if(pl_empty | i_out_rdy) begin
				if(word_cntr == 12'd255 || (&prev_data[35:32] & ~&i_in_data[35:32]))
					word_cntr <= 12'd0;
				else
					word_cntr <= word_cntr + 12'd1;
				pl_sop <= (&prev_data[35:32] & ~&i_in_data[35:32]) ? 1'b1 : 1'b0;
				pl_eop <= (~&prev_data[35:32] & &i_in_data[35:32]) ? 1'b1 : 1'b0;
			end
		end
		else
			if(i_out_rdy) begin
				pl_sop <= 1'b0;
				pl_eop <= 1'b0;
			end
	end
	
assign o_sop = pl_sop | (~|word_cntr);
assign o_eop = pl_eop | (word_cntr == 12'd255 ? 1'b1 : 1'b0);

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		pl_empty <= 1'b0;
	else
		pl_empty <= ~i_in_vld & i_out_rdy ? 1'b1 : 1'b0;

assign o_in_rdy = pl_empty | i_out_rdy;

always_ff @ (posedge clk or negedge rst_n) begin
	if(~rst_n)
		pl_vld <= 1'b0;
	else
		if(i_in_vld) begin
			if(pl_empty | i_out_rdy) begin
				pl_data <= i_in_data;
				pl_vld <= 1'b1;
			end
		end 
		else
			if(i_out_rdy)
				pl_vld <= 1'b0;
end

assign o_out_data = pl_data[31:0];
assign o_out_vld = pl_vld; // & ~ch_order_error_flag & ~ds_cntr_error & ~&recv_data_len;

endmodule
