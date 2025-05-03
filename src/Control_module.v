module Control_module #(
    parameter S_AXIS_TDATA_WIDTH = 128, 
    parameter KERNEL_ENTRIES = 10, 
    parameter WEIGHT_RES = 8,
    parameter MAX_DIM = 32)
    (
    input wire clk_i, 
    input wire resetn_i, 
    
    // DMA AXIS signals
    input wire [S_AXIS_TDATA_WIDTH-1:0] s_axis_tdata, 
    input wire s_axis_tvalid, 
    input wire s_axis_tlast, 

    output wire s_axis_tready,
    
    output reg [KERNEL_ENTRIES*WEIGHT_RES-1:0] kernel, //control message for the kernel weights and bias
    output reg [$clog2(MAX_DIM)-1:0] image_dimension //control message for size of the image
    );
    
    localparam KERNEL_WIDTH = KERNEL_ENTRIES*WEIGHT_RES;
    
    assign s_axis_tready = s_axis_tvalid; // Combinational loop to immediately accept incoming data

    always @(posedge clk_i) begin 
        if(!resetn_i) begin 
            kernel <= 'd0; 
            image_dimension <= 'd0;
        end else if (s_axis_tvalid) begin 
                //check highest 8 bits to see whether kernel weights need to be updated
                if (s_axis_tdata[S_AXIS_TDATA_WIDTH-9] == 1'b0) begin
                    kernel <= s_axis_tdata[KERNEL_WIDTH-1:0]; // Assign lower bits to kernel register
                end
                image_dimension <= s_axis_tdata[KERNEL_WIDTH +: $clog2(MAX_DIM)]; //Assign next bits to update image dimension
                // You can (conditionally) sequester and assign the incoming s_axis_tdata however you want to whatever control signal you declare 
            end
        end  
endmodule
