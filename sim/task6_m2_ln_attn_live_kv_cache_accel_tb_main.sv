`timescale 1ns/1ps

module task6_m2_ln_attn_live_kv_cache_accel_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 40000;
  localparam logic [2:0] S_DONE = 3'd6;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic start_i;
  logic clear_i;
  logic [31:0] status_o;
  logic [31:0] cycle_count_o;
  logic [31:0] output_checksum_o;
  logic [31:0] output_sample0_o;
  logic [31:0] output_sample1_o;
  logic [511:0] output_vector_o;
  logic [31:0] debug_o;
  logic [511:0] expected_output_vector;
  logic [31:0] expected_checksum;
  logic [31:0] expected_sample0;
  logic [31:0] expected_sample1;
  integer cycles;
  integer i;

  task6_m2_ln_attn_live_kv_cache_accel_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(start_i),
    .clear_i(clear_i),
    .status_o(status_o),
    .cycle_count_o(cycle_count_o),
    .output_checksum_o(output_checksum_o),
    .output_sample0_o(output_sample0_o),
    .output_sample1_o(output_sample1_o),
    .output_vector_o(output_vector_o),
    .debug_o(debug_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    start_i = 1'b0;
    clear_i = 1'b0;
    expected_output_vector = 512'd0;
    expected_checksum = 32'd0;
    expected_sample0 = 32'd0;
    expected_sample1 = 32'd0;
    cycles = 0;

    for (i = 0; i < ATTN_HEAD_DIM; i = i + 1) begin
      expected_output_vector[i * 8 +: 8] = attn_expected_value_q[i];
      expected_checksum =
        expected_checksum + ({24'd0, attn_expected_value_q[i][7:0]} * (i + 1));
      if (i < 4) begin
        expected_sample0 =
          expected_sample0 | ({24'd0, attn_expected_value_q[i][7:0]} << (8 * i));
      end else if (i < 8) begin
        expected_sample1 =
          expected_sample1 | ({24'd0, attn_expected_value_q[i][7:0]} << (8 * (i - 4)));
      end
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
          "FAIL: task6 M2 live-kv-cache accel entered error status=%08x debug=%08x",
          status_o,
          debug_o
        );
      end

      if (status_o[6:4] == S_DONE && status_o[3]) begin
        if (output_checksum_o !== expected_checksum) begin
          $fatal(
            1,
            "FAIL: checksum expected %08x got %08x",
            expected_checksum,
            output_checksum_o
          );
        end
        if (output_sample0_o !== expected_sample0) begin
          $fatal(
            1,
            "FAIL: sample0 expected %08x got %08x",
            expected_sample0,
            output_sample0_o
          );
        end
        if (output_sample1_o !== expected_sample1) begin
          $fatal(
            1,
            "FAIL: sample1 expected %08x got %08x",
            expected_sample1,
            output_sample1_o
          );
        end
        if (output_vector_o !== expected_output_vector) begin
          $fatal(1, "FAIL: output vector mismatch");
        end
        $display(
          "PASS: task6 M2 ln attn live-kv-cache accel cycles %0d checksum %08x sample0 %08x sample1 %08x",
          cycle_count_o,
          output_checksum_o,
          output_sample0_o,
          output_sample1_o
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 M2 ln attn live-kv-cache accel done");
  end
endmodule
