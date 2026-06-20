`timescale 1ns/1ps
`default_nettype none

module task6_m2_embedding_handoff_pcie_bar_tb;
  `include "task6_m2_embedding_block_input_tb_data.sv"

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
  wire [31:0] m2_status;
  wire [31:0] m2_cycle_count;
  wire [31:0] m2_output_checksum;
  wire [31:0] m2_output_sample0;
  wire [31:0] m2_output_sample1;
  wire [31:0] m2_output_count;
  wire [127:0] m2_output_hash;
  wire [31:0] m2_debug;
  wire [31:0] m2_debug1;
  wire [31:0] m2_debug2;
  wire [31:0] m2_debug3;
  wire [31:0] m2_provenance;
  wire [511:0] m2_output_vector;

  logic [511:0] expected_token_vector;
  logic [511:0] expected_output_vector;
  logic [127:0] expected_output_hash;
  logic [31:0] expected_block_input_checksum;
  logic [31:0] expected_ln_input_checksum;
  logic [31:0] value;

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
    .command_payload_o(),
    .command_event_o(),
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
    .status_clear_pulse_o(),
    .top1_hidden_vector_o(),
    .top1_start_pulse_o(),
    .top1_status_clear_pulse_o(),
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
    .mlp_selftest_debug_select_o(),
    .mlp_accel_activation_vector_o(),
    .mlp_accel_residual_vector_o(),
    .mlp_accel_start_pulse_o(),
    .mlp_accel_clear_pulse_o(),
    .mlp_accel_status_i(32'd0),
    .mlp_accel_cycle_count_i(32'd0),
    .mlp_accel_output_checksum_i(32'd0),
    .mlp_accel_output_sample0_i(32'd0),
    .mlp_accel_output_sample1_i(32'd0),
    .mlp_accel_output_vector_i(512'd0),
    .m2_full_block_input_vector_o(m2_input_vector),
    .m2_full_block_residual_vector_o(m2_residual_vector),
    .m2_full_block_start_pulse_o(m2_start_pulse),
    .m2_full_block_clear_pulse_o(m2_clear_pulse),
    .m2_full_block_status_i(m2_status),
    .m2_full_block_cycle_count_i(m2_cycle_count),
    .m2_full_block_output_checksum_i(m2_output_checksum),
    .m2_full_block_output_sample0_i(m2_output_sample0),
    .m2_full_block_output_sample1_i(m2_output_sample1),
    .m2_full_block_output_count_i(m2_output_count),
    .m2_full_block_debug_i(m2_debug),
    .m2_full_block_debug1_i(m2_debug1),
    .m2_full_block_debug2_i(m2_debug2),
    .m2_full_block_debug3_i(m2_debug3),
    .m2_full_block_provenance_i(m2_provenance),
    .m2_full_block_output_hash_i(m2_output_hash),
    .m2_full_block_output_vector_i(m2_output_vector)
  );

  task6_m2_embedding_handoff_pcie_accel_top #(
    .M2_FULL_BLOCK_TOKEN_INDEX(EMBED_BLOCK_SEQ - 1)
  ) handoff (
    .SYS_CLK(clk),
    .SYS_RSTN(rst_n),
    .pcie_token_ids_i(m2_input_vector),
    .pcie_reserved_i(m2_residual_vector),
    .pcie_start_pulse_i(m2_start_pulse),
    .pcie_clear_pulse_i(m2_clear_pulse),
    .pcie_status_o(m2_status),
    .pcie_cycle_count_o(m2_cycle_count),
    .pcie_output_checksum_o(m2_output_checksum),
    .pcie_output_sample0_o(m2_output_sample0),
    .pcie_output_sample1_o(m2_output_sample1),
    .pcie_output_count_o(m2_output_count),
    .pcie_output_vector_o(m2_output_vector),
    .pcie_output_hash_o(m2_output_hash),
    .pcie_debug_o(m2_debug),
    .pcie_debug1_o(m2_debug1),
    .pcie_debug2_o(m2_debug2),
    .pcie_debug3_o(m2_debug3),
    .pcie_provenance_o(m2_provenance)
  );

  always #5 clk = ~clk;

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

  function automatic logic [31:0] checksum_bytes(input logic [511:0] vec);
    logic [31:0] acc;
    begin
      acc = 32'd0;
      for (int i = 0; i < 64; i++)
        acc = acc + ({24'd0, vec[i * 8 +: 8]} * (i + 1));
      checksum_bytes = acc;
    end
  endfunction

  function automatic logic [127:0] vector_hash128(input logic [511:0] vector);
    logic [31:0] h0;
    logic [31:0] h1;
    logic [31:0] h2;
    logic [31:0] h3;
    logic [7:0] byte_value;
    logic [31:0] index_mix;
    begin
      h0 = 32'h811c9dc5;
      h1 = 32'h9e3779b9;
      h2 = 32'h85ebca6b;
      h3 = 32'hc2b2ae35;
      for (int index = 0; index < 64; index++) begin
        byte_value = vector[index * 8 +: 8];
        index_mix = 32'(index);
        h0 = {h0[26:0], h0[31:27]} ^ {24'd0, byte_value} ^ (32'h9e3779b9 + index_mix);
        h1 = {h1[6:0], h1[31:7]} + ({16'd0, byte_value, 8'd0} ^ (32'h85ebca6b + index_mix));
        h2 = {h2[28:0], h2[31:29]} ^ ({8'd0, byte_value, 16'd0} + 32'hc2b2ae35 + index_mix);
        h3 = h3 + ({24'd0, byte_value} ^ {index_mix[15:0], index_mix[15:0]} ^ {byte_value, byte_value, byte_value, byte_value});
      end
      vector_hash128 = {h3, h2, h1, h0};
    end
  endfunction

  function automatic logic [31:0] checksum_q12_all_tokens;
    logic [31:0] acc;
    logic signed [15:0] sample;
    begin
      acc = 32'd0;
      for (int token = 0; token < EMBED_BLOCK_SEQ; token++) begin
        for (int i = 0; i < EMBED_BLOCK_DIM; i++) begin
          sample = embed_block_expected_ln_input_q12_by_token[token][i];
          acc = acc + ({16'd0, sample} * ((token * EMBED_BLOCK_DIM) + i + 1));
        end
      end
      checksum_q12_all_tokens = acc;
    end
  endfunction

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
    expected_output_vector = 512'd0;

    repeat (8) @(negedge clk);
    rst_n = 1'b1;
    repeat (4) @(negedge clk);

    for (int i = 0; i < EMBED_BLOCK_SEQ; i++)
      expected_token_vector[i * 16 +: 16] = embed_block_expected_token_ids[i];
    for (int i = 0; i < EMBED_BLOCK_DIM; i++)
      expected_output_vector[i * 8 +: 8] = embed_block_expected_last_input_q[i];
    expected_output_hash = vector_hash128(expected_output_vector);
    expected_block_input_checksum = checksum_bytes(expected_output_vector);
    expected_ln_input_checksum = checksum_q12_all_tokens();

    for (int word = 0; word < 16; word++)
      axil_write(32'h540 + word * 4, expected_token_vector[word * 32 +: 32]);

    axil_write(32'h50c, 32'h1);
    for (int cycles = 0; cycles < 5000; cycles++) begin
      axil_read(32'h50c, value);
      if (value[6:4] == 3'd5 || value[6:4] == 3'd6)
        break;
    end

    if (value[6:4] !== 3'd5)
      $fatal(1, "FAIL: M2.3 BAR handoff status expected DONE got %08x", value);
    if (value[3] !== 1'b1)
      $fatal(1, "FAIL: M2.3 BAR handoff output_valid not set: %08x", value);

    axil_read(32'h518, value);
    if (value !== expected_block_input_checksum)
      $fatal(1, "FAIL: M2.3 BAR checksum expected %08x got %08x", expected_block_input_checksum, value);
    axil_read(32'h5c8, value);
    if (value !== expected_ln_input_checksum)
      $fatal(1, "FAIL: M2.3 BAR LN checksum expected %08x got %08x", expected_ln_input_checksum, value);
    axil_read(32'h5cc, value);
    if (value !== expected_block_input_checksum)
      $fatal(1, "FAIL: M2.3 BAR debug1 expected %08x got %08x", expected_block_input_checksum, value);

    for (int word = 0; word < 4; word++) begin
      axil_read(32'h640 + word * 4, value);
      if (value !== expected_output_hash[word * 32 +: 32])
        $fatal(1, "FAIL: M2.3 BAR output hash word %0d expected %08x got %08x",
               word, expected_output_hash[word * 32 +: 32], value);
    end

    for (int word = 0; word < 16; word++) begin
      axil_read(32'h600 + word * 4, value);
      if (value !== expected_output_vector[word * 32 +: 32])
        $fatal(1, "FAIL: M2.3 BAR output vector word %0d expected %08x got %08x",
               word, expected_output_vector[word * 32 +: 32], value);
    end

    $display("PASS: task6 M2.3 embedding handoff PCIe BAR sim cycles %0d block_input_checksum %08x ln_input_checksum %08x",
             m2_cycle_count, expected_block_input_checksum, expected_ln_input_checksum);
    $finish;
  end
endmodule

`default_nettype wire
