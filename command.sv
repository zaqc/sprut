module command(
	input						rst_n,
	input						clk,
	
	input		[7:0]			i_cmd_addr,
	input		[31:0]		i_cmd_data,
	input						i_cmd_wr,

	output 	[47:0]		o_dst_mac,
	output 	[47:0]		o_src_mac,
	output 	[1:0]			o_operation,
	output 	[47:0]		o_SHA,
	output 	[31:0]		o_SPA,
	output 	[47:0]		o_THA,
	output 	[31:0]		o_TPA,
	
	output	[31:0]		o_src_ip,
	output	[31:0]		o_dst_ip,
	
	output	[15:0]		o_src_port,
	output 	[15:0]		o_dst_port,
	
	output	[15:0]		o_udp_data_len,
	
	output	[1:0]			o_send_packet
);

//----------------------------------------------------------------------------

reg		[1:0]			send_packet;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		send_packet <= 2'd0;
	else
		if(i_cmd_wr && i_cmd_addr == 8'd2)
			send_packet <= i_cmd_data[1:0];
		else
			send_packet <= 2'd0;

assign o_send_packet = send_packet;

//----------------------------------------------------------------------------

//
//always_ff @ (posedge clk or negedge rst_n)
//	if(~rst_n)
//		src_mac <= 48'd0;
//	else
//		if(i_cmd_wr)
//			if(i_cmd_addr == 8'd24)
//				src_mac[47:16] <= i_cmd_data;
//			else
//				if(i_cmd_addr == 8'd28)
//					src_mac[15:0] <= i_cmd_data[15:0];
//

//----------------------------------------------------------------------------

//
//always_ff @ (posedge clk or negedge rst_n)
//	if(~rst_n)
//		dst_mac <= 48'd0;
//	else
//		if(i_cmd_wr)
//			if(i_cmd_addr == 8'd32)
//				dst_mac[47:16] <= i_cmd_data;
//			else
//				if(i_cmd_addr == 8'd36)
//					dst_mac[15:0] <= i_cmd_data[15:0];
//

//----------------------------------------------------------------------------

assign o_operation = arp_operation;
assign o_SHA = arp_src_mac;
assign o_SPA = arp_src_ip;
assign o_THA = arp_dst_mac;
assign o_TPA = arp_dst_ip;

reg		[47:0]		src_mac;
assign o_src_mac = src_mac;

reg		[47:0]		dst_mac;
assign o_dst_mac = dst_mac;

reg		[31:0]		src_ip;
assign o_src_ip = src_ip;

reg		[31:0]		dst_ip;
assign o_dst_ip = dst_ip;

reg		[15:0]		src_port;
assign o_src_port = src_port;

reg		[15:0]		dst_port;
assign o_dst_port = dst_port;

reg		[15:0]		udp_data_len;
assign o_udp_data_len = udp_data_len;

reg		[1:0]			arp_operation;

reg		[47:0]		arp_dst_mac;
reg		[31:0]		arp_dst_ip;
reg		[47:0]		arp_src_mac;
reg		[31:0]		arp_src_ip;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n) begin
		src_mac <= 48'd0;
		dst_mac <= 48'd0;
		src_ip <= 32'd0;
		dst_ip <= 32'd0;
		src_port <= 16'd0;
		dst_port <= 16'd0;
		udp_data_len <= 16'd0;
		arp_operation <= 2'd0;
		arp_src_mac <= 48'd0;
		arp_dst_mac <= 48'd0;
		arp_src_ip <= 32'd0;
		arp_dst_ip <= 32'd0;
	end
	else
		if(i_cmd_wr)
			case(i_cmd_addr)
				8'd24: src_mac[47:16] <= i_cmd_data[31:0];
				8'd28: src_mac[15:0] <= i_cmd_data[15:0];				
				8'd32: dst_mac[47:16] <= i_cmd_data[31:0];
				8'd36: dst_mac[15:0] <= i_cmd_data[15:0];
				
				8'd40: src_ip[31:0] <= i_cmd_data[31:0];
				8'd44: dst_ip[31:0] <= i_cmd_data[31:0];
				
				8'd48: src_port[15:0] <= i_cmd_data[15:0];
				8'd52: dst_port[15:0] <= i_cmd_data[15:0];
				
				8'd60: udp_data_len[15:0] <= i_cmd_data[15:0];
				
				8'd64: arp_operation[1:0] <= i_cmd_data[1:0];
				
				8'd68: arp_dst_mac[47:16] <= i_cmd_data[31:0];
				8'd72: arp_dst_mac[15:0] <= i_cmd_data[15:0];
				8'd76: arp_dst_ip[31:0] <= i_cmd_data[31:0];
				
				8'd80: arp_src_mac[47:16] <= i_cmd_data[31:0];
				8'd84: arp_src_mac[15:0] <= i_cmd_data[15:0];
				8'd88: arp_src_ip[31:0] <= i_cmd_data[31:0];
				default: ;
			endcase

endmodule
