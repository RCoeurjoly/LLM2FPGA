`timescale 1ns/1ps

module task6_m2_first_token_attention_out_proj_accel_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 10000;
  localparam logic [2:0] ST_DONE = 3'd4;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic start_i;
  logic [31:0] status_o;
  logic [31:0] cycle_count_o;
  logic [31:0] output_checksum_o;
  logic [31:0] output_sample0_o;
  logic [31:0] output_sample1_o;
  logic [511:0] output_vector_o;
  logic [31:0] residual_checksum_o;
  logic [31:0] residual_sample0_o;
  logic [31:0] residual_sample1_o;
  logic [511:0] residual_vector_o;
  logic [31:0] ln2_checksum_o;
  logic [31:0] ln2_sample0_o;
  logic [31:0] ln2_sample1_o;
  logic [511:0] ln2_vector_o;
  logic [31:0] debug_o;
  logic [511:0] expected_vector;
  logic [511:0] expected_residual_vector;
  logic [511:0] expected_ln2_vector;
  logic [511:0] external_context_vector_i;
  logic [511:0] external_block_input_vector_i;
  integer cycles;
  integer i;

  task6_m2_first_token_attention_out_proj_accel_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(start_i),
    .use_external_context_i(1'b1),
    .external_context_vector_i(external_context_vector_i),
    .use_external_block_input_i(1'b1),
    .external_block_input_vector_i(external_block_input_vector_i),
    .status_o(status_o),
    .cycle_count_o(cycle_count_o),
    .output_checksum_o(output_checksum_o),
    .output_sample0_o(output_sample0_o),
    .output_sample1_o(output_sample1_o),
    .output_vector_o(output_vector_o),
    .residual_checksum_o(residual_checksum_o),
    .residual_sample0_o(residual_sample0_o),
    .residual_sample1_o(residual_sample1_o),
    .residual_vector_o(residual_vector_o),
    .ln2_checksum_o(ln2_checksum_o),
    .ln2_sample0_o(ln2_sample0_o),
    .ln2_sample1_o(ln2_sample1_o),
    .ln2_vector_o(ln2_vector_o),
    .debug_o(debug_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    start_i = 1'b0;
    expected_vector = 512'd0;
    expected_residual_vector = 512'd0;
    expected_ln2_vector = 512'd0;
    external_context_vector_i = 512'd0;
    external_block_input_vector_i = 512'd0;
    cycles = 0;

    for (i = 0; i < OUT_PROJ_DIM; i = i + 1) begin
      expected_vector[i * 8 +: 8] = out_proj_expected_q[i];
      expected_residual_vector[i * 8 +: 8] = attn_residual_expected_q[i];
      expected_ln2_vector[i * 8 +: 8] = ln2_expected_q[i];
      external_context_vector_i[i * 8 +: 8] = out_proj_context_q[i];
      external_block_input_vector_i[i * 8 +: 8] = out_proj_block_input_q[i];
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);
    start_i = 1'b1;
    @(posedge SYS_CLK);
    start_i = 1'b0;

    while (cycles < TIMEOUT_CYCLES) begin
      @(posedge SYS_CLK);
      cycles = cycles + 1;

      if (status_o[2]) begin
        $fatal(
          1,
          "FAIL: task6 M2 first-token attention out projection error status=%08x debug=%08x",
          status_o,
          debug_o
        );
      end

      if (status_o[6:4] == ST_DONE && status_o[3]) begin
        if (output_checksum_o !== OUT_PROJ_EXPECTED_CHECKSUM) begin
          $fatal(
            1,
            "FAIL: checksum expected %08x got %08x",
            OUT_PROJ_EXPECTED_CHECKSUM,
            output_checksum_o
          );
        end
        if (output_sample0_o !== OUT_PROJ_EXPECTED_SAMPLE0) begin
          $fatal(
            1,
            "FAIL: sample0 expected %08x got %08x",
            OUT_PROJ_EXPECTED_SAMPLE0,
            output_sample0_o
          );
        end
        if (output_sample1_o !== OUT_PROJ_EXPECTED_SAMPLE1) begin
          $fatal(
            1,
            "FAIL: sample1 expected %08x got %08x",
            OUT_PROJ_EXPECTED_SAMPLE1,
            output_sample1_o
          );
        end
        if (output_vector_o !== expected_vector) begin
          $fatal(1, "FAIL: output vector mismatch");
        end
        if (residual_checksum_o !== ATTN_RESIDUAL_EXPECTED_CHECKSUM) begin
          $fatal(
            1,
            "FAIL: residual checksum expected %08x got %08x",
            ATTN_RESIDUAL_EXPECTED_CHECKSUM,
            residual_checksum_o
          );
        end
        if (residual_sample0_o !== ATTN_RESIDUAL_EXPECTED_SAMPLE0) begin
          $fatal(
            1,
            "FAIL: residual sample0 expected %08x got %08x",
            ATTN_RESIDUAL_EXPECTED_SAMPLE0,
            residual_sample0_o
          );
        end
        if (residual_sample1_o !== ATTN_RESIDUAL_EXPECTED_SAMPLE1) begin
          $fatal(
            1,
            "FAIL: residual sample1 expected %08x got %08x",
            ATTN_RESIDUAL_EXPECTED_SAMPLE1,
            residual_sample1_o
          );
        end
        if (residual_vector_o !== expected_residual_vector) begin
          $fatal(1, "FAIL: residual vector mismatch");
        end
        if (ln2_checksum_o !== LN2_EXPECTED_CHECKSUM) begin
          $fatal(
            1,
            "FAIL: ln2 checksum expected %08x got %08x",
            LN2_EXPECTED_CHECKSUM,
            ln2_checksum_o
          );
        end
        if (ln2_sample0_o !== LN2_EXPECTED_SAMPLE0) begin
          $fatal(
            1,
            "FAIL: ln2 sample0 expected %08x got %08x",
            LN2_EXPECTED_SAMPLE0,
            ln2_sample0_o
          );
        end
        if (ln2_sample1_o !== LN2_EXPECTED_SAMPLE1) begin
          $fatal(
            1,
            "FAIL: ln2 sample1 expected %08x got %08x",
            LN2_EXPECTED_SAMPLE1,
            ln2_sample1_o
          );
        end
        if (ln2_vector_o !== expected_ln2_vector) begin
          $fatal(1, "FAIL: ln2 vector mismatch");
        end
        $display(
          "PASS: task6 M2 first-token attention out projection cycles %0d checksum %08x sample0 %08x sample1 %08x residual_checksum %08x residual_sample0 %08x residual_sample1 %08x ln2_checksum %08x ln2_sample0 %08x ln2_sample1 %08x",
          cycle_count_o,
          output_checksum_o,
          output_sample0_o,
          output_sample1_o,
          residual_checksum_o,
          residual_sample0_o,
          residual_sample1_o,
          ln2_checksum_o,
          ln2_sample0_o,
          ln2_sample1_o
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 M2 first-token attention out projection done");
  end
endmodule
