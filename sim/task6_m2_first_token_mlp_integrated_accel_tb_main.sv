`timescale 1ns/1ps

module task6_m2_first_token_mlp_integrated_accel_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 40000;
  localparam logic [2:0] ST_DONE = 3'd7;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic start_i;
  logic [31:0] status_o;
  logic [31:0] cycle_count_o;
  logic [31:0] post_gelu_checksum_o;
  logic [31:0] c_proj_checksum_o;
  logic [31:0] final_checksum_o;
  logic [31:0] final_sample0_o;
  logic [31:0] final_sample1_o;
  logic [511:0] final_vector_o;
  logic [31:0] debug_o;
  logic [511:0] expected_final_vector;
  integer cycles;
  integer i;

  task6_m2_first_token_mlp_integrated_accel_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(start_i),
    .use_external_ln2_i(1'b0),
    .external_ln2_vector_i(512'd0),
    .use_external_residual_i(1'b0),
    .external_residual_vector_i(512'd0),
    .status_o(status_o),
    .cycle_count_o(cycle_count_o),
    .post_gelu_checksum_o(post_gelu_checksum_o),
    .c_proj_checksum_o(c_proj_checksum_o),
    .final_checksum_o(final_checksum_o),
    .final_sample0_o(final_sample0_o),
    .final_sample1_o(final_sample1_o),
    .final_vector_o(final_vector_o),
    .debug_o(debug_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    start_i = 1'b0;
    expected_final_vector = 512'd0;
    cycles = 0;

    for (i = 0; i < MLP_C_PROJ_OUT_DIM; i = i + 1) begin
      expected_final_vector[i * 8 +: 8] = mlp_final_expected_q[i];
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
          "FAIL: task6 M2 first-token integrated MLP error status=%08x debug=%08x",
          status_o,
          debug_o
        );
      end

      if (status_o[6:4] == ST_DONE && status_o[3]) begin
        if (post_gelu_checksum_o !== MLP_POST_GELU_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: post_gelu checksum expected %08x got %08x", MLP_POST_GELU_EXPECTED_CHECKSUM, post_gelu_checksum_o);
        end
        if (c_proj_checksum_o !== MLP_C_PROJ_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: c_proj checksum expected %08x got %08x", MLP_C_PROJ_EXPECTED_CHECKSUM, c_proj_checksum_o);
        end
        if (final_checksum_o !== MLP_FINAL_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: final checksum expected %08x got %08x", MLP_FINAL_EXPECTED_CHECKSUM, final_checksum_o);
        end
        if (final_sample0_o !== MLP_FINAL_EXPECTED_SAMPLE0) begin
          $fatal(1, "FAIL: final sample0 expected %08x got %08x", MLP_FINAL_EXPECTED_SAMPLE0, final_sample0_o);
        end
        if (final_sample1_o !== MLP_FINAL_EXPECTED_SAMPLE1) begin
          $fatal(1, "FAIL: final sample1 expected %08x got %08x", MLP_FINAL_EXPECTED_SAMPLE1, final_sample1_o);
        end
        if (final_vector_o !== expected_final_vector) begin
          $fatal(1, "FAIL: final vector mismatch");
        end
        $display(
          "PASS: task6 M2 first-token integrated MLP cycles %0d post_gelu_checksum %08x c_proj_checksum %08x final_checksum %08x final_sample0 %08x final_sample1 %08x",
          cycle_count_o,
          post_gelu_checksum_o,
          c_proj_checksum_o,
          final_checksum_o,
          final_sample0_o,
          final_sample1_o
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 M2 first-token integrated MLP done");
  end
endmodule
