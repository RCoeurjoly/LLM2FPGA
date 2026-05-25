`timescale 1ns/1ps
`default_nettype none

module task6_pcie_rowstream_loader_ingress_tb;
  localparam logic [31:0] COMMAND_MAGIC = 32'h33445244;
  localparam logic [7:0] OP_WRITE_DENSE_BYTE = 8'h05;
  localparam logic [7:0] OP_READ_DENSE_BEAT = 8'h06;
  localparam logic [7:0] OP_RUN_FULLBEAT = 8'h09;

  logic clk;
  logic rst_n;
  logic boot_done;
  logic [31:0] awaddr;
  logic awvalid;
  wire awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  wire wready;
  wire [1:0] bresp;
  wire bvalid;
  logic bready;
  logic [31:0] araddr;
  logic arvalid;
  wire arready;
  wire [31:0] rdata;
  wire rvalid;
  logic rready;
  wire [1:0] rresp;

  wire [191:0] command_payload;
  wire status_clear_pulse;
  wire command_event;
  wire wb_cyc;
  wire wb_stb;
  wire wb_we;
  wire [9:0] wb_addr;
  wire [511:0] wb_data;
  wire [63:0] wb_sel;
  logic wb_stall;
  logic wb_ack;
  logic wb_err;
  logic [511:0] wb_rdata;
  wire loader_done;
  wire loader_error;
  wire loader_write_ack_seen;
  wire loader_read_ack_seen;
  wire loader_stall_seen;
  wire [511:0] loader_read_data;
  wire [31:0] loader_wait_cycles;
  wire [31:0] loader_command_payload_addr;
  wire [7:0] loader_last_opcode;
  wire [1:0] loader_last_chunk;
  wire loader_last_magic_ok;
  wire loader_last_accepted;
  wire loader_fullbeat_done;
  wire [6:0] loader_fullbeat_mismatch_count;
  wire [9:0] loader_fullbeat_addr;
  wire [7:0] loader_fullbeat_expected_base;
  wire [3:0] loader_state;

  logic [511:0] mem [0:1023];
  int errors;

  task6_pcie_axil_rowstream_loader_ingress ingress (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready),
    .s_axi_rresp(rresp),
    .command_payload_o(command_payload),
    .command_event_o(command_event),
    .boot_done_i(boot_done),
    .loader_done_i(loader_done),
    .loader_error_i(loader_error),
    .loader_last_accepted_i(loader_last_accepted),
    .loader_last_magic_ok_i(loader_last_magic_ok),
    .loader_last_opcode_i(loader_last_opcode),
    .loader_last_chunk_i(loader_last_chunk),
    .loader_command_payload_addr_i(loader_command_payload_addr),
    .loader_wait_cycles_i(loader_wait_cycles),
    .loader_read_data_i(loader_read_data),
    .status_clear_pulse_o(status_clear_pulse)
  );

  task6_uberddr3_rowstream_loader_contract #(
    .WB_ADDR_BITS(10)
  ) loader (
    .clk_i(clk),
    .rst_ni(rst_n),
    .boot_done_i(boot_done),
    .command_payload_i(command_payload),
    .command_event_i(command_event),
    .wb_cyc_o(wb_cyc),
    .wb_stb_o(wb_stb),
    .wb_we_o(wb_we),
    .wb_addr_o(wb_addr),
    .wb_data_o(wb_data),
    .wb_sel_o(wb_sel),
    .wb_stall_i(wb_stall),
    .wb_ack_i(wb_ack),
    .wb_err_i(wb_err),
    .wb_data_i(wb_rdata),
    .loader_done_o(loader_done),
    .loader_error_o(loader_error),
    .loader_write_ack_seen_o(loader_write_ack_seen),
    .loader_read_ack_seen_o(loader_read_ack_seen),
    .loader_stall_seen_o(loader_stall_seen),
    .loader_read_data_o(loader_read_data),
    .loader_wait_cycles_o(loader_wait_cycles),
    .loader_command_payload_addr_o(loader_command_payload_addr),
    .loader_last_opcode_o(loader_last_opcode),
    .loader_last_chunk_o(loader_last_chunk),
    .loader_last_magic_ok_o(loader_last_magic_ok),
    .loader_last_accepted_o(loader_last_accepted),
    .loader_fullbeat_done_o(loader_fullbeat_done),
    .loader_fullbeat_mismatch_count_o(loader_fullbeat_mismatch_count),
    .loader_fullbeat_addr_o(loader_fullbeat_addr),
    .loader_fullbeat_expected_base_o(loader_fullbeat_expected_base),
    .loader_state_o(loader_state)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_ack <= 1'b0;
      wb_err <= 1'b0;
      wb_rdata <= '0;
    end else begin
      wb_ack <= wb_cyc && wb_stb && !wb_stall;
      wb_err <= 1'b0;
      if (wb_cyc && wb_stb && !wb_stall) begin
        wb_rdata <= mem[wb_addr];
        if (wb_we) begin
          for (int lane = 0; lane < 64; lane++) begin
            if (wb_sel[lane])
              mem[wb_addr][lane * 8 +: 8] <= wb_data[lane * 8 +: 8];
          end
        end
      end
    end
  end

  task automatic check(input bit condition, input string message);
    if (!condition) begin
      $display("FAIL: %s", message);
      errors++;
    end
  endtask

  task automatic axil_write(input logic [31:0] addr, input logic [31:0] data);
    bit aw_seen;
    bit w_seen;
    begin
      @(negedge clk);
      awaddr = addr;
      wdata = data;
      wstrb = 4'hf;
      awvalid = 1'b1;
      wvalid = 1'b1;
      bready = 1'b1;
      aw_seen = 1'b0;
      w_seen = 1'b0;
      while (!aw_seen || !w_seen) begin
        @(negedge clk);
        if (awready) aw_seen = 1'b1;
        if (wready) w_seen = 1'b1;
      end
      @(negedge clk);
      awvalid = 1'b0;
      wvalid = 1'b0;
      while (!bvalid) @(negedge clk);
      check(bresp == 2'b00, "write response must be OKAY");
      @(negedge clk);
      bready = 1'b0;
    end
  endtask

  task automatic axil_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      @(negedge clk);
      araddr = addr;
      arvalid = 1'b1;
      rready = 1'b1;
      while (arvalid) begin
        @(negedge clk);
        if (arready) arvalid = 1'b0;
      end
      while (!rvalid) @(negedge clk);
      data = rdata;
      check(rresp == 2'b00, "read response must be OKAY");
      @(negedge clk);
      rready = 1'b0;
    end
  endtask

  task automatic wait_loader_done(output logic [31:0] status);
    begin
      status = 32'd0;
      repeat (2000) begin
        axil_read(32'h034, status);
        if (status[1] || status[2])
          return;
        @(negedge clk);
      end
      check(1'b0, "loader command timed out");
    end
  endtask

  task automatic pcie_command(
    input logic [7:0] opcode,
    input logic [1:0] chunk,
    input logic [31:0] addr,
    input logic [7:0] data_byte
  );
    logic [31:0] status;
    begin
      axil_write(32'h008, 32'h1);
      axil_write(32'h010, COMMAND_MAGIC);
      axil_write(32'h014, {22'd0, chunk, opcode});
      axil_write(32'h018, addr);
      axil_write(32'h020, {24'd0, data_byte});
      axil_write(32'h024, 32'd0);
      axil_write(32'h028, 32'd0);
      axil_write(32'h02c, 32'd0);
      axil_write(32'h030, 32'h1);
      axil_write(32'h030, 32'h1);
      wait_loader_done(status);
      check(!status[2], "loader must not report an error");
      check(status[4], "loader must accept the PCIe command");
      check(status[3], "loader must see the rowstream command magic");
      check(loader_last_opcode == opcode, "loader opcode must match PCIe command");
    end
  endtask

  initial begin
    logic [31:0] value;

    clk = 1'b0;
    rst_n = 1'b0;
    boot_done = 1'b0;
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = '0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b0;
    wb_stall = 1'b0;
    errors = 0;

    for (int i = 0; i < 1024; i++)
      mem[i] = '0;

    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(negedge clk);
    boot_done = 1'b1;

    axil_read(32'h000, value);
    check(value == 32'h54365043, "PCIe ingress magic must match T6PC");
    axil_read(32'h004, value);
    check(value == 32'd3, "PCIe ingress version must be 3");

    pcie_command(OP_WRITE_DENSE_BYTE, 2'd0, 32'd13, 8'ha5);
    check(mem[0][13 * 8 +: 8] == 8'ha5, "PCIe dense-byte write must land in DDR3 rowstream memory model");

    pcie_command(OP_WRITE_DENSE_BYTE, 2'd0, 32'd70, 8'h5a);
    check(mem[1][6 * 8 +: 8] == 8'h5a, "PCIe dense-byte write must address the next 512-bit beat");

    pcie_command(OP_READ_DENSE_BEAT, 2'd0, 32'd1, 8'd0);
    axil_read(32'h048, value);
    check(value[23:16] == 8'h5a, "PCIe readback aperture must expose loader DDR3 read data");

    pcie_command(OP_RUN_FULLBEAT, 2'd0, 32'd128, 8'h30);
    check(loader_fullbeat_done, "PCIe-triggered fullbeat write/read must complete");
    check(loader_fullbeat_mismatch_count == 7'd0, "PCIe-triggered fullbeat run must compare cleanly");

    axil_read(32'h00c, value);
    check(value == 32'd4, "duplicate BAR doorbells must be ignored by ingress");
    axil_read(32'h034, value);
    check(value[4], "loader accepted status must be visible in the BAR status aperture");

    if (errors == 0) begin
      $display("PASS: task6 PCIe rowstream loader ingress simulation");
      $finish;
    end else begin
      $display("FAIL: task6 PCIe rowstream loader ingress simulation errors %0d", errors);
      $fatal(1);
    end
  end
endmodule

`default_nettype wire
