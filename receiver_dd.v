module receiver_dd(
	res_n,
	d_rs,
	clk_rs,
	dout,
	validout
);

input	res_n;
input	d_rs;
input	clk_rs;
output	[35:0] dout;
reg		[35:0] dout;
output	validout;
reg		validout;

reg		[18:0] shreg_h;
reg		[18:0] shreg_l;
reg		[4:0] bitcounter;
reg		tmpreg;
wire	endcycle;
wire	start;
 
assign	endcycle = (bitcounter == 5'd18);
assign	start = &{d_rs,tmpreg};

always@(negedge clk_rs or negedge res_n)
begin
	if(!res_n) tmpreg <= 0;
	else tmpreg <= d_rs;
end

always@(posedge clk_rs or negedge res_n)
begin
	if(!res_n) 
	begin
		bitcounter <= 5'd18;
		{shreg_h,shreg_l} <= 0;
		dout <= 0;
	end
	else
	begin
		casex({endcycle,start})
			2'b10:
			begin
				bitcounter <= bitcounter;
				validout <= &{shreg_l[18],shreg_h[18]};
				dout <= {shreg_h[17:0],shreg_l[17:0]};
				{shreg_h,shreg_l} <= 0;
			end
			2'b11:
			begin
				bitcounter <= 0;
				validout <= &{shreg_l[18],shreg_h[18]};
				dout <= {shreg_h[17:0],shreg_l[17:0]};
				shreg_l <= {shreg_l[17:0],d_rs};
				shreg_h <= {shreg_h[17:0],tmpreg};
			end
			2'b0x:
			begin
				bitcounter <= bitcounter + 1'b1;
				validout <= 0;
				dout <= dout;
				shreg_l <= {shreg_l[17:0],d_rs};
				shreg_h <= {shreg_h[17:0],tmpreg};
			end
		endcase	
	end
end

endmodule
