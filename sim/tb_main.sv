`timescale 1ns/1ps

module tb;
  `include "tb_data.sv"

// tb_data.sv (which is built with nix build .#tb-data-sv) provides 3 signals: a_mem, b_mem and expected.
// a_mem is the input a
// b_mem is the input b
// expected is the value calculated by simulating the PyTorch module, therefor being our gold reference.

   
`ifdef ENABLE_WAVES
  initial begin
`ifdef ENABLE_WAVES_VCD
    $dumpfile("wave.vcd");
`else
    $dumpfile("wave.fst");
`endif
    $dumpvars(0, tb);
  end
`endif

  logic clock;
  logic reset;
  logic in3_valid;
  logic in3_ready;

  logic [3:0] in0_ld0_addr;
  logic       in0_ld0_addr_valid;
  wire [31:0] in0_ld0_data = in0_ld0_addr_valid ? a_mem[in0_ld0_addr] : 32'd0;
  wire        in0_ld0_data_valid = in0_ld0_addr_valid;

  logic [3:0] in1_ld0_addr;
  logic       in1_ld0_addr_valid;
  wire [31:0] in1_ld0_data = in1_ld0_addr_valid ? b_mem[in1_ld0_addr] : 32'd0;
  wire        in1_ld0_data_valid = in1_ld0_addr_valid;

  wire [31:0] in2_st0_data;
  wire        in2_st0_valid;
  wire        in2_st0_done_ready;
  wire	      in0_ld0_data_ready;
  wire	      in1_ld0_data_ready;
   
  main dut(
    .in0_ld0_data(in0_ld0_data),
    .in0_ld0_data_valid(in0_ld0_data_valid),
    .in1_ld0_data(in1_ld0_data),
    .in1_ld0_data_valid(in1_ld0_data_valid),
    .in2_st0_done_valid(1'b0),
    .in3_valid(in3_valid),
    .clock(clock),
    .reset(reset),
    .out0_ready(1'b1),
    .in0_ld0_addr_ready(1'b1),
    .in1_ld0_addr_ready(1'b1),
    .in2_st0_ready(1'b1),
    .in0_ld0_data_ready(in0_ld0_data_ready),
    .in1_ld0_data_ready(in1_ld0_data_ready),
    .in2_st0_done_ready(in2_st0_done_ready),
    .in3_ready(in3_ready),
    .in0_ld0_addr(in0_ld0_addr),
    .in0_ld0_addr_valid(in0_ld0_addr_valid),
    .in1_ld0_addr(in1_ld0_addr),
    .in1_ld0_addr_valid(in1_ld0_addr_valid),
    .in2_st0(in2_st0_data),
    .in2_st0_valid(in2_st0_valid)
  );

  always #5 clock = ~clock;

  always_ff @(posedge clock) begin
    if (reset) begin
      in3_valid <= 1'b1;
    end else if (in3_ready) begin
      in3_valid <= 1'b0;
    end
  end

  initial begin
    clock = 1'b0;
    reset = 1'b1;
    #40;
    reset = 1'b0;
  end

  integer cycles;
  always_ff @(posedge clock) begin
    if (reset) begin
      cycles <= 0;
    end else begin
      cycles <= cycles + 1;
      if (cycles > 10000) begin
        $fatal(1, "Timeout waiting for completion");
      end
      if (in2_st0_valid) begin
        if (in2_st0_data !== expected) begin
          $display("FAIL: expected %0d got %0d", expected, in2_st0_data);
          $fatal(1);
        end else begin
          $display("PASS: expected %0d got %0d", expected, in2_st0_data);
          $finish;
        end
      end
    end
  end
endmodule
