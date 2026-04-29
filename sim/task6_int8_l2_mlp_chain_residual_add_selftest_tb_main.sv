`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_selftest_tb;
  localparam int TIMEOUT_CYCLES = 26000;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [2:0] led_3bits_tri_o;
  integer cycles;

  task6_int8_l2_mlp_chain_residual_add_selftest_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .led_3bits_tri_o(led_3bits_tri_o)
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
        $display(
          "FAIL: task6 int8 L2 residual add selftest asserted fail at cycle %0d",
          cycles
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
