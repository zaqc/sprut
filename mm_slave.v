// mm_slave.v

// This file was auto-generated as a prototype implementation of a module
// created in component editor.  It ties off all outputs to ground and
// ignores all inputs.  It needs to be edited to make it do something
// useful.
// 
// This file will not be automatically regenerated.  You should check it in
// to your version control system if you want to keep it.

`timescale 1 ps / 1 ps
module mm_slave (
		input  wire [7:0]  avs_s0_address,     //    s0.address
		input  wire        avs_s0_read,        //      .read
		output wire [31:0] avs_s0_readdata,    //      .readdata
		input  wire        avs_s0_write,       //      .write
		input  wire [31:0] avs_s0_writedata,   //      .writedata
		output wire        avs_s0_waitrequest, //      .waitrequest
		input  wire        clk,                // clock.clk
		input  wire        reset               // reset.reset
	);

	// TODO: Auto-generated HDL template

	assign avs_s0_waitrequest = 1'b0;

	assign avs_s0_readdata = 32'b00000000000000000000000000000000;

endmodule
