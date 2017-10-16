module eth_send(
	input						clk,
	input						rst_n,
	
	input		[47:0]		i_dst_mac,
	input		[47:0]		i_src_mac,
	
	input		[1:0]			i_operation,
	
	input		[47:0]		i_SHA,
	input		[31:0]		i_SPA,
	input		[47:0]		i_THA,
	input		[31:0]		i_TPA,
	
	output	[7:0]			o_tx_data,
	output					o_tx_en,
	
	input						i_enable,
	output					o_ready
);

// ===========================================================================
// READY
// ===========================================================================

assign o_ready = (state == STATE_IDLE) ? 1'b1 : 1'b0;

// ===========================================================================
// PARAMETERS
// ===========================================================================

/*
parameter	[47:0]		i_dst_mac = {8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
parameter	[47:0]		i_src_mac = {8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06};
parameter	[1:0]			i_operation = 2'd1;	// 1 - for request
parameter	[47:0]		i_SHA = {8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06};
parameter	[31:0]		i_SPA = {8'd10, 8'd0, 8'd0, 8'd123};
parameter	[47:0]		i_THA = {8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
parameter	[31:0]		i_TPA = {8'd10, 8'd0, 8'd0, 8'd2};
*/
wire 			[63:0]		arp_header;
parameter	[15:0]		ARP_HTYPE = 16'h0001;
parameter	[15:0]		ARP_PTYPE = 16'h0800;
parameter	[7:0]			ARP_HLEN = 8'h06;	//	MAC size
parameter	[7:0]			ARP_PLEN = 8'h04;	// for IPv4
assign arp_header = {ARP_HTYPE, ARP_PTYPE, ARP_HLEN, ARP_PLEN, {14'd0, i_operation}};

// ===========================================================================
// STATE MACHINE
// ===========================================================================

enum logic [3:0] {
	NONE = 4'd0,
	STATE_IDLE = 4'd1,
	ETH_START = 4'd2,
	SEND_PREAMBLE = 4'd3,
	SEND_DST_MAC = 4'd4,
	SEND_SRC_MAC = 4'd5,
	SEND_ETHER_TYPE = 4'd6,
	SEND_ARP_HEADER = 4'd7,
	SEND_SHA = 4'd8,
	SEND_SPA = 4'd9,
	SEND_THA = 4'd10,
	SEND_TPA = 4'd11,
	SEND_DUMMY_BYTES = 4'd12,
	SEND_CRC32 = 4'd13,
	DELAY = 4'd14,
	SET_READY = 4'd15
} state, new_state;

always_ff @ (posedge clk or negedge rst_n) begin
	if(1'b0 == rst_n)
		state <= NONE;
	else
		state <= new_state;
end

always_comb begin
	new_state = state;
	case(state)
		NONE: if(rst_n) new_state = STATE_IDLE;
		STATE_IDLE: if(i_enable == 1'b1) new_state = ETH_START;
		ETH_START: if(i_enable == 1'b0) new_state = SEND_PREAMBLE;
		SEND_PREAMBLE: if(ds_cnt == 16'd8) new_state = SEND_DST_MAC;
		SEND_DST_MAC: if(ds_cnt == 16'd6) new_state = SEND_SRC_MAC;
		SEND_SRC_MAC: if(ds_cnt == 16'd6) new_state = SEND_ETHER_TYPE;
		SEND_ETHER_TYPE: if(ds_cnt == 16'd2) new_state = SEND_ARP_HEADER;
		SEND_ARP_HEADER: if(ds_cnt == 16'd8) new_state = SEND_SHA;
		SEND_SHA: if(ds_cnt == 16'd6) new_state = SEND_SPA;
		SEND_SPA: if(ds_cnt == 16'd4) new_state = SEND_THA;
		SEND_THA: if(ds_cnt == 16'd6) new_state = SEND_TPA;
		SEND_TPA: if(ds_cnt == 16'd4) new_state = SEND_DUMMY_BYTES;
		SEND_DUMMY_BYTES: if(ds_cnt == 16'd18) new_state = SEND_CRC32;
		SEND_CRC32: if(ds_cnt == 16'd4) new_state = DELAY;
		DELAY: if(ds_cnt == 16'd200) new_state = SET_READY;
		SET_READY: if(i_enable == 1'b0) new_state = STATE_IDLE;
	endcase
end

assign o_tx_en = (state > ETH_START && state < DELAY) ? 1'b1 : 1'b0;

// ===========================================================================
//	DATA SHIFT & SEND
// ===========================================================================

wire			[7:0]			o_data;
assign o_data = (state == SEND_CRC32) ? crc32[7:0] : ds[63:56];
assign o_tx_data = o_data;

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
				SEND_DST_MAC: ds <= {i_dst_mac, 16'd0};
				SEND_SRC_MAC: ds <= {i_src_mac, 16'd0};
				SEND_ETHER_TYPE: ds <= {16'h0806, 48'd0};	// ARP frame
				SEND_ARP_HEADER: ds <= arp_header;
				SEND_SHA: ds <= {i_SHA, 16'd0};
				SEND_SPA: ds <= {i_SPA, 32'd0};
				SEND_THA: ds <= {i_THA, 16'd0};
				SEND_TPA: ds <= {i_TPA, 32'd0};
				SEND_DUMMY_BYTES: ds <= 64'd0;
				SEND_CRC32: ds <= 64'd0;
				DELAY: ds <= 64'd0;
			endcase
			ds_cnt <= 16'd1;
		end 
		else begin
			ds <= {ds[55:0], 8'h00};
			ds_cnt <= ds_cnt + 16'd1;
		end
	end
end

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
				if(new_state == SEND_CRC32)
					calc_crc_flag <= 1'b0;
		end
end

wire		[31:0]		crc32;

calc_crc32 calc_crc32_unit(
	.rst_n(rst_n),
	.clk(clk),
	.i_calc(calc_crc_flag),
	.i_vl(o_tx_en),
	.i_data(o_data),
	.o_crc32(crc32)
);

endmodule
