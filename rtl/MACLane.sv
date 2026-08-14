`timescale 1ns/1ps

module MACLane #(
    parameter int DATA_WIDTH = 512,                                                           
    parameter int TAG_WIDTH  = 32,
    parameter int FIFO_DEPTH = 3,
    parameter int PTR_WIDTH  = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH),
    parameter int CNT_WIDTH  = $clog2(FIFO_DEPTH + 1)
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  in_valid,
    output logic                  in_ready,
    input  logic [TAG_WIDTH-1:0]  in_tag,
    input  logic [DATA_WIDTH-1:0] in_data,
    input  logic [DATA_WIDTH-1:0] in_weight,

    output logic                  out_valid,
    input  logic                  out_ready,
    output logic [TAG_WIDTH-1:0]  out_tag,
    output logic [DATA_WIDTH-1:0] out_data,
    output logic [DATA_WIDTH-1:0] out_weight,

    output logic [CNT_WIDTH-1:0]  fifo_level
);

    logic [TAG_WIDTH-1:0]  tag_mem    [0:FIFO_DEPTH-1];
    logic [DATA_WIDTH-1:0] data_mem   [0:FIFO_DEPTH-1];
    logic [DATA_WIDTH-1:0] weight_mem [0:FIFO_DEPTH-1];

    logic [PTR_WIDTH-1:0] wr_ptr_q;
    logic [PTR_WIDTH-1:0] rd_ptr_q;
    logic [CNT_WIDTH-1:0] count_q;
    logic                 push;
    logic                 pop;

    assign out_valid  = (count_q != 0);
    assign in_ready   = (count_q < FIFO_DEPTH) || (out_valid && out_ready);
    assign push       = in_valid && in_ready;
    assign pop        = out_valid && out_ready;
    assign out_tag    = out_valid ? tag_mem[rd_ptr_q] : '0;
    assign out_data   = out_valid ? data_mem[rd_ptr_q] : '0;
    assign out_weight = out_valid ? weight_mem[rd_ptr_q] : '0;
    assign fifo_level = count_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr_q <= '0;
            rd_ptr_q <= '0;
            count_q  <= '0;
        end else begin
            if (push) begin
                tag_mem[wr_ptr_q]    <= in_tag;
                data_mem[wr_ptr_q]   <= in_data;
                weight_mem[wr_ptr_q] <= in_weight;

                if (wr_ptr_q == PTR_WIDTH'(FIFO_DEPTH - 1)) begin
                    wr_ptr_q <= '0;
                end else begin
                    wr_ptr_q <= wr_ptr_q + PTR_WIDTH'(1);
                end
            end

            if (pop) begin
                if (rd_ptr_q == PTR_WIDTH'(FIFO_DEPTH - 1)) begin
                    rd_ptr_q <= '0;
                end else begin
                    rd_ptr_q <= rd_ptr_q + PTR_WIDTH'(1);
                end
            end

            unique case ({push, pop})
                2'b10: count_q <= count_q + CNT_WIDTH'(1);
                2'b01: count_q <= count_q - CNT_WIDTH'(1);
                default: count_q <= count_q;
            endcase
        end
    end

endmodule
