`timescale 1ns/1ps

module task6_int8_v4k_l2_residual_add_output_head_selftest_tb;
  localparam int TIMEOUT_CYCLES = 1000000;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [2:0] led_3bits_tri_o;
  integer cycles;
  bit passed;

  task6_int8_v4k_l2_residual_add_output_head_selftest_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .led_3bits_tri_o(led_3bits_tri_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    cycles = 0;
    passed = 1'b0;

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;

    while (cycles < TIMEOUT_CYCLES) begin
      @(posedge SYS_CLK);
      cycles = cycles + 1;

      if (led_3bits_tri_o[2]) begin
        $display(
          "FAIL: task6 int8 v4k residual output-head selftest fail cycle %0d state %0d reason %0d fail_index %0d top_index %0d top_acc %0d",
          cycles,
          dut.state_q,
          dut.fail_reason_q,
          dut.fail_index_q,
          dut.top_index,
          dut.top_acc
        );
        $fatal(1);
      end

      if (led_3bits_tri_o[1]) begin
        $display(
          "PASS: task6 int8 v4k residual output-head selftest led_pass cycles %0d top_index %0d top_acc %0d",
          cycles,
          dut.top_index,
          dut.top_acc
        );
        passed = 1'b1;
        break;
      end
    end

    if (!passed) begin
      $fatal(
        1,
        "Timeout waiting for task6 int8 v4k residual output-head selftest pass LED"
      );
    end
    $finish;
  end
endmodule
