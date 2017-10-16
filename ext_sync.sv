module ext_sync(
	input					clk,
	input					rst_n,
		
	input					i_dp_a,
	input					i_dp_b,
	
	output	[31:0]	o_counter	
);

//----------------------------------------------------------------------------

parameter	[15:0]	clk_divider = 16'h927C;	// K_div == (75 MHz / 2000 kHz)

wire						div_cntr_done;
assign div_cntr_done = (clk_div_cntr == clk_divider) ? 1'b1 : 1'b0;

reg			[15:0]	clk_div_cntr; 
always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		clk_div_cntr <= 16'd0;
	else
		if(~div_cntr_done)
			clk_div_cntr <= clk_div_cntr + 1'b1;
		else
			if(|inc_dec)
				clk_div_cntr <= 16'd0;
			else
				clk_div_cntr <= clk_div_cntr;

reg			[1:0]			dp_ab;
reg			[31:0]		counter;

reg			[1:0]			inc_dec;		// 2'b00-None 2'b10-Inc 2'b01-Dec

assign o_counter = counter;
always_ff @ (posedge clk or negedge rst_n) 
	if(~rst_n)
		counter <= 32'd0;
	else
		if(div_cntr_done) 
			case(inc_dec)
				2'b01: counter <= counter - 1'b1;
				2'b10: counter <= counter + 1'b1;
				default: counter <= counter;
			endcase
		else
			counter <= counter;

always_ff @ (posedge clk) dp_ab <= {i_dp_a, i_dp_b};

always_ff @ (posedge clk or negedge rst_n)
	if(~rst_n)
		inc_dec <= 2'b0;
	else
		case({dp_ab, i_dp_a, i_dp_b})
			4'b0111, 
			4'b1110, 
			4'b1000, 
			4'b0001: 
				inc_dec <= 2'b01;
			
			4'b1101,
			4'b0100,
			4'b0010,
			4'b1011:
				inc_dec <= 2'b10;
				
			default: 
				if(div_cntr_done)
					inc_dec <= 2'b00;
				else
					inc_dec <= inc_dec;
		endcase

//----------------------------------------------------------------------------

endmodule
