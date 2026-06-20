`timescale 1ns/1ps

module task6_m2_embedding_handoff_pcie_accel_tb;
  `include "task6_m2_embedding_block_input_tb_data.sv"

  localparam int TIMEOUT_CYCLES = 20000;
  localparam logic [2:0] M2_IDLE = 3'd0;
  localparam logic [2:0] M2_DONE = 3'd5;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [511:0] pcie_token_ids_i;
  logic [511:0] pcie_reserved_i;
  logic pcie_start_pulse_i;
  logic pcie_clear_pulse_i;
  logic [31:0] pcie_status_o;
  logic [31:0] pcie_cycle_count_o;
  logic [31:0] pcie_output_checksum_o;
  logic [31:0] pcie_output_sample0_o;
  logic [31:0] pcie_output_sample1_o;
  logic [31:0] pcie_output_count_o;
  logic [511:0] pcie_output_vector_o;
  logic [127:0] pcie_output_hash_o;
  logic [31:0] pcie_debug_o;
  logic [31:0] pcie_debug1_o;
  logic [31:0] pcie_debug2_o;
  logic [31:0] pcie_debug3_o;
  logic [31:0] pcie_provenance_o;

  logic [31:0] expected_block_input_checksum;
  logic [31:0] expected_ln_input_checksum;
  logic [511:0] expected_block_input_vector;
  logic [31:0] checked_cycle_count;
  logic [31:0] checked_block_input_checksum;
  logic [31:0] checked_ln_input_checksum;
  logic [31:0] checked_debug3;
  logic [31:0] checked_provenance;

  function automatic logic [2:0] status_state(input logic [31:0] status);
    begin
      status_state = status[6:4];
    end
  endfunction

  task automatic pulse_start;
    begin
      pcie_start_pulse_i = 1'b1;
      @(posedge SYS_CLK);
      pcie_start_pulse_i = 1'b0;
    end
  endtask

  task automatic pulse_clear;
    begin
      pcie_clear_pulse_i = 1'b1;
      @(posedge SYS_CLK);
      pcie_clear_pulse_i = 1'b0;
    end
  endtask

  task automatic wait_done;
    int cycles;
    begin
      cycles = 0;
      while (cycles < TIMEOUT_CYCLES) begin
        @(posedge SYS_CLK);
        cycles = cycles + 1;
        if (pcie_status_o[2]) begin
          $fatal(1, "FAIL: embedding handoff wrapper entered error status=%08x debug=%08x", pcie_status_o, pcie_debug_o);
        end
        if (status_state(pcie_status_o) == M2_DONE && pcie_status_o[3]) begin
          return;
        end
      end
      $fatal(1, "Timeout waiting for embedding handoff wrapper done status=%08x debug=%08x", pcie_status_o, pcie_debug_o);
    end
  endtask

  task6_m2_embedding_handoff_pcie_accel_top #(
    .M2_FULL_BLOCK_TOKEN_INDEX(5)
  ) dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .pcie_token_ids_i(pcie_token_ids_i),
    .pcie_reserved_i(pcie_reserved_i),
    .pcie_start_pulse_i(pcie_start_pulse_i),
    .pcie_clear_pulse_i(pcie_clear_pulse_i),
    .pcie_status_o(pcie_status_o),
    .pcie_cycle_count_o(pcie_cycle_count_o),
    .pcie_output_checksum_o(pcie_output_checksum_o),
    .pcie_output_sample0_o(pcie_output_sample0_o),
    .pcie_output_sample1_o(pcie_output_sample1_o),
    .pcie_output_count_o(pcie_output_count_o),
    .pcie_output_vector_o(pcie_output_vector_o),
    .pcie_output_hash_o(pcie_output_hash_o),
    .pcie_debug_o(pcie_debug_o),
    .pcie_debug1_o(pcie_debug1_o),
    .pcie_debug2_o(pcie_debug2_o),
    .pcie_debug3_o(pcie_debug3_o),
    .pcie_provenance_o(pcie_provenance_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    pcie_token_ids_i = 512'd0;
    pcie_reserved_i = 512'd0;
    pcie_start_pulse_i = 1'b0;
    pcie_clear_pulse_i = 1'b0;
    expected_block_input_checksum = 32'd0;
    expected_ln_input_checksum = 32'd0;
    expected_block_input_vector = 512'd0;
    checked_cycle_count = 32'd0;
    checked_block_input_checksum = 32'd0;
    checked_ln_input_checksum = 32'd0;
    checked_debug3 = 32'd0;
    checked_provenance = 32'd0;

    for (int token = 0; token < EMBED_BLOCK_SEQ; token = token + 1) begin
      pcie_token_ids_i[token * 16 +: 16] = embed_block_expected_token_ids[token];
    end
    for (int dim = 0; dim < EMBED_BLOCK_DIM; dim = dim + 1) begin
      expected_block_input_vector[dim * 8 +: 8] = embed_block_expected_last_input_q[dim];
      expected_block_input_checksum =
        expected_block_input_checksum + ({24'd0, embed_block_expected_last_input_q[dim][7:0]} * (dim + 1));
    end
    for (int token = 0; token < EMBED_BLOCK_SEQ; token = token + 1) begin
      for (int dim = 0; dim < EMBED_BLOCK_DIM; dim = dim + 1) begin
        expected_ln_input_checksum =
          expected_ln_input_checksum +
          ({16'd0, embed_block_expected_ln_input_q12_by_token[token][dim][15:0]} *
            ((token * EMBED_BLOCK_DIM) + dim + 1));
      end
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);

    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0] || pcie_status_o[1]) begin
      $fatal(1, "FAIL: initial status expected idle/ready got %08x", pcie_status_o);
    end

    pulse_start();
    wait_done();

    if (pcie_status_o[31:16] !== 16'h4d32) begin
      $fatal(1, "FAIL: status magic expected 4d32 got %04x", pcie_status_o[31:16]);
    end
    if (pcie_output_checksum_o !== expected_block_input_checksum) begin
      $fatal(1, "FAIL: block input checksum expected %08x got %08x", expected_block_input_checksum, pcie_output_checksum_o);
    end
    if (pcie_debug_o !== expected_ln_input_checksum) begin
      $fatal(1, "FAIL: LN input checksum expected %08x got %08x", expected_ln_input_checksum, pcie_debug_o);
    end
    if (pcie_debug3_o !== {expected_block_input_checksum[15:0], expected_ln_input_checksum[15:0]}) begin
      $fatal(1, "FAIL: debug3 expected %08x got %08x", {expected_block_input_checksum[15:0], expected_ln_input_checksum[15:0]}, pcie_debug3_o);
    end
    if (pcie_output_vector_o !== expected_block_input_vector) begin
      $fatal(1, "FAIL: block input output vector mismatch");
    end
    if (pcie_output_count_o !== 32'd64) begin
      $fatal(1, "FAIL: output count expected 64 got %0d", pcie_output_count_o);
    end
    if (pcie_provenance_o !== 32'h4d32_3105) begin
      $fatal(1, "FAIL: provenance expected 4d323105 got %08x", pcie_provenance_o);
    end
    checked_cycle_count = pcie_cycle_count_o;
    checked_block_input_checksum = pcie_output_checksum_o;
    checked_ln_input_checksum = pcie_debug_o;
    checked_debug3 = pcie_debug3_o;
    checked_provenance = pcie_provenance_o;

    pulse_clear();
    repeat (4) @(posedge SYS_CLK);
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0] || pcie_status_o[1]) begin
      $fatal(1, "FAIL: post-clear status expected idle/ready got %08x", pcie_status_o);
    end

    $display(
      "PASS: task6 M2 embedding handoff PCIe wrapper cycles %0d block_input_checksum %08x ln_input_checksum %08x debug3 %08x provenance %08x",
      checked_cycle_count,
      checked_block_input_checksum,
      checked_ln_input_checksum,
      checked_debug3,
      checked_provenance
    );
    $finish;
  end
endmodule
