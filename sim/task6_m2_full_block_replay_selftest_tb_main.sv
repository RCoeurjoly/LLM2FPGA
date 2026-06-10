`timescale 1ns/1ps

module task6_m2_full_block_replay_selftest_tb;
  localparam int TIMEOUT_CYCLES = 30000;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [2:0] led_3bits_tri_o;
  logic [31:0] status_o;
  logic [31:0] cycle_count_o;
  logic [31:0] output_checksum_o;
  logic [31:0] output_sample0_o;
  logic [31:0] output_sample1_o;
  logic [31:0] fail_detail_o;
  integer cycles;

  task6_m2_full_block_replay_selftest_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .led_3bits_tri_o(led_3bits_tri_o),
    .status_o(status_o),
    .cycle_count_o(cycle_count_o),
    .output_checksum_o(output_checksum_o),
    .output_sample0_o(output_sample0_o),
    .output_sample1_o(output_sample1_o),
    .fail_detail_o(fail_detail_o)
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
          "FAIL: task6 M2 full block replay selftest status=%08x cycles=%0d checksum=%08x sample0=%08x sample1=%08x fail_detail=%08x",
          status_o,
          cycle_count_o,
          output_checksum_o,
          output_sample0_o,
          output_sample1_o,
          fail_detail_o
        );
        $fatal(1);
      end

      if (led_3bits_tri_o[1]) begin
        $display(
          "PASS: task6 M2 full block replay selftest cycles %0d checksum %08x sample0 %08x sample1 %08x",
          cycle_count_o,
          output_checksum_o,
          output_sample0_o,
          output_sample1_o
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 M2 full block replay selftest pass LED");
  end
endmodule
