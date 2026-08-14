module CDMA_data_load #(
    DATA_BURST_BEAT = 8,// 2 to the power of n
    DATA_TOTAL_WIDTH = 32 * DATA_BURST_BEAT,
    CBUF_BANK_NUM = 4,
    CBUF_ADDR_DEPTH = 1024
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        axi_ready,
    output logic        axi_req_valid,
    input  logic        axi_data_err,
    output logic        axi_data_load_ready,
    input  logic        axi_data_load_valid,
    output logic [31:0] data_req_addr,
    input  logic [DATA_TOTAL_WIDTH-1:0] loaded_data,

    input  logic [31:0] DATA_MATRIX_WIDTH,
    input  logic [31:0] DATA_MATRIX_HEIGHT,
    input  logic [31:0] DATA_CHANNEL_COUNT,
    input  logic [31:0] DATA_SRC_BASE_ADDR,
    
    input  logic        consumer_pointer,
    input  logic        cdma_start_pulse,
    output logic        cdma_op_enable_clear,
    output logic [1:0]  cdma_data_status,

    input  logic        cbuf_wr_done,
    output logic        cbuf_wr_start,
    output logic        cbuf_wr_en,
    input  logic        cbuf_ready,
    output logic [31:0] cbuf_wr_count,

    input  logic        data_refill_valid,
    output logic        data_refill_ready,
    input  logic [31:0] data_refill_position_base,
    input  logic [31:0] data_refill_position_count,
    input  logic        data_refill_last,

    input  logic        data_release_valid,
    output logic        data_release_ready,

    // Current CBUF chunk range in the input-position space.
    output logic        data_chunk_valid,
    output logic [31:0] data_chunk_position_base,
    output logic [31:0] data_chunk_position_count,
    output logic        data_chunk_last,

    output logic [DATA_TOTAL_WIDTH-1:0] cbuf_wrdata
);
    
    localparam int DATA_BURST_BYTE_ADDR = DATA_BURST_BEAT << 2;

    typedef enum logic [2:0] {
        S_IDLE,
        S_READY,
        S_CALC,
        S_START,
        S_LOAD,
        S_REPEAT,
        S_DONE,
        S_ERR
    } state_t;

    //logics
    logic        data_load_start;
    logic        data_load_done;
    logic        data_err;//error occure
    logic        data_err_q;
    logic        axi_req_fire;
    logic        axi_load_fire;
    logic        data_refill_fire;
    logic        data_release_fire;
    logic        data_refill_command_valid;
    logic        data_lane_stall;
    logic [31:0] data_req_addr_recovery;//for error
    logic [31:0] data_load_burst_counter;
    logic [31:0] accepted_position_base;
    logic [31:0] accepted_position_count;
    logic        accepted_position_last;
    logic [31:0] data_matrix_width_cfg;
    logic [31:0] data_matrix_height_cfg;
    logic [31:0] data_total_positions;
    logic        initial_chunk_ready;
    logic        initial_chunk_command_valid;

    logic [7:0]  data_channel_count; // max 64
    logic [1:0]  data_bursts_per_position;
    logic        active_group_q;

    state_t p_data_state, n_data_state; 

    assign data_load_start = cdma_start_pulse;
    assign data_load_done = (data_load_burst_counter == 0);
    assign data_lane_stall = !cbuf_ready && cbuf_wr_en;
    assign axi_req_valid = (p_data_state == S_LOAD) && (data_load_burst_counter != 0) && cbuf_ready;
    assign axi_req_fire = axi_ready && axi_req_valid;

    assign axi_data_load_ready = (!data_lane_stall);
    assign axi_load_fire = axi_data_load_ready && axi_data_load_valid;

    assign data_channel_count = DATA_CHANNEL_COUNT[7:0];

    assign data_bursts_per_position =
        (data_channel_count == 0) ? 1 : (data_channel_count + 31) >> 5;
    assign data_refill_command_valid =
        (data_refill_position_count != 0) &&
        (data_refill_position_count <= CBUF_ADDR_DEPTH) &&
        (data_channel_count <= 64);
    // The first chunk starts from input position zero without a CSC refill request.
    assign initial_chunk_command_valid =
        (data_total_positions != 0) &&
        (data_channel_count != 0) &&
        (data_channel_count <= 64);
    assign data_refill_ready =
        (p_data_state == S_REPEAT) && cbuf_ready;
    assign data_refill_fire = data_refill_valid && data_refill_ready;
    // Keep CDMA available for backward refills until CSC releases the operation.
    assign data_release_ready = (p_data_state == S_REPEAT);
    assign data_release_fire = data_release_valid && data_release_ready;

    assign data_err = data_err_q || axi_data_err;// latch 1-cycle AXI error pulse
    assign cbuf_wr_count = data_load_burst_counter;
    assign cbuf_wr_start =
        (p_data_state == S_START) && cbuf_ready;

    //fsm
    always_comb begin
        n_data_state = p_data_state;
        unique case(p_data_state)
            S_IDLE: if (data_load_start) begin n_data_state = S_READY; end
            S_READY: begin
                if (initial_chunk_ready) begin
                    if (initial_chunk_command_valid) begin n_data_state = S_CALC; end
                    else                             begin n_data_state = S_ERR; end
                end
            end
            S_CALC: n_data_state = S_START;
            S_START: begin
                if (cbuf_ready) begin n_data_state = S_LOAD; end
            end
            S_LOAD: begin
                if (data_err) begin
                    n_data_state = S_ERR;
                end else if (data_load_done && cbuf_wr_done) begin
                    n_data_state = S_REPEAT;
                end
            end
            S_REPEAT: begin 
                if (data_refill_fire) begin
                    if (data_refill_command_valid) begin n_data_state = S_CALC; end
                    else                           begin n_data_state = S_ERR; end
                end else if (data_release_fire) begin
                    n_data_state = S_DONE;
                end
            end
            S_DONE: n_data_state = S_IDLE;
            S_ERR:  n_data_state = S_IDLE;
            default: begin n_data_state = S_IDLE; end
        endcase
    end

    //fsm data status
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            cdma_data_status <= 2'b00;
            active_group_q <= 1'b0;
        end else begin
            if(p_data_state == S_IDLE && n_data_state == S_READY) begin
                active_group_q <= consumer_pointer;
                cdma_data_status[consumer_pointer] <= 1'b1;
            end else if(p_data_state == S_IDLE) begin
                cdma_data_status[active_group_q] <= 1'b0;
            end else begin
                cdma_data_status[active_group_q] <= 1'b1;
            end
        end
    end

    //op enable clear
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            cdma_op_enable_clear <= 0;
        end else begin
            if(p_data_state == S_IDLE && n_data_state == S_READY) begin
                cdma_op_enable_clear <= 1;
            end else begin
                cdma_op_enable_clear <= 0;
            end
        end
    end

    //ready and load count
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            data_load_burst_counter <= 0;
            data_req_addr <= 0;
            data_req_addr_recovery <= 0;
            data_err_q <= 0;
            data_chunk_valid <= 0;
            data_chunk_position_base <= 0;
            data_chunk_position_count <= 0;
            data_chunk_last <= 0;
            accepted_position_base <= 0;
            accepted_position_count <= 0;
            accepted_position_last <= 0;
            data_matrix_width_cfg <= 0;
            data_matrix_height_cfg <= 0;
            data_total_positions <= 0;
            initial_chunk_ready <= 0;
        end else begin
            if (p_data_state == S_IDLE && data_load_start) begin
                data_err_q <= 1'b0;
                data_chunk_valid <= 1'b0;
                data_matrix_width_cfg <= DATA_MATRIX_WIDTH;
                data_matrix_height_cfg <= DATA_MATRIX_HEIGHT;
                initial_chunk_ready <= 1'b0;
            end else if (axi_data_err) begin
                data_err_q <= 1'b1;
            end else if (data_refill_fire) begin
                data_err_q <= 1'b0;
            end

            // Build the initial CBUF-sized command internally; later commands come from CSC.
            if ((p_data_state == S_READY) && !initial_chunk_ready) begin
                data_total_positions <= data_matrix_width_cfg * data_matrix_height_cfg;
                initial_chunk_ready <= 1'b1;
            end else if ((p_data_state == S_READY) && initial_chunk_ready) begin
                accepted_position_base <= 0;
                if (data_total_positions > CBUF_ADDR_DEPTH) begin
                    accepted_position_count <= CBUF_ADDR_DEPTH;
                    accepted_position_last <= 1'b0;
                end else begin
                    accepted_position_count <= data_total_positions;
                    accepted_position_last <= 1'b1;
                end
                data_chunk_valid <= 1'b0;
            end else if (data_refill_fire && data_refill_command_valid) begin
                accepted_position_base <= data_refill_position_base;
                accepted_position_count <= data_refill_position_count;
                accepted_position_last <= data_refill_last;
                data_chunk_valid <= 1'b0;
            end
            // Convert semantic input positions into DDR words, bytes and bursts.
            if (p_data_state == S_CALC) begin
                if (data_bursts_per_position > 1) begin
                    data_load_burst_counter <= accepted_position_count << 1;
                    data_req_addr <= DATA_SRC_BASE_ADDR +
                                     (accepted_position_base << 6);
                    data_req_addr_recovery <= DATA_SRC_BASE_ADDR +
                                              (accepted_position_base << 6);
                end else begin
                    data_load_burst_counter <= accepted_position_count;
                    data_req_addr <= DATA_SRC_BASE_ADDR +
                                     (accepted_position_base << 5);
                    data_req_addr_recovery <= DATA_SRC_BASE_ADDR +
                                              (accepted_position_base << 5);
                end
                data_chunk_position_base <= accepted_position_base;
                data_chunk_position_count <= accepted_position_count;
                data_chunk_last <= accepted_position_last;
            end
            if (p_data_state == S_LOAD) begin
                if (data_load_burst_counter > 0) begin
                    if(axi_req_fire) begin
                        data_req_addr <= data_req_addr + DATA_BURST_BYTE_ADDR;  
                        data_req_addr_recovery <= data_req_addr;
                        data_load_burst_counter <= data_load_burst_counter - 1;
                    end else begin
                        data_req_addr <= data_req_addr;
                        data_load_burst_counter <= data_load_burst_counter;
                    end
                end
                if (data_load_done && cbuf_wr_done && !data_err) begin
                    data_chunk_valid <= 1'b1;
                end
            end
        end
    end

    //data_lane
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            cbuf_wr_en <= 0;
            cbuf_wrdata <= 0;
        end else begin
            if (p_data_state == S_LOAD) begin
                if(data_lane_stall) begin
                    cbuf_wr_en <= cbuf_wr_en;
                    cbuf_wrdata <= cbuf_wrdata; //latched when cbuf is not ready
                end else begin
                    cbuf_wr_en <= 0;
                    if (axi_load_fire) begin
                        cbuf_wrdata <= loaded_data;
                        cbuf_wr_en <= 1;
                    end
                end
            end else begin
                cbuf_wr_en <= 0;
            end
        end
    end

    //fsm ff
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            p_data_state <= S_IDLE;
        end else begin
            p_data_state <= n_data_state;
        end
    end
endmodule
