`timescale 1ns/1ps
`default_nettype none

module task6_pcie_rowstream_loader_ingress_m2_pcie7x_tb;
  logic clk;
  logic rst_n;
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
  wire command_event;
  wire status_clear_pulse;
  wire [511:0] top1_hidden_vector;
  wire top1_start_pulse;
  wire top1_status_clear_pulse;
  wire [31:0] mlp_selftest_debug_select;
  wire [511:0] mlp_accel_activation_vector;
  wire [511:0] mlp_accel_residual_vector;
  wire mlp_accel_start_pulse;
  wire mlp_accel_clear_pulse;
  wire [511:0] m2_full_block_input_vector;
  wire [511:0] m2_full_block_residual_vector;
  wire m2_full_block_start_pulse;
  wire m2_full_block_clear_pulse;

  int errors;

  task6_pcie_axil_rowstream_loader_ingress #(
    .M2_INPUT_PCIE7X_ROR64_COMPENSATE(1)
  ) ingress (
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
    .calib_complete_i(1'b1),
    .boot_done_i(1'b1),
    .ddr_debug1_i(32'd0),
    .debug_rowstream_heartbeat_count_i(32'd0),
    .debug_rowstream_status_i(32'd0),
    .debug_rowstream_seen_i(32'd0),
    .loader_done_i(1'b0),
    .loader_error_i(1'b0),
    .loader_last_accepted_i(1'b0),
    .loader_last_magic_ok_i(1'b0),
    .loader_last_opcode_i(8'd0),
    .loader_last_chunk_i(2'd0),
    .loader_command_payload_addr_i(32'd0),
    .loader_wait_cycles_i(32'd0),
    .loader_read_data_i(512'd0),
    .status_clear_pulse_o(status_clear_pulse),
    .top1_hidden_vector_o(top1_hidden_vector),
    .top1_start_pulse_o(top1_start_pulse),
    .top1_status_clear_pulse_o(top1_status_clear_pulse),
    .top1_busy_i(1'b0),
    .top1_done_i(1'b0),
    .top1_error_i(1'b0),
    .top1_token_i(32'd0),
    .top1_score_q024_i(32'd0),
    .top1_rows_scanned_i(32'd0),
    .top1_cycle_count_i(32'd0),
    .top1_debug_status_i(32'd0),
    .top1_debug_reader_addr_i(32'd0),
    .top1_debug_wb_ack_count_i(32'd0),
    .top1_debug_wb_err_count_i(32'd0),
    .top1_debug_packet_wb_write_ack_count_i(32'd0),
    .top1_debug_packet_wb_read_ack_count_i(32'd0),
    .mlp_selftest_present_i(1'b0),
    .mlp_selftest_status_i(32'd0),
    .mlp_selftest_cycle_count_i(32'd0),
    .mlp_selftest_fail_detail_i(32'd0),
    .mlp_selftest_fail_values_i(32'd0),
    .mlp_selftest_first_add_sample_i(32'd0),
    .mlp_selftest_first_requant_sample_i(32'd0),
    .mlp_selftest_requant_debug0_i(32'd0),
    .mlp_selftest_requant_debug1_i(32'd0),
    .mlp_selftest_debug_select_o(mlp_selftest_debug_select),
    .mlp_accel_activation_vector_o(mlp_accel_activation_vector),
    .mlp_accel_residual_vector_o(mlp_accel_residual_vector),
    .mlp_accel_start_pulse_o(mlp_accel_start_pulse),
    .mlp_accel_clear_pulse_o(mlp_accel_clear_pulse),
    .mlp_accel_status_i(32'd0),
    .mlp_accel_cycle_count_i(32'd0),
    .mlp_accel_output_checksum_i(32'd0),
    .mlp_accel_output_sample0_i(32'd0),
    .mlp_accel_output_sample1_i(32'd0),
    .mlp_accel_output_vector_i(512'd0),
    .m2_full_block_input_vector_o(m2_full_block_input_vector),
    .m2_full_block_residual_vector_o(m2_full_block_residual_vector),
    .m2_full_block_start_pulse_o(m2_full_block_start_pulse),
    .m2_full_block_clear_pulse_o(m2_full_block_clear_pulse),
    .m2_full_block_status_i(32'd0),
    .m2_full_block_cycle_count_i(32'd0),
    .m2_full_block_output_checksum_i(32'd0),
    .m2_full_block_output_sample0_i(32'd0),
    .m2_full_block_output_sample1_i(32'd0),
    .m2_full_block_output_count_i(32'd0),
    .m2_full_block_debug_i(32'd0),
    .m2_full_block_debug1_i(32'd0),
    .m2_full_block_debug2_i(32'd0),
    .m2_full_block_debug3_i(32'd0),
    .m2_full_block_provenance_i(32'h4d32_4205),
    .m2_full_block_output_hash_i(128'd0),
    .m2_full_block_output_vector_i(512'd0)
  );

  always #5 clk = ~clk;

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

  function automatic [63:0] pcie7x_ror1(input [63:0] value);
    pcie7x_ror1 = {value[0], value[63:1]};
  endfunction

  initial begin
    logic [31:0] expected [0:15];
    logic [31:0] raw [0:15];
    logic [31:0] value;
    logic [63:0] pair;
    logic [63:0] rotated;

    clk = 1'b0;
    rst_n = 1'b0;
    awaddr = 32'd0;
    awvalid = 1'b0;
    wdata = 32'd0;
    wstrb = 4'd0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = 32'd0;
    arvalid = 1'b0;
    rready = 1'b0;
    errors = 0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    for (int word = 0; word < 16; word++) begin
      expected[word] = 32'h2500_1000 + word;
    end
    for (int word = 0; word < 16; word += 2) begin
      pair = {expected[word + 1], expected[word]};
      rotated = pcie7x_ror1(pair);
      raw[word] = rotated[31:0];
      raw[word + 1] = rotated[63:32];
    end

    for (int word = 0; word < 16; word++) begin
      axil_write(32'h540 + word * 4, raw[word]);
    end
    for (int word = 0; word < 16; word++) begin
      axil_read(32'h540 + word * 4, value);
      check(value == expected[word], "M2 PCIe7x-compensated input BAR readback must be host identity");
      check(
        m2_full_block_input_vector[word * 32 +: 32] == expected[word],
        "M2 PCIe7x-compensated input vector must be host identity internally"
      );
    end

    if (errors == 0) begin
      $display("PASS: task6 M2 input PCIe7x BAR compensation simulation");
      $finish;
    end else begin
      $display("FAIL: task6 M2 input PCIe7x BAR compensation simulation errors=%0d", errors);
      $fatal(1);
    end
  end
endmodule
