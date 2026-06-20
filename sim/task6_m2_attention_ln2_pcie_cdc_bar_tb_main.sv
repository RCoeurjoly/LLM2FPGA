`timescale 1ns/1ps
`default_nettype none

module task6_m2_attention_ln2_pcie_cdc_bar_tb;
  `include "tb_data.sv"
  `include "task6_m2_embedding_block_input_tb_data.sv"
  `include "task6_m2_ln_attn_live_kv_all_heads_context_tb_data.sv"

  localparam int TIMEOUT_CYCLES = 200000;

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

  wire [511:0] m2_input_vector;
  wire [511:0] m2_residual_vector;
  wire m2_start_pulse;
  wire m2_clear_pulse;
  logic [31:0] m2_status;
  logic [31:0] m2_cycle_count;
  logic [31:0] m2_output_checksum;
  logic [31:0] m2_output_sample0;
  logic [31:0] m2_output_sample1;
  logic [31:0] m2_output_count;
  logic [511:0] m2_output_vector;
  logic [127:0] m2_output_hash;
  logic [31:0] m2_debug;
  logic [31:0] m2_debug1;
  logic [31:0] m2_debug2;
  logic [31:0] m2_debug3;
  logic [31:0] m2_provenance;

  logic [31:0] m2_status_raw;
  logic [31:0] m2_cycle_count_raw;
  logic [31:0] m2_output_checksum_raw;
  logic [31:0] m2_output_sample0_raw;
  logic [31:0] m2_output_sample1_raw;
  logic [31:0] m2_output_count_raw;
  logic [511:0] m2_output_vector_raw;
  logic [31:0] m2_debug_raw;
  logic [31:0] m2_debug1_raw;
  logic [31:0] m2_debug2_raw;
  logic [31:0] m2_debug3_raw;
  logic [31:0] m2_provenance_raw;
  logic [95:0] m2_token_ids_for_accel_q;
  logic [95:0] m2_token_ids_for_accel;

  logic [511:0] expected_token_vector;
  logic [511:0] expected_ln2_vector;
  logic [31:0] value;

  task6_pcie_axil_rowstream_loader_ingress_cdc ingress (
    .pcie_clk(clk),
    .pcie_rst_n(rst_n),
    .rowstream_clk(clk),
    .rowstream_rst_n(rst_n),
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
    .rowstream_command_payload_o(),
    .rowstream_command_event_o(),
    .rowstream_status_clear_o(),
    .rowstream_calib_complete_i(1'b1),
    .rowstream_boot_done_i(1'b1),
    .rowstream_ddr_debug1_i(32'hd00d600d),
    .rowstream_loader_done_i(1'b0),
    .rowstream_loader_error_i(1'b0),
    .rowstream_loader_last_accepted_i(1'b0),
    .rowstream_loader_last_magic_ok_i(1'b0),
    .rowstream_loader_last_opcode_i(8'd0),
    .rowstream_loader_last_chunk_i(2'd0),
    .rowstream_loader_command_payload_addr_i(32'd0),
    .rowstream_loader_wait_cycles_i(32'd0),
    .rowstream_loader_read_data_i(512'd0),
    .rowstream_top1_hidden_vector_o(),
    .rowstream_top1_start_o(),
    .rowstream_top1_status_clear_o(),
    .rowstream_top1_busy_i(1'b0),
    .rowstream_top1_done_i(1'b0),
    .rowstream_top1_error_i(1'b0),
    .rowstream_top1_token_i(32'd0),
    .rowstream_top1_score_q024_i(32'd0),
    .rowstream_top1_rows_scanned_i(32'd0),
    .rowstream_top1_cycle_count_i(32'd0),
    .rowstream_top1_debug_status_i(32'd0),
    .rowstream_top1_debug_reader_addr_i(32'd0),
    .rowstream_top1_debug_wb_ack_count_i(32'd0),
    .rowstream_top1_debug_wb_err_count_i(32'd0),
    .rowstream_top1_debug_packet_wb_write_ack_count_i(32'd0),
    .rowstream_top1_debug_packet_wb_read_ack_count_i(32'd0),
    .rowstream_mlp_selftest_present_i(1'b0),
    .rowstream_mlp_selftest_status_i(32'd0),
    .rowstream_mlp_selftest_cycle_count_i(32'd0),
    .rowstream_mlp_selftest_fail_detail_i(32'd0),
    .rowstream_mlp_selftest_fail_values_i(32'd0),
    .rowstream_mlp_selftest_first_add_sample_i(32'd0),
    .rowstream_mlp_selftest_first_requant_sample_i(32'd0),
    .rowstream_mlp_selftest_requant_debug0_i(32'd0),
    .rowstream_mlp_selftest_requant_debug1_i(32'd0),
    .rowstream_mlp_selftest_debug_select_o(),
    .rowstream_mlp_accel_activation_vector_o(),
    .rowstream_mlp_accel_residual_vector_o(),
    .rowstream_mlp_accel_start_o(),
    .rowstream_mlp_accel_clear_o(),
    .rowstream_mlp_accel_status_i(32'd0),
    .rowstream_mlp_accel_cycle_count_i(32'd0),
    .rowstream_mlp_accel_output_checksum_i(32'd0),
    .rowstream_mlp_accel_output_sample0_i(32'd0),
    .rowstream_mlp_accel_output_sample1_i(32'd0),
    .rowstream_mlp_accel_output_vector_i(512'd0),
    .rowstream_m2_full_block_input_vector_o(m2_input_vector),
    .rowstream_m2_full_block_residual_vector_o(m2_residual_vector),
    .rowstream_m2_full_block_start_o(m2_start_pulse),
    .rowstream_m2_full_block_clear_o(m2_clear_pulse),
    .rowstream_m2_full_block_status_i(m2_status),
    .rowstream_m2_full_block_cycle_count_i(m2_cycle_count),
    .rowstream_m2_full_block_output_checksum_i(m2_output_checksum),
    .rowstream_m2_full_block_output_sample0_i(m2_output_sample0),
    .rowstream_m2_full_block_output_sample1_i(m2_output_sample1),
    .rowstream_m2_full_block_output_count_i(m2_output_count),
    .rowstream_m2_full_block_debug_i(m2_debug),
    .rowstream_m2_full_block_debug1_i(m2_debug1),
    .rowstream_m2_full_block_debug2_i(m2_debug2),
    .rowstream_m2_full_block_debug3_i(m2_debug3),
    .rowstream_m2_full_block_provenance_i(m2_provenance),
    .rowstream_m2_full_block_output_hash_i(m2_output_hash),
    .rowstream_m2_full_block_output_vector_i(m2_output_vector)
  );

  assign m2_token_ids_for_accel =
    m2_start_pulse ? m2_input_vector[95:0] : m2_token_ids_for_accel_q;

  task6_m2_embedding_live_context_attention_ln2_pcie_accel_top #(
    .M2_FULL_BLOCK_TOKEN_INDEX(5),
    .ENABLE_CONTEXT_INTERNAL_CHECKS(1'b0)
  ) accel (
    .SYS_CLK(clk),
    .SYS_RSTN(rst_n),
    .pcie_token_ids_i({416'd0, m2_token_ids_for_accel}),
    .pcie_reserved_i(m2_residual_vector),
    .pcie_start_pulse_i(m2_start_pulse),
    .pcie_clear_pulse_i(m2_clear_pulse),
    .pcie_status_o(m2_status_raw),
    .pcie_cycle_count_o(m2_cycle_count_raw),
    .pcie_output_checksum_o(m2_output_checksum_raw),
    .pcie_output_sample0_o(m2_output_sample0_raw),
    .pcie_output_sample1_o(m2_output_sample1_raw),
    .pcie_output_count_o(m2_output_count_raw),
    .pcie_output_vector_o(m2_output_vector_raw),
    .pcie_debug_o(m2_debug_raw),
    .pcie_debug1_o(m2_debug1_raw),
    .pcie_debug2_o(m2_debug2_raw),
    .pcie_debug3_o(m2_debug3_raw),
    .pcie_provenance_o(m2_provenance_raw)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m2_status <= 32'd0;
      m2_cycle_count <= 32'd0;
      m2_output_checksum <= 32'd0;
      m2_output_sample0 <= 32'd0;
      m2_output_sample1 <= 32'd0;
      m2_output_count <= 32'd0;
      m2_output_vector <= 512'd0;
      m2_output_hash <= 128'd0;
      m2_debug <= 32'd0;
      m2_debug1 <= 32'd0;
      m2_debug2 <= 32'd0;
      m2_debug3 <= 32'd0;
      m2_provenance <= 32'd0;
      m2_token_ids_for_accel_q <= 96'd0;
    end else begin
      m2_token_ids_for_accel_q <= m2_input_vector[95:0];
      m2_status <= m2_status_raw;
      m2_cycle_count <= m2_cycle_count_raw;
      m2_output_checksum <= m2_output_checksum_raw;
      m2_output_sample0 <= m2_output_sample0_raw;
      m2_output_sample1 <= m2_output_sample1_raw;
      m2_output_count <= m2_output_count_raw;
      m2_output_vector <= m2_output_vector_raw;
      m2_output_hash <= 128'd0;
      m2_debug <= m2_debug_raw;
      m2_debug1 <= m2_debug1_raw;
      m2_debug2 <= m2_debug2_raw;
      m2_debug3 <= m2_debug3_raw;
      m2_provenance <= m2_provenance_raw;
    end
  end

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
      if (bresp !== 2'b00)
        $fatal(1, "FAIL: AXI write response not OKAY");
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
      if (rresp !== 2'b00)
        $fatal(1, "FAIL: AXI read response not OKAY");
      @(negedge clk);
      rready = 1'b0;
    end
  endtask

  initial begin
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
    expected_token_vector = 512'd0;
    expected_ln2_vector = 512'd0;

    repeat (8) @(negedge clk);
    rst_n = 1'b1;
    repeat (8) @(negedge clk);

    for (int index = 0; index < EMBED_BLOCK_SEQ; index++)
      expected_token_vector[index * 16 +: 16] = embed_block_expected_token_ids[index];
    for (int index = 0; index < 64; index++)
      expected_ln2_vector[index * 8 +: 8] = ln2_expected_q[index];

    axil_write(32'h50c, 32'h0);
    axil_write(32'h50c, 32'h2);
    repeat (4) @(negedge clk);

    for (int word = 0; word < 16; word++)
      axil_write(32'h540 + word * 4, expected_token_vector[word * 32 +: 32]);
    for (int word = 0; word < 16; word++)
      axil_write(32'h580 + word * 4, 32'd0);

    for (int word = 0; word < 16; word++) begin
      axil_read(32'h540 + word * 4, value);
      if (value !== expected_token_vector[word * 32 +: 32])
        $fatal(1, "FAIL: input BAR word %0d expected %08x got %08x",
               word, expected_token_vector[word * 32 +: 32], value);
      axil_read(32'h580 + word * 4, value);
      if (value !== 32'd0)
        $fatal(1, "FAIL: residual BAR word %0d expected 00000000 got %08x", word, value);
    end

    axil_write(32'h50c, 32'h0);
    axil_write(32'h50c, 32'h1);

    for (int cycle = 0; cycle < TIMEOUT_CYCLES; cycle++) begin
      @(posedge clk);
      if (m2_status[6:4] == 3'd5 || m2_status[6:4] == 3'd6)
        break;
    end
    repeat (8) @(posedge clk);

    axil_read(32'h50c, value);
    if (value[6:4] !== 3'd5 || value[3] !== 1'b1 || value[2] !== 1'b0)
      $fatal(1, "FAIL: M2.5 CDC BAR status expected DONE/no-error/output-valid got %08x", value);
    axil_read(32'h518, value);
    if (value !== LN2_EXPECTED_CHECKSUM)
      $fatal(1, "FAIL: M2.5 CDC BAR checksum expected %08x got %08x", LN2_EXPECTED_CHECKSUM, value);
    axil_read(32'h5c0, value);
    if (value !== LN2_EXPECTED_SAMPLE0)
      $fatal(1, "FAIL: M2.5 CDC BAR sample0 expected %08x got %08x", LN2_EXPECTED_SAMPLE0, value);
    axil_read(32'h5c4, value);
    if (value !== LN2_EXPECTED_SAMPLE1)
      $fatal(1, "FAIL: M2.5 CDC BAR sample1 expected %08x got %08x", LN2_EXPECTED_SAMPLE1, value);

    for (int word = 0; word < 16; word++) begin
      axil_read(32'h600 + word * 4, value);
      if (value !== expected_ln2_vector[word * 32 +: 32])
        $fatal(1, "FAIL: M2.5 CDC BAR output vector word %0d expected %08x got %08x",
               word, expected_ln2_vector[word * 32 +: 32], value);
    end

    $display(
      "PASS: task6 M2.5 attention LN2 PCIe CDC BAR sim cycles %0d ln2_checksum %08x ln2_sample0 %08x ln2_sample1 %08x debug %08x debug1 %08x debug2 %08x debug3 %08x provenance %08x",
      m2_cycle_count,
      m2_output_checksum,
      m2_output_sample0,
      m2_output_sample1,
      m2_debug,
      m2_debug1,
      m2_debug2,
      m2_debug3,
      m2_provenance
    );
    $finish;
  end
endmodule

`default_nettype wire
