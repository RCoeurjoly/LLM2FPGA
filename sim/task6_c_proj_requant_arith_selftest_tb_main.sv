`timescale 1ns/1ps

module task6_c_proj_requant_arith_selftest_tb;
  logic SYS_CLK;
  logic SYS_RSTN;
  logic [2:0] led_3bits_tri_o;

  task6_c_proj_requant_arith_selftest_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .led_3bits_tri_o(led_3bits_tri_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;

    for (int cycle = 0; cycle < 1000; cycle++) begin
      @(posedge SYS_CLK);
      if (led_3bits_tri_o == 3'b010) begin
        $display("PASS: task6 c_proj requant arithmetic selftest cycles %0d", cycle);
        $finish;
      end
    end

    $fatal(1, "FAIL: task6 c_proj requant arithmetic selftest did not pass, leds=%03b",
           led_3bits_tri_o);
  end
endmodule
