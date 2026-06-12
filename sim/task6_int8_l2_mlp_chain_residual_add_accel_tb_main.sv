`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_accel_tb;
  localparam int TIMEOUT_CYCLES = 100000;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [511:0] activation_vector;
  logic [511:0] residual_vector;
  logic start_pulse;
  logic clear_pulse;
  logic [31:0] status;
  logic [31:0] cycle_count;
  logic [31:0] output_checksum;
  logic [31:0] output_sample0;
  logic [31:0] output_sample1;
  logic [511:0] output_vector;
  logic [511:0] expected_vector;
  integer cycles;
  integer i;

  task6_int8_l2_mlp_chain_residual_add_accel_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .pcie_accel_activation_i(activation_vector),
    .pcie_accel_residual_i(residual_vector),
    .pcie_accel_start_pulse_i(start_pulse),
    .pcie_accel_clear_pulse_i(clear_pulse),
    .pcie_accel_status_o(status),
    .pcie_accel_cycle_count_o(cycle_count),
    .pcie_accel_output_checksum_o(output_checksum),
    .pcie_accel_output_sample0_o(output_sample0),
    .pcie_accel_output_sample1_o(output_sample1),
    .pcie_accel_output_vector_o(output_vector)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    activation_vector = 512'd0;
    residual_vector = 512'd0;
    expected_vector = 512'd0;
    start_pulse = 1'b0;
    clear_pulse = 1'b0;
    cycles = 0;

    for (i = 0; i < 64; i = i + 1) begin
      activation_vector[i * 8 +: 8] = dut.c_fc_activation_values[i];
      residual_vector[i * 8 +: 8] = dut.residual_q_values[i];
      expected_vector[i * 8 +: 8] = dut.expected_residual_add_output_q_values[i];
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;

    while (cycles < TIMEOUT_CYCLES && status[7:4] != 4'h4) begin
      @(posedge SYS_CLK);
      cycles = cycles + 1;
    end
    if (status[7:4] != 4'h4)
      $fatal(1, "Timeout waiting for accelerator idle: status=%08x", status);

    @(negedge SYS_CLK);
    clear_pulse = 1'b1;
    @(negedge SYS_CLK);
    clear_pulse = 1'b0;
    @(negedge SYS_CLK);
    start_pulse = 1'b1;
    @(negedge SYS_CLK);
    start_pulse = 1'b0;

    while (cycles < TIMEOUT_CYCLES && status[7:4] != 4'hb) begin
      @(posedge SYS_CLK);
      cycles = cycles + 1;
    end
    if (status[7:4] != 4'hb)
      $fatal(1, "Timeout waiting for accelerator done: status=%08x", status);

    if (!status[3])
      $fatal(1, "Accelerator done without output_valid: status=%08x", status);
    if (output_vector !== expected_vector)
      $fatal(1, "Output vector mismatch: got=%0128x expected=%0128x", output_vector, expected_vector);
    if (output_checksum !== 32'h00001eec)
      $fatal(1, "Checksum mismatch: got=%08x expected=00001eec", output_checksum);
    if (output_sample0 !== 32'hde10ff3e)
      $fatal(1, "Sample0 mismatch: got=%08x expected=de10ff3e", output_sample0);
    if (output_sample1 !== 32'hfd3eed6c)
      $fatal(1, "Sample1 mismatch: got=%08x expected=fd3eed6c", output_sample1);

    $display(
      "PASS: task6 int8 L2 residual add accelerator sim cycles %0d checksum %08x sample0 %08x sample1 %08x",
      cycles,
      output_checksum,
      output_sample0,
      output_sample1
    );
    $finish;
  end
endmodule
