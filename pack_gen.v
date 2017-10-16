module pack_gen
(
	input i_clk,
	input i_rst,
	
	output		[7:0]			o_data,
	output 	   				o_tx_en,
	output 						cntr,

	output CRC_rd,
	output CRC_init
);

`define FAST (1'b0)
`define HIGH (1'b1)

parameter SPEED = `HIGH; // Determines that to send bytes or nibbles

reg [26:0] clk_counter; // Number of bits determines pause time
reg [7:0] byte;            // Current output byte

wire [26:0] clk_bytes;

assign cntr = clk_counter[26];

assign clk_bytes = (SPEED == `FAST) ? clk_counter[9:1] : clk_counter; 
//assign o_data    = (SPEED == `FAST) ? (clk_counter[0] ? byte[3:0] : byte[7:4]) : byte;

reg			[7:0]				dly_byte;
reg			[0:0]				dly_tx_en;

always @ (posedge i_clk) begin
	dly_byte <= byte;		
	dly_tx_en <= r_tx_en;
end

assign o_data = (clk_bytes < 70) ? dly_byte : crc32[7:0];
assign o_tx_en = dly_tx_en;

reg			[0:0]				r_tx_en;

assign CRC_rd = ((clk_bytes >= 69) && (clk_bytes < 73)) ? 1'b1 : 1'b0;
assign CRC_init = (clk_bytes < 9) ? 1'b1 : 1'b0;

reg			[47:0]			dst_mac;
reg			[47:0]			src_mac;

wire			[15:0]			data_len;
assign data_len = 16'd18;

wire			[15:0]			pkt_len;
assign pkt_len = data_len + 16'h0008;

always @(posedge i_clk) begin
	if (i_rst) begin
		clk_counter <= 0;
		dst_mac <= 48'hd8d38526c578;
		src_mac <= 48'h0023543c471b;
	end					
	else begin
		clk_counter <= clk_counter + 1'b1;

		if ((clk_bytes >= 9'h0) && (clk_bytes < 9'd72))
			r_tx_en <= 1'b1; // Transmission is enabled
		else
			r_tx_en <= 1'b0;

		case (clk_bytes)
			// Sending the preambule and asserting TX_EN
			0: byte <= 8'h55;
			1: byte <= 8'h55; 
			2: byte <= 8'h55; 
			3: byte <= 8'h55; 
			4: byte <= 8'h55; 
			5: byte <= 8'h55; 
			6: byte <= 8'h55; 
			7: byte <= 8'hd5;
			  
			default: 
				case (clk_bytes-8)
					// Sending the UDP/IP-packet itself
					0: byte <= dst_mac[47:40]; //8'hd8; // dst_mac
					1: byte <= dst_mac[39:32]; //8'hd3; 
					2: byte <= dst_mac[31:24]; //8'h85; 
					3: byte <= dst_mac[23:16]; //8'h26; 
					4: byte <= dst_mac[15:8]; //8'hc5; 
					5: byte <= dst_mac[7:0]; //8'h78; 
					 
					6: byte <= src_mac[47:40]; //8'h00; // src_mac
					7: byte <= src_mac[39:32]; //8'h23;                 
					8: byte <= src_mac[31:24]; //8'h54; 
					9: byte <= src_mac[23:16]; //8'h3c; 
					10: byte <= src_mac[15:8]; //8'h47; 
					11: byte <= src_mac[7:0]; //8'h1b; 
					 
					12: byte <= 8'h08; // 08 00
					13: byte <= 8'h00; 
					
					14: byte <= 8'h45; // hdr1
					15: byte <= 8'h00; 					 
					16: byte <= 8'h00; 
					17: byte <= 8'h2e; 
					
					18: byte <= 8'h00; // hdr2
					19: byte <= 8'h00; 
					20: byte <= 8'h00; 
					21: byte <= 8'h00; 
					22: byte <= 8'hc8; // hdr3
					23: byte <= 8'h11;				
					24: byte <= 8'hd6; 
					25: byte <= 8'h73;
					
					26: byte <= 8'hc0; // src_ip
					27: byte <= 8'ha8;
					28: byte <= 8'h4d;
					29: byte <= 8'h21;
					
					30: byte <= 8'hc0; // dst_ip
					31: byte <= 8'ha8;
					32: byte <= 8'h4d;
					33: byte <= 8'hd9;
					
					34: byte <= 8'hc3; // src_port
					35: byte <= 8'h50;
					
					36: byte <= 8'hc3; // dst_port
					37: byte <= 8'h60;
					
					38: byte <= pkt_len[15:8]; //8'h00; // pkt_len
					39: byte <= pkt_len[7:0]; //8'h1a; 

					40: byte <= 8'h00; // pkt_chksum
					41: byte <= 8'h00;
					
					42: byte <= 8'h01; // 8'h01; // udp_data
					43: byte <= 8'h02; // 8'h02; 
					44: byte <= 8'h03; // 8'h03; 
					45: byte <= 8'h04; // 8'h04; 
					46: byte <= 8'h05; // 8'h01; 
					47: byte <= 8'h06; // 8'h01;
					 
					48: byte <= 8'h00; // 8'h01; 
					49: byte <= 8'h00; // 8'h01; 
					50: byte <= 8'h00; // 8'h01; 
					51: byte <= 8'h00; // 8'h01; 
					52: byte <= 8'h00; // 8'h01; 
					53: byte <= 8'h00; // 8'h01; 
					54: byte <= 8'h00; // 8'h01; 
					55: byte <= 8'h00; // 8'h01;

					56: byte <= 8'h00; // 8'h01; 
					57: byte <= 8'h00; // 8'h01; 
					58: byte <= 8'h00; // 8'h01; 
					59: byte <= 8'h00; // 8'h01;

					// The CRC32 control sum (checked in Matlab programm)
					//60: byte <= 8'hCF; // 8'he3;
					//61: byte <= 8'h50; // 8'h8e;
					//62: byte <= 8'h8D; // 8'hdf;
					//63: byte <= 8'h2E; // 8'h1f;
					
					//60: byte <= crc32[7:0]; //8'hCF; // 8'he3;
					//61: byte <= crc32[7:0]; //8'h50; // 8'h8e;
					//62: byte <= crc32[7:0]; //8'h8D; // 8'hdf;
					//63: byte <= crc32[7:0]; //8'h2E; // 8'h1f;
					default: byte <= 0; // Pause 
				endcase
			endcase
		end
	end

wire			[31:0]		crc32;

tx_calc_crc32 tx_calc_crc32_unit(
	.rst_n(~i_rst),
	.clk(i_clk),
	.i_vl(((clk_bytes > 8) && (clk_bytes < 73)) ? 1'b1 : 1'b0),
	.i_data(byte),
	.i_calc(((clk_bytes > 8) && (clk_bytes < 69)) ? 1'b1 : 1'b0),
	.o_crc32(crc32)
);

endmodule
