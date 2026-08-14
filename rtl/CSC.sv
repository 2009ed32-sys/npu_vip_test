`timescale 1ns/1ps

module CSC #(
    parameter int BANK_WIDTH      = 128,
    parameter int BANK_NUM        = 4,
    parameter int MACLANE_WIDTH   = 256,
    parameter int BANK_ADDR_WIDTH = 10,
    parameter int TAG_WIDTH       = 32,
    parameter int MACLANE_DEPTH   = 3
) (
    input  logic clk,
    input  logic rst_n,

    // CSB control and configuration
    input  logic        consumer_pointer,
    input  logic        csc_op_enable_level,
    input  logic [31:0] CSC_INPUT_WIDTH_HEIGHT,
    input  logic [31:0] CSC_INPUT_CHANNELS,
    input  logic [31:0] CSC_KERNEL_WIDTH_HEIGHT,
    input  logic [31:0] CSC_STRIDE_XY,
    input  logic [31:0] CSC_OUTPUT_WIDTH_HEIGHT,
    input  logic [31:0] CSC_OUTPUT_CHANNELS,
    input  logic [31:0] CSC_PADDING,

    output logic       csc_op_enable_clear,
    output logic [1:0] csc_status,

    // CDMA data chunk
    input  logic        data_chunk_valid,
    input  logic [31:0] data_chunk_position_base,
    input  logic [31:0] data_chunk_position_count,
    input  logic        data_chunk_last,
    output logic        data_refill_valid,
    input  logic        data_refill_ready,
    output logic [31:0] data_refill_position_base,
    output logic [31:0] data_refill_position_count,
    output logic        data_refill_last,

    // CDMA weight chunk
    input  logic        weight_chunk_valid,
    input  logic [31:0] weight_chunk_word_base,
    input  logic [31:0] weight_chunk_word_count,
    input  logic        weight_chunk_last,
    output logic        csc_weight_cbuf_refill_req,

    // Data CBUF read port
    output logic                                    data_cbuf_rd_en,
    output logic [BANK_NUM-1:0]                     data_cbuf_rd_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]   data_cbuf_rd_addr,
    input  logic                                    data_cbuf_rd_valid,
    input  logic [(BANK_NUM*BANK_WIDTH)-1:0]        data_cbuf_rd_data,

    // Weight CBUF read port
    output logic                                    weight_cbuf_rd_en,
    output logic [BANK_NUM-1:0]                     weight_cbuf_rd_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]   weight_cbuf_rd_addr,
    input  logic                                    weight_cbuf_rd_valid,
    input  logic [(BANK_NUM*BANK_WIDTH)-1:0]        weight_cbuf_rd_data,

    // Sequential MACLane FIFO output
    output logic                                    maclane_valid,
    input  logic                                    maclane_ready,
    output logic [TAG_WIDTH-1:0]                    maclane_tag,
    output logic [MACLANE_WIDTH-1:0]                maclane_data,
    output logic [MACLANE_WIDTH-1:0]                maclane_weight,
    output logic [$clog2(MACLANE_DEPTH+1)-1:0]      maclane_level
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_WAIT_CHUNK,
        S_WORK,
        S_DONE
    } state_t;

    state_t p_state;
    state_t n_state;

    localparam int CBUF_READ_WIDTH = BANK_NUM * BANK_WIDTH;

    logic                         active_group_q;
    logic [TAG_WIDTH-1:0]         next_tag_q;
    logic [TAG_WIDTH-1:0]         pending_tag_q;
    logic                         read_pending_q;
    logic                         data_hold_valid_q;
    logic                         weight_hold_valid_q;
    logic [CBUF_READ_WIDTH-1:0]   data_hold_q;
    logic [CBUF_READ_WIDTH-1:0]   weight_hold_q;
    logic                         read_issue;
    logic                         data_available;
    logic                         weight_available;
    logic                         maclane_in_valid;
    logic                         maclane_in_ready;
    logic [TAG_WIDTH-1:0]         maclane_in_tag;
    logic [MACLANE_WIDTH-1:0]     maclane_in_data;
    logic [MACLANE_WIDTH-1:0]     maclane_in_weight;
    logic                         operation_done;
    logic [7:0]                   input_channel_count;
    logic [2:0]                   active_bank_count;
    logic [BANK_NUM-1:0]          read_bank_enable;
    logic [CBUF_READ_WIDTH-1:0]   selected_data_row;
    logic [CBUF_READ_WIDTH-1:0]   selected_weight_row;
    logic [15:0]                  input_width;
    logic [15:0]                  input_height;
    logic [15:0]                  kernel_width;
    logic [15:0]                  kernel_height;
    logic [15:0]                  stride_x;
    logic [15:0]                  stride_y;
    logic [15:0]                  output_width;
    logic [15:0]                  output_height;
    logic [15:0]                  output_channel_count;
    logic [7:0]                   pad_left;
    logic [7:0]                   pad_top;
    logic [2:0]                   channel_packet_count;
    logic [15:0]                  output_x_counter;
    logic [15:0]                  output_y_counter;
    logic [15:0]                  kernel_x_counter;
    logic [15:0]                  kernel_y_counter;
    logic [15:0]                  output_kernel_counter;
    logic [1:0]                   channel_packet_counter;
    logic [BANK_ADDR_WIDTH-1:0]   data_read_address;
    logic [BANK_ADDR_WIDTH-1:0]   weight_read_address;
    logic                         pending_padding;
    logic                         scheduler_finished;
    logic                         last_packet;
    logic                         packet_accept;
    logic [31:0]                  data_total_positions;
    logic [31:0]                  data_chunk_position_end;
    logic [31:0]                  data_local_position_offset;
    logic [31:0]                  refill_position;
    logic [31:0]                  refill_position_base;
    logic [31:0]                  refill_position_count;
    logic [31:0]                  refill_positions_remaining;
    logic                         data_chunk_hit;
    logic                         data_refill_needed;
    logic                         data_refill_fire;
    logic                         data_refill_wait;
    logic [2:0]                   schedule_stage;
    logic [31:0]                  calculated_padded_x;
    logic [31:0]                  calculated_padded_y;
    logic                         calculated_input_valid;
    logic [31:0]                  calculated_input_x;
    logic [31:0]                  calculated_input_y;
    logic [31:0]                  calculated_data_position;
    logic [31:0]                  calculated_weight_position;
    logic                         calculated_last_packet;
    logic [TAG_WIDTH-1:0]         calculated_tag;
    logic [31:0]                  kernel_area;

    localparam logic [2:0] SCHEDULE_IDLE     = 3'd0;
    localparam logic [2:0] SCHEDULE_COORD    = 3'd1;
    localparam logic [2:0] SCHEDULE_POSITION = 3'd2;
    localparam logic [2:0] SCHEDULE_ADDRESS  = 3'd3;
    localparam logic [2:0] SCHEDULE_READY    = 3'd4;

    assign read_issue = (schedule_stage == SCHEDULE_READY) &&
                        !read_pending_q &&
                        !data_hold_valid_q &&
                        !weight_hold_valid_q &&
                        data_chunk_hit &&
                        !data_refill_wait &&
                        !data_refill_valid &&
                        maclane_in_ready;

    assign data_available = pending_padding || data_hold_valid_q || data_cbuf_rd_valid;
    assign weight_available = weight_hold_valid_q || weight_cbuf_rd_valid;
    assign maclane_in_valid = read_pending_q && data_available && weight_available;
    assign maclane_in_tag = pending_tag_q;
    assign selected_data_row = data_cbuf_rd_valid ? data_cbuf_rd_data : data_hold_q;
    assign selected_weight_row = weight_cbuf_rd_valid ? weight_cbuf_rd_data : weight_hold_q;
    assign maclane_in_data = pending_padding ? '0 : selected_data_row[MACLANE_WIDTH-1:0];
    assign maclane_in_weight = selected_weight_row[MACLANE_WIDTH-1:0];
    assign packet_accept = maclane_in_valid && maclane_in_ready;

    // Added bank-pair selection for the 4x128-bit CBUF layout.
    assign active_bank_count = (input_channel_count == 0) ? 0 : (input_channel_count >= 64) ? 4 : (input_channel_count + 15) >> 4;
    assign channel_packet_count = (input_channel_count == 0) ? 1 : (input_channel_count + 63) >> 6;

    // Registered scheduler stages leave DDR word and byte conversion to CDMA.
    assign data_chunk_position_end =
        data_chunk_position_base + data_chunk_position_count;
    assign data_chunk_hit = !calculated_input_valid ||
                            (data_chunk_valid &&
                             (calculated_data_position >= data_chunk_position_base) &&
                             (calculated_data_position < data_chunk_position_end));
    assign data_local_position_offset =
        calculated_data_position - data_chunk_position_base;
    assign data_read_address = data_local_position_offset[BANK_ADDR_WIDTH-1:0];
    assign weight_read_address = calculated_weight_position[BANK_ADDR_WIDTH-1:0];
    assign last_packet = calculated_last_packet;

    always_comb begin
        read_bank_enable = 0;
        for (int bank = 0; bank < BANK_NUM; bank++) begin
            if (bank < active_bank_count) begin
                read_bank_enable[bank] = 1'b1;
            end
        end
    end

    assign operation_done = scheduler_finished &&
                            !read_pending_q &&
                            (maclane_level == 0);

    // Refill one CBUF-sized group of complete input positions.
    assign refill_position =
        (p_state == S_WAIT_CHUNK) ? 0 : calculated_data_position;
    assign refill_position_base = (refill_position >> BANK_ADDR_WIDTH) << BANK_ADDR_WIDTH;
    assign refill_positions_remaining = data_total_positions - refill_position_base;
    assign refill_position_count = (refill_positions_remaining > (1 << BANK_ADDR_WIDTH)) ?
                                   (1 << BANK_ADDR_WIDTH) : refill_positions_remaining;
    // CDMA creates the first chunk; CSC requests only a later missing chunk.
    assign data_refill_needed = ((schedule_stage == SCHEDULE_READY) &&
                                  calculated_input_valid &&
                                  !data_chunk_hit);
    assign data_refill_fire = data_refill_valid && data_refill_ready;
    assign csc_weight_cbuf_refill_req = 1'b0;

    // FSM next-state logic
    always_comb begin
        n_state = p_state;
        unique case (p_state)
            S_IDLE: begin
                if (csc_op_enable_level) begin
                    n_state = S_WAIT_CHUNK;
                end
            end
            S_WAIT_CHUNK: begin
                if (data_chunk_valid && weight_chunk_valid && !data_refill_wait) begin
                    n_state = S_WORK;
                end
            end
            S_WORK: begin
                if (operation_done) begin
                    n_state = S_DONE;
                end
            end
            S_DONE: begin
                n_state = S_IDLE;
            end
            default: begin
                n_state = S_IDLE;
            end
        endcase
    end

    // FSM state register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            p_state <= S_IDLE;
        end else begin
            p_state <= n_state;
        end
    end

    // Latch one operation's configuration before scheduler arithmetic begins.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            input_channel_count <= 0;
            input_width <= 0;
            input_height <= 0;
            kernel_width <= 0;
            kernel_height <= 0;
            stride_x <= 0;
            stride_y <= 0;
            output_width <= 0;
            output_height <= 0;
            output_channel_count <= 0;
            pad_left <= 0;
            pad_top <= 0;
            data_total_positions <= 0;
            kernel_area <= 0;
        end else if ((p_state == S_IDLE) && (n_state == S_WAIT_CHUNK)) begin
            input_channel_count <= CSC_INPUT_CHANNELS[7:0];
            input_width <= CSC_INPUT_WIDTH_HEIGHT[15:0];
            input_height <= CSC_INPUT_WIDTH_HEIGHT[31:16];
            kernel_width <= CSC_KERNEL_WIDTH_HEIGHT[15:0];
            kernel_height <= CSC_KERNEL_WIDTH_HEIGHT[31:16];
            stride_x <= CSC_STRIDE_XY[15:0];
            stride_y <= CSC_STRIDE_XY[31:16];
            output_width <= CSC_OUTPUT_WIDTH_HEIGHT[15:0];
            output_height <= CSC_OUTPUT_WIDTH_HEIGHT[31:16];
            output_channel_count <= CSC_OUTPUT_CHANNELS[15:0];
            pad_left <= CSC_PADDING[7:0];
            pad_top <= CSC_PADDING[23:16];
            data_total_positions <=
                CSC_INPUT_WIDTH_HEIGHT[15:0] *
                CSC_INPUT_WIDTH_HEIGHT[31:16];
            kernel_area <=
                CSC_KERNEL_WIDTH_HEIGHT[15:0] *
                CSC_KERNEL_WIDTH_HEIGHT[31:16];
        end
    end

    // Hold each position-based refill command until CDMA accepts it.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            data_refill_wait <= 1'b0;
            data_refill_valid <= 1'b0;
            data_refill_position_base <= 0;
            data_refill_position_count <= 0;
            data_refill_last <= 1'b0;
        end else if ((p_state == S_IDLE) && (n_state == S_WAIT_CHUNK)) begin
            data_refill_wait <= 1'b0;
            data_refill_valid <= 1'b0;
        end else if (data_refill_fire) begin
            data_refill_wait <= 1'b1;
            data_refill_valid <= 1'b0;
        end else if (data_refill_wait && data_chunk_valid) begin
            data_refill_wait <= 1'b0;
        end else if (data_refill_needed &&
                     !data_refill_valid &&
                     !data_refill_wait) begin
            data_refill_position_base <= refill_position_base;
            data_refill_position_count <= refill_position_count;
            data_refill_last <=
                (refill_position_base + refill_position_count) >=
                data_total_positions;
            data_refill_valid <= 1'b1;
        end
    end

    // Calculate one scheduler entry over multiple registered stages.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            next_tag_q <= '0;
            pending_tag_q <= '0;
            read_pending_q <= 1'b0;
            data_hold_valid_q <= 1'b0;
            weight_hold_valid_q <= 1'b0;
            data_hold_q <= '0;
            weight_hold_q <= '0;
            pending_padding <= 1'b0;
            scheduler_finished <= 1'b0;
            output_x_counter <= 16'd0;
            output_y_counter <= 16'd0;
            kernel_x_counter <= 16'd0;
            kernel_y_counter <= 16'd0;
            output_kernel_counter <= 16'd0;
            channel_packet_counter <= 2'd0;
            schedule_stage <= SCHEDULE_IDLE;
            calculated_padded_x <= 0;
            calculated_padded_y <= 0;
            calculated_input_valid <= 1'b0;
            calculated_input_x <= 0;
            calculated_input_y <= 0;
            calculated_data_position <= 0;
            calculated_weight_position <= 0;
            calculated_last_packet <= 1'b0;
            calculated_tag <= 0;
            data_cbuf_rd_en <= 1'b0;
            data_cbuf_rd_bank_en <= 0;
            data_cbuf_rd_addr <= 0;
            weight_cbuf_rd_en <= 1'b0;
            weight_cbuf_rd_bank_en <= 0;
            weight_cbuf_rd_addr <= 0;
        end else begin
            data_cbuf_rd_en <= 1'b0;
            data_cbuf_rd_bank_en <= 0;
            weight_cbuf_rd_en <= 1'b0;
            weight_cbuf_rd_bank_en <= 0;

            if ((p_state == S_IDLE) && (n_state == S_WAIT_CHUNK)) begin
                next_tag_q <= '0;
                pending_tag_q <= '0;
                read_pending_q <= 1'b0;
                data_hold_valid_q <= 1'b0;
                weight_hold_valid_q <= 1'b0;
                pending_padding <= 1'b0;
                scheduler_finished <= 1'b0;
                output_x_counter <= 16'd0;
                output_y_counter <= 16'd0;
                kernel_x_counter <= 16'd0;
                kernel_y_counter <= 16'd0;
                output_kernel_counter <= 16'd0;
                channel_packet_counter <= 2'd0;
                schedule_stage <= SCHEDULE_IDLE;
            end else begin
                if (p_state != S_WORK) begin
                    schedule_stage <= SCHEDULE_IDLE;
                end else begin
                    unique case (schedule_stage)
                        SCHEDULE_IDLE: begin
                            if (!scheduler_finished &&
                                !read_pending_q &&
                                !data_hold_valid_q &&
                                !weight_hold_valid_q &&
                                !data_refill_wait &&
                                !data_refill_valid) begin
                                calculated_padded_x <=
                                    (output_x_counter * stride_x) +
                                    kernel_x_counter;
                                calculated_padded_y <=
                                    (output_y_counter * stride_y) +
                                    kernel_y_counter;
                                calculated_weight_position <=
                                    (output_kernel_counter * kernel_area) +
                                    (kernel_y_counter * kernel_width) +
                                    kernel_x_counter;
                                calculated_last_packet <=
                                    ((output_kernel_counter + 1) >=
                                     output_channel_count) &&
                                    ((output_y_counter + 1) >=
                                     output_height) &&
                                    ((output_x_counter + 1) >=
                                     output_width) &&
                                    ((kernel_y_counter + 1) >=
                                     kernel_height) &&
                                    ((kernel_x_counter + 1) >=
                                     kernel_width) &&
                                    ((channel_packet_counter + 1) >=
                                     channel_packet_count);
                                calculated_tag <= next_tag_q;
                                schedule_stage <= SCHEDULE_COORD;
                            end
                        end
                        SCHEDULE_COORD: begin
                            if ((calculated_padded_x >= pad_left) &&
                                (calculated_padded_x <
                                 (pad_left + input_width)) &&
                                (calculated_padded_y >= pad_top) &&
                                (calculated_padded_y <
                                 (pad_top + input_height))) begin
                                calculated_input_valid <= 1'b1;
                                calculated_input_x <=
                                    calculated_padded_x - pad_left;
                                calculated_input_y <=
                                    calculated_padded_y - pad_top;
                            end else begin
                                calculated_input_valid <= 1'b0;
                                calculated_input_x <= 0;
                                calculated_input_y <= 0;
                            end
                            schedule_stage <= SCHEDULE_POSITION;
                        end
                        SCHEDULE_POSITION: begin
                            calculated_data_position <=
                                (calculated_input_y * input_width) +
                                calculated_input_x;
                            schedule_stage <= SCHEDULE_ADDRESS;
                        end
                        SCHEDULE_ADDRESS: begin
                            schedule_stage <= SCHEDULE_READY;
                        end
                        SCHEDULE_READY: begin
                            if (read_issue) begin
                                pending_tag_q <= calculated_tag;
                                read_pending_q <= 1'b1;
                                pending_padding <=
                                    !calculated_input_valid;
                                data_cbuf_rd_en <=
                                    calculated_input_valid;
                                data_cbuf_rd_bank_en <=
                                    calculated_input_valid ?
                                    read_bank_enable : '0;
                                data_cbuf_rd_addr <=
                                    {BANK_NUM{data_read_address}};
                                weight_cbuf_rd_en <= 1'b1;
                                weight_cbuf_rd_bank_en <=
                                    read_bank_enable;
                                weight_cbuf_rd_addr <=
                                    {BANK_NUM{weight_read_address}};
                                schedule_stage <= SCHEDULE_IDLE;
                            end
                        end
                        default: begin
                            schedule_stage <= SCHEDULE_IDLE;
                        end
                    endcase
                end

                if (read_pending_q && data_cbuf_rd_valid) begin
                    data_hold_q <= data_cbuf_rd_data;
                    data_hold_valid_q <= 1'b1;
                end

                if (read_pending_q && weight_cbuf_rd_valid) begin
                    weight_hold_q <= weight_cbuf_rd_data;
                    weight_hold_valid_q <= 1'b1;
                end

                if (packet_accept) begin
                    read_pending_q <= 1'b0;
                    data_hold_valid_q <= 1'b0;
                    weight_hold_valid_q <= 1'b0;
                    pending_padding <= 1'b0;
                    next_tag_q <= next_tag_q + TAG_WIDTH'(1);

                    if (last_packet) begin
                        scheduler_finished <= 1'b1;
                    end else if ((channel_packet_counter + 1) <
                                 channel_packet_count) begin
                        channel_packet_counter <=
                            channel_packet_counter + 1'b1;
                    end else begin
                        channel_packet_counter <= 2'd0;
                        if ((kernel_x_counter + 1) < kernel_width) begin
                            kernel_x_counter <= kernel_x_counter + 1'b1;
                        end else begin
                            kernel_x_counter <= 16'd0;
                            if ((kernel_y_counter + 1) <
                                kernel_height) begin
                                kernel_y_counter <=
                                    kernel_y_counter + 1'b1;
                            end else begin
                                kernel_y_counter <= 16'd0;
                                if ((output_x_counter + 1) <
                                    output_width) begin
                                    output_x_counter <=
                                        output_x_counter + 1'b1;
                                end else begin
                                    output_x_counter <= 16'd0;
                                    if ((output_y_counter + 1) <
                                        output_height) begin
                                        output_y_counter <=
                                            output_y_counter + 1'b1;
                                    end else begin
                                        output_y_counter <= 16'd0;
                                        output_kernel_counter <=
                                            output_kernel_counter + 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    // Ping-pong group status: 1 is busy, 0 is idle.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            csc_status <= 2'b00;
            active_group_q <= 1'b0;
        end else if (p_state == S_IDLE && n_state == S_WAIT_CHUNK) begin
            csc_status[consumer_pointer] <= 1'b1;
            active_group_q <= consumer_pointer;
        end else if (p_state == S_WORK && n_state == S_DONE) begin
            csc_status[active_group_q] <= 1'b0;
        end
    end

    // Hold the clear request until CSB confirms that op-enable is cleared.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            csc_op_enable_clear <= 1'b0;
        end else if (!csc_op_enable_level) begin
            csc_op_enable_clear <= 1'b0;
        end else if ((p_state == S_IDLE) && (n_state == S_WAIT_CHUNK)) begin
            csc_op_enable_clear <= 1'b1;
        end
    end

    MACLane #(
        .DATA_WIDTH (MACLANE_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .FIFO_DEPTH (MACLANE_DEPTH)
    ) u_maclane (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (maclane_in_valid),
        .in_ready   (maclane_in_ready),
        .in_tag     (maclane_in_tag),
        .in_data    (maclane_in_data),
        .in_weight  (maclane_in_weight),
        .out_valid  (maclane_valid),
        .out_ready  (maclane_ready),
        .out_tag    (maclane_tag),
        .out_data   (maclane_data),
        .out_weight (maclane_weight),
        .fifo_level (maclane_level)
    );

endmodule
