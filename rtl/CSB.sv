`timescale 1ns/1ps

module csb #(
    parameter int SLVREG_NUM = 30
)(
    input  logic PCLK,
    input  logic rst_n,
    input  logic PSELx,
    input  logic PWRITE,
    input  logic PENABLE,
    output logic PSLVERR,
    output logic PREADY,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,

    output logic [31:0] S_POINTER,
    output logic        producer_pointer,
    output logic        consumer_pointer,
    output logic [1:0] CDMA_D_OP_ENABLE,
    output logic [31:0] DATA_MATRIX_WIDTH,
    output logic [31:0] DATA_MATRIX_HEIGHT,
    output logic [31:0] DATA_CHANNEL_COUNT,
    output logic [31:0] DATA_DST_BASE,
    output logic [31:0] DATA_SRC_BASE_ADDR,
    output logic [31:0] WEIGHT_MATRIX_WIDTH,
    output logic [31:0] WEIGHT_MATRIX_HEIGHT,
    output logic [31:0] WEIGHT_CHANNEL_COUNT,
    output logic [31:0] WEIGHT_DST_BASE,
    output logic [31:0] WEIGHT_SRC_BASE_ADDR,
    output logic [31:0] WEIGHT_KERNELS_PER_CHUNK,
    output logic [31:0] CSC_D_OP_ENABLE,
    output logic [31:0] CSC_STATUS,
    output logic [31:0] CSC_ATOMICS,
    output logic [31:0] CSC_INPUT_WIDTH_HEIGHT,
    output logic [31:0] CSC_INPUT_CHANNELS,
    output logic [31:0] CSC_KERNEL_WIDTH_HEIGHT,
    output logic [31:0] CSC_STRIDE_XY,
    output logic [31:0] CSC_OUTPUT_WIDTH_HEIGHT,
    output logic [31:0] CSC_OUTPUT_CHANNELS,
    output logic [31:0] CSC_PADDING,
    output logic [31:0] CACC_S_STATUS,
    output logic [31:0] CACC_D_OP_ENABLE,
    output logic [31:0] CACC_D_DATAOUT_SIZE_0,
    output logic [31:0] CACC_D_DATAOUT_SIZE_1,
    output logic [31:0] CACC_D_DATAOUT_ADDR,
    output logic [31:0] CACC_D_LINE_STRIDE,
    output logic [31:0] CACC_D_SURF_STRIDE,
    output logic [31:0] CACC_D_DATAOUT_MAP,

    output logic        cdma_op_enable_level,
    output logic        csc_op_enable_level,
    output logic        cacc_op_enable_level,

    input  logic        cdma_op_data_enable_clear,
    input  logic [1:0]  cdma_data_status, //cdma_data_status && cdma_weight_status 
    input  logic        cdma_op_weight_enable_clear,
    input  logic [1:0]  cdma_weight_status, //cdma_data_status && cdma_weight_status 
    input  logic        csc_op_enable_clear,
    input  logic [1:0]  csc_status, 
    input  logic        cacc_op_enable_clear,
    input  logic [1:0]  cacc_status  
);

    logic [31:0] slvreg [0:1][SLVREG_NUM-1:0];
    logic [31:0] decoded_idx;
    logic [31:0] op_enable_idx;
    logic        decoded_valid;
    logic        decoded_op_enable;
    logic        decoded_pointer;
    logic        decoded_status;
    logic [31:0] status_idx;
    logic        transfer_fire;
    logic [31:0] op_enable_reg [0:1][0:2]; // group, 0: cdma, 1: csc, 2: cacc
    logic        producer_pointer_q;
    logic        consumer_pointer_q;

    logic       consumer_advance_cond;
    logic [2:0] consumer_busy_seen;
    logic       cdma_op_enable_clear;
    logic       cdma_data_enable_clear_sticky;
    logic       cdma_weight_enable_clear_sticky;
    logic [1:0] cdma_status;

    assign cdma_status = cdma_data_status & cdma_weight_status;
    assign cdma_op_enable_clear = cdma_data_enable_clear_sticky && cdma_weight_enable_clear_sticky;


    typedef enum logic[1:0] { 
        S_IDLE,
        S_SETUP,
        S_ACCESS
    } state_t;

    //FSM
    state_t p_state, n_state;
    always_comb begin
        n_state = S_IDLE;
        unique case(p_state)
            S_IDLE:   if (PSELx && !PENABLE) n_state = S_SETUP;
            S_SETUP: begin
                if (!PSELx) begin
                    n_state = S_IDLE;
                end else if (PENABLE) begin
                    n_state = S_ACCESS;
                end else begin
                    n_state = S_SETUP;
                end
            end
            S_ACCESS: begin 
                if (!PSELx) begin
                    n_state = S_IDLE;
                end else if (!PENABLE) begin
                    n_state = S_SETUP;
                end else begin
                    n_state = S_ACCESS;
                end
            end
            default: begin n_state = S_IDLE; end
        endcase
    end

    assign transfer_fire = (p_state == S_SETUP) && PSELx && PENABLE;

    assign consumer_advance_cond = (&consumer_busy_seen) && !cdma_status[consumer_pointer_q] && !csc_status[consumer_pointer_q] && !cacc_status[consumer_pointer_q];

    //decode
    always_comb begin
        decoded_idx = 0;
        op_enable_idx = 0;
        decoded_valid = 1'b1;
        decoded_op_enable = 1'b0;
        decoded_pointer = 1'b0;
        decoded_status = 1'b0;
        status_idx = 32'd0;
        if(PSELx) begin
            unique case (PADDR)
                32'h00: begin decoded_op_enable = 1'b1; op_enable_idx = 32'd0; end // CDMA_D_OP_ENABLE
                32'h04: begin decoded_status = 1'b1; status_idx = 32'd0; end // CDMA_STATUS
                32'h08: decoded_idx = 32'd1;  // DATA_MATRIX_WIDTH
                32'h0c: decoded_idx = 32'd2;  // DATA_MATRIX_HEIGHT
                32'h10: decoded_idx = 32'd3;  // DATA_CHANNEL_COUNT
                32'h14: decoded_idx = 32'd4;  // DATA_DST_BASE
                32'h18: decoded_idx = 32'd5;  // DATA_SRC_BASE_ADDR
                32'h1c: decoded_idx = 32'd6;  // WEIGHT_MATRIX_WIDTH
                32'h20: decoded_idx = 32'd7;  // WEIGHT_MATRIX_HEIGHT
                32'h24: decoded_idx = 32'd8;  // WEIGHT_CHANNEL_COUNT
                32'h28: decoded_idx = 32'd9;  // WEIGHT_DST_BASE
                32'h2c: decoded_idx = 32'd10; // WEIGHT_SRC_BASE_ADDR
                32'h30: begin decoded_op_enable = 1'b1; op_enable_idx = 32'd1; end // CSC_D_OP_ENABLE
                32'h34: begin decoded_status = 1'b1; status_idx = 32'd1; end // CSC_STATUS
                32'h38: decoded_idx = 32'd12; // CSC_ATOMICS
                // 0x3c and 0x40 are reserved; CBUF chunk addresses start at zero.
                32'h44: decoded_idx = 32'd15; // CSC_INPUT_WIDTH_HEIGHT
                32'h48: decoded_idx = 32'd16; // CSC_INPUT_CHANNELS
                32'h4c: decoded_idx = 32'd17; // CSC_KERNEL_WIDTH_HEIGHT
                32'h50: decoded_idx = 32'd18; // CSC_STRIDE_XY
                32'h54: decoded_idx = 32'd19; // CSC_OUTPUT_WIDTH_HEIGHT
                32'h58: decoded_idx = 32'd20; // CSC_OUTPUT_CHANNEL
                32'h5c: begin decoded_op_enable = 1'b1; op_enable_idx = 32'd2; end // CACC_D_OP_ENABLE
                32'h60: begin decoded_status = 1'b1; status_idx = 32'd2; end // CACC_S_STATUS
                32'h64: decoded_idx = 32'd22; // CACC_D_DATAOUT_SIZE_0
                32'h68: decoded_idx = 32'd23; // CACC_D_DATAOUT_SIZE_1
                32'h6c: decoded_idx = 32'd24; // CACC_D_DATAOUT_ADDR
                32'h70: decoded_idx = 32'd25; // CACC_D_LINE_STRIDE
                32'h74: decoded_idx = 32'd26; // CACC_D_SURF_STRIDE
                32'h78: decoded_idx = 32'd27; // CACC_D_DATAOUT_MAP
                32'h7c: decoded_pointer = 1'b1; // S_POINTER: [0] producer, [16] consumer
                32'h80: decoded_idx = 32'd28; // CSC_PADDING: left/right/top/bottom
                32'h84: decoded_idx = 32'd29; // WEIGHT_KERNELS_PER_CHUNK
                default: begin
                    decoded_idx = 1'b0;
                    op_enable_idx = 1'b0;
                    decoded_valid = 1'b0;
                    decoded_op_enable = 1'b0;
                    decoded_pointer = 1'b0;
                    decoded_status = 1'b0;
                    status_idx = 32'd0;
                end
            endcase
        end else begin
            decoded_idx = 1'b0;
            op_enable_idx = 1'b0;
            decoded_valid = 1'b0;
            decoded_op_enable = 1'b0;
            decoded_pointer = 1'b0;
            decoded_status = 1'b0;
            status_idx = 32'd0;
        end
    end

    // APB response uses the current transfer signals so data is valid in ACCESS.
    always_comb begin
        PREADY = 1'b0;
        PRDATA = 32'd0;
        PSLVERR = 1'b0;

        if (transfer_fire) begin
            PREADY = 1'b1;

            if (!PWRITE && decoded_valid) begin
                if (decoded_pointer) begin
                    PRDATA = {15'd0, consumer_pointer_q, 15'd0, producer_pointer_q};
                end else if (decoded_op_enable) begin
                    PRDATA = op_enable_reg[producer_pointer_q][op_enable_idx];
                end else if (decoded_status) begin
                    unique case (status_idx)
                        32'd0: PRDATA = {30'd0, cdma_status};
                        32'd1: PRDATA = {30'd0, csc_status};
                        32'd2: PRDATA = {30'd0, cacc_status};
                        default: PRDATA = 32'd0;
                    endcase
                end else begin
                    PRDATA = slvreg[producer_pointer_q][decoded_idx];
                end
            end

            PSLVERR = !decoded_valid || (PWRITE && decoded_status);
        end
    end

    //read,write ff
    always_ff @ (posedge PCLK) begin
        if(!rst_n) begin
            p_state <=S_IDLE;
            producer_pointer_q <= 1'b0;
            consumer_pointer_q <= 1'b0;
            consumer_busy_seen <= 3'b000;
            for(int g = 0; g < 2; g++ ) begin
                for(int i = 0; i < SLVREG_NUM; i++ ) begin
                    slvreg[g][i] <= 0;
                end
            end
            for(int g = 0; g < 2; g++ ) begin
                for(int i = 0; i < 3; i++ ) begin
                    op_enable_reg[g][i] <= 0;
                end
            end
        end else begin
            p_state <= n_state;
            if (consumer_advance_cond) begin
                consumer_pointer_q <= ~consumer_pointer_q;
                consumer_busy_seen <= 3'b000;
            end else begin
                if (cdma_status[consumer_pointer_q]) begin
                    consumer_busy_seen[0] <= 1'b1;
                end
                if (csc_status[consumer_pointer_q]) begin
                    consumer_busy_seen[1] <= 1'b1;
                end
                if (cacc_status[consumer_pointer_q]) begin
                    consumer_busy_seen[2] <= 1'b1;
                end
            end
            if (cdma_op_enable_clear) begin
                op_enable_reg[consumer_pointer_q][0][0] <= 1'b0;
            end
            if (csc_op_enable_clear) begin
                op_enable_reg[consumer_pointer_q][1][0] <= 1'b0;
            end

            if (transfer_fire && PWRITE && decoded_valid) begin
                if (decoded_pointer) begin
                    producer_pointer_q <= PWDATA[0];
                end else if (decoded_op_enable) begin
                    op_enable_reg[producer_pointer_q][op_enable_idx] <= PWDATA;
                end else if (!decoded_status) begin
                    slvreg[producer_pointer_q][decoded_idx] <= PWDATA;
                end
            end
        end
    end
    
    //sticky clear
    always_ff @ (posedge PCLK) begin
        if(!rst_n) begin
            cdma_data_enable_clear_sticky <= 1'b0;
            cdma_weight_enable_clear_sticky <= 1'b0;
        end else begin
            if (cdma_op_enable_clear) begin
                cdma_data_enable_clear_sticky <= 1'b0;
                cdma_weight_enable_clear_sticky <= 1'b0;
            end else begin
                if (cdma_op_data_enable_clear) begin
                    cdma_data_enable_clear_sticky <= 1'b1;
                end
                if (cdma_op_weight_enable_clear) begin
                    cdma_weight_enable_clear_sticky <= 1'b1;
                end
            end
        end
    end

    always_comb begin
        S_POINTER               =  { 15'd0, consumer_pointer_q, 15'd0, producer_pointer_q };
        producer_pointer        = producer_pointer_q;
        consumer_pointer        = consumer_pointer_q;
        CDMA_D_OP_ENABLE        = op_enable_reg[consumer_pointer_q][0];
        DATA_MATRIX_WIDTH       = slvreg[consumer_pointer_q][1];
        DATA_MATRIX_HEIGHT      = slvreg[consumer_pointer_q][2];
        DATA_CHANNEL_COUNT      = slvreg[consumer_pointer_q][3];
        DATA_DST_BASE           = slvreg[consumer_pointer_q][4];
        DATA_SRC_BASE_ADDR      = slvreg[consumer_pointer_q][5];
        WEIGHT_MATRIX_WIDTH     = slvreg[consumer_pointer_q][6];
        WEIGHT_MATRIX_HEIGHT    = slvreg[consumer_pointer_q][7];
        WEIGHT_CHANNEL_COUNT    = slvreg[consumer_pointer_q][8];
        WEIGHT_DST_BASE         = slvreg[consumer_pointer_q][9];
        WEIGHT_SRC_BASE_ADDR    = slvreg[consumer_pointer_q][10];
        WEIGHT_KERNELS_PER_CHUNK = slvreg[consumer_pointer_q][29];
        CSC_D_OP_ENABLE         = op_enable_reg[consumer_pointer_q][1];
        CSC_STATUS              = {30'd0, csc_status};
        CSC_ATOMICS             = slvreg[consumer_pointer_q][12];
        CSC_INPUT_WIDTH_HEIGHT  = slvreg[consumer_pointer_q][15];
        CSC_INPUT_CHANNELS      = slvreg[consumer_pointer_q][16];
        CSC_KERNEL_WIDTH_HEIGHT = slvreg[consumer_pointer_q][17];
        CSC_STRIDE_XY           = slvreg[consumer_pointer_q][18];
        CSC_OUTPUT_WIDTH_HEIGHT = slvreg[consumer_pointer_q][19];
        CSC_OUTPUT_CHANNELS     = slvreg[consumer_pointer_q][20];
        CSC_PADDING             = slvreg[consumer_pointer_q][28];
        CACC_D_OP_ENABLE        = op_enable_reg[consumer_pointer_q][2];
        CACC_S_STATUS           = {30'd0, cacc_status};
        CACC_D_DATAOUT_SIZE_0   = slvreg[consumer_pointer_q][22];
        CACC_D_DATAOUT_SIZE_1   = slvreg[consumer_pointer_q][23];
        CACC_D_DATAOUT_ADDR     = slvreg[consumer_pointer_q][24];
        CACC_D_LINE_STRIDE      = slvreg[consumer_pointer_q][25];
        CACC_D_SURF_STRIDE      = slvreg[consumer_pointer_q][26];
        CACC_D_DATAOUT_MAP      = slvreg[consumer_pointer_q][27];
        cdma_op_enable_level    = op_enable_reg[consumer_pointer_q][0][0];
        csc_op_enable_level     = op_enable_reg[consumer_pointer_q][1][0];
        cacc_op_enable_level    = op_enable_reg[consumer_pointer_q][2][0];
    end

endmodule
