module udp_packet(
	input						rst_n,
	input						clk,
	
	output reg				o_tx_en,
	output	[7:0]			o_tx_data,
	
	input		[47:0]		i_src_mac,
	input		[47:0]		i_dst_mac,
	input		[31:0]		i_src_ip,
	input		[31:0]		i_dst_ip,
	input		[15:0]		i_src_port,
	input		[15:0]		i_dst_port,
	
	input		[15:0]		i_udp_len,
	input		[7:0]			i_udp_stream,
	output					o_udp_rd,
	
	input						i_enable,
	output					o_ready,
	
	output	[4:0]			o_state,
	output	[2:0]			o_send_state,
	output					o_crc_calc,
	
	output   [7:0]			o_crc_data,
	
	output	[31:0]		o_crc32
);

assign o_state = state;
assign o_send_state = send_state;
assign o_crc_calc = ccrc32;

assign o_ready = start;
//----------------------------------------------------------------------------

reg			[0:0]			prev_prev_enable;
always_ff @ (posedge clk or negedge rst_n) 
	if(~rst_n)
		prev_prev_enable <= 1'b0;
	else
		prev_prev_enable <= i_enable;
		
reg			[0:0]			prev_enable;
always_ff @ (posedge clk or negedge rst_n) 
	if(~rst_n)
		prev_enable <= 1'b0;
	else
		prev_enable <= prev_prev_enable;

assign start = (~prev_prev_enable & prev_enable);

//----------------------------------------------------------------------------

reg			[47:0]		src_mac;
reg			[47:0]		dst_mac;
reg			[31:0]		src_ip;
reg			[31:0]		dst_ip;
reg			[15:0]		src_port;
reg			[15:0]		dst_port;
reg			[15:0]		udp_len;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n) begin
		dst_mac <= 48'hd8d38526c578; //48'h0023543c471b;
		src_mac <= 48'h0023543c471b; // 48'h0c54a5312485;
		src_ip <= 32'hc0a84d21; //32'h0A000064;
		dst_ip <= 32'hc0a84dd9; //32'h0A000002;
		dst_port <= 16'hc350; //16'd5152;
		src_port <= 16'hc360; //16'd2179;
		udp_len <= 16'd18; //16'd16;
	end
	else 
		if(start & ready) begin
//			src_mac = i_src_mac;
//			dst_mac = i_dst_mac;
//			src_ip <= i_src_ip;
//			dst_ip <= i_dst_ip;
//			src_port <= i_src_port;
//			dst_port <= i_dst_port;
//			udp_len <= i_udp_len;

			dst_mac <= 48'hd8d38526c578; //48'h0023543c471b;
			src_mac <= 48'h0023543c471b; // 48'h0c54a5312485;
			src_ip <= 32'hc0a84d21; //32'h0A000064;
			dst_ip <= 32'hc0a84dd9; //32'h0A000002;
			dst_port <= 16'hc350; //16'd5152;
			src_port <= 16'hc360; //16'd2179;
			udp_len <= 16'd18; //16'd16;
			
		end

//----------------------------------------------------------------------------

reg			[0:0]			ready;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		ready <= 1'b1;
	else
		if(ready) begin
			if(start)
				ready <= 1'b0;
		end
		else begin
		end

//----------------------------------------------------------------------------

reg			[4:0]			state;
reg			[4:0]			new_state;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		state <= 5'd0;
	else
		state <= new_state;
		
wire							fifo_rst;
wire							sender_ready;

always_comb begin
	new_state = state;
	fifo_rst = 1'b0;
	if(state == 5'h00) begin
		new_state = 5'd1;
	end 
	else 
		if(state == 5'h01) begin
			if(start) begin
				new_state = 5'h02;
				fifo_rst = 1'b1;
			end
		end
		else 
			if(state >= 5'h02 && state <= 5'h16) 
				new_state = state + 1'd1; 
			else
				if(sender_ready)
					new_state = 5'h01;
end

// ===========================================================================
// IP/UDP parameters & header
// ===========================================================================

parameter	[3:0]			ip_header_ver = 4'h4;		// 4 - for IPv4
parameter	[3:0]			ip_header_size = 4'h5;		// size in 32bit word's
parameter	[7:0]			ip_DSCP_ECN = 8'h00;			// ?
wire			[15:0]		ip_pkt_size;
assign  ip_pkt_size = udp_len + 16'h001C;	// 16'h002E size of UDP packet
wire			[31:0]		ip_hdr1;
assign ip_hdr1 = {ip_header_ver, ip_header_size, ip_DSCP_ECN, ip_pkt_size};

parameter	[15:0]		ip_pkt_id = 16'h0;			// pkt id
parameter	[2:0]			ip_pkt_flags = 3'h0;			// pkt flags
reg			[12:0]		ip_pkt_offset = 13'h0;		// pkt offset
wire			[31:0]		ip_hdr2;
assign ip_hdr2 = {ip_pkt_id, ip_pkt_flags, ip_pkt_offset};

parameter	[7:0]			ip_pkt_TTL = 8'hC8;			// pkt TTL
parameter	[7:0]			ip_pkt_type = 8'd17;			// pkt UDP == 17
wire			[15:0]		ip_pkt_CRC;						// pkt flags
wire			[31:0]		tmp_crc;
assign tmp_crc = ip_hdr1[31:16] + ip_hdr1[15:0] +
	ip_hdr2[31:16] + ip_hdr2[15:0] + ip_hdr3[31:16] + // ip_hdr3[15:0] +
	src_ip[31:16] + src_ip[15:0] + dst_ip[31:16] + dst_ip[15:0];
assign ip_pkt_CRC = ~(tmp_crc[31:16] + tmp_crc[15:0]);
wire			[31:0]	ip_hdr3;	
assign ip_hdr3 = {ip_pkt_TTL, ip_pkt_type, ip_pkt_CRC};

wire			[15:0]	udp_crc;
assign udp_crc = 16'd0;

//----------------------------------------------------------------------------

wire			[15:0]		ds_data;
wire							ds_wrreq;
assign ds_wrreq = (state >= 5'h02 && state <= 5'h16) ?  1'b1 : 1'b0;

always_comb begin
	ds_data = 32'd0;
	case(state)
		5'h02: ds_data = dst_mac[47:32];
		5'h03: ds_data = dst_mac[31:16];
		5'h04: ds_data = dst_mac[16:0];
		
		5'h05: ds_data = src_mac[47:32];
		5'h06: ds_data = src_mac[31:16];
		5'h07: ds_data = src_mac[15:0];
		
		5'h08: ds_data = 16'h0800;
		
		5'h09: ds_data = ip_hdr1[31:16];
		5'h0A: ds_data = ip_hdr1[15:0];
		5'h0B: ds_data = ip_hdr2[31:16];
		5'h0C: ds_data = ip_hdr2[15:0];
		5'h0D: ds_data = ip_hdr3[31:16];
		5'h0E: ds_data = ip_hdr3[15:0];
		
		5'h0F: ds_data = src_ip[31:16];
		5'h10: ds_data = src_ip[15:0];
		
		5'h11: ds_data = dst_ip[31:16];
		5'h12: ds_data = dst_ip[15:0];
		
		5'h13: ds_data = dst_port;
		5'h14: ds_data = src_port;
		
		5'h15: ds_data = udp_len + 16'd8;
		5'h16: ds_data = udp_crc;
	endcase
end

//----------------------------------------------------------------------------

tx_fifo_out tx_fifo_out_unit(
	.aclr(start),
	
	.wrclk(clk),
	.data({ds_data[7:0], ds_data[15:8]}),
	.wrreq(ds_wrreq),
	
	.rdclk(clk),
	.rdreq(fifo_rd),
	.q(fifo_tx_data),
	.rdempty(fifo_tx_empty)
);

wire							fifo_rd;
wire							fifo_tx_empty;
wire			[7:0]			fifo_tx_data;

//----------------------------------------------------------------------------

reg			[2:0]			send_state;
reg			[2:0]			next_send_state;

reg			[2:0]			prm_count;
wire							prm_inc;
reg			[2:0]			crc_count;
wire							crc_inc;
reg			[15:0]		udp_count;
wire							udp_inc;

wire							tx_en;
wire							ccrc32;

reg			[7:0]			udp_stream;
always_ff @ (posedge clk) udp_stream <= 8'h00; //i_udp_stream;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		send_state <= 4'd0;
	else 
		send_state <= next_send_state;

always_comb begin
	w_tx_data = 8'h00;
	next_send_state = send_state;
	prm_inc = 1'b0;
	crc_inc = 1'b0;
	udp_inc = 1'b0;
	fifo_rd = 1'b0;
	w_tx_en = 1'b1;
	ccrc32 = 1'b0;
	sender_ready = 1'b0;
	o_udp_rd = 1'b0;
	case(send_state)
		3'h00: {w_tx_en, ccrc32, next_send_state} = (state >= 5'h02) ? {1'b1, 1'b0, 3'h01} : {1'b0, 1'b0, 3'h00}; 
		3'h01: {ccrc32, prm_inc, next_send_state, w_tx_data} = (prm_count != 3'h07) ? {1'b0, 1'b1, 3'h01, 8'h55} : {1'b0, 1'b1, 3'h02, 8'hD5};
		3'h02: {o_udp_rd, ccrc32, fifo_rd, udp_inc, crc_inc, next_send_state, w_tx_data} = (~fifo_tx_empty) ? {1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 3'h02, fifo_tx_data} : 
						((|udp_len) ? {1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 3'h03, udp_stream} : {1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 3'h04, crc32[7:0]});
		3'h03: {o_udp_rd, ccrc32, udp_inc, crc_inc, next_send_state, w_tx_data} = (udp_count != udp_len) ? {1'b1, 1'b1, 1'b1, 1'b0, 3'h03, udp_stream} : 
						{1'b0, 1'b0, 1'b0, 1'b1, 3'h04, crc32[7:0]};
		3'h04: {w_tx_en, ccrc32, crc_inc, next_send_state, w_tx_data} = (crc_count != 3'h04) ? {1'b1, 1'b0, 1'b1, 3'h04, crc32[7:0]} : {1'b1, 1'b0, 1'b0, 3'h05, 8'h00};
		3'h05: {w_tx_en, , sender_ready, next_send_state} = (state == 1) ? {1'b0, 1'b0, 1'b1, 3'h00} : {1'b0, 1'b0, 1'b1, 3'h05};
	endcase
end

wire			[7:0]			w_tx_data;
reg			[7:0]			r_tx_data;
wire							w_tx_en;
reg			[0:0]			r_tx_en;

always_ff @ (posedge clk) begin
	r_tx_data <= w_tx_data;
	r_tx_en <= w_tx_en;
end

assign o_tx_data = r_tx_data;
assign o_tx_en = r_tx_en;

always_ff @ (posedge clk)
	if(prm_inc) 
		prm_count <= prm_count + 1'b1; 
	else
		prm_count <= 3'h00;
		
always_ff @ (posedge clk)
	if(crc_inc)
		crc_count <= crc_count + 1'b1;
	else
		crc_count <= 3'h00;
		
always_ff @ (posedge clk)
	if(udp_inc)
		udp_count <= udp_count + 1'b1;
	else
		udp_count <= 16'h0000;

//assign o_tx_en = (send_state >= 3'h01 && send_state <= 3'h04) ? 1'b1 : 1'b0;

// ===========================================================================
// CRC 32
// ===========================================================================

reg		[0:0]			calc_crc_flag;

always @ (posedge clk or negedge rst_n) begin
	if(1'b0 == rst_n)
		calc_crc_flag <= 1'b0;
	else
		if(send_state != next_send_state) begin
			if(next_send_state == 3'h02)
				calc_crc_flag <= 1'b1;
			else 
				if(next_send_state == 3'h04)
					calc_crc_flag <= 1'b0;
		end
end

wire		[31:0]		crc32;

assign o_crc_data = ccrc32 ? w_tx_data : 8'hFF;

calc_crc32 u_crc32(
	.rst_n(rst_n),
	.clk(clk),
	.i_calc(ccrc32),
	.i_vl(w_tx_en),
	.i_data(w_tx_data),
	.o_crc32(crc32)
);

assign o_crc32 = crc32;

endmodule
