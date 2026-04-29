`timescale 1ns/1ps

module task6_int8_vocab_output_head_top1_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 250000;

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
  wire [VOCAB_ADDR_WIDTH - 1:0] top_index;
  wire signed [ACC_WIDTH - 1:0] top_acc;

  integer cycles;
  integer compute_cycles;

  task6_int8_vocab_output_head_top1_kernel #(
    .IN_DIM(IN_DIM),
    .VOCAB_SIZE(VOCAB_SIZE),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
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
    .top_index(top_index),
    .top_acc(top_acc)
  );

  always #5 clock = ~clock;

  initial begin : init_control
    integer in_index;
    integer word_index;

    clock = 1'b0;
    reset = 1'b1;
    weight_load_valid = 1'b0;
    weight_load_addr = '0;
    weight_load_data = '0;
    activation_load_valid = 1'b0;
    activation_load_addr = '0;
    activation_load_data = '0;
    start = 1'b0;
    cycles = 0;
    compute_cycles = 0;

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

    @(negedge clock);
    reset = 1'b0;
    @(negedge clock);
    start = 1'b1;
    @(negedge clock);
    start = 1'b0;

    wait (done);
    compute_cycles = cycles;
    @(negedge clock);

    if (top_index !== EXPECTED_TOP_INDEX) begin
      $display(
        "FAIL: output head top index expected %0d got %0d",
        EXPECTED_TOP_INDEX,
        top_index
      );
      $fatal(1);
    end
    if (top_acc !== EXPECTED_TOP_ACC) begin
      $display(
        "FAIL: output head top acc expected %0d got %0d",
        EXPECTED_TOP_ACC,
        top_acc
      );
      $fatal(1);
    end

    $display(
      "PASS: task6 int8 vocab output head top1 weights %0d top_index %0d top_acc %0d compute_cycles %0d total_cycles %0d",
      PACKED_WEIGHT_WORDS,
      top_index,
      top_acc,
      compute_cycles,
      cycles
    );
    $finish;
  end

  always_ff @(posedge clock) begin
    if (!reset) begin
      cycles <= cycles + 1;
      if (cycles > TIMEOUT_CYCLES)
        $fatal(1, "Timeout waiting for task6 int8 vocab output head top1 completion");
    end
  end
endmodule
