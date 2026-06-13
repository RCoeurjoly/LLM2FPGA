`timescale 1ns/1ps

module task6_m2_first_token_mlp_c_fc_gelu_accel_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 30000;
  localparam logic [2:0] ST_DONE = 3'd3;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic start_i;
  logic [31:0] status_o;
  logic [31:0] cycle_count_o;
  logic [31:0] post_gelu_checksum_o;
  logic [31:0] post_gelu_sample0_o;
  logic [31:0] post_gelu_sample1_o;
  logic [511:0] post_gelu_first64_vector_o;
  logic [31:0] debug_o;
  logic [511:0] expected_first64_vector;
  integer cycles;
  integer i;

  task6_m2_first_token_mlp_c_fc_gelu_accel_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(start_i),
    .status_o(status_o),
    .cycle_count_o(cycle_count_o),
    .post_gelu_checksum_o(post_gelu_checksum_o),
    .post_gelu_sample0_o(post_gelu_sample0_o),
    .post_gelu_sample1_o(post_gelu_sample1_o),
    .post_gelu_first64_vector_o(post_gelu_first64_vector_o),
    .debug_o(debug_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    start_i = 1'b0;
    expected_first64_vector = 512'd0;
    cycles = 0;

    for (i = 0; i < 64; i = i + 1) begin
      expected_first64_vector[i * 8 +: 8] = mlp_post_gelu_q[i];
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
          "FAIL: task6 M2 first-token MLP c_fc GELU error status=%08x debug=%08x",
          status_o,
          debug_o
        );
      end

      if (status_o[6:4] == ST_DONE && status_o[3]) begin
        if (post_gelu_checksum_o !== MLP_POST_GELU_EXPECTED_CHECKSUM) begin
          $fatal(
            1,
            "FAIL: post_gelu checksum expected %08x got %08x",
            MLP_POST_GELU_EXPECTED_CHECKSUM,
            post_gelu_checksum_o
          );
        end
        if (post_gelu_sample0_o !== MLP_POST_GELU_EXPECTED_SAMPLE0) begin
          $fatal(
            1,
            "FAIL: post_gelu sample0 expected %08x got %08x",
            MLP_POST_GELU_EXPECTED_SAMPLE0,
            post_gelu_sample0_o
          );
        end
        if (post_gelu_sample1_o !== MLP_POST_GELU_EXPECTED_SAMPLE1) begin
          $fatal(
            1,
            "FAIL: post_gelu sample1 expected %08x got %08x",
            MLP_POST_GELU_EXPECTED_SAMPLE1,
            post_gelu_sample1_o
          );
        end
        if (post_gelu_first64_vector_o !== expected_first64_vector) begin
          $fatal(1, "FAIL: post_gelu first64 vector mismatch");
        end
        $display(
          "PASS: task6 M2 first-token MLP c_fc GELU cycles %0d post_gelu_checksum %08x post_gelu_sample0 %08x post_gelu_sample1 %08x",
          cycle_count_o,
          post_gelu_checksum_o,
          post_gelu_sample0_o,
          post_gelu_sample1_o
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 M2 first-token MLP c_fc GELU done");
  end
endmodule
