module CNN_control # (
	parameter DATA_RES = 8, 
	parameter WEIGHT_RES = 8, 
	parameter MAX_DIM = 32, 
	parameter KERNEL_WIDTH = 3,
	parameter KERNEL_SIZE = 9
) ( 
	input  clk_i, 
	input  resetn_i, 

	//Control
	input wire [$clog2(MAX_DIM)-1:0] image_dimension,
	input DMA_not_ready,

	input wire [DATA_RES-1:0] pixel_i, 
	input wire data_valid_i, 
	input wire [WEIGHT_RES*(KERNEL_SIZE+1)-1:0] kernel_i,

	output wire [DATA_RES-1:0] pixel_o,
	output wire data_valid_o,
	output wire [1:0] control_state,
	
	//Debugging signals
	output wire [19:0] acc,
	output wire [19:0] acc_comb
); 
	
	reg [$clog2(MAX_DIM*MAX_DIM)-1:0] total_pix_counter; // [clog2(image_dimension^2)-1:0] 
	reg [$clog2(MAX_DIM)-1:0] row_pix_counter;  // [clog2(image_dimension)-1:0] 
	reg [1:0] write_state;		// Tracks which buffer is being written to 
	reg [3:0] buffer_wr_en;  // One-hot encoding of write_state, tracks buffer receiving valid bits
	wire [KERNEL_WIDTH*DATA_RES-1:0] p_buffers [3:0]; // The actual {KERNEL_WIDTH}-pixel wide buffers 
	
	reg [$clog2(MAX_DIM)-1:0] read_row_pix_counter; // (left) position of the CNN kernel
	reg [$clog2(MAX_DIM-KERNEL_WIDTH)-1:0] read_row_counter; // How many lines have been processed 
	reg buffer_data_valid;               // High when the convolutional kernel is active 
	reg [1:0] read_state;			// Tracks which buffers are currently being read from 
		
	reg [KERNEL_SIZE*DATA_RES-1:0] pixel_grid;

	reg flush_buffers;
	
	// States 
	reg [1:0] State;
	localparam awaitBuffers = 2'b00;
	localparam doConv = 2'b01;
	localparam stallConv = 2'b10; 
	localparam imageDone = 2'b11;
	// End states 
	
	assign control_state = State;
	
	always @(posedge clk_i) begin // Write counters
		if (!resetn_i | flush_buffers) begin 
			total_pix_counter <= 'd0;
			row_pix_counter <= 'd0; 
		end else begin 
			if (data_valid_i) begin 
				total_pix_counter <= (total_pix_counter == image_dimension*image_dimension-1) ? 'd0 : total_pix_counter + 1;
				row_pix_counter <= (row_pix_counter == image_dimension-1) ? 'd0 : row_pix_counter + 1; 
			end 
		end 
	end 
	
	always @(posedge clk_i) begin // Read counters
		if (!resetn_i | flush_buffers) begin 
			read_row_pix_counter <= 'd0; 
			read_row_counter <= 'd0; 
		end else if (buffer_data_valid) begin 
			if (read_row_pix_counter == image_dimension-KERNEL_WIDTH) begin 
				read_row_pix_counter <= 'd0; 
				read_row_counter <= read_row_counter + 1; 
			end else begin 
				read_row_pix_counter <= read_row_pix_counter + 1; 
				read_row_counter <= read_row_counter;
			end 
		end 
	end 
	
	// FSM
	always @(posedge clk_i) begin 
		if (!resetn_i) begin 
			State <= awaitBuffers; 
			buffer_data_valid <= 1'b0;
			flush_buffers <= 1'b0; 
		end else begin  
			case (State) 
				awaitBuffers: begin 
					flush_buffers <= 1'b0; 
					buffer_data_valid <= 1'b0; 
					if (total_pix_counter == KERNEL_WIDTH*image_dimension-1) begin 	
						State <= doConv; 
					end else begin 
						State <= awaitBuffers;
					end 
				end 
				
				doConv: begin 
					flush_buffers <= 1'b0; 
					buffer_data_valid <= 1'b1;
					if (read_row_counter == (image_dimension-KERNEL_WIDTH) && read_row_pix_counter == (image_dimension-KERNEL_WIDTH-1)) begin 
						State <= imageDone; 
					end else if (read_row_pix_counter == image_dimension-KERNEL_WIDTH-1 && data_valid_i) begin 
						State <= stallConv; 
					end else begin 
						State <= doConv; 
					end  
				end 
				
				stallConv: begin 
					flush_buffers <= 1'b0; 
					buffer_data_valid <= 1'b0; 
					if (row_pix_counter == image_dimension-1 && data_valid_i) begin 
						State <= doConv; 
					end else begin 
						State <= stallConv;
					end 
				end 
				
				imageDone: begin 
					flush_buffers <= 1'b1; 
					buffer_data_valid <= 1'b0; 
					State <= awaitBuffers; 
				end 
			endcase 
		end 
	end 
	
	always @(posedge clk_i) begin 
		if (!resetn_i | flush_buffers) begin 
			write_state <= 'd0; 
		end else begin 
			if (row_pix_counter == image_dimension-1 && data_valid_i) begin 
				write_state <= write_state + 1;
			end 
		end 
	end 
	
	always @(*) begin 
		case (write_state) // One-hot encoding of write_state
			2'd0: buffer_wr_en = 4'b0001; 
			2'd1: buffer_wr_en = 4'b0010; 
			2'd2: buffer_wr_en = 4'b0100; 
			2'd3: buffer_wr_en = 4'b1000; 
		endcase
	end 	
	
	always @(posedge clk_i) begin 
		if (!resetn_i | flush_buffers) begin 
			read_state <= 'd0; 
		end else if (read_row_pix_counter == image_dimension-KERNEL_WIDTH && buffer_data_valid) begin 
			read_state <= read_state + 1;
		end 
	end 
	
	always @(*) begin // Select appropriate buffer-data for pixel grid
        case (read_state) 
            2'd0: begin 
				// read_pixel_buffer = {{3{buffer_data_valid}}, 1'b0}; 
				pixel_grid = {p_buffers[2], p_buffers[1], p_buffers[0]}; 
			end 
            2'd1: begin 
				// read_pixel_buffer = {1'b0, {3{buffer_data_valid}}};
				pixel_grid = {p_buffers[3], p_buffers[2], p_buffers[1]}; 
			end 
			2'd2: begin 
				// read_pixel_buffer = {buffer_data_valid, 1'b0, {2{buffer_data_valid}}}; 
				pixel_grid = {p_buffers[0], p_buffers[3], p_buffers[2]}; 
			end 
			2'd3: begin 
				// read_pixel_buffer = {{2{buffer_data_valid}}, 1'b0, buffer_data_valid}; 
				pixel_grid = {p_buffers[1], p_buffers[0], p_buffers[3]}; 
			end 
		endcase
  end

	// Module declarations

	MAC # (
		.DATA_RES(DATA_RES), 
		.WEIGHT_RES(WEIGHT_RES), 
		.KERNEL_SIZE(KERNEL_SIZE), 
		.MAX_LINE_WIDTH(MAX_DIM)
	) MAC (
		.clk_i(clk_i), 
		.resetn_i(resetn_i), 
		//.flush_buffers(flush_buffers),
		.DMA_not_ready(DMA_not_ready),
		.pixel_grid_i(pixel_grid),
		.data_valid_i(buffer_data_valid), 
		.kernel_i(kernel_i),
		.pixel_o(pixel_o), 
		.pixel_valid_o(data_valid_o),
		.acc_o(acc),
		.acc_comb_o(acc_comb)
	); 

	generate 
		genvar i; 
		for (i = 0; i < 4; i = i + 1) begin : p
			PixelBuffer # (
				.DATA_RES(DATA_RES),
				.KERNEL_WIDTH(KERNEL_WIDTH),
				.MAX_LINE_WIDTH(MAX_DIM)
			) PixelBuffer (
				.clk_i(clk_i),
				.resetn_i(resetn_i), 
				.pixel_i(pixel_i), 
				.data_valid_i(buffer_wr_en[i] & data_valid_i), 
				.read_address(read_row_pix_counter),
				// .read_buff_i(read_pixel_buffer[i]), 
				.pixels_o(p_buffers[i]),
				.image_dimension(image_dimension)
			);
		end 
	endgenerate 
		
endmodule 

