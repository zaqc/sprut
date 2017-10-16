module status(
	input					rst_n,
	input					clk,
	
	input		[7:0]		i_rx_cmd_addr,
	output	[31:0]	o_rx_pkt_data,
	input					i_rx_pkt_rd,

	input		[47:0]	i_dst_mac,
	input 	[47:0]	i_src_mac,
	input		[47:0]	i_SHA,
	input		[31:0]	i_SPA,
	input		[47:0]	i_THA,
	input		[31:0]	i_TPA,
	
	input		[1:0]		i_pkt_type
);

reg			[47:0]	dst_mac;
reg			[47:0]	src_mac;
reg			[47:0]	SHA;
reg			[31:0]	SPA;
reg			[47:0]	THA;
reg			[31:0]	TPA;
	
reg			[1:0]		pkt_type;


always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n) begin
		dst_mac <= 48'd0;
		src_mac <= 48'd0;
		SHA <= 48'd0;
		SPA <= 32'd0;
		THA <= 48'd0;
		TPA <= 32'd0;
	end
	else 
		if(|i_pkt_type) begin
			dst_mac <= i_dst_mac;
			src_mac <= i_src_mac;
			SHA <= i_SHA;
			SPA <= i_SPA;
			THA <= i_THA;
			TPA <= i_TPA;
			pkt_type <= i_pkt_type;
		end

reg			[31:0]			rx_pkt_data;
assign o_rx_pkt_data = rx_pkt_data;

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		rx_pkt_data <= 32'd0;
	else
		if(i_rx_pkt_rd)
			case(i_rx_cmd_addr[3:0])
				4'h1: rx_pkt_data <= dst_mac[31:0];
				4'h2: rx_pkt_data <= {16'd0, dst_mac[47:32]};
				4'h3: rx_pkt_data <= src_mac[31:0];
				4'h4: rx_pkt_data <= {16'd0, src_mac[47:32]};
				4'h5: rx_pkt_data <= SHA[31:0];
				4'h6: rx_pkt_data <= {16'd0, SHA[47:32]};
				4'h7: rx_pkt_data <= SPA;
				4'h8: rx_pkt_data <= THA[31:0];
				4'h9: rx_pkt_data <= {16'd0, THA[47:32]};
				4'hA: rx_pkt_data <= TPA;
				4'hB: rx_pkt_data <= {30'd0, pkt_type};
				default:
					rx_pkt_data <= {i_rx_cmd_addr, i_rx_cmd_addr, i_rx_cmd_addr, i_rx_cmd_addr};
			endcase
	

endmodule
