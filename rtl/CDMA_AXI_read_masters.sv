`timescale 1ns/1ps

module CDMA_AXI_read_masters #(
    parameter int AXI_ID_WIDTH   = 1,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int BURST_LEN      = 8,
    parameter int PACKET_WIDTH   = AXI_DATA_WIDTH * BURST_LEN
) (
    input  logic clk,
    input  logic rst_n,

    input  logic                        data_axi_req_valid,
    output logic                        data_axi_ready,
    input  logic [AXI_ADDR_WIDTH-1:0]   data_req_addr,
    output logic                        data_axi_err,
    output logic                        data_axi_load_valid,
    input  logic                        data_axi_load_ready,
    output logic [PACKET_WIDTH-1:0]     loaded_data,

    input  logic                        weight_axi_req_valid,
    output logic                        weight_axi_ready,
    input  logic [AXI_ADDR_WIDTH-1:0]   weight_req_addr,
    output logic                        weight_axi_err,
    output logic                        weight_axi_load_valid,
    input  logic                        weight_axi_load_ready,
    output logic [PACKET_WIDTH-1:0]     loaded_weight,

    output logic [AXI_ID_WIDTH-1:0]     m_data_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_data_axi_araddr,
    output logic [7:0]                  m_data_axi_arlen,
    output logic [2:0]                  m_data_axi_arsize,
    output logic [1:0]                  m_data_axi_arburst,
    output logic                        m_data_axi_arlock,
    output logic [3:0]                  m_data_axi_arcache,
    output logic [2:0]                  m_data_axi_arprot,
    output logic [3:0]                  m_data_axi_arqos,
    output logic                        m_data_axi_arvalid,
    input  logic                        m_data_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]     m_data_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]   m_data_axi_rdata,
    input  logic [1:0]                  m_data_axi_rresp,
    input  logic                        m_data_axi_rlast,
    input  logic                        m_data_axi_rvalid,
    output logic                        m_data_axi_rready,

    output logic [AXI_ID_WIDTH-1:0]     m_weight_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_weight_axi_araddr,
    output logic [7:0]                  m_weight_axi_arlen,
    output logic [2:0]                  m_weight_axi_arsize,
    output logic [1:0]                  m_weight_axi_arburst,
    output logic                        m_weight_axi_arlock,
    output logic [3:0]                  m_weight_axi_arcache,
    output logic [2:0]                  m_weight_axi_arprot,
    output logic [3:0]                  m_weight_axi_arqos,
    output logic                        m_weight_axi_arvalid,
    input  logic                        m_weight_axi_arready,
    input  logic [AXI_ID_WIDTH-1:0]     m_weight_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]   m_weight_axi_rdata,
    input  logic [1:0]                  m_weight_axi_rresp,
    input  logic                        m_weight_axi_rlast,
    input  logic                        m_weight_axi_rvalid,
    output logic                        m_weight_axi_rready
);

    logic data_response_valid;
    logic data_response_ready;
    logic data_response_error;
    logic weight_response_valid;
    logic weight_response_ready;
    logic weight_response_error;

    assign data_axi_load_valid = data_response_valid && !data_response_error;
    assign data_axi_err = data_response_valid && data_response_error;
    assign data_response_ready = data_axi_load_ready;

    assign weight_axi_load_valid = weight_response_valid && !weight_response_error;
    assign weight_axi_err = weight_response_valid && weight_response_error;
    assign weight_response_ready = weight_axi_load_ready;

    AXI_read_master #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .BURST_LEN      (BURST_LEN),
        .PACKET_WIDTH   (PACKET_WIDTH)
    ) u_data_axi_master (
        .clk            (clk),
        .rst_n          (rst_n),
        .read_req_valid (data_axi_req_valid),
        .read_req_ready (data_axi_ready),
        .read_req_addr  (data_req_addr),
        .read_rsp_valid (data_response_valid),
        .read_rsp_ready (data_response_ready),
        .read_rsp_data  (loaded_data),
        .read_rsp_error (data_response_error),
        .m_axi_arid     (m_data_axi_arid),
        .m_axi_araddr   (m_data_axi_araddr),
        .m_axi_arlen    (m_data_axi_arlen),
        .m_axi_arsize   (m_data_axi_arsize),
        .m_axi_arburst  (m_data_axi_arburst),
        .m_axi_arlock   (m_data_axi_arlock),
        .m_axi_arcache  (m_data_axi_arcache),
        .m_axi_arprot   (m_data_axi_arprot),
        .m_axi_arqos    (m_data_axi_arqos),
        .m_axi_arvalid  (m_data_axi_arvalid),
        .m_axi_arready  (m_data_axi_arready),
        .m_axi_rid      (m_data_axi_rid),
        .m_axi_rdata    (m_data_axi_rdata),
        .m_axi_rresp    (m_data_axi_rresp),
        .m_axi_rlast    (m_data_axi_rlast),
        .m_axi_rvalid   (m_data_axi_rvalid),
        .m_axi_rready   (m_data_axi_rready)
    );

    AXI_read_master #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .BURST_LEN      (BURST_LEN),
        .PACKET_WIDTH   (PACKET_WIDTH)
    ) u_weight_axi_master (
        .clk            (clk),
        .rst_n          (rst_n),
        .read_req_valid (weight_axi_req_valid),
        .read_req_ready (weight_axi_ready),
        .read_req_addr  (weight_req_addr),
        .read_rsp_valid (weight_response_valid),
        .read_rsp_ready (weight_response_ready),
        .read_rsp_data  (loaded_weight),
        .read_rsp_error (weight_response_error),
        .m_axi_arid     (m_weight_axi_arid),
        .m_axi_araddr   (m_weight_axi_araddr),
        .m_axi_arlen    (m_weight_axi_arlen),
        .m_axi_arsize   (m_weight_axi_arsize),
        .m_axi_arburst  (m_weight_axi_arburst),
        .m_axi_arlock   (m_weight_axi_arlock),
        .m_axi_arcache  (m_weight_axi_arcache),
        .m_axi_arprot   (m_weight_axi_arprot),
        .m_axi_arqos    (m_weight_axi_arqos),
        .m_axi_arvalid  (m_weight_axi_arvalid),
        .m_axi_arready  (m_weight_axi_arready),
        .m_axi_rid      (m_weight_axi_rid),
        .m_axi_rdata    (m_weight_axi_rdata),
        .m_axi_rresp    (m_weight_axi_rresp),
        .m_axi_rlast    (m_weight_axi_rlast),
        .m_axi_rvalid   (m_weight_axi_rvalid),
        .m_axi_rready   (m_weight_axi_rready)
    );

endmodule
