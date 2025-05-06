module CNN_tb;
	parameter MAX_DIM = 28; // MNIST
	parameter WEIGHT_RES = 8; 
	parameter KERNEL_SIZE = 9;
	
	logic [7:0] io_pixel_i;
	logic 		io_pix_data_valid;
	logic [7:0] io_pixel_o;
	logic		output_valid;
	logic       m_tlast;
	logic       clk;
	logic       reset;
	logic		waiter;
	logic       tlast;
	logic       tready;
	logic [WEIGHT_RES * (KERNEL_SIZE+1) - 1:0] k_val; // KERNEL_SIZE = 9 weights + 1 weight to hold the bias-term!
	logic [$clog2(MAX_DIM)-1] im_dim;
    
	CNN_AXIS CNN (
		.kernel_weights(k_val), 
		.image_dimension(im_dim),
		.s_axis_tdata(io_pixel_i),
		.s_axis_tlast(tlast),
		.s_axis_tready(tready),
		.s_axis_tvalid(io_pix_data_valid),
		.m_axis_tdata(io_pixel_o),
		.m_axis_tready(1'b1),
		.m_axis_tvalid(output_valid),
		.m_axis_tlast(m_tlast),
		.clk_i(clk),
		.resetn_i(!reset)
	);

	always #50 clk = ~clk;   

	initial begin
		$display("Hey there! Starting simulation...");
		im_dim = 28; 
		k_val[79:71] = 'd0; 
		k_val[70:62] = 'd1; 
		k_val[61:53] = 'd0; 
		k_val[52:44] = 'd1; 
		k_val[43:35] = 'd2; 
		k_val[34:26] = 'd1; 
		k_val[25:18] = 'd0; 
		k_val[17:9] = 'd1; 
		k_val[8:0] = 'd0; 
		tlast = 0;
		reset = 1; 
		clk = 0;
		io_pix_data_valid = 0;
		io_pixel_i = '0; 
		#110 reset = 0; 
	end

	integer data_file;
	integer scan_file; 
	logic [7:0] captured_data;
	integer out_file;
 
	initial begin
	  data_file = $fopen("stim.txt", "r");
	  out_file = $fopen("picout.txt", "w");
	  if (data_file == 0) begin
		$display("data_file handle was NULL");
		$finish;
	  end
	end

    always @(posedge clk) begin
		if (!reset) begin
			io_pix_data_valid <= 1'b1;
			scan_file = $fscanf(data_file, "%d\n", captured_data); 
			if (!$feof(data_file)) begin
				//use captured_data as you would any other wire or reg value
				waiter <= 1'b1;
				io_pixel_i <= captured_data; 
			end else begin
				waiter <= 1'b0;
				io_pix_data_valid <= waiter;
			end
		end else begin 
			waiter <= 1'b0;
			io_pix_data_valid <= 1'b0;
		end 
	end 
  
	always @(posedge clk) begin
		if (output_valid == 1) begin
			$fwrite(out_file, "%d\n", io_pixel_o);         
		end
	end
  
endmodule : CNN_tb
