`timescale 1ns/1ps

module renewal_vip_TB;

    import axi_vip_pkg::*;
    import axi_vip_0_pkg::*;
    import axi_vip_1_pkg::*;

    localparam int CLK_PERIOD_NS = 20;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int BURST_LEN = 8;
    localparam int MACLANE_WIDTH = 512;
    localparam int INPUT_WIDTH = 5;
    localparam int INPUT_HEIGHT = 5;
    localparam int KERNEL_WIDTH = 3;
    localparam int KERNEL_HEIGHT = 3;
    localparam int OUTPUT_WIDTH = INPUT_WIDTH - KERNEL_WIDTH + 1;
    localparam int OUTPUT_HEIGHT = INPUT_HEIGHT - KERNEL_HEIGHT + 1;
    localparam int DATA_POSITION_COUNT = INPUT_WIDTH * INPUT_HEIGHT;
    localparam int WEIGHT_POSITION_COUNT = KERNEL_WIDTH * KERNEL_HEIGHT;
    localparam int MACLANE_PACKET_COUNT =
        OUTPUT_WIDTH * OUTPUT_HEIGHT * WEIGHT_POSITION_COUNT;

    localparam xil_axi_ulong DATA_DDR_BASE = 32'h0100_0000;
    localparam xil_axi_ulong WEIGHT_DDR_BASE = 32'h0200_0000;
    localparam logic [31:0] DATA_PATTERN = 32'hD000_0000;
    localparam logic [31:0] WEIGHT_PATTERN = 32'hA000_0000;
    localparam string MACLANE_ACTUAL_FILE = "renewal_maclane_actual.txt";

    logic clk;
    logic resetn;
    logic maclane_valid;
    logic maclane_ready;
    logic [31:0] maclane_tag;
    logic [MACLANE_WIDTH-1:0] maclane_data;
    logic [MACLANE_WIDTH-1:0] maclane_weight;
    logic [1:0] maclane_level;
    logic cacc_op_enable_level;
    logic cacc_op_enable_clear;
    logic [1:0] cacc_status;
    logic [31:0] CACC_D_OP_ENABLE;
    logic [31:0] CACC_D_DATAOUT_SIZE_0;
    logic [31:0] CACC_D_DATAOUT_SIZE_1;
    logic [31:0] CACC_D_DATAOUT_ADDR;
    logic [31:0] CACC_D_LINE_STRIDE;
    logic [31:0] CACC_D_SURF_STRIDE;
    logic [31:0] CACC_D_DATAOUT_MAP;

    int unsigned data_burst_count;
    int unsigned weight_burst_count;
    integer maclane_actual_file;

    axi_vip_0_mst_t control_agent;
    axi_vip_1_slv_mem_t memory_agent;

    renewal_vip_wrapper u_dut (
        .clk(clk),
        .resetn(resetn),
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
        .CACC_D_DATAOUT_MAP(CACC_D_DATAOUT_MAP)
    );

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    task automatic axi_write32(
        input xil_axi_ulong address,
        input logic [31:0] data
    );
        bit [63:0] payload;
        xil_axi_resp_t response;
        begin
            payload = 64'd0;
            payload[31:0] = data;
            control_agent.AXI4LITE_WRITE_BURST(
                address,
                3'b000,
                payload,
                response
            );
            if (response != XIL_AXI_RESP_OKAY) begin
                $display("[CSB WRITE FAIL] addr=0x%08h data=0x%08h BRESP=%0d",
                         address, data, response);
                $fatal(1,
                       "CSB write failed: addr=0x%08h data=0x%08h response=%0d",
                       address, data, response);
            end else begin
                $display("[CSB WRITE PASS] addr=0x%08h data=0x%08h BRESP=%0d",
                         address, data, response);
            end
        end
    endtask

    task automatic axi_read32(
        input  xil_axi_ulong address,
        output logic [31:0] data
    );
        bit [63:0] payload;
        xil_axi_resp_t response;
        begin
            payload = 64'd0;
            control_agent.AXI4LITE_READ_BURST(
                address,
                3'b000,
                payload,
                response
            );
            data = payload[31:0];
            if (response != XIL_AXI_RESP_OKAY) begin
                $fatal(1,
                       "CSB read failed: addr=0x%08h response=%0d",
                       address, response);
            end
        end
    endtask

    task automatic preload_memory;
        for (int position = 0; position < DATA_POSITION_COUNT; position++) begin
            for (int beat = 0; beat < BURST_LEN; beat++) begin
                memory_agent.mem_model.backdoor_memory_write(
                    DATA_DDR_BASE + (position * BURST_LEN * 4) + (beat * 4),
                    DATA_PATTERN + (position * BURST_LEN) + beat,
                    4'hF
                );
            end
        end
        for (int position = 0; position < WEIGHT_POSITION_COUNT; position++) begin
            for (int beat = 0; beat < BURST_LEN; beat++) begin
                memory_agent.mem_model.backdoor_memory_write(
                    WEIGHT_DDR_BASE + (position * BURST_LEN * 4) + (beat * 4),
                    WEIGHT_PATTERN + (position * BURST_LEN) + beat,
                    4'hF
                );
            end
        end
    endtask

    task automatic program_5x5_3x3_operation;
        logic [31:0] pointer_value;
        begin
            axi_read32(32'h0000_007c, pointer_value);
            axi_write32(32'h0000_007c, {31'd0, pointer_value[16]});

            axi_write32(32'h0000_0008, INPUT_WIDTH);
            axi_write32(32'h0000_000c, INPUT_HEIGHT);
            axi_write32(32'h0000_0010, 32'd32);
            axi_write32(32'h0000_0018, DATA_DDR_BASE[31:0]);
            axi_write32(32'h0000_001c, KERNEL_WIDTH);
            axi_write32(32'h0000_0020, KERNEL_HEIGHT);
            axi_write32(32'h0000_0024, 32'd32);
            axi_write32(32'h0000_002c, WEIGHT_DDR_BASE[31:0]);

            axi_write32(32'h0000_0044, {16'(INPUT_HEIGHT), 16'(INPUT_WIDTH)});
            axi_write32(32'h0000_0048, 32'd32);
            axi_write32(32'h0000_004c, {16'(KERNEL_HEIGHT), 16'(KERNEL_WIDTH)});
            axi_write32(32'h0000_0050, 32'h0001_0001);
            axi_write32(32'h0000_0054, {16'(OUTPUT_HEIGHT), 16'(OUTPUT_WIDTH)});
            axi_write32(32'h0000_0058, 32'd1);
            axi_write32(32'h0000_0080, 32'd0);
            axi_write32(32'h0000_0084, 32'd1);

            axi_write32(32'h0000_0000, 32'h0000_0003);
            axi_write32(32'h0000_0030, 32'h0000_0001);
        end
    endtask

    task automatic check_maclane_packet(input int unsigned packet);
        logic [MACLANE_WIDTH-1:0] expected_data_packet;
        logic [MACLANE_WIDTH-1:0] expected_weight_packet;
        int unsigned output_position;
        int unsigned kernel_position;
        int unsigned output_x;
        int unsigned output_y;
        int unsigned kernel_x;
        int unsigned kernel_y;
        int unsigned data_position;
        begin
            output_position = packet / WEIGHT_POSITION_COUNT;
            kernel_position = packet % WEIGHT_POSITION_COUNT;
            output_x = output_position % OUTPUT_WIDTH;
            output_y = output_position / OUTPUT_WIDTH;
            kernel_x = kernel_position % KERNEL_WIDTH;
            kernel_y = kernel_position / KERNEL_WIDTH;
            data_position = ((output_y + kernel_y) * INPUT_WIDTH) +
                            output_x + kernel_x;

            expected_data_packet = '0;
            expected_weight_packet = '0;
            for (int beat = 0; beat < BURST_LEN; beat++) begin
                expected_data_packet[(beat*AXI_DATA_WIDTH)+:AXI_DATA_WIDTH] =
                    DATA_PATTERN + (data_position * BURST_LEN) + beat;
                expected_weight_packet[(beat*AXI_DATA_WIDTH)+:AXI_DATA_WIDTH] =
                    WEIGHT_PATTERN + (kernel_position * BURST_LEN) + beat;
            end
            if (maclane_tag !== packet ||
                maclane_data !== expected_data_packet ||
                maclane_weight !== expected_weight_packet) begin
                $fatal(1,
                       "MACLane mismatch: packet=%0d tag=%0d out=(%0d,%0d) kernel=(%0d,%0d) data_position=%0d data=%h weight=%h",
                       packet, maclane_tag, output_x, output_y,
                       kernel_x, kernel_y, data_position,
                       maclane_data, maclane_weight);
            end
            $display("[MACLANE PASS] packet=%0d out=(%0d,%0d) kernel=(%0d,%0d) data_position=%0d",
                     packet, output_x, output_y,
                     kernel_x, kernel_y, data_position);
            $display("  maclane_data   = 0x%0h", maclane_data);
            $display("  maclane_weight = 0x%0h", maclane_weight);
        end
    endtask

    always @(posedge clk) begin// to avoid non-blocking limit
        if (resetn && u_dut.memory_arvalid && u_dut.memory_arready) begin
            if (u_dut.memory_arlen !== BURST_LEN-1 ||
                u_dut.memory_arsize !== 3'b010 ||
                u_dut.memory_arburst !== 2'b01) begin
                $fatal(1,
                       "DDR AR mismatch: addr=0x%08h id=0x%0h len=%0d size=%0d burst=%0d",
                       u_dut.memory_araddr,
                       u_dut.memory_arid,
                       u_dut.memory_arlen,
                       u_dut.memory_arsize,
                       u_dut.memory_arburst);
            end

            if ((weight_burst_count < WEIGHT_POSITION_COUNT) &&
                (u_dut.memory_araddr ==
                 (WEIGHT_DDR_BASE + (weight_burst_count * BURST_LEN * 4)))) begin
                $display("[DDR READ] WEIGHT position=%0d addr=0x%08h id=0x%0h",
                         weight_burst_count,
                         u_dut.memory_araddr,
                         u_dut.memory_arid);
                weight_burst_count = weight_burst_count + 1;
            end else if ((data_burst_count < DATA_POSITION_COUNT) &&
                         (u_dut.memory_araddr == (DATA_DDR_BASE + (data_burst_count * BURST_LEN * 4)))) begin
                $display("[DDR READ] DATA   position=%0d addr=0x%08h id=0x%0h", data_burst_count, u_dut.memory_araddr, u_dut.memory_arid);
                data_burst_count = data_burst_count + 1;//blocking to use it with *data_burst_count = 0
            end else begin
                $fatal(1, "Unexpected DDR read address: 0x%08h", u_dut.memory_araddr);
            end
        end
    end

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        maclane_ready = 1'b0;
        cacc_op_enable_clear = 1'b0;
        cacc_status = 2'b00;
        data_burst_count = 0;
        weight_burst_count = 0;
        maclane_actual_file = $fopen(MACLANE_ACTUAL_FILE, "w");
        if (maclane_actual_file == 0) begin
            $fatal(1, "Cannot open MACLane actual-output file: %s",
                   MACLANE_ACTUAL_FILE);
        end

        control_agent = new(
            "Renewal CSB AXI4-Lite master agent",
            u_dut.u_control_vip.inst.IF
        );
        control_agent.set_agent_tag("CONTROL_MASTER_VIP");
        control_agent.set_verbosity(0);
        control_agent.start_master();

        memory_agent = new(
            "Renewal DDR AXI slave memory agent",
            u_dut.u_memory_vip.inst.IF
        );
        memory_agent.set_agent_tag("MEMORY_SLAVE_VIP");
        memory_agent.set_verbosity(0);
        memory_agent.start_slave();
        memory_agent.mem_model.set_memory_fill_policy(XIL_AXI_MEMORY_FILL_FIXED);
        memory_agent.mem_model.set_default_memory_value(32'h0000_0000);
        preload_memory();

        repeat (20) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        program_5x5_3x3_operation();

        wait (maclane_valid);
        check_maclane_packet(0);

        repeat (2) begin
            @(posedge clk);
            if (!maclane_valid ||
                maclane_tag !== 32'd0) begin
                $fatal(1, "MACLane payload changed during backpressure");
            end
            check_maclane_packet(0);
        end

        @(negedge clk);
        maclane_ready = 1'b1;
        for (int packet = 0; packet < MACLANE_PACKET_COUNT; packet++) begin
            do begin
                @(posedge clk);
            end while (!(maclane_valid && maclane_ready));
            $fdisplay(maclane_actual_file, "%08h %h %h",
                      maclane_tag, maclane_data, maclane_weight);
            $fflush(maclane_actual_file);
            check_maclane_packet(packet);
        end
        repeat (5) @(posedge clk);

        if (data_burst_count != DATA_POSITION_COUNT ||
            weight_burst_count != WEIGHT_POSITION_COUNT) begin
            $fatal(1,
                   "Unexpected burst count: data=%0d weight=%0d",
                   data_burst_count, weight_burst_count);
        end

        $display("renewal_vip_TB PASSED: 5x5 DATA and 3x3 WEIGHT verified");
        $fclose(maclane_actual_file);
        $finish;
    end
    
    initial begin
        repeat (10000) @(posedge clk);
        $fatal(1, "renewal_vip_TB timeout");
    end

endmodule
