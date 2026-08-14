`timescale 1ns/1ps

module renewal_vip_wrapper #(
    parameter int MACLANE_WIDTH = 512,
    parameter int TAG_WIDTH = 32,
    parameter int MACLANE_DEPTH = 3
) (
    input  logic clk,
    input  logic resetn,

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
    output logic [31:0] CACC_D_DATAOUT_MAP
);

    logic [31:0] control_awaddr;
    logic [2:0]  control_awprot;
    logic        control_awvalid;
    logic        control_awready;
    logic [31:0] control_wdata;
    logic        control_wvalid;
    logic        control_wready;
    logic [1:0]  control_bresp;
    logic        control_bvalid;
    logic        control_bready;
    logic [31:0] control_araddr;
    logic [2:0]  control_arprot;
    logic        control_arvalid;
    logic        control_arready;
    logic [31:0] control_rdata;
    logic [1:0]  control_rresp;
    logic        control_rvalid;
    logic        control_rready;

    logic [31:0] apb_paddr;
    logic [0:0]  apb_psel;
    logic        apb_penable;
    logic        apb_pwrite;
    logic [31:0] apb_pwdata;
    logic [0:0]  apb_pready;
    logic [31:0] apb_prdata;
    logic [0:0]  apb_pslverr;

    logic [0:0]  data_arid;
    logic [31:0] data_araddr;
    logic [7:0]  data_arlen;
    logic [2:0]  data_arsize;
    logic [1:0]  data_arburst;
    logic        data_arlock;
    logic [3:0]  data_arcache;
    logic [2:0]  data_arprot;
    logic [3:0]  data_arqos;
    logic        data_arvalid;
    logic        data_arready;
    logic [0:0]  data_rid;
    logic [31:0] data_rdata;
    logic [1:0]  data_rresp;
    logic        data_rlast;
    logic        data_rvalid;
    logic        data_rready;

    logic [0:0]  weight_arid;
    logic [31:0] weight_araddr;
    logic [7:0]  weight_arlen;
    logic [2:0]  weight_arsize;
    logic [1:0]  weight_arburst;
    logic        weight_arlock;
    logic [3:0]  weight_arcache;
    logic [2:0]  weight_arprot;
    logic [3:0]  weight_arqos;
    logic        weight_arvalid;
    logic        weight_arready;
    logic [0:0]  weight_rid;
    logic [31:0] weight_rdata;
    logic [1:0]  weight_rresp;
    logic        weight_rlast;
    logic        weight_rvalid;
    logic        weight_rready;

    logic [4:0]  memory_arid;
    logic [31:0] memory_araddr;
    logic [7:0]  memory_arlen;
    logic [2:0]  memory_arsize;
    logic [1:0]  memory_arburst;
    logic [3:0]  memory_arcache;
    logic [2:0]  memory_arprot;
    logic [3:0]  memory_arqos;
    logic        memory_arvalid;
    logic        memory_arready;
    logic [4:0]  memory_rid;
    logic [31:0] memory_rdata;
    logic [1:0]  memory_rresp;
    logic        memory_rlast;
    logic        memory_rvalid;
    logic        memory_rready;

    axi_vip_0 u_control_vip (
        .aclk(clk),
        .aresetn(resetn),
        .m_axi_awaddr(control_awaddr),
        .m_axi_awprot(control_awprot),
        .m_axi_awvalid(control_awvalid),
        .m_axi_awready(control_awready),
        .m_axi_wdata(control_wdata),
        .m_axi_wstrb(),
        .m_axi_wvalid(control_wvalid),
        .m_axi_wready(control_wready),
        .m_axi_bresp(control_bresp),
        .m_axi_bvalid(control_bvalid),
        .m_axi_bready(control_bready),
        .m_axi_araddr(control_araddr),
        .m_axi_arprot(control_arprot),
        .m_axi_arvalid(control_arvalid),
        .m_axi_arready(control_arready),
        .m_axi_rdata(control_rdata),
        .m_axi_rresp(control_rresp),
        .m_axi_rvalid(control_rvalid),
        .m_axi_rready(control_rready)
    );

    axi_apb_bridge_0 u_axi_apb_bridge (
        .s_axi_aclk(clk),
        .s_axi_aresetn(resetn),
        .s_axi_awaddr(control_awaddr),
        .s_axi_awvalid(control_awvalid),
        .s_axi_awready(control_awready),
        .s_axi_wdata(control_wdata),
        .s_axi_wvalid(control_wvalid),
        .s_axi_wready(control_wready),
        .s_axi_bresp(control_bresp),
        .s_axi_bvalid(control_bvalid),
        .s_axi_bready(control_bready),
        .s_axi_araddr(control_araddr),
        .s_axi_arvalid(control_arvalid),
        .s_axi_arready(control_arready),
        .s_axi_rdata(control_rdata),
        .s_axi_rresp(control_rresp),
        .s_axi_rvalid(control_rvalid),
        .s_axi_rready(control_rready),
        .m_apb_paddr(apb_paddr),
        .m_apb_psel(apb_psel),
        .m_apb_penable(apb_penable),
        .m_apb_pwrite(apb_pwrite),
        .m_apb_pwdata(apb_pwdata),
        .m_apb_pready(apb_pready),
        .m_apb_prdata(apb_prdata),
        .m_apb_pslverr(apb_pslverr)
    );

    renewal #(
        .AXI_ID_WIDTH(1),
        .AXI_ADDR_WIDTH(32),
        .AXI_DATA_WIDTH(32),
        .MACLANE_WIDTH(MACLANE_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .MACLANE_DEPTH(MACLANE_DEPTH)
    ) u_renewal (
        .PCLK(clk),
        .PRESETn(resetn),
        .PSEL(apb_psel[0]),
        .PENABLE(apb_penable),
        .PWRITE(apb_pwrite),
        .PADDR(apb_paddr),
        .PWDATA(apb_pwdata),
        .PRDATA(apb_prdata),
        .PREADY(apb_pready[0]),
        .PSLVERR(apb_pslverr[0]),
        .maclane_valid(maclane_valid),
        .maclane_ready(maclane_ready),
        .maclane_tag(maclane_tag),
        .maclane_data(maclane_data),
        .maclane_weight(maclane_weight),
        .maclane_level(maclane_level),
        .cacc_op_enable_level(cacc_op_enable_level),
        .cacc_op_enable_clear(cacc_op_enable_clear),
        .cacc_status(cacc_status),
        .CACC_D_OP_ENABLE(CACC_D_OP_ENABLE),
        .CACC_D_DATAOUT_SIZE_0(CACC_D_DATAOUT_SIZE_0),
        .CACC_D_DATAOUT_SIZE_1(CACC_D_DATAOUT_SIZE_1),
        .CACC_D_DATAOUT_ADDR(CACC_D_DATAOUT_ADDR),
        .CACC_D_LINE_STRIDE(CACC_D_LINE_STRIDE),
        .CACC_D_SURF_STRIDE(CACC_D_SURF_STRIDE),
        .CACC_D_DATAOUT_MAP(CACC_D_DATAOUT_MAP),
        .M_DATA_AXI_ARID(data_arid),
        .M_DATA_AXI_ARADDR(data_araddr),
        .M_DATA_AXI_ARLEN(data_arlen),
        .M_DATA_AXI_ARSIZE(data_arsize),
        .M_DATA_AXI_ARBURST(data_arburst),
        .M_DATA_AXI_ARLOCK(data_arlock),
        .M_DATA_AXI_ARCACHE(data_arcache),
        .M_DATA_AXI_ARPROT(data_arprot),
        .M_DATA_AXI_ARQOS(data_arqos),
        .M_DATA_AXI_ARVALID(data_arvalid),
        .M_DATA_AXI_ARREADY(data_arready),
        .M_DATA_AXI_RID(data_rid),
        .M_DATA_AXI_RDATA(data_rdata),
        .M_DATA_AXI_RRESP(data_rresp),
        .M_DATA_AXI_RLAST(data_rlast),
        .M_DATA_AXI_RVALID(data_rvalid),
        .M_DATA_AXI_RREADY(data_rready),
        .M_WEIGHT_AXI_ARID(weight_arid),
        .M_WEIGHT_AXI_ARADDR(weight_araddr),
        .M_WEIGHT_AXI_ARLEN(weight_arlen),
        .M_WEIGHT_AXI_ARSIZE(weight_arsize),
        .M_WEIGHT_AXI_ARBURST(weight_arburst),
        .M_WEIGHT_AXI_ARLOCK(weight_arlock),
        .M_WEIGHT_AXI_ARCACHE(weight_arcache),
        .M_WEIGHT_AXI_ARPROT(weight_arprot),
        .M_WEIGHT_AXI_ARQOS(weight_arqos),
        .M_WEIGHT_AXI_ARVALID(weight_arvalid),
        .M_WEIGHT_AXI_ARREADY(weight_arready),
        .M_WEIGHT_AXI_RID(weight_rid),
        .M_WEIGHT_AXI_RDATA(weight_rdata),
        .M_WEIGHT_AXI_RRESP(weight_rresp),
        .M_WEIGHT_AXI_RLAST(weight_rlast),
        .M_WEIGHT_AXI_RVALID(weight_rvalid),
        .M_WEIGHT_AXI_RREADY(weight_rready)
    );

    axi_interconnect_0 u_memory_interconnect (
        .INTERCONNECT_ACLK(clk),
        .INTERCONNECT_ARESETN(resetn),
        .S00_AXI_ARESET_OUT_N(),
        .S00_AXI_ACLK(clk),
        .S00_AXI_AWID('0),
        .S00_AXI_AWADDR('0),
        .S00_AXI_AWLEN('0),
        .S00_AXI_AWSIZE('0),
        .S00_AXI_AWBURST('0),
        .S00_AXI_AWLOCK(1'b0),
        .S00_AXI_AWCACHE('0),
        .S00_AXI_AWPROT('0),
        .S00_AXI_AWQOS('0),
        .S00_AXI_AWVALID(1'b0),
        .S00_AXI_AWREADY(),
        .S00_AXI_WDATA('0),
        .S00_AXI_WSTRB('0),
        .S00_AXI_WLAST(1'b0),
        .S00_AXI_WVALID(1'b0),
        .S00_AXI_WREADY(),
        .S00_AXI_BID(),
        .S00_AXI_BRESP(),
        .S00_AXI_BVALID(),
        .S00_AXI_BREADY(1'b0),
        .S00_AXI_ARID(data_arid),
        .S00_AXI_ARADDR(data_araddr),
        .S00_AXI_ARLEN(data_arlen),
        .S00_AXI_ARSIZE(data_arsize),
        .S00_AXI_ARBURST(data_arburst),
        .S00_AXI_ARLOCK(data_arlock),
        .S00_AXI_ARCACHE(data_arcache),
        .S00_AXI_ARPROT(data_arprot),
        .S00_AXI_ARQOS(data_arqos),
        .S00_AXI_ARVALID(data_arvalid),
        .S00_AXI_ARREADY(data_arready),
        .S00_AXI_RID(data_rid),
        .S00_AXI_RDATA(data_rdata),
        .S00_AXI_RRESP(data_rresp),
        .S00_AXI_RLAST(data_rlast),
        .S00_AXI_RVALID(data_rvalid),
        .S00_AXI_RREADY(data_rready),
        .S01_AXI_ARESET_OUT_N(),
        .S01_AXI_ACLK(clk),
        .S01_AXI_AWID('0),
        .S01_AXI_AWADDR('0),
        .S01_AXI_AWLEN('0),
        .S01_AXI_AWSIZE('0),
        .S01_AXI_AWBURST('0),
        .S01_AXI_AWLOCK(1'b0),
        .S01_AXI_AWCACHE('0),
        .S01_AXI_AWPROT('0),
        .S01_AXI_AWQOS('0),
        .S01_AXI_AWVALID(1'b0),
        .S01_AXI_AWREADY(),
        .S01_AXI_WDATA('0),
        .S01_AXI_WSTRB('0),
        .S01_AXI_WLAST(1'b0),
        .S01_AXI_WVALID(1'b0),
        .S01_AXI_WREADY(),
        .S01_AXI_BID(),
        .S01_AXI_BRESP(),
        .S01_AXI_BVALID(),
        .S01_AXI_BREADY(1'b0),
        .S01_AXI_ARID(weight_arid),
        .S01_AXI_ARADDR(weight_araddr),
        .S01_AXI_ARLEN(weight_arlen),
        .S01_AXI_ARSIZE(weight_arsize),
        .S01_AXI_ARBURST(weight_arburst),
        .S01_AXI_ARLOCK(weight_arlock),
        .S01_AXI_ARCACHE(weight_arcache),
        .S01_AXI_ARPROT(weight_arprot),
        .S01_AXI_ARQOS(weight_arqos),
        .S01_AXI_ARVALID(weight_arvalid),
        .S01_AXI_ARREADY(weight_arready),
        .S01_AXI_RID(weight_rid),
        .S01_AXI_RDATA(weight_rdata),
        .S01_AXI_RRESP(weight_rresp),
        .S01_AXI_RLAST(weight_rlast),
        .S01_AXI_RVALID(weight_rvalid),
        .S01_AXI_RREADY(weight_rready),
        .M00_AXI_ARESET_OUT_N(),
        .M00_AXI_ACLK(clk),
        .M00_AXI_AWID(),
        .M00_AXI_AWADDR(),
        .M00_AXI_AWLEN(),
        .M00_AXI_AWSIZE(),
        .M00_AXI_AWBURST(),
        .M00_AXI_AWLOCK(),
        .M00_AXI_AWCACHE(),
        .M00_AXI_AWPROT(),
        .M00_AXI_AWQOS(),
        .M00_AXI_AWVALID(),
        .M00_AXI_AWREADY(1'b0),
        .M00_AXI_WDATA(),
        .M00_AXI_WSTRB(),
        .M00_AXI_WLAST(),
        .M00_AXI_WVALID(),
        .M00_AXI_WREADY(1'b0),
        .M00_AXI_BID('0),
        .M00_AXI_BRESP('0),
        .M00_AXI_BVALID(1'b0),
        .M00_AXI_BREADY(),
        .M00_AXI_ARID(memory_arid),
        .M00_AXI_ARADDR(memory_araddr),
        .M00_AXI_ARLEN(memory_arlen),
        .M00_AXI_ARSIZE(memory_arsize),
        .M00_AXI_ARBURST(memory_arburst),
        .M00_AXI_ARLOCK(),
        .M00_AXI_ARCACHE(memory_arcache),
        .M00_AXI_ARPROT(memory_arprot),
        .M00_AXI_ARQOS(memory_arqos),
        .M00_AXI_ARVALID(memory_arvalid),
        .M00_AXI_ARREADY(memory_arready),
        .M00_AXI_RID(memory_rid),
        .M00_AXI_RDATA(memory_rdata),
        .M00_AXI_RRESP(memory_rresp),
        .M00_AXI_RLAST(memory_rlast),
        .M00_AXI_RVALID(memory_rvalid),
        .M00_AXI_RREADY(memory_rready)
    );

    // axi_vip_1 must be configured as AXI4, slave, read-only, ID width 5.
    axi_vip_1 u_memory_vip (
        .aclk(clk),
        .aresetn(resetn),
        .s_axi_arid(memory_arid),
        .s_axi_araddr(memory_araddr),
        .s_axi_arlen(memory_arlen),
        .s_axi_arsize(memory_arsize),
        .s_axi_arburst(memory_arburst),
        .s_axi_arcache(memory_arcache),
        .s_axi_arprot(memory_arprot),
        .s_axi_arregion(4'b0000),
        .s_axi_arqos(memory_arqos),
        .s_axi_arvalid(memory_arvalid),
        .s_axi_arready(memory_arready),
        .s_axi_rid(memory_rid),
        .s_axi_rdata(memory_rdata),
        .s_axi_rresp(memory_rresp),
        .s_axi_rlast(memory_rlast),
        .s_axi_rvalid(memory_rvalid),
        .s_axi_rready(memory_rready)
    );

endmodule
