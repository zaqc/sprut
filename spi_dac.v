module spi_dac(
	clk,
	data_spi,
	valid,
	dout,
	dsync_n
);

input	clk;
input	[7:0] data_spi;
input	valid;
output	dout;
output	dsync_n;

reg		[15:0] Reg_d, Reg_s;
wire	[15:0] Data;


assign	Data = {4'b0000,data_spi,4'b0000};
assign	dout = Reg_d[15];
assign	dsync_n = Reg_s[15];

always@(posedge clk)
begin
	if (valid)
	begin
		Reg_d <= Data;
		Reg_s <= 0;
	end
	else
	begin
		Reg_d <= {Reg_d[14:0],1'b0};
		Reg_s <= {Reg_s[14:0],1'b1};			
	end
end

endmodule
