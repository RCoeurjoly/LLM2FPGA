`timescale 1ns/1ps

module task6_int8_gemv64_tb;
  localparam int IN_DIM = 64;
  localparam int OUT_DIM = 64;
  localparam int WEIGHT_WORDS = IN_DIM * OUT_DIM;
  localparam int TIMEOUT_CYCLES = 10000;

  logic clock;
  logic reset;
  logic start;
  wire busy;
  wire done;

  wire [5:0] activation_addr;
  logic signed [7:0] activation_data;
  wire [11:0] weight_addr;
  logic signed [7:0] weight_data;
  wire [5:0] out_addr;
  wire signed [31:0] out_data;
  wire out_valid;
  logic out_ready;

  logic signed [7:0] activation_mem [0:IN_DIM - 1];
  logic signed [7:0] weight_mem [0:WEIGHT_WORDS - 1];
  logic signed [31:0] expected_mem [0:OUT_DIM - 1];
  logic seen_mem [0:OUT_DIM - 1];
  integer cycles;
  integer observed_count;

  task6_int8_gemv64_kernel dut(
    .clock(clock),
    .reset(reset),
    .start(start),
    .busy(busy),
    .done(done),
    .activation_addr(activation_addr),
    .activation_data(activation_data),
    .weight_addr(weight_addr),
    .weight_data(weight_data),
    .out_addr(out_addr),
    .out_data(out_data),
    .out_valid(out_valid),
    .out_ready(out_ready)
  );

  always #5 clock = ~clock;

  assign activation_data = activation_mem[activation_addr];
  assign weight_data = weight_mem[weight_addr];

  function automatic int activation_value(input int index);
    int value;
    begin
      value = ((index * 7 + 3) % 31) - 15;
      activation_value = value;
    end
  endfunction

  function automatic int weight_value(input int out_index, input int in_index);
    int value;
    begin
      value = ((out_index * 11 + in_index * 5 + 1) % 47) - 23;
      weight_value = value;
    end
  endfunction

  function automatic logic signed [31:0] expected_value(input int out_index);
    int index;
    int sum;
    int activation;
    int weight;
    begin
      sum = 0;
      for (index = 0; index < IN_DIM; index = index + 1) begin
        activation = activation_value(index);
        weight = weight_value(out_index, index);
        sum = sum + activation * weight;
      end
      expected_value = sum;
    end
  endfunction

  initial begin : init_memories
    integer in_index;
    integer out_index;
    for (in_index = 0; in_index < IN_DIM; in_index = in_index + 1) begin
      activation_mem[in_index] = 8'(activation_value(in_index));
    end
    for (out_index = 0; out_index < OUT_DIM; out_index = out_index + 1) begin
      expected_mem[out_index] = expected_value(out_index);
      for (in_index = 0; in_index < IN_DIM; in_index = in_index + 1) begin
        weight_mem[out_index * IN_DIM + in_index] =
          8'(weight_value(out_index, in_index));
      end
    end
  end

  initial begin : init_control
    integer index;
    clock = 1'b0;
    reset = 1'b1;
    start = 1'b0;
    out_ready = 1'b1;
    cycles = 0;
    observed_count = 0;
    for (index = 0; index < OUT_DIM; index = index + 1) begin
      seen_mem[index] = 1'b0;
    end
    #40;
    reset = 1'b0;
    @(negedge clock);
    start = 1'b1;
    @(negedge clock);
    start = 1'b0;
  end

  always_ff @(posedge clock) begin
    if (!reset) begin
      cycles <= cycles + 1;
      if (cycles > TIMEOUT_CYCLES)
        $fatal(1, "Timeout waiting for task6 int8 GEMV completion");

      if (out_valid && out_ready) begin
        if (seen_mem[out_addr])
          $fatal(1, "Duplicate output store for address %0d", out_addr);
        seen_mem[out_addr] <= 1'b1;
        observed_count <= observed_count + 1;
        if (out_data !== expected_mem[out_addr]) begin
          $display(
            "FAIL: addr %0d expected %0d got %0d",
            out_addr,
            expected_mem[out_addr],
            out_data
          );
          $fatal(1);
        end
      end

      if (done) begin
        if (observed_count != OUT_DIM)
          $fatal(1, "Expected %0d outputs but observed %0d", OUT_DIM, observed_count);
        $display(
          "PASS: task6 int8 GEMV stores %0d outputs %0d cycles %0d",
          observed_count,
          OUT_DIM,
          cycles
        );
        $finish;
      end
    end
  end
endmodule
