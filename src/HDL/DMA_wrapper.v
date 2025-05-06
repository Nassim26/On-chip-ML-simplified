module DMA_wrapper #
(
    // Parameters of Axi Master Bus Interface M_AXIS
    parameter integer M_AXIS_TDATA_WIDTH	= 8,
    // Parameters of Axi Slave Bus Interface S_AXIS
    parameter integer S_AXIS_TDATA_WIDTH	= 8,

    // CNN-bound parameters
    parameter DATA_RES = 8, // Should match master & slave tdata widths
    parameter WEIGHT_RES = 8, 
    //parameter IM_DIM = 28, 
    parameter KERNEL_WIDTH = 3, 
    parameter KERNEL_SIZE = 9,
    parameter MAX_DIM = 32
)
(
    input   clk_i,
    input   resetn_i,
    
    // Control signals (from control DMA)
    input wire [WEIGHT_RES*(KERNEL_SIZE+1)-1:0] kernel_weights,
    input wire [$clog2(MAX_DIM)-1:0] image_dimension,
    
    // Ports of Axi Master Bus Interface M_AXIS
    output wire  m_axis_tvalid,
    output wire [M_AXIS_TDATA_WIDTH-1 : 0] m_axis_tdata,
    output wire  m_axis_tlast,
    input wire  m_axis_tready,

    // Ports of Axi Slave Bus Interface S_AXIS
    output wire  s_axis_tready,
    input wire [S_AXIS_TDATA_WIDTH-1 : 0] s_axis_tdata,
    input wire  s_axis_tlast,
    input wire  s_axis_tvalid,
    
    // Debugging signals
    output wire [1:0] axi_state,
    output wire [1:0] control_state,
    output wire out_val,
    output wire [19:0] acc,
    output wire [19:0] acc_comb
    
);

  wire [M_AXIS_TDATA_WIDTH-1:0] CNN_out; // Wire to accept output from CNN accelerator

    // Instantiate accelerator(s) here
    CNN_control # (
        .DATA_RES(DATA_RES),
        .WEIGHT_RES(WEIGHT_RES),
        .MAX_DIM(MAX_DIM),
        .KERNEL_WIDTH(KERNEL_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE)
    ) CNN (
        .clk_i(clk_i), 
        .resetn_i(resetn_i),
        .image_dimension(image_dimension), 
        .DMA_not_ready(!m_axis_tready),
        .pixel_i(s_axis_tdata),
        .data_valid_i(s_axis_tvalid & m_axis_tready), 
        .kernel_i(kernel_weights), 
        .pixel_o(CNN_out), //o 
        .data_valid_o(out_val), //o
        
        .control_state(control_state),
        .acc(acc),
        .acc_comb(acc_comb)
    );

    // Internal signal for the data
    reg [M_AXIS_TDATA_WIDTH-1:0]    tdata_reg;
    reg                             tvalid_reg;
    reg                             tlast_reg;

    // States
    reg [1:0] State;
    localparam Init = 2'b00; 
    localparam Reading = 2'b01; 
    localparam Streaming = 2'b10;
    // End states
    
    assign axi_state = State;

    // Track number of writes to control FSM accordingly
    reg [9:0] nr_of_writes;

    // Handshaking (ready/valid mechanism)
    assign s_axis_tready = m_axis_tready;  // Slave ready if master is ready
    assign m_axis_tvalid = tvalid_reg;     // Valid output data when tvalid_reg is set
    assign m_axis_tdata  = tdata_reg;      // Output the processed data
    assign m_axis_tlast  = tlast_reg;      // Propagate tlast signal

    always @(posedge clk_i) begin 
        if (!resetn_i) begin 
            State <= Init; 
            tlast_reg <= 1'b0; 
            nr_of_writes <= 'b0;
        end else begin
            case(State) 
            Init: begin 
                tlast_reg <= 1'b0; 
                nr_of_writes <= (image_dimension - KERNEL_WIDTH + 1)*(image_dimension - KERNEL_WIDTH + 1); // Initialise nr_of_writes with expected number of outputs based on configured accelerator
                tdata_reg <= 'd0;	
                tvalid_reg <= 1'b0;
                if (s_axis_tvalid & m_axis_tready) begin 
                    State <= Reading;			
                end else begin 
                    State <= Init; 
                end 
            end 
            
            Reading: begin 
                tlast_reg <= 1'b0; 
                if (out_val) begin  
                    tvalid_reg <= 1'b1;
                    nr_of_writes <= nr_of_writes - 1;
                    tdata_reg <= CNN_out;
                    State <= Streaming; 
                end else begin 
                    tvalid_reg <= 1'b0;
                    nr_of_writes <= nr_of_writes;
                    tdata_reg <= 'd0;
                    State <= Reading; 
                end 
            end  
            
            Streaming: begin 
                if (out_val) begin
                    tvalid_reg <= 1'b1;
                    nr_of_writes <= nr_of_writes - 1; 
                    tdata_reg <= CNN_out;
                end else begin 
                    tvalid_reg <= 1'b0;
                    nr_of_writes <= nr_of_writes;
                    tdata_reg <= tdata_reg;
                end 
                
                if (nr_of_writes == 'd1) begin 
                    tlast_reg <= 1'b1; 
                    State <= Streaming; 
                end else if (nr_of_writes == 'd0) begin 
                    tlast_reg <= 1'b0; 
                    State <= Init;
                end else begin
                    tlast_reg <= 1'b0; 
                    State <= Streaming;
                end 
        end 
        endcase 
    end 
 end 

endmodule
