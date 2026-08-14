`timescale 1ns/1ps
// TODO: Replace wr_count-based/temporary write-done logic with wr_last.
// CDMA should track AXI response count separately from request count.
module CBUF_weight #(
    parameter int BANK_WIDTH      = 128,
    parameter int BANK_NUM        = 4,
    parameter int WRITE_WIDTH     = 256,
    parameter int BANK_ADDR_WIDTH = 10,
    parameter int BANK_DEPTH      = (1 << BANK_ADDR_WIDTH)
) (
    input  logic clk,
    input  logic rst_n,

    input  logic                                   wr_start,
    input  logic [7:0]                             wr_channel_count,
    input  logic                                   wr_valid,
    output logic                                   wr_ready,
    input  logic [WRITE_WIDTH-1:0]                 wr_data,
    input  logic [31:0]                            wr_count,
    output logic                                   cbuf_wr_done,

    input  logic                                   rd_en,
    input  logic [BANK_NUM-1:0]                    rd_bank_en,
    input  logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]  rd_addr,
    output logic                                   rd_valid,
    output logic [(BANK_NUM*BANK_WIDTH)-1:0]       rd_data
);
    logic [BANK_ADDR_WIDTH-1:0] wr_row_addr_q;
    logic                       wr_fire;
    logic                       wr_fifo_push;
    logic                       wr_fifo_pop;
    logic                       wr_fifo_wr_ptr;
    logic                       wr_fifo_rd_ptr;
    logic [1:0]                 wr_fifo_count;
    logic [BANK_ADDR_WIDTH-1:0] wr_push_addr_w;
    logic [$clog2(BANK_NUM)-1:0]   wr_bank_pair;
    logic [$clog2(BANK_NUM)-1:0]   selected_bank_pair;
    logic [$clog2(BANK_NUM+1)-1:0] selected_bank_count;
    logic [7:0]                    channel_count;
    logic [7:0]                    selected_channel_count;
    logic [BANK_NUM-1:0]           wr_push_bank_enable;
    logic [WRITE_WIDTH-1:0]        wr_push_data;

    //write counter
    logic        wr_active;
    logic [31:0] wr_remain;

    logic [BANK_ADDR_WIDTH-1:0]       wr_fifo_addr [0:1];
    logic [BANK_NUM-1:0]              wr_fifo_bank_enable [0:1];
    logic [WRITE_WIDTH-1:0]           wr_fifo_data [0:1];

    assign cbuf_wr_done = wr_fifo_pop && wr_active && (wr_remain == 1);
    assign wr_ready = (wr_fifo_count < 2) || wr_fifo_pop;
    assign wr_fire  = wr_valid && wr_ready;
    assign wr_fifo_push = wr_fire;
    assign wr_fifo_pop  = (wr_fifo_count != 0);
    assign wr_push_addr_w = wr_start ? 0 : wr_row_addr_q;

    // Added bank selection: one 256-bit write fills up to two 128-bit banks.
    always_comb begin
        selected_bank_pair = wr_start ? 0 : wr_bank_pair;
        selected_channel_count = wr_start ? wr_channel_count : channel_count;
        if (selected_channel_count == 0) begin
            selected_bank_count = 0;
        end else if (selected_channel_count >= (BANK_NUM * 16)) begin
            selected_bank_count = BANK_NUM;
        end else begin
            selected_bank_count = (selected_channel_count + 15) >> 4;
        end
        wr_push_bank_enable = 0;
        wr_push_data = 0;
        for (int bank = 0; bank < BANK_NUM; bank++) begin
            if ((bank >= (selected_bank_pair * 2)) &&
                (bank < ((selected_bank_pair * 2) + 2)) &&
                (bank < selected_bank_count)) begin
                wr_push_bank_enable[bank] = 1'b1;
            end
        end
        for (int lane = 0; lane < 32; lane++) begin
            if (((selected_bank_pair * 32) + lane) < selected_channel_count) begin
                wr_push_data[(lane*8)+:8] = wr_data[(lane*8)+:8];
            end
        end
    end

    // Address/control path.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_valid <= 0;
            wr_row_addr_q <= 0;
            wr_fifo_wr_ptr <= 0;
            wr_fifo_rd_ptr <= 0;
            wr_fifo_count  <= 0;
            wr_active      <= 0;
            wr_remain      <= 0;
            wr_bank_pair <= 0;
            channel_count <= 0;
        end else begin
            rd_valid <= rd_en;

            if (wr_start) begin
                wr_active <= (wr_count != 0);
                wr_remain <= wr_count;
                channel_count <= wr_channel_count;
                wr_row_addr_q <= 0;
                wr_bank_pair <= 0;
            end else if (wr_fifo_pop && wr_active) begin
                if (wr_remain > 1) begin
                    wr_remain <= wr_remain - 32'd1;
                end else begin
                    wr_remain <= 32'd0;
                    wr_active <= 1'b0;
                end
            end

            // Added row progression: advance after all active bank pairs are written.
            if (wr_fire) begin
                if ((((selected_bank_pair + 1) * 2) >= selected_bank_count) ||
                    (selected_bank_count == 0)) begin
                    wr_row_addr_q <= (wr_start ? 0 : wr_row_addr_q) + BANK_ADDR_WIDTH'(1);
                    wr_bank_pair <= 0;
                end else begin
                    wr_bank_pair <= selected_bank_pair + 1'b1;
                end
            end

            if (wr_fifo_push) begin
                wr_fifo_addr[wr_fifo_wr_ptr] <= wr_push_addr_w;
                wr_fifo_bank_enable[wr_fifo_wr_ptr] <= wr_push_bank_enable;
                wr_fifo_data[wr_fifo_wr_ptr] <= wr_push_data;
                wr_fifo_wr_ptr <= wr_fifo_wr_ptr + 1;
            end

            if (wr_fifo_pop) begin
                wr_fifo_rd_ptr <= wr_fifo_rd_ptr + 1;
            end

            unique case ({wr_fifo_push, wr_fifo_pop})
                2'b10: wr_fifo_count <= wr_fifo_count + 1;
                2'b01: wr_fifo_count <= wr_fifo_count - 1;
                default: wr_fifo_count <= wr_fifo_count;
            endcase
        end
    end

    // Added physical banks: each bank has an independent address and read enable.
    generate
        for (genvar bank = 0; bank < BANK_NUM; bank++) begin : g_weight_bank
            (* ram_style = "block" *)
            logic [BANK_WIDTH-1:0] mem [0:BANK_DEPTH-1];

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    rd_data[(bank*BANK_WIDTH)+:BANK_WIDTH] <= 0;
                end else begin
                    if (wr_fifo_pop && wr_fifo_bank_enable[wr_fifo_rd_ptr][bank]) begin
                        mem[wr_fifo_addr[wr_fifo_rd_ptr]] <=
                            wr_fifo_data[wr_fifo_rd_ptr][((bank % 2)*BANK_WIDTH)+:BANK_WIDTH];
                    end

                    if (rd_en) begin
                        if (rd_bank_en[bank]) begin
                            rd_data[(bank*BANK_WIDTH)+:BANK_WIDTH] <=
                                mem[rd_addr[(bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH]];
                        end else begin
                            rd_data[(bank*BANK_WIDTH)+:BANK_WIDTH] <= 0;
                        end
                    end
                end
            end
        end
    endgenerate

endmodule
