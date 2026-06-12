`timescale 1ns/1ps

module task6_m2_ln_attn_sublane_accel_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 10000;
  localparam logic [2:0] M2_DONE = 3'd5;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [511:0] pcie_block_input_i;
  logic [511:0] pcie_residual_after_attention_i;
  logic pcie_start_pulse_i;
  logic pcie_clear_pulse_i;
  logic [31:0] pcie_status_o;
  logic [31:0] pcie_cycle_count_o;
  logic [31:0] pcie_output_checksum_o;
  logic [31:0] pcie_output_sample0_o;
  logic [31:0] pcie_output_sample1_o;
  logic [31:0] pcie_output_count_o;
  logic [511:0] pcie_output_vector_o;
  logic [31:0] pcie_debug_o;
  logic [511:0] expected_output_vector;
  logic [31:0] expected_checksum;
  logic [31:0] expected_sample0;
  logic [31:0] expected_sample1;
  integer cycles;
  integer i;

  task6_m2_ln_attn_sublane_accel_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .pcie_block_input_i(pcie_block_input_i),
    .pcie_residual_after_attention_i(pcie_residual_after_attention_i),
    .pcie_start_pulse_i(pcie_start_pulse_i),
    .pcie_clear_pulse_i(pcie_clear_pulse_i),
    .pcie_status_o(pcie_status_o),
    .pcie_cycle_count_o(pcie_cycle_count_o),
    .pcie_output_checksum_o(pcie_output_checksum_o),
    .pcie_output_sample0_o(pcie_output_sample0_o),
    .pcie_output_sample1_o(pcie_output_sample1_o),
    .pcie_output_count_o(pcie_output_count_o),
    .pcie_output_vector_o(pcie_output_vector_o),
    .pcie_debug_o(pcie_debug_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    pcie_block_input_i = 512'd0;
    pcie_residual_after_attention_i = 512'd0;
    pcie_start_pulse_i = 1'b0;
    pcie_clear_pulse_i = 1'b0;
    expected_output_vector = 512'd0;
    expected_checksum = 32'd0;
    expected_sample0 = 32'd0;
    expected_sample1 = 32'd0;
    cycles = 0;

    for (i = 0; i < 32; i = i + 1) begin
      pcie_block_input_i[i * 16 +: 16] = ln_input_q12[i];
    end
    for (i = 0; i < 32; i = i + 1) begin
      pcie_residual_after_attention_i[i * 16 +: 16] = ln_input_q12[i + 32];
    end
    for (i = 0; i < 64; i = i + 1) begin
      expected_output_vector[i * 8 +: 8] = ln_expected_q[i];
      expected_checksum =
        expected_checksum + ({24'd0, ln_expected_q[i][7:0]} * (i + 1));
      if (i < 4) begin
        expected_sample0 =
          expected_sample0 | ({24'd0, ln_expected_q[i][7:0]} << (8 * i));
      end else if (i < 8) begin
        expected_sample1 =
          expected_sample1 | ({24'd0, ln_expected_q[i][7:0]} << (8 * (i - 4)));
      end
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);
    pcie_start_pulse_i = 1'b1;
    @(posedge SYS_CLK);
    pcie_start_pulse_i = 1'b0;

    while (cycles < TIMEOUT_CYCLES) begin
      @(posedge SYS_CLK);
      cycles = cycles + 1;

      if (pcie_status_o[2]) begin
        $fatal(
          1,
          "FAIL: task6 M2 ln attn sublane accel entered error status=%08x debug=%08x",
          pcie_status_o,
          pcie_debug_o
        );
      end

      if (pcie_status_o[6:4] == M2_DONE && pcie_status_o[3]) begin
        if (pcie_output_count_o !== 32'd64) begin
          $fatal(1, "FAIL: output_count expected 64 got %0d", pcie_output_count_o);
        end
        if (pcie_output_checksum_o !== expected_checksum) begin
          $fatal(
            1,
            "FAIL: checksum expected %08x got %08x",
            expected_checksum,
            pcie_output_checksum_o
          );
        end
        if (pcie_output_sample0_o !== expected_sample0) begin
          $fatal(
            1,
            "FAIL: sample0 expected %08x got %08x",
            expected_sample0,
            pcie_output_sample0_o
          );
        end
        if (pcie_output_sample1_o !== expected_sample1) begin
          $fatal(
            1,
            "FAIL: sample1 expected %08x got %08x",
            expected_sample1,
            pcie_output_sample1_o
          );
        end
        if (pcie_output_vector_o !== expected_output_vector) begin
          $fatal(1, "FAIL: output vector mismatch");
        end
        $display(
          "PASS: task6 M2 ln attn sublane accel cycles %0d checksum %08x sample0 %08x sample1 %08x",
          pcie_cycle_count_o,
          pcie_output_checksum_o,
          pcie_output_sample0_o,
          pcie_output_sample1_o
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 M2 ln attn sublane accel done");
  end
endmodule
