`timescale 1ns/1ps

module AXI_read_master #(
    parameter int AXI_ID_WIDTH   = 1,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int BURST_LEN      = 8,
    parameter int PACKET_WIDTH   = AXI_DATA_WIDTH * BURST_LEN
) (
    input  logic                        clk,
    input  logic                        rst_n,

    input  logic                        read_req_valid,
    output logic                        read_req_ready,
    input  logic [AXI_ADDR_WIDTH-1:0]   read_req_addr,

    output logic                        read_rsp_valid,
    input  logic                        read_rsp_ready,
    output logic [PACKET_WIDTH-1:0]     read_rsp_data,
    output logic                        read_rsp_error,

    output logic [AXI_ID_WIDTH-1:0]     m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,
    output logic                        m_axi_arlock,
    output logic [3:0]                  m_axi_arcache,
    output logic [2:0]                  m_axi_arprot,
    output logic [3:0]                  m_axi_arqos,
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]     m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]                  m_axi_rresp,
    input  logic                        m_axi_rlast,
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready
);

    localparam int BEAT_COUNT_WIDTH = (BURST_LEN <= 1) ? 1 : $clog2(BURST_LEN);

    typedef enum logic [1:0] {
        S_IDLE,
        S_SEND_AR,
        S_READ,
        S_RESP
    } state_t;

    state_t state;

    logic [AXI_ADDR_WIDTH-1:0] request_address;
    logic [BEAT_COUNT_WIDTH-1:0] beat_count;
    logic burst_error;
    logic request_fire;
    logic address_fire;
    logic read_fire;
    logic response_fire;
    logic current_beat_error;

    assign read_req_ready = (state == S_IDLE);
    assign request_fire = read_req_valid && read_req_ready;
    assign address_fire = m_axi_arvalid && m_axi_arready;
    assign read_fire = m_axi_rvalid && m_axi_rready;
    assign response_fire = read_rsp_valid && read_rsp_ready;
    assign current_beat_error = (m_axi_rresp != 2'b00) || (m_axi_rid != 0);

    assign m_axi_arid = 0;
    assign m_axi_araddr = request_address;
    assign m_axi_arlen = BURST_LEN - 1;
    assign m_axi_arsize = $clog2(AXI_DATA_WIDTH / 8);
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'b0010;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arqos = 4'b0000;
    assign m_axi_rready = (state == S_READ);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            request_address <= 0;
            beat_count <= 0;
            burst_error <= 0;
            read_rsp_valid <= 0;
            read_rsp_data <= 0;
            read_rsp_error <= 0;
            m_axi_arvalid <= 0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    beat_count <= 0;
                    burst_error <= 0;
                    read_rsp_valid <= 0;
                    read_rsp_error <= 0;
                    m_axi_arvalid <= 0;
                    if (request_fire) begin
                        request_address <= read_req_addr;
                        m_axi_arvalid <= 1'b1;
                        state <= S_SEND_AR;
                    end
                end

                S_SEND_AR: begin
                    if (address_fire) begin
                        m_axi_arvalid <= 1'b0;
                        state <= S_READ;
                    end
                end

                S_READ: begin
                    if (read_fire) begin
                        read_rsp_data[(beat_count*AXI_DATA_WIDTH)+:AXI_DATA_WIDTH] <= m_axi_rdata;
                        if (current_beat_error) begin
                            burst_error <= 1'b1;
                        end

                        if (m_axi_rlast || (beat_count == BURST_LEN-1)) begin
                            read_rsp_valid <= 1'b1;
                            read_rsp_error <= burst_error ||
                                              current_beat_error ||
                                              (beat_count != BURST_LEN-1) ||
                                              !m_axi_rlast;
                            state <= S_RESP;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                S_RESP: begin
                    if (response_fire) begin
                        read_rsp_valid <= 1'b0;
                        read_rsp_error <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    m_axi_arvalid <= 1'b0;
                    read_rsp_valid <= 1'b0;
                    read_rsp_error <= 1'b0;
                end
            endcase
        end
    end

endmodule
