module CDMA_weight_load #(
    WEIGHT_BURST_BEAT = 8,// 2 to the power of n
    WEIGHT_TOTAL_WIDTH = 32 * WEIGHT_BURST_BEAT,
    CBUF_BANK_NUM = 4,
    CBUF_ADDR_DEPTH = 1024
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        axi_ready,
    output logic        axi_req_valid,
    input  logic        axi_data_err,
    output logic        axi_weight_load_ready,
    input  logic        axi_weight_load_valid,
    output logic [31:0] weight_req_addr,
    input  logic [WEIGHT_TOTAL_WIDTH-1:0] loaded_weight,

    input  logic [31:0] WEIGHT_MATRIX_WIDTH,
    input  logic [31:0] WEIGHT_MATRIX_HEIGHT,
    input  logic [31:0] WEIGHT_CHANNEL_COUNT,
    input  logic [31:0] WEIGHT_OUTPUT_CHANNELS,
    input  logic [31:0] WEIGHT_SRC_BASE_ADDR,
    input  logic [31:0] WEIGHT_KERNELS_PER_CHUNK,
    
    input  logic        consumer_pointer,
    input  logic        cdma_start_pulse,
    output logic        cdma_op_weight_enable_clear,
    output logic [1:0]  cdma_weight_status,

    input  logic        weight_cbuf_wr_done,
    output logic        weight_cbuf_wr_start,
    output logic        weight_cbuf_wr_en,
    input  logic        weight_cbuf_ready,
    output logic [31:0] weight_cbuf_wr_count,

    input  logic        csc_weight_cbuf_refill_req,

    // Current weight CBUF chunk range in the original 32-bit weight-word space.
    output logic        weight_chunk_valid,
    output logic [31:0] weight_chunk_word_base,
    output logic [31:0] weight_chunk_word_count,
    output logic        weight_chunk_last,

    output logic [WEIGHT_TOTAL_WIDTH-1:0] weight_cbuf_wrdata
);
    
    localparam int WEIGHT_BURST_BEAT_SHIFT = $clog2(WEIGHT_BURST_BEAT);
    localparam int WEIGHT_BURST_BYTE_ADDR = WEIGHT_BURST_BEAT << 2;

    typedef enum logic [2:0] {
        S_IDLE,
        S_READY,
        S_LOAD,
        S_REPEAT,
        S_DONE,
        S_ERR
    } state_t;

    //logics
    logic        weight_load_start;
    logic        weight_load_done;
    logic        weight_ready_done;
    logic        repeat_load_allowed;
    logic        weight_calc_done;
    logic        weight_err;//error occure
    logic        weight_err_q;
    logic        axi_req_fire;
    logic        axi_load_fire;
    logic        weight_lane_stall;
    logic [31:0] weight_req_addr_recovery;//for error
    logic [31:0] weight_total_words;
    logic [31:0] weight_total_bursts;
    logic [31:0] weight_load_burst_counter;
    logic [31:0] weight_remaining_bursts;

    logic [31:0] weight_remaining_words;
    logic [31:0] next_chunk_word_count;
    logic [31:0] next_chunk_burst_count;

    logic [1:0]  weight_bursts_per_position;
    logic [31:0] weight_kernel_depth;
    logic [31:0] weight_bursts_per_kernel;
    logic [31:0] weight_chunk_burst_limit;
    logic [31:0] weight_chunk_word_limit;
    logic        active_group_q;

    // Added staged weight-size calculation to break the CSB-to-CBUF path.
    logic [1:0]  weight_calc_stage;
    logic [31:0] weight_matrix_width_cfg;
    logic [31:0] weight_matrix_height_cfg;
    logic [31:0] weight_channel_count_cfg;
    logic [31:0] weight_output_channels_cfg;
    logic [31:0] weight_src_base_addr_cfg;
    logic [31:0] weight_kernels_per_chunk_cfg;

    state_t p_weight_state, n_weight_state; 

    assign weight_load_start = cdma_start_pulse;
    assign weight_load_done = (weight_load_burst_counter == 0);
    assign weight_ready_done = weight_calc_done && weight_cbuf_ready;
    assign repeat_load_allowed = weight_ready_done && csc_weight_cbuf_refill_req;
    assign weight_lane_stall = !weight_cbuf_ready && weight_cbuf_wr_en;
    assign axi_req_valid = (p_weight_state == S_LOAD) && (weight_load_burst_counter != 0) && weight_cbuf_ready;
    assign axi_req_fire = axi_ready && axi_req_valid;

    assign axi_weight_load_ready = (!weight_lane_stall);
    assign axi_load_fire = axi_weight_load_ready && axi_weight_load_valid;

    // Added kernel-major layout. A chunk contains only complete kernels.
    assign weight_total_words = weight_total_bursts << WEIGHT_BURST_BEAT_SHIFT;
    assign weight_chunk_word_limit = weight_chunk_burst_limit << WEIGHT_BURST_BEAT_SHIFT;

    assign weight_err = weight_err_q || axi_data_err;

    assign next_chunk_word_count = (weight_remaining_words > weight_chunk_word_limit)
                                 ? weight_chunk_word_limit : weight_remaining_words;
    assign next_chunk_burst_count = (weight_remaining_bursts > weight_chunk_burst_limit)
                                  ? weight_chunk_burst_limit : weight_remaining_bursts;

    assign weight_cbuf_wr_count = (p_weight_state == S_REPEAT) ? next_chunk_burst_count : weight_load_burst_counter;
    assign weight_cbuf_wr_start = ((p_weight_state == S_READY) && (n_weight_state == S_LOAD)) || ((p_weight_state == S_REPEAT) && (n_weight_state == S_LOAD));

    assign weight_chunk_valid = (p_weight_state == S_REPEAT);
    assign weight_chunk_last = (weight_remaining_words == 0);

    //fsm
    always_comb begin
        n_weight_state = p_weight_state;
        unique case(p_weight_state)
            S_IDLE: if (weight_load_start) begin n_weight_state = S_READY; end
            S_READY: begin 
                if (weight_ready_done)  begin 
                    if (weight_total_bursts == 0) begin n_weight_state = S_DONE; end
                    else if (weight_kernels_per_chunk_cfg == 0) begin n_weight_state = S_ERR; end
                    else begin n_weight_state = S_LOAD; end
                end     
            end
            S_LOAD: begin
                if (weight_err) begin
                    n_weight_state = S_ERR;
                end else if (weight_load_done && weight_cbuf_wr_done) begin
                    n_weight_state = S_REPEAT;
                end
            end
            S_REPEAT: begin 
                if (repeat_load_allowed) begin
                    if (weight_remaining_bursts != 0) begin
                        n_weight_state = S_LOAD;
                    end else begin
                        n_weight_state = S_DONE;
                    end
                end 
            end
            S_DONE: n_weight_state = S_IDLE;
            S_ERR:  n_weight_state = S_REPEAT;
            default: begin n_weight_state = S_IDLE; end
        endcase
    end

    //fsm weight status
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            cdma_weight_status <= 2'b00;
            active_group_q <= 1'b0;
        end else begin
            if(p_weight_state == S_IDLE && n_weight_state == S_READY) begin
                active_group_q <= consumer_pointer;
                cdma_weight_status[consumer_pointer] <= 1'b1;
            end else if(p_weight_state == S_IDLE) begin
                cdma_weight_status[active_group_q] <= 1'b0;
            end else begin
                cdma_weight_status[active_group_q] <= 1'b1;
            end
        end
    end

    //op enable clear
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            cdma_op_weight_enable_clear <= 0;
        end else begin
            if(p_weight_state == S_IDLE && n_weight_state == S_READY) begin
                cdma_op_weight_enable_clear <= 1;
            end else begin
                cdma_op_weight_enable_clear <= 0;
            end
        end
    end

    //ready and load count
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            weight_calc_done <= 0;
            weight_load_burst_counter <= 0;
            weight_remaining_bursts <= 0;
            weight_req_addr <= 0;
            weight_req_addr_recovery <= 0;
            weight_err_q <= 0;
            weight_remaining_words <= 0;
            weight_chunk_word_base <= 0;
            weight_chunk_word_count <= 0;
            weight_calc_stage <= 0;
            weight_bursts_per_position <= 0;
            weight_kernel_depth <= 0;
            weight_bursts_per_kernel <= 0;
            weight_total_bursts <= 0;
            weight_chunk_burst_limit <= 0;
            weight_matrix_width_cfg <= 0;
            weight_matrix_height_cfg <= 0;
            weight_channel_count_cfg <= 0;
            weight_output_channels_cfg <= 0;
            weight_src_base_addr_cfg <= 0;
            weight_kernels_per_chunk_cfg <= 0;
        end else begin
            if (p_weight_state == S_IDLE && weight_load_start) begin
                weight_err_q <= 1'b0;
                weight_calc_done <= 1'b0;
                weight_calc_stage <= 0;
                weight_matrix_width_cfg <= WEIGHT_MATRIX_WIDTH;
                weight_matrix_height_cfg <= WEIGHT_MATRIX_HEIGHT;
                weight_channel_count_cfg <= WEIGHT_CHANNEL_COUNT;
                weight_output_channels_cfg <= WEIGHT_OUTPUT_CHANNELS;
                weight_src_base_addr_cfg <= WEIGHT_SRC_BASE_ADDR;
                weight_kernels_per_chunk_cfg <= WEIGHT_KERNELS_PER_CHUNK;
            end else if (axi_data_err) begin
                weight_err_q <= 1'b1;
            end else if (p_weight_state == S_REPEAT && weight_err_q) begin
                weight_err_q <= 1'b0;
            end

            if (p_weight_state == S_READY) begin
                if (weight_calc_stage == 0) begin
                    weight_bursts_per_position <= (weight_channel_count_cfg[7:0] + 31) >> 5;
                    weight_kernel_depth <= weight_matrix_width_cfg * weight_matrix_height_cfg;
                    weight_calc_stage <= 1;
                end else if (weight_calc_stage == 1) begin
                    weight_bursts_per_kernel <= weight_kernel_depth * weight_bursts_per_position;
                    weight_calc_stage <= 2;
                end else if (weight_calc_stage == 2) begin
                    weight_total_bursts <= weight_bursts_per_kernel * weight_output_channels_cfg;
                    weight_chunk_burst_limit <= weight_kernels_per_chunk_cfg * weight_bursts_per_kernel;
                    weight_calc_stage <= 3;
                end else begin
                    weight_calc_done <= 1;
                    if (weight_total_bursts > weight_chunk_burst_limit) begin
                        weight_load_burst_counter <= weight_chunk_burst_limit;
                        weight_remaining_bursts <= weight_total_bursts - weight_chunk_burst_limit;
                    end else begin
                        weight_load_burst_counter <= weight_total_bursts;
                        weight_remaining_bursts <= 0;
                    end
                    weight_req_addr <= weight_src_base_addr_cfg;
                    weight_req_addr_recovery <= weight_src_base_addr_cfg;

                    weight_chunk_word_base <= 0;
                    if (weight_total_words > weight_chunk_word_limit) begin
                        weight_chunk_word_count <= weight_chunk_word_limit;
                        weight_remaining_words <= weight_total_words - weight_chunk_word_limit;
                    end else begin
                        weight_chunk_word_count <= weight_total_words;
                        weight_remaining_words <= 0;
                    end
                end
            end 
            if (p_weight_state == S_LOAD) begin
                if (weight_load_burst_counter > 0) begin
                    weight_calc_done <= 0;
                    if(axi_req_fire) begin
                        weight_req_addr <= weight_req_addr + WEIGHT_BURST_BYTE_ADDR;  
                        weight_req_addr_recovery <= weight_req_addr;
                        weight_load_burst_counter <= weight_load_burst_counter - 1;
                    end else begin
                        weight_req_addr <= weight_req_addr;
                        weight_load_burst_counter <= weight_load_burst_counter;
                    end
                end
            end
            if (p_weight_state == S_REPEAT) begin
                weight_calc_done <= 1;
                if(weight_err) begin
                    weight_req_addr <= weight_req_addr_recovery;
                    weight_load_burst_counter <= weight_load_burst_counter + 1;
                end else if (repeat_load_allowed && (weight_load_burst_counter == 0)) begin
                    if (weight_remaining_bursts > weight_chunk_burst_limit) begin
                        weight_load_burst_counter <= weight_chunk_burst_limit;
                        weight_remaining_bursts <= weight_remaining_bursts - weight_chunk_burst_limit;
                    end else begin
                        weight_load_burst_counter <= weight_remaining_bursts;
                        weight_remaining_bursts <= 0;
                    end

                    if (weight_remaining_words != 0) begin
                        weight_chunk_word_base <= weight_chunk_word_base + weight_chunk_word_count;
                        weight_chunk_word_count <= next_chunk_word_count;
                        weight_remaining_words <= weight_remaining_words - next_chunk_word_count;
                    end
                end
            end
        end
    end

    //weight_lane
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            weight_cbuf_wr_en <= 0;
            weight_cbuf_wrdata <= 0;
        end else begin
            if (p_weight_state == S_LOAD) begin
                if(weight_lane_stall) begin
                    weight_cbuf_wr_en <= weight_cbuf_wr_en;
                    weight_cbuf_wrdata <= weight_cbuf_wrdata;
                end else begin
                    weight_cbuf_wr_en <= 0;
                    if (axi_load_fire) begin
                        weight_cbuf_wrdata <= loaded_weight;
                        weight_cbuf_wr_en <= 1;
                    end
                end
            end else begin
                weight_cbuf_wr_en <= 0;
            end
        end
    end

    //fsm ff
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            p_weight_state <= S_IDLE;
        end else begin
            p_weight_state <= n_weight_state;
        end
    end
endmodule
