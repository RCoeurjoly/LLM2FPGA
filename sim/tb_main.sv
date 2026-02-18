`timescale 1ns/1ps

module tb;
  `include "tb_data.sv"

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

  logic        clock;
  logic        reset;
  logic        in3_valid;
  logic        in3_ready;
  logic        out0_ready;
  logic        out0_valid;

  logic [3:0]  in0_ld0_addr;
  logic        in0_ld0_addr_valid;
  logic        in0_ld0_addr_ready;
  logic [31:0] in0_ld0_data;
  logic        in0_ld0_data_valid;
  logic        in0_ld0_data_ready;

  logic [3:0]  in1_ld0_addr;
  logic        in1_ld0_addr_valid;
  logic        in1_ld0_addr_ready;
  logic [31:0] in1_ld0_data;
  logic        in1_ld0_data_valid;
  logic        in1_ld0_data_ready;

  logic [31:0] in2_st0_data;
  logic        in2_st0_valid;
  logic        in2_st0_ready;
  logic        in2_st0_done_valid;
  logic        in2_st0_done_ready;

  main dut(
    .in0_ld0_data(in0_ld0_data),
    .in0_ld0_data_valid(in0_ld0_data_valid),
    .in1_ld0_data(in1_ld0_data),
    .in1_ld0_data_valid(in1_ld0_data_valid),
    .in2_st0_done_valid(in2_st0_done_valid),
    .in3_valid(in3_valid),
    .clock(clock),
    .reset(reset),
    .out0_ready(out0_ready),
    .in0_ld0_addr_ready(in0_ld0_addr_ready),
    .in1_ld0_addr_ready(in1_ld0_addr_ready),
    .in2_st0_ready(in2_st0_ready),
    .in0_ld0_data_ready(in0_ld0_data_ready),
    .in1_ld0_data_ready(in1_ld0_data_ready),
    .in2_st0_done_ready(in2_st0_done_ready),
    .in3_ready(in3_ready),
    .out0_valid(out0_valid),
    .in0_ld0_addr(in0_ld0_addr),
    .in0_ld0_addr_valid(in0_ld0_addr_valid),
    .in1_ld0_addr(in1_ld0_addr),
    .in1_ld0_addr_valid(in1_ld0_addr_valid),
    .in2_st0(in2_st0_data),
    .in2_st0_valid(in2_st0_valid)
  );

  always #5 clock = ~clock;

  initial begin
    clock = 1'b0;
    reset = 1'b1;
    in3_valid = 1'b0;
    out0_ready = 1'b1;
    in2_st0_ready = 1'b1;
    in0_ld0_data_valid = 1'b0;
    in1_ld0_data_valid = 1'b0;
    in2_st0_done_valid = 1'b0;
    #40;
    reset = 1'b0;
  end

  logic go_sent;
  always_ff @(posedge clock) begin
    if (reset) begin
      go_sent <= 1'b0;
      in3_valid <= 1'b0;
    end else begin
      in3_valid <= ~go_sent;
      if (!go_sent && in3_ready) begin
        go_sent <= 1'b1;
      end
    end
  end

  logic [3:0] in0_addr_q;
  logic       in0_addr_pending;
  always_ff @(posedge clock) begin
    if (reset) begin
      in0_addr_pending <= 1'b0;
      in0_ld0_data_valid <= 1'b0;
      in0_ld0_data <= 32'd0;
    end else begin
      if (in0_ld0_addr_valid && in0_ld0_addr_ready) begin
        in0_addr_q <= in0_ld0_addr;
        in0_ld0_data <= a_mem[in0_ld0_addr];
        in0_addr_pending <= 1'b1;
        in0_ld0_data_valid <= 1'b1;
      end
      if (in0_ld0_data_valid && in0_ld0_data_ready) begin
        in0_ld0_data_valid <= 1'b0;
        in0_addr_pending <= 1'b0;
      end
    end
  end

  logic [3:0] in1_addr_q;
  logic       in1_addr_pending;
  always_ff @(posedge clock) begin
    if (reset) begin
      in1_addr_pending <= 1'b0;
      in1_ld0_data_valid <= 1'b0;
      in1_ld0_data <= 32'd0;
    end else begin
      if (in1_ld0_addr_valid && in1_ld0_addr_ready) begin
        in1_addr_q <= in1_ld0_addr;
        in1_ld0_data <= b_mem[in1_ld0_addr];
        in1_addr_pending <= 1'b1;
        in1_ld0_data_valid <= 1'b1;
      end
      if (in1_ld0_data_valid && in1_ld0_data_ready) begin
        in1_ld0_data_valid <= 1'b0;
        in1_addr_pending <= 1'b0;
      end
    end
  end

  assign in0_ld0_addr_ready = go_sent && ~in0_addr_pending;
  assign in1_ld0_addr_ready = go_sent && ~in1_addr_pending;

  logic [31:0] result_reg;
  logic        result_seen;
  logic        st_done_pending;
  always_ff @(posedge clock) begin
    if (reset) begin
      result_reg <= 32'd0;
      result_seen <= 1'b0;
      st_done_pending <= 1'b0;
      in2_st0_done_valid <= 1'b0;
    end else begin
      in2_st0_done_valid <= 1'b0;
      if (in2_st0_valid && in2_st0_ready) begin
        result_reg <= in2_st0_data;
        result_seen <= 1'b1;
        st_done_pending <= 1'b1;
        in2_st0_done_valid <= 1'b1;
      end
      if (in2_st0_done_valid && in2_st0_done_ready) begin
        in2_st0_done_valid <= 1'b0;
        st_done_pending <= 1'b0;
      end
    end
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
      if (result_seen && out0_valid && out0_ready) begin
        if (result_reg !== expected) begin
          $display("FAIL: expected %0d got %0d", expected, result_reg);
          $fatal(1);
        end else begin
          $display("PASS: expected %0d got %0d", expected, result_reg);
          $finish;
        end
      end
    end
  end
endmodule
