module udp_send(
	input							clk,
	input							rst_n,
	
	output		[7:0]			o_tx_data,
	output						o_tx_en,
	
	input reg	[47:0]		i_dst_mac,
	input	reg	[47:0]		i_src_mac,
	
	input	reg	[31:0]		i_src_ip,
	input	reg	[31:0]		i_dst_ip,
	input	reg	[15:0]		i_src_port,
	input	reg	[15:0]		i_dst_port,
	
	input		[7:0]				i_in_data,
	input		[15:0]			i_data_len,
	output						o_rd,
	
	input							i_enable,
	output						o_ready,

	output	[7:0]				o_dbg_crc32_data,
	output						o_dbg_crc32_flag,
	output	[31:0]			o_dbg_crc32
);

reg			[47:0]		dst_mac;
reg			[47:0]		src_mac;
reg			[31:0]		dst_ip;
reg			[31:0]		src_ip;
reg			[15:0]		dst_port;
reg			[15:0]		src_port;
reg			[15:0]		data_len;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n) begin
//		dst_mac <= 48'd0;
//		src_mac <= 48'd0;
//		dst_ip <= 32'd0;
//		src_ip <= 32'd0;
//		dst_port <= 16'd0;
//		src_port <= 16'd0;
//		data_len <= 16'd0;

		dst_mac <= 48'hd8d38526c578; //48'h0023543c471b;
		src_mac <= 48'h0023543c471b; // 48'h0c54a5312485;
		src_ip <= 32'hc0a84d21; //32'h0A000064;
		dst_ip <= 32'hc0a84dd9; //32'h0A000002;
		src_port <= 16'hc350; //16'd5152;
		dst_port <= 16'hc360; //16'd2179;
		data_len <= 16'd18; //16'd16;
	end
	else 
		if(state != new_state && new_state == SEND_PREAMBLE) begin
			dst_mac <= i_dst_mac;
			src_mac <= i_src_mac;
			dst_ip <= i_dst_ip;
			src_ip <= i_src_ip;
			dst_port <= i_dst_port;
			src_port <= i_src_port;
			data_len <= i_data_len;

//			dst_mac <= 48'hd8d38526c578; //48'h0023543c471b;
//			src_mac <= 48'h0023543c471b; // 48'h0c54a5312485;
//			src_ip <= 32'hc0a84d21; //32'h0A000064;
//			dst_ip <= 32'hc0a84dd9; //32'h0A000002;
//			src_port <= 16'hc350; //16'd5152;
//			dst_port <= 16'hc360; //16'd2179;
//			data_len <= 16'd18; //16'd16;
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
assign  ip_pkt_size = data_len + 16'h001C;	// 16'h002E size of UDP packet
wire			[31:0]	ip_hdr1;
assign ip_hdr1 = {ip_header_ver, ip_header_size, ip_DSCP_ECN, ip_pkt_size};

parameter	[15:0]	ip_pkt_id = 16'h0;			// pkt id
parameter	[2:0]		ip_pkt_flags = 3'h0;			// pkt flags
reg			[12:0]	ip_pkt_offset = 13'h0;		// pkt offset
wire			[31:0]	ip_hdr2;
assign ip_hdr2 = {ip_pkt_id, ip_pkt_flags, ip_pkt_offset};

parameter	[7:0]		ip_pkt_TTL = 8'hC8;			// pkt TTL
parameter	[7:0]		ip_pkt_type = 8'd17;			// pkt UDP == 17
wire			[15:0]	ip_pkt_CRC;						// pkt flags
wire			[31:0]	tmp_crc;
assign tmp_crc = ip_hdr1[31:16] + ip_hdr1[15:0] +
	ip_hdr2[31:16] + ip_hdr2[15:0] + ip_hdr3[31:16] + // ip_hdr3[15:0] +
	src_ip[31:16] + src_ip[15:0] + dst_ip[31:16] + dst_ip[15:0];
assign ip_pkt_CRC = ~(tmp_crc[31:16] + tmp_crc[15:0]);
wire			[31:0]	ip_hdr3;	
assign ip_hdr3 = {ip_pkt_TTL, ip_pkt_type, ip_pkt_CRC};

// ===========================================================================
// STATE MACHINE
// ===========================================================================

enum logic [4:0] {
	NONE = 5'd0,
	IDLE = 5'd1,
	ETH_START = 5'd2,
	SEND_PREAMBLE = 5'd3,
	SEND_DST_MAC = 5'd4,
	SEND_SRC_MAC = 5'd5,
	SEND_ETHER_TYPE = 5'd6,
	SEND_HDR1 = 5'd7,
	SEND_HDR2 = 5'd8,
	SEND_HDR3 = 5'd9,
	SEND_SRC_IP = 5'd10,
	SEND_DST_IP = 5'd11,
	SEND_UDP_SRC_PORT = 5'd12,
	SEND_UDP_DST_PORT = 5'd13,
	SEND_UDP_LEN = 5'd14,
	SEND_UDP_CRC = 5'd15,
	SEND_UDP_DATA = 5'd16,
	WAIT_FOR_CRC32 = 5'd17,
	SEND_CRC32 = 5'd18,
	DELAY = 5'd19,
	SET_READY = 5'd20
} new_state, state;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		state <= NONE;
	else
		state <= new_state;

always_comb begin
	new_state = state;
	case(state)
		NONE: if(rst_n) new_state = IDLE;
		IDLE: if(i_enable) new_state = ETH_START;
		ETH_START: if(~i_enable) new_state = SEND_PREAMBLE;
		SEND_PREAMBLE: if(ds_cnt == 16'd8) new_state = SEND_DST_MAC;
		SEND_DST_MAC: if(ds_cnt == 16'd6) new_state = SEND_SRC_MAC;
		SEND_SRC_MAC: if(ds_cnt == 16'd6) new_state = SEND_ETHER_TYPE;
		SEND_ETHER_TYPE: if(ds_cnt == 16'd2) new_state = SEND_HDR1;
		SEND_HDR1: if(ds_cnt == 16'd4) new_state = SEND_HDR2;
		SEND_HDR2: if(ds_cnt == 16'd4) new_state = SEND_HDR3;
		SEND_HDR3: if(ds_cnt == 16'd4) new_state = SEND_SRC_IP;
		SEND_SRC_IP: if(ds_cnt == 16'd4) new_state = SEND_DST_IP;
		SEND_DST_IP: if(ds_cnt == 16'd4) new_state = SEND_UDP_SRC_PORT;
		SEND_UDP_SRC_PORT: if(ds_cnt == 16'd2) new_state = SEND_UDP_DST_PORT;
		SEND_UDP_DST_PORT: if(ds_cnt == 16'd2) new_state = SEND_UDP_LEN;
		SEND_UDP_LEN: if(ds_cnt == 16'd2) new_state = SEND_UDP_CRC;
		SEND_UDP_CRC: if(ds_cnt == 16'd2) new_state = SEND_UDP_DATA;
		SEND_UDP_DATA: if(ds_cnt == data_len) new_state = WAIT_FOR_CRC32;
		WAIT_FOR_CRC32: new_state = SEND_CRC32;
		SEND_CRC32: if(ds_cnt == 16'd4) new_state = DELAY;
		DELAY: if(ds_cnt == 16'd10) new_state = SET_READY;
		SET_READY: if(~i_enable) new_state = IDLE;
	endcase
end

wire							tmp_tx_en;
assign tmp_tx_en = (state > ETH_START && state < DELAY && new_state < DELAY) ? 1'b1 : 1'b0;
wire			[7:0]			tmp_tx_data;
assign tmp_tx_data = (state == SEND_UDP_DATA) ? i_in_data : ds[63:56];

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

reg			[63:0]		ds;
reg			[15:0]		ds_cnt;
always_ff @ (posedge clk or negedge rst_n) begin
	if(rst_n == 1'b0) begin
		ds <= 64'd0;
		ds_cnt <= 16'd0;
	end
	else begin
		if(new_state != state) begin
			case(new_state)
				SEND_PREAMBLE: ds <= 64'h55555555555555d5;
				SEND_DST_MAC: ds[63:16] <= dst_mac;
				SEND_SRC_MAC: ds[63:16] <= src_mac;
				SEND_ETHER_TYPE: ds[63:48] <= 16'h0800;	// UDP frame
				SEND_HDR1: ds[63:32] <= ip_hdr1;
				SEND_HDR2: ds[63:32] <= ip_hdr2;
				SEND_HDR3: ds[63:32] <= ip_hdr3;
				SEND_SRC_IP: ds[63:32] <= src_ip;
				SEND_DST_IP: ds[63:32] <= dst_ip;
				SEND_UDP_SRC_PORT: ds[63:48] <= src_port;
				SEND_UDP_DST_PORT: ds[63:48] <= dst_port;
				SEND_UDP_LEN: ds[63:48] <= udp_length;
				SEND_UDP_CRC: ds[63:48] <= udp_crc;
			endcase
			ds_cnt <= 16'd1;
		end 
		else begin
			ds <= {ds[55:0], 8'h00};
			ds_cnt <= ds_cnt + 16'd1;
		end
	end
end

//----------------------------------------------------------------------------

wire			[15:0]	udp_length;
assign udp_length = data_len + 16'd8;
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
			if(new_state == SEND_DST_MAC)
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
