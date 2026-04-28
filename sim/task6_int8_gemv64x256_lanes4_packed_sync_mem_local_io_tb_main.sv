`timescale 1ns/1ps

module task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_tb;
  localparam int IN_DIM = 64;
  localparam int OUT_DIM = 256;
  localparam int LANES = 4;
  localparam int PACKED_WEIGHT_WORDS = (OUT_DIM / LANES) * IN_DIM;
  localparam int TIMEOUT_CYCLES = 9000;

  logic clock;
  logic reset;
  logic weight_load_valid;
  logic [11:0] weight_load_addr;
  logic [LANES * 8 - 1:0] weight_load_data;
  logic activation_load_valid;
  logic [5:0] activation_load_addr;
  logic signed [7:0] activation_load_data;
  logic start;
  wire busy;
  wire done;

  logic [7:0] output_read_addr;
  wire signed [31:0] output_read_data;

  logic signed [31:0] expected_mem [0:OUT_DIM - 1];
  integer cycles;
  integer compute_cycles;
  integer read_count;

  task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel dut(
    .clock(clock),
    .reset(reset),
    .weight_load_valid(weight_load_valid),
    .weight_load_addr(weight_load_addr),
    .weight_load_data(weight_load_data),
    .activation_load_valid(activation_load_valid),
    .activation_load_addr(activation_load_addr),
    .activation_load_data(activation_load_data),
    .start(start),
    .busy(busy),
    .done(done),
    .output_read_addr(output_read_addr),
    .output_read_data(output_read_data)
  );

  always #5 clock = ~clock;

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

  function automatic logic [LANES * 8 - 1:0] packed_weight_value(
    input int output_group_index,
    input int in_index
  );
    logic [LANES * 8 - 1:0] packed_word;
    begin
      packed_word = '0;
      for (int lane_index = 0; lane_index < LANES; lane_index = lane_index + 1) begin
        packed_word[lane_index * 8 +: 8] =
          8'(weight_value(output_group_index * LANES + lane_index, in_index));
      end
      packed_weight_value = packed_word;
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

  initial begin : init_vectors
    integer out_index;
    for (out_index = 0; out_index < OUT_DIM; out_index = out_index + 1) begin
      expected_mem[out_index] = expected_value(out_index);
    end
  end

  initial begin : init_control
    integer output_group_index;
    integer in_index;
    integer out_index;

    clock = 1'b0;
    reset = 1'b1;
    weight_load_valid = 1'b0;
    weight_load_addr = '0;
    weight_load_data = '0;
    activation_load_valid = 1'b0;
    activation_load_addr = '0;
    activation_load_data = '0;
    start = 1'b0;
    output_read_addr = '0;
    cycles = 0;
    compute_cycles = 0;
    read_count = 0;

    repeat (2) @(negedge clock);
    for (in_index = 0; in_index < IN_DIM; in_index = in_index + 1) begin
      activation_load_addr = 6'(in_index);
      activation_load_data = 8'(activation_value(in_index));
      activation_load_valid = 1'b1;
      @(negedge clock);
    end
    activation_load_valid = 1'b0;
    activation_load_addr = '0;
    activation_load_data = '0;

    for (
      output_group_index = 0;
      output_group_index < OUT_DIM / LANES;
      output_group_index = output_group_index + 1
    ) begin
      for (in_index = 0; in_index < IN_DIM; in_index = in_index + 1) begin
        weight_load_addr = 12'(output_group_index * IN_DIM + in_index);
        weight_load_data = packed_weight_value(output_group_index, in_index);
        weight_load_valid = 1'b1;
        @(negedge clock);
      end
    end
    weight_load_valid = 1'b0;
    weight_load_addr = '0;
    weight_load_data = '0;

    repeat (2) @(negedge clock);
    reset = 1'b0;
    @(negedge clock);
    start = 1'b1;
    @(negedge clock);
    start = 1'b0;

    wait (done);
    compute_cycles = cycles;
    @(negedge clock);

    for (out_index = 0; out_index < OUT_DIM; out_index = out_index + 1) begin
      output_read_addr = 8'(out_index);
      @(posedge clock);
      #1;
      if (output_read_data !== expected_mem[out_index]) begin
        $display(
          "FAIL: read addr %0d expected %0d got %0d",
          out_index,
          expected_mem[out_index],
          output_read_data
        );
        $fatal(1);
      end
      read_count = read_count + 1;
      @(negedge clock);
    end

    $display(
      "PASS: task6 int8 GEMV4x256 localio reads %0d outputs %0d compute_cycles %0d total_cycles %0d",
      read_count,
      OUT_DIM,
      compute_cycles,
      cycles
    );
    $finish;
  end

  always_ff @(posedge clock) begin
    if (!reset) begin
      cycles <= cycles + 1;
      if (cycles > TIMEOUT_CYCLES)
        $fatal(1, "Timeout waiting for task6 int8 GEMV4x256 localio completion");
    end
  end
endmodule
