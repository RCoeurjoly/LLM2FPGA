`timescale 1ns/1ps

module task6_int8_l2_c_proj_from_post_gelu_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 10000;

  logic clock;
  logic reset;
  logic weight_load_valid;
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] weight_load_addr;
  logic [LANES * 8 - 1:0] weight_load_data;
  logic activation_load_valid;
  logic [ACTIVATION_ADDR_WIDTH - 1:0] activation_load_addr;
  logic signed [7:0] activation_load_data;
  logic start;
  wire busy;
  wire done;

  logic [OUT_ADDR_WIDTH - 1:0] output_read_addr;
  wire signed [31:0] output_read_data;

  integer cycles;
  integer compute_cycles;
  integer read_count;

  task6_int8_l2_c_proj_from_post_gelu_kernel #(
    .IN_DIM(IN_DIM),
    .OUT_DIM(OUT_DIM),
    .LANES(LANES),
    .PACKED_WEIGHT_WORDS(PACKED_WEIGHT_WORDS)
  ) dut (
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

  initial begin : init_control
    integer in_index;
    integer word_index;
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
      activation_load_addr = ACTIVATION_ADDR_WIDTH'(in_index);
      activation_load_data = activation_values[in_index];
      activation_load_valid = 1'b1;
      @(negedge clock);
    end
    activation_load_valid = 1'b0;
    activation_load_addr = '0;
    activation_load_data = '0;

    for (word_index = 0; word_index < PACKED_WEIGHT_WORDS; word_index = word_index + 1) begin
      weight_load_addr = PACKED_WEIGHT_ADDR_WIDTH'(word_index);
      weight_load_data = packed_weight_values[word_index];
      weight_load_valid = 1'b1;
      @(negedge clock);
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
      output_read_addr = OUT_ADDR_WIDTH'(out_index);
      @(posedge clock);
      #1;
      if (output_read_data !== expected_acc_values[out_index]) begin
        $display(
          "FAIL: c_proj read addr %0d expected %0d got %0d",
          out_index,
          expected_acc_values[out_index],
          output_read_data
        );
        $fatal(1);
      end
      read_count = read_count + 1;
      @(negedge clock);
    end

    $display(
      "PASS: task6 int8 L2 c_proj from postgelu reads %0d outputs %0d compute_cycles %0d total_cycles %0d",
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
        $fatal(1, "Timeout waiting for task6 int8 L2 c_proj from postgelu completion");
    end
  end
endmodule
