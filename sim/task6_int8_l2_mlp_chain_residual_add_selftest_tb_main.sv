`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_selftest_tb;
  localparam int TIMEOUT_CYCLES = 100000;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [2:0] led_3bits_tri_o;
  logic [31:0] pcie_status_o;
  logic [31:0] pcie_cycle_count_o;
  logic [31:0] pcie_fail_detail_o;
  logic [31:0] pcie_fail_values_o;
  logic [31:0] pcie_first_add_sample_o;
  logic [31:0] pcie_first_requant_sample_o;
  logic [31:0] pcie_accel_status_o;
  logic [31:0] pcie_accel_cycle_count_o;
  logic [31:0] pcie_accel_output_checksum_o;
  logic [31:0] pcie_accel_output_sample0_o;
  logic [31:0] pcie_accel_output_sample1_o;
  logic [511:0] pcie_accel_output_vector_o;
  integer cycles;

  task6_int8_l2_mlp_chain_residual_add_selftest_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .led_3bits_tri_o(led_3bits_tri_o),
    .pcie_status_o(pcie_status_o),
    .pcie_cycle_count_o(pcie_cycle_count_o),
    .pcie_fail_detail_o(pcie_fail_detail_o),
    .pcie_fail_values_o(pcie_fail_values_o),
    .pcie_first_add_sample_o(pcie_first_add_sample_o),
    .pcie_first_requant_sample_o(pcie_first_requant_sample_o),
    .pcie_accel_activation_i(512'd0),
    .pcie_accel_residual_i(512'd0),
    .pcie_accel_start_pulse_i(1'b0),
    .pcie_accel_clear_pulse_i(1'b0),
    .pcie_accel_status_o(pcie_accel_status_o),
    .pcie_accel_cycle_count_o(pcie_accel_cycle_count_o),
    .pcie_accel_output_checksum_o(pcie_accel_output_checksum_o),
    .pcie_accel_output_sample0_o(pcie_accel_output_sample0_o),
    .pcie_accel_output_sample1_o(pcie_accel_output_sample1_o),
    .pcie_accel_output_vector_o(pcie_accel_output_vector_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    cycles = 0;

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;

    while (cycles < TIMEOUT_CYCLES) begin
      @(posedge SYS_CLK);
      cycles = cycles + 1;

      if (led_3bits_tri_o[2]) begin
        @(posedge SYS_CLK);
        $display(
          "FAIL: task6 int8 L2 residual add selftest asserted fail at cycle %0d",
          cycles
        );
        $display(
          "FAIL_DETAIL: status=%08x cycle_count=%0d fail_detail=%08x fail_values=%08x first_add=%08x first_requant=%08x",
          pcie_status_o,
          pcie_cycle_count_o,
          pcie_fail_detail_o,
          pcie_fail_values_o,
          pcie_first_add_sample_o,
          pcie_first_requant_sample_o
        );
        $display(
          "C_PROJ_REQUANT0: acc=%0d expected_acc=%0d scale=%0d expected_scale=%0d bias=%0d expected_bias=%0d product=%0d expected_product=%0d scaled=%0d expected_scaled=%0d biased=%0d expected_biased=%0d out=%0d expected_out=%0d",
          dut.first_c_proj_requant_acc_q,
          dut.expected_c_proj_acc_values[0],
          dut.first_c_proj_requant_scale_mul_q,
          dut.c_proj_requant_scale_mul_values[0],
          dut.first_c_proj_requant_bias_q,
          dut.c_proj_requant_bias_q_values[0],
          dut.first_c_proj_requant_product_q,
          dut.expected_c_proj_product_q0_w,
          dut.first_c_proj_requant_scaled_q,
          dut.expected_c_proj_scaled_q0_w,
          dut.first_c_proj_requant_biased_q,
          dut.expected_c_proj_biased_q0_w,
          dut.first_c_proj_requant_output_q,
          dut.expected_c_proj_output_q_values[0]
        );
        $display(
          "C_PROJ_GEMV0: final_acc=%0d expected_acc=%0d sample_count=%0d",
          dut.debug_c_proj_gemv_lane0_final_acc,
          dut.expected_c_proj_acc_values[0],
          dut.debug_c_proj_gemv_lane0_sample_count
        );
        $display(
          "C_PROJ_TRANSFER: observed=%016x expected=%016x",
          dut.debug_c_proj_transfer_post_gelu_samples,
          dut.expected_c_proj_activation_samples
        );
        $fatal(1);
      end

      if (led_3bits_tri_o[1]) begin
        $display(
          "PASS: task6 int8 L2 residual add selftest led_pass cycles %0d",
          cycles
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 int8 L2 residual add selftest pass LED");
  end
endmodule
