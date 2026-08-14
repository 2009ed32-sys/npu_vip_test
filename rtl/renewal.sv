`timescale 1ns/1ps

module renewal #(
    parameter int AXI_ID_WIDTH   = 1,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int BURST_LEN      = 8,
    parameter int BANK_WIDTH     = 128,
    parameter int BANK_NUM       = 4,
    parameter int BANK_ADDR_WIDTH = 10,
    parameter int MACLANE_WIDTH  = BANK_WIDTH * BANK_NUM,
    parameter int TAG_WIDTH      = 32,
    parameter int MACLANE_DEPTH  = 3
) (
    input  logic PCLK,
    input  logic PRESETn,

    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    output logic                                    maclane_valid,
    input  logic                                    maclane_ready,
    output logic [TAG_WIDTH-1:0]                    maclane_tag,
    output logic [MACLANE_WIDTH-1:0]                maclane_data,
    output logic [MACLANE_WIDTH-1:0]                maclane_weight,
    output logic [$clog2(MACLANE_DEPTH+1)-1:0]      maclane_level,

    output logic        cacc_op_enable_level,
    input  logic        cacc_op_enable_clear,
    input  logic [1:0]  cacc_status,
    output logic [31:0] CACC_D_OP_ENABLE,
    output logic [31:0] CACC_D_DATAOUT_SIZE_0,
    output logic [31:0] CACC_D_DATAOUT_SIZE_1,
    output logic [31:0] CACC_D_DATAOUT_ADDR,
    output logic [31:0] CACC_D_LINE_STRIDE,
    output logic [31:0] CACC_D_SURF_STRIDE,
    output logic [31:0] CACC_D_DATAOUT_MAP,

    output logic [AXI_ID_WIDTH-1:0]     M_DATA_AXI_ARID,
    output logic [AXI_ADDR_WIDTH-1:0]   M_DATA_AXI_ARADDR,
    output logic [7:0]                  M_DATA_AXI_ARLEN,
    output logic [2:0]                  M_DATA_AXI_ARSIZE,
    output logic [1:0]                  M_DATA_AXI_ARBURST,
    output logic                        M_DATA_AXI_ARLOCK,
    output logic [3:0]                  M_DATA_AXI_ARCACHE,
    output logic [2:0]                  M_DATA_AXI_ARPROT,
    output logic [3:0]                  M_DATA_AXI_ARQOS,
    output logic                        M_DATA_AXI_ARVALID,
    input  logic                        M_DATA_AXI_ARREADY,
    input  logic [AXI_ID_WIDTH-1:0]     M_DATA_AXI_RID,
    input  logic [AXI_DATA_WIDTH-1:0]   M_DATA_AXI_RDATA,
    input  logic [1:0]                  M_DATA_AXI_RRESP,
    input  logic                        M_DATA_AXI_RLAST,
    input  logic                        M_DATA_AXI_RVALID,
    output logic                        M_DATA_AXI_RREADY,

    output logic [AXI_ID_WIDTH-1:0]     M_WEIGHT_AXI_ARID,
    output logic [AXI_ADDR_WIDTH-1:0]   M_WEIGHT_AXI_ARADDR,
    output logic [7:0]                  M_WEIGHT_AXI_ARLEN,
    output logic [2:0]                  M_WEIGHT_AXI_ARSIZE,
    output logic [1:0]                  M_WEIGHT_AXI_ARBURST,
    output logic                        M_WEIGHT_AXI_ARLOCK,
    output logic [3:0]                  M_WEIGHT_AXI_ARCACHE,
    output logic [2:0]                  M_WEIGHT_AXI_ARPROT,
    output logic [3:0]                  M_WEIGHT_AXI_ARQOS,
    output logic                        M_WEIGHT_AXI_ARVALID,
    input  logic                        M_WEIGHT_AXI_ARREADY,
    input  logic [AXI_ID_WIDTH-1:0]     M_WEIGHT_AXI_RID,
    input  logic [AXI_DATA_WIDTH-1:0]   M_WEIGHT_AXI_RDATA,
    input  logic [1:0]                  M_WEIGHT_AXI_RRESP,
    input  logic                        M_WEIGHT_AXI_RLAST,
    input  logic                        M_WEIGHT_AXI_RVALID,
    output logic                        M_WEIGHT_AXI_RREADY
);

    localparam int PACKET_WIDTH = AXI_DATA_WIDTH * BURST_LEN;

    logic        consumer_pointer;
    logic [1:0]  cdma_op_enable;
    logic        csc_op_enable_level;
    logic        cdma_op_enable_level;
    logic        cdma_op_data_enable_clear;
    logic        cdma_op_weight_enable_clear;
    logic [1:0]  cdma_data_status;
    logic [1:0]  cdma_weight_status;
    logic        csc_op_enable_clear;
    logic [1:0]  csc_status;

    logic [31:0] data_matrix_width;
    logic [31:0] data_matrix_height;
    logic [31:0] data_channel_count;
    logic [31:0] data_src_base_addr;
    logic [31:0] weight_matrix_width;
    logic [31:0] weight_matrix_height;
    logic [31:0] weight_channel_count;
    logic [31:0] weight_src_base_addr;
    logic [31:0] weight_kernels_per_chunk;
    logic [31:0] csc_input_width_height;
    logic [31:0] csc_input_channels;
    logic [31:0] csc_kernel_width_height;
    logic [31:0] csc_stride_xy;
    logic [31:0] csc_output_width_height;
    logic [31:0] csc_output_channels;
    logic [31:0] csc_padding;

    logic        data_axi_req_valid;
    logic        data_axi_ready;
    logic        data_axi_err;
    logic        data_axi_load_ready;
    logic        data_axi_load_valid;
    logic [31:0] data_req_addr;
    logic [PACKET_WIDTH-1:0] loaded_data;

    logic        weight_axi_req_valid;
    logic        weight_axi_ready;
    logic        weight_axi_err;
    logic        weight_axi_load_ready;
    logic        weight_axi_load_valid;
    logic [31:0] weight_req_addr;
    logic [PACKET_WIDTH-1:0] loaded_weight;

    logic        data_cbuf_wr_start;
    logic        data_cbuf_wr_en;
    logic        data_cbuf_wr_ready;
    logic        data_cbuf_wr_done;
    logic [31:0] data_cbuf_wr_count;
    logic [PACKET_WIDTH-1:0] data_cbuf_wrdata;

    logic        weight_cbuf_wr_start;
    logic        weight_cbuf_wr_en;
    logic        weight_cbuf_wr_ready;
    logic        weight_cbuf_wr_done;
    logic [31:0] weight_cbuf_wr_count;
    logic [PACKET_WIDTH-1:0] weight_cbuf_wrdata;

    logic                                    data_cbuf_rd_en;
    logic [BANK_NUM-1:0]                     data_cbuf_rd_bank_en;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]   data_cbuf_rd_addr;
    logic                                    data_cbuf_rd_valid;
    logic [(BANK_NUM*BANK_WIDTH)-1:0]        data_cbuf_rd_data;

    logic                                    weight_cbuf_rd_en;
    logic [BANK_NUM-1:0]                     weight_cbuf_rd_bank_en;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]   weight_cbuf_rd_addr;
    logic                                    weight_cbuf_rd_valid;
    logic [(BANK_NUM*BANK_WIDTH)-1:0]        weight_cbuf_rd_data;

    logic        data_refill_valid;
    logic        data_refill_ready;
    logic [31:0] data_refill_position_base;
    logic [31:0] data_refill_position_count;
    logic        data_refill_last;
    logic        data_release_valid;
    logic        data_release_ready;
    logic        data_chunk_valid;
    logic [31:0] data_chunk_position_base;
    logic [31:0] data_chunk_position_count;
    logic        data_chunk_last;

    logic        weight_chunk_valid;
    logic [31:0] weight_chunk_word_base;
    logic [31:0] weight_chunk_word_count;
    logic        weight_chunk_last;
    logic        weight_cbuf_refill_req;

    csb u_csb (
        .PCLK(PCLK),
        .rst_n(PRESETn),
        .PSELx(PSEL),
        .PWRITE(PWRITE),
        .PENABLE(PENABLE),
        .PSLVERR(PSLVERR),
        .PREADY(PREADY),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .S_POINTER(),
        .producer_pointer(),
        .consumer_pointer(consumer_pointer),
        .CDMA_D_OP_ENABLE(cdma_op_enable),
        .DATA_MATRIX_WIDTH(data_matrix_width),
        .DATA_MATRIX_HEIGHT(data_matrix_height),
        .DATA_CHANNEL_COUNT(data_channel_count),
        .DATA_DST_BASE(),
        .DATA_SRC_BASE_ADDR(data_src_base_addr),
        .WEIGHT_MATRIX_WIDTH(weight_matrix_width),
        .WEIGHT_MATRIX_HEIGHT(weight_matrix_height),
        .WEIGHT_CHANNEL_COUNT(weight_channel_count),
        .WEIGHT_DST_BASE(),
        .WEIGHT_SRC_BASE_ADDR(weight_src_base_addr),
        .WEIGHT_KERNELS_PER_CHUNK(weight_kernels_per_chunk),
        .CSC_D_OP_ENABLE(),
        .CSC_STATUS(),
        .CSC_ATOMICS(),
        .CSC_INPUT_WIDTH_HEIGHT(csc_input_width_height),
        .CSC_INPUT_CHANNELS(csc_input_channels),
        .CSC_KERNEL_WIDTH_HEIGHT(csc_kernel_width_height),
        .CSC_STRIDE_XY(csc_stride_xy),
        .CSC_OUTPUT_WIDTH_HEIGHT(csc_output_width_height),
        .CSC_OUTPUT_CHANNELS(csc_output_channels),
        .CSC_PADDING(csc_padding),
        .CACC_S_STATUS(),
        .CACC_D_OP_ENABLE(CACC_D_OP_ENABLE),
        .CACC_D_DATAOUT_SIZE_0(CACC_D_DATAOUT_SIZE_0),
        .CACC_D_DATAOUT_SIZE_1(CACC_D_DATAOUT_SIZE_1),
        .CACC_D_DATAOUT_ADDR(CACC_D_DATAOUT_ADDR),
        .CACC_D_LINE_STRIDE(CACC_D_LINE_STRIDE),
        .CACC_D_SURF_STRIDE(CACC_D_SURF_STRIDE),
        .CACC_D_DATAOUT_MAP(CACC_D_DATAOUT_MAP),
        .cdma_op_enable_level(cdma_op_enable_level),
        .csc_op_enable_level(csc_op_enable_level),
        .cacc_op_enable_level(cacc_op_enable_level),
        .cdma_op_data_enable_clear(cdma_op_data_enable_clear),
        .cdma_data_status(cdma_data_status),
        .cdma_op_weight_enable_clear(cdma_op_weight_enable_clear),
        .cdma_weight_status(cdma_weight_status),
        .csc_op_enable_clear(csc_op_enable_clear),
        .csc_status(csc_status),
        .cacc_op_enable_clear(cacc_op_enable_clear),
        .cacc_status(cacc_status)
    );

    CDMA_data_load #(
        .DATA_BURST_BEAT(BURST_LEN),
        .DATA_TOTAL_WIDTH(PACKET_WIDTH),
        .CBUF_BANK_NUM(BANK_NUM),
        .CBUF_ADDR_DEPTH(1 << BANK_ADDR_WIDTH)
    ) u_cdma_data (
        .clk(PCLK),
        .rst_n(PRESETn),
        .axi_ready(data_axi_ready),
        .axi_req_valid(data_axi_req_valid),
        .axi_data_err(data_axi_err),
        .axi_data_load_ready(data_axi_load_ready),
        .axi_data_load_valid(data_axi_load_valid),
        .data_req_addr(data_req_addr),
        .loaded_data(loaded_data),
        .DATA_MATRIX_WIDTH(data_matrix_width),
        .DATA_MATRIX_HEIGHT(data_matrix_height),
        .DATA_CHANNEL_COUNT(data_channel_count),
        .DATA_SRC_BASE_ADDR(data_src_base_addr),
        .consumer_pointer(consumer_pointer),
        .cdma_start_pulse(cdma_op_enable[0]),
        .cdma_op_enable_clear(cdma_op_data_enable_clear),
        .cdma_data_status(cdma_data_status),
        .cbuf_wr_done(data_cbuf_wr_done),
        .cbuf_wr_start(data_cbuf_wr_start),
        .cbuf_wr_en(data_cbuf_wr_en),
        .cbuf_ready(data_cbuf_wr_ready),
        .cbuf_wr_count(data_cbuf_wr_count),
        .data_refill_valid(data_refill_valid),
        .data_refill_ready(data_refill_ready),
        .data_refill_position_base(data_refill_position_base),
        .data_refill_position_count(data_refill_position_count),
        .data_refill_last(data_refill_last),
        .data_release_valid(data_release_valid),
        .data_release_ready(data_release_ready),
        .data_chunk_valid(data_chunk_valid),
        .data_chunk_position_base(data_chunk_position_base),
        .data_chunk_position_count(data_chunk_position_count),
        .data_chunk_last(data_chunk_last),
        .cbuf_wrdata(data_cbuf_wrdata)
    );

    CDMA_weight_load #(
        .WEIGHT_BURST_BEAT(BURST_LEN),
        .WEIGHT_TOTAL_WIDTH(PACKET_WIDTH),
        .CBUF_BANK_NUM(BANK_NUM),
        .CBUF_ADDR_DEPTH(1 << BANK_ADDR_WIDTH)
    ) u_cdma_weight (
        .clk(PCLK),
        .rst_n(PRESETn),
        .axi_ready(weight_axi_ready),
        .axi_req_valid(weight_axi_req_valid),
        .axi_data_err(weight_axi_err),
        .axi_weight_load_ready(weight_axi_load_ready),
        .axi_weight_load_valid(weight_axi_load_valid),
        .weight_req_addr(weight_req_addr),
        .loaded_weight(loaded_weight),
        .WEIGHT_MATRIX_WIDTH(weight_matrix_width),
        .WEIGHT_MATRIX_HEIGHT(weight_matrix_height),
        .WEIGHT_CHANNEL_COUNT(weight_channel_count),
        .WEIGHT_OUTPUT_CHANNELS(csc_output_channels),
        .WEIGHT_SRC_BASE_ADDR(weight_src_base_addr),
        .WEIGHT_KERNELS_PER_CHUNK(weight_kernels_per_chunk),
        .consumer_pointer(consumer_pointer),
        .cdma_start_pulse(cdma_op_enable[1]),
        .cdma_op_weight_enable_clear(cdma_op_weight_enable_clear),
        .cdma_weight_status(cdma_weight_status),
        .weight_cbuf_wr_done(weight_cbuf_wr_done),
        .weight_cbuf_wr_start(weight_cbuf_wr_start),
        .weight_cbuf_wr_en(weight_cbuf_wr_en),
        .weight_cbuf_ready(weight_cbuf_wr_ready),
        .weight_cbuf_wr_count(weight_cbuf_wr_count),
        .csc_weight_cbuf_refill_req(weight_cbuf_refill_req),
        .weight_chunk_valid(weight_chunk_valid),
        .weight_chunk_word_base(weight_chunk_word_base),
        .weight_chunk_word_count(weight_chunk_word_count),
        .weight_chunk_last(weight_chunk_last),
        .weight_cbuf_wrdata(weight_cbuf_wrdata)
    );

    CBUF_data #(
        .BANK_WIDTH(BANK_WIDTH),
        .BANK_NUM(BANK_NUM),
        .WRITE_WIDTH(PACKET_WIDTH),
        .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)
    ) u_cbuf_data (
        .clk(PCLK),
        .rst_n(PRESETn),
        .wr_start(data_cbuf_wr_start),
        .wr_channel_count(data_channel_count[7:0]),
        .wr_valid(data_cbuf_wr_en),
        .wr_ready(data_cbuf_wr_ready),
        .wr_data(data_cbuf_wrdata),
        .wr_count(data_cbuf_wr_count),
        .cbuf_wr_done(data_cbuf_wr_done),
        .rd_en(data_cbuf_rd_en),
        .rd_bank_en(data_cbuf_rd_bank_en),
        .rd_addr(data_cbuf_rd_addr),
        .rd_valid(data_cbuf_rd_valid),
        .rd_data(data_cbuf_rd_data)
    );

    CBUF_weight #(
        .BANK_WIDTH(BANK_WIDTH),
        .BANK_NUM(BANK_NUM),
        .WRITE_WIDTH(PACKET_WIDTH),
        .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)
    ) u_cbuf_weight (
        .clk(PCLK),
        .rst_n(PRESETn),
        .wr_start(weight_cbuf_wr_start),
        .wr_channel_count(weight_channel_count[7:0]),
        .wr_valid(weight_cbuf_wr_en),
        .wr_ready(weight_cbuf_wr_ready),
        .wr_data(weight_cbuf_wrdata),
        .wr_count(weight_cbuf_wr_count),
        .cbuf_wr_done(weight_cbuf_wr_done),
        .rd_en(weight_cbuf_rd_en),
        .rd_bank_en(weight_cbuf_rd_bank_en),
        .rd_addr(weight_cbuf_rd_addr),
        .rd_valid(weight_cbuf_rd_valid),
        .rd_data(weight_cbuf_rd_data)
    );

    CSC #(
        .BANK_WIDTH(BANK_WIDTH),
        .BANK_NUM(BANK_NUM),
        .MACLANE_WIDTH(MACLANE_WIDTH),
        .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .MACLANE_DEPTH(MACLANE_DEPTH)
    ) u_csc (
        .clk(PCLK),
        .rst_n(PRESETn),
        .consumer_pointer(consumer_pointer),
        .csc_op_enable_level(csc_op_enable_level),
        .CSC_INPUT_WIDTH_HEIGHT(csc_input_width_height),
        .CSC_INPUT_CHANNELS(csc_input_channels),
        .CSC_KERNEL_WIDTH_HEIGHT(csc_kernel_width_height),
        .CSC_STRIDE_XY(csc_stride_xy),
        .CSC_OUTPUT_WIDTH_HEIGHT(csc_output_width_height),
        .CSC_OUTPUT_CHANNELS(csc_output_channels),
        .CSC_PADDING(csc_padding),
        .csc_op_enable_clear(csc_op_enable_clear),
        .csc_status(csc_status),
        .data_chunk_valid(data_chunk_valid),
        .data_chunk_position_base(data_chunk_position_base),
        .data_chunk_position_count(data_chunk_position_count),
        .data_chunk_last(data_chunk_last),
        .data_refill_valid(data_refill_valid),
        .data_refill_ready(data_refill_ready),
        .data_refill_position_base(data_refill_position_base),
        .data_refill_position_count(data_refill_position_count),
        .data_refill_last(data_refill_last),
        .data_release_valid(data_release_valid),
        .data_release_ready(data_release_ready),
        .weight_chunk_valid(weight_chunk_valid),
        .weight_chunk_word_base(weight_chunk_word_base),
        .weight_chunk_word_count(weight_chunk_word_count),
        .weight_chunk_last(weight_chunk_last),
        .csc_weight_cbuf_refill_req(weight_cbuf_refill_req),
        .data_cbuf_rd_en(data_cbuf_rd_en),
        .data_cbuf_rd_bank_en(data_cbuf_rd_bank_en),
        .data_cbuf_rd_addr(data_cbuf_rd_addr),
        .data_cbuf_rd_valid(data_cbuf_rd_valid),
        .data_cbuf_rd_data(data_cbuf_rd_data),
        .weight_cbuf_rd_en(weight_cbuf_rd_en),
        .weight_cbuf_rd_bank_en(weight_cbuf_rd_bank_en),
        .weight_cbuf_rd_addr(weight_cbuf_rd_addr),
        .weight_cbuf_rd_valid(weight_cbuf_rd_valid),
        .weight_cbuf_rd_data(weight_cbuf_rd_data),
        .maclane_valid(maclane_valid),
        .maclane_ready(maclane_ready),
        .maclane_tag(maclane_tag),
        .maclane_data(maclane_data),
        .maclane_weight(maclane_weight),
        .maclane_level(maclane_level)
    );

    CDMA_AXI_read_masters #(
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .BURST_LEN(BURST_LEN),
        .PACKET_WIDTH(PACKET_WIDTH)
    ) u_axi_read_masters (
        .clk(PCLK),
        .rst_n(PRESETn),
        .data_axi_req_valid(data_axi_req_valid),
        .data_axi_ready(data_axi_ready),
        .data_req_addr(data_req_addr),
        .data_axi_err(data_axi_err),
        .data_axi_load_valid(data_axi_load_valid),
        .data_axi_load_ready(data_axi_load_ready),
        .loaded_data(loaded_data),
        .weight_axi_req_valid(weight_axi_req_valid),
        .weight_axi_ready(weight_axi_ready),
        .weight_req_addr(weight_req_addr),
        .weight_axi_err(weight_axi_err),
        .weight_axi_load_valid(weight_axi_load_valid),
        .weight_axi_load_ready(weight_axi_load_ready),
        .loaded_weight(loaded_weight),
        .m_data_axi_arid(M_DATA_AXI_ARID),
        .m_data_axi_araddr(M_DATA_AXI_ARADDR),
        .m_data_axi_arlen(M_DATA_AXI_ARLEN),
        .m_data_axi_arsize(M_DATA_AXI_ARSIZE),
        .m_data_axi_arburst(M_DATA_AXI_ARBURST),
        .m_data_axi_arlock(M_DATA_AXI_ARLOCK),
        .m_data_axi_arcache(M_DATA_AXI_ARCACHE),
        .m_data_axi_arprot(M_DATA_AXI_ARPROT),
        .m_data_axi_arqos(M_DATA_AXI_ARQOS),
        .m_data_axi_arvalid(M_DATA_AXI_ARVALID),
        .m_data_axi_arready(M_DATA_AXI_ARREADY),
        .m_data_axi_rid(M_DATA_AXI_RID),
        .m_data_axi_rdata(M_DATA_AXI_RDATA),
        .m_data_axi_rresp(M_DATA_AXI_RRESP),
        .m_data_axi_rlast(M_DATA_AXI_RLAST),
        .m_data_axi_rvalid(M_DATA_AXI_RVALID),
        .m_data_axi_rready(M_DATA_AXI_RREADY),
        .m_weight_axi_arid(M_WEIGHT_AXI_ARID),
        .m_weight_axi_araddr(M_WEIGHT_AXI_ARADDR),
        .m_weight_axi_arlen(M_WEIGHT_AXI_ARLEN),
        .m_weight_axi_arsize(M_WEIGHT_AXI_ARSIZE),
        .m_weight_axi_arburst(M_WEIGHT_AXI_ARBURST),
        .m_weight_axi_arlock(M_WEIGHT_AXI_ARLOCK),
        .m_weight_axi_arcache(M_WEIGHT_AXI_ARCACHE),
        .m_weight_axi_arprot(M_WEIGHT_AXI_ARPROT),
        .m_weight_axi_arqos(M_WEIGHT_AXI_ARQOS),
        .m_weight_axi_arvalid(M_WEIGHT_AXI_ARVALID),
        .m_weight_axi_arready(M_WEIGHT_AXI_ARREADY),
        .m_weight_axi_rid(M_WEIGHT_AXI_RID),
        .m_weight_axi_rdata(M_WEIGHT_AXI_RDATA),
        .m_weight_axi_rresp(M_WEIGHT_AXI_RRESP),
        .m_weight_axi_rlast(M_WEIGHT_AXI_RLAST),
        .m_weight_axi_rvalid(M_WEIGHT_AXI_RVALID),
        .m_weight_axi_rready(M_WEIGHT_AXI_RREADY)
    );

endmodule
