module transmitter(
	clk,
	res_n,
	din,
	validin,
	readyin,
	d_tr
);

input	clk;
input	res_n;
input	[31:0] din;
input	validin;
output	readyin;
output	d_tr;


reg		[32:0] shreg;
reg		[5:0] bitcounter;
 
assign	readyin = (bitcounter == 6'd32);


assign	d_tr = shreg[32];

always@(posedge clk or negedge res_n)
begin
	if(!res_n) bitcounter <= 6'd32;
	else
	begin
		casex({readyin,validin})
			2'b10:
			begin
				bitcounter <= bitcounter;
				shreg <= 0;
			end
			2'b11:
			begin
				bitcounter <= 0;
				shreg <= {1'b1,din};
			end
			2'b0x:
			begin
				bitcounter <= bitcounter + 1'b1;
				shreg <= {shreg[31:0],1'b0};
			end
		endcase	
	end
end

endmodule
