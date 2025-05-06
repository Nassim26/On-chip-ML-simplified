module PixelBuffer # (
	parameter DATA_RES = 8,
	parameter KERNEL_WIDTH = 3,
	parameter MAX_LINE_WIDTH = 32 // e.g., 28 for MNIST	& its variants	
) (
	input  clk_i, 
	input  resetn_i, 
	//input flush_buffers,
	input wire [DATA_RES-1:0] pixel_i, 
	input wire data_valid_i,
	// input wire read_buff_i, 
	input wire [4:0] read_address,
	
	output wire [KERNEL_WIDTH*DATA_RES-1:0] pixels_o,
	
	input wire [$clog2(MAX_LINE_WIDTH)-1:0] image_dimension
); 
	
	integer i;
	reg [DATA_RES-1:0] buffer [MAX_LINE_WIDTH-1:0]; 
	reg [$clog2(MAX_LINE_WIDTH)-1:0] write_address; // ceil[log2(LINE_WIDTH)], log2(28) ~= 4.8 bits 
	
	always @(posedge clk_i) begin 
		if (!resetn_i ) begin 
		    for(i=0;i<MAX_LINE_WIDTH;i=i+1) begin 
				buffer[i] <= 0; 
			end 
			write_address <= 'd0; 
		end else if (data_valid_i) begin 
			buffer[write_address] <= pixel_i; 
			write_address <= (write_address == image_dimension-1) ? 'd0 : write_address + 1;
		end
	end 

	assign pixels_o = {buffer[read_address], buffer[read_address+1], buffer[read_address+2]}; 	

endmodule 
