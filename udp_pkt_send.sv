module udp_pkt_send(
	input							clk,
	input							rst_n,
	
	output		[7:0]			o_tx_data,
	output						o_tx_en,
	
	input 		[47:0]		i_dst_mac,
	input			[47:0]		i_src_mac,
	
	input			[31:0]		i_src_ip,
	input			[31:0]		i_dst_ip,
	input			[15:0]		i_src_port,
	input			[15:0]		i_dst_port,
	
	input			[7:0]			i_in_data,
	input			[15:0]		i_data_len,
	output						o_rd,
	
	input							i_enable,
	output						o_ready,

	output		[7:0]			o_dbg_crc32_data,
	output						o_dbg_crc32_flag,
	output		[31:0]		o_dbg_crc32
);

reg			[7:0]			pkt[42];

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n) begin
		for(integer i = 0; i < 42; i++)
			pkt[i] = 8'h00;
	end
	else
		if(state == IDLE && new_state == LATCH_PARAM) begin
			{pkt[0], pkt[1], pkt[2], pkt[3], pkt[4], pkt[5],
			 pkt[6], pkt[7], pkt[8], pkt[9], pkt[10], pkt[11],
			 pkt[12], pkt[13],
			 pkt[14], pkt[15], pkt[16], pkt[17],
			 pkt[18], pkt[19], pkt[20], pkt[21],
			 pkt[22], pkt[23], pkt[24], pkt[25],
			 pkt[26], pkt[27], pkt[28], pkt[29],
			 pkt[30], pkt[31], pkt[32], pkt[33],
			 pkt[34], pkt[35],
			 pkt[36], pkt[37],
			 pkt[38], pkt[39],
			 pkt[40], pkt[41]} <= {i_dst_mac, i_src_mac, 16'h0800, 
											ip_hdr1, ip_hdr2, ip_hdr3, i_src_ip, i_dst_ip,
											i_src_port, i_dst_port, udp_length, udp_crc};
		end

// ===========================================================================
// READY
// ===========================================================================

assign o_ready = (state == IDLE) ? 1'b1 : 1'b0;
assign o_rd = (state == SEND_UDP_DATA) ? 1'b1 : 1'b0;

// ===========================================================================
// IP/UDP parameters & header
// ===========================================================================

parameter	[3:0]		ip_header_ver = 4'h4;		// 4 - for IPv4
parameter	[3:0]		ip_header_size = 4'h5;		// size in 32bit word's
parameter	[7:0]		ip_DSCP_ECN = 8'h00;			// ?
wire			[15:0]	ip_pkt_size;
assign  ip_pkt_size = i_data_len + 16'h001C;	// 16'h002E size of UDP packet
wire			[31:0]	ip_hdr1;
assign ip_hdr1 = {ip_header_ver, ip_header_size, ip_DSCP_ECN, ip_pkt_size};

parameter	[15:0]	ip_pkt_id = 16'h0;			// pkt id
parameter	[2:0]		ip_pkt_flags = 3'h0;			// pkt flags
reg			[12:0]	ip_pkt_offset = 13'h0;		// pkt offset
wire			[31:0]	ip_hdr2;
assign ip_hdr2 = {ip_pkt_id, ip_pkt_flags, ip_pkt_offset};

parameter	[7:0]		ip_pkt_TTL = 8'hC8;			// pkt TTL
parameter	[7:0]		ip_pkt_type = 8'd17;			// pkt UDP == 17

wire			[31:0]	tmp_crc_1;
wire			[31:0]	tmp_crc_2;
wire			[31:0]	tmp_crc_3;
wire			[31:0]	tmp_crc_4;
wire			[31:0]	tmp_crc_5;
wire			[31:0]	tmp_crc_6;
wire			[31:0]	tmp_crc_7;
wire			[31:0]	tmp_crc;
assign tmp_crc_1 = ip_hdr1[31:16] + ip_hdr1[15:0];
assign tmp_crc_2 = tmp_crc_1 + ip_hdr2[31:16];
assign tmp_crc_3 = tmp_crc_2 + ip_hdr2[15:0];
assign tmp_crc_4 = tmp_crc_3 + {ip_pkt_TTL, ip_pkt_type};
assign tmp_crc_5 = tmp_crc_4 + i_src_ip[31:16];
assign tmp_crc_6 = tmp_crc_5 + i_src_ip[15:0];
assign tmp_crc_7 = tmp_crc_6 + i_dst_ip[31:16];
assign tmp_crc = tmp_crc_7 + i_dst_ip[15:0];

wire			[31:0]	ip_pkt_CRC;						// pkt flags
assign ip_pkt_CRC = ~(tmp_crc[31:16] + tmp_crc[15:0]);
wire			[31:0]	ip_hdr3;	
assign ip_hdr3 = {ip_pkt_TTL, ip_pkt_type, ip_pkt_CRC[15:0]};

// ===========================================================================
// STATE MACHINE
// ===========================================================================

enum logic [3:0] { 
	NONE, 
	IDLE, 
	LATCH_PARAM, 
	ETH_START, 
	SEND_PREAMBLE, 
	SEND_HEADER, 
	SEND_UDP_DATA, 
	WAIT_FOR_CRC32,
	SEND_CRC32, 
	DELAY, 
	SET_READY 
} state, new_state;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		state <= NONE;
	else
		state <= new_state;

always @ (*) begin
	new_state = state;
	case(state)
		NONE: if(rst_n) new_state = IDLE;
		IDLE: if(i_enable) new_state = LATCH_PARAM;
		LATCH_PARAM: new_state = ETH_START;
		ETH_START: new_state = SEND_PREAMBLE;
		SEND_PREAMBLE: if(ds_cnt == 16'd7) new_state = SEND_HEADER;
		SEND_HEADER: if(ds_cnt == 16'd41) new_state = SEND_UDP_DATA;
		SEND_UDP_DATA: if(ds_cnt == i_data_len || ds_cnt + 16'd1 == i_data_len) new_state = WAIT_FOR_CRC32;
		WAIT_FOR_CRC32: new_state = SEND_CRC32;
		SEND_CRC32: if(ds_cnt == 16'd3) new_state = DELAY;
		DELAY: if(ds_cnt == 16'd10) new_state = SET_READY;
		SET_READY: if(~i_enable) new_state = IDLE;
		default: new_state = state;
	endcase
end

wire							tmp_tx_en;
assign tmp_tx_en = (state > ETH_START && state < DELAY && new_state < DELAY) ? 1'b1 : 1'b0;

wire			[7:0]			tmp_tx_data;
always_comb begin
	case(state)
		SEND_PREAMBLE: tmp_tx_data = (ds_cnt != 16'd7) ? 8'h55 : 8'hD5;
		SEND_HEADER: tmp_tx_data = pkt[ds_cnt];
		SEND_UDP_DATA: tmp_tx_data = i_in_data;
		default: tmp_tx_data = 8'h00;
	endcase
end

always_ff @ (posedge clk) begin
	dly_tx_data <= tmp_tx_data;
	dly_tx_en <= tmp_tx_en;
end

reg			[7:0]			dly_tx_data;
reg			[0:0]			dly_tx_en;

assign o_tx_en = dly_tx_en;
assign o_tx_data = (state == SEND_CRC32) ? crc32[7:0] : dly_tx_data;

// ===========================================================================
//	DATA SHIFT & SEND
// ===========================================================================

reg			[15:0]		ds_cnt;
always_ff @ (posedge clk or negedge rst_n)
	if(rst_n == 1'b0)
		ds_cnt <= 16'd0;
	else 
		if(new_state != state)
			ds_cnt <= 16'd0;
		else
			ds_cnt <= ds_cnt + 16'd1;

//----------------------------------------------------------------------------

wire			[15:0]	udp_length;
assign udp_length = i_data_len + 16'd8;
wire			[15:0]	udp_crc;
assign udp_crc = 16'd0;

// ===========================================================================
// CRC 32
// ===========================================================================

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

endmodule
