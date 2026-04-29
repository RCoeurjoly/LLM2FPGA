`timescale 1ns/1ps

module task6_int8_l2_c_fc_post_gelu_requant_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 100000;

  logic clock;
  logic reset;
  logic weight_load_valid;
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] weight_load_addr;
  logic [LANES * 8 - 1:0] weight_load_data;
  logic activation_load_valid;
  logic [ACTIVATION_ADDR_WIDTH - 1:0] activation_load_addr;
  logic signed [7:0] activation_load_data;
  logic requant_load_valid;
  logic [OUT_ADDR_WIDTH - 1:0] requant_load_addr;
  logic signed [31:0] requant_scale_mul_load_data;
  logic signed [31:0] requant_bias_q_load_data;
  logic start;
  wire busy;
  wire done;

  logic [OUT_ADDR_WIDTH - 1:0] output_read_addr;
  wire signed [7:0] output_read_data;
  wire [8 * 144 - 1:0] debug_post_gelu_samples;
  wire [3:0] debug_post_gelu_sample_count;
  wire [8 * 128 - 1:0] debug_gemv_samples;
  wire [3:0] debug_gemv_sample_count;
  wire signed [31:0] debug_gemv_final_acc;

  integer cycles;
  integer compute_cycles;
  integer read_count;

  task6_int8_l2_c_fc_post_gelu_requant_kernel #(
    .IN_DIM(IN_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .OUT_DIM(OUT_DIM),
    .LANES(LANES),
    .PACKED_WEIGHT_WORDS(PACKED_WEIGHT_WORDS),
    .X_FRAC(X_FRAC),
    .SCALE_SHIFT(SCALE_SHIFT),
    .GELU_QUAD_Q(GELU_QUAD_Q),
    .OUTPUT_REQUANT_SHIFT(OUTPUT_REQUANT_SHIFT),
    .OUTPUT_REQUANT_MULT(OUTPUT_REQUANT_MULT)
  ) dut (
    .clock(clock),
    .reset(reset),
    .weight_load_valid(weight_load_valid),
    .weight_load_addr(weight_load_addr),
    .weight_load_data(weight_load_data),
    .activation_load_valid(activation_load_valid),
    .activation_load_addr(activation_load_addr),
    .activation_load_data(activation_load_data),
    .requant_load_valid(requant_load_valid),
    .requant_load_addr(requant_load_addr),
    .requant_scale_mul_load_data(requant_scale_mul_load_data),
    .requant_bias_q_load_data(requant_bias_q_load_data),
    .start(start),
    .busy(busy),
    .done(done),
    .output_read_addr(output_read_addr),
    .output_read_data(output_read_data),
    .debug_post_gelu_samples(debug_post_gelu_samples),
    .debug_post_gelu_sample_count(debug_post_gelu_sample_count),
    .debug_gemv_samples(debug_gemv_samples),
    .debug_gemv_sample_count(debug_gemv_sample_count),
    .debug_gemv_final_acc(debug_gemv_final_acc)
  );

  always #5 clock = ~clock;

  initial begin : init_control
    integer in_index;
    integer word_index;
    integer out_index;
    integer sample_index;

    clock = 1'b0;
    reset = 1'b1;
    weight_load_valid = 1'b0;
    weight_load_addr = '0;
    weight_load_data = '0;
    activation_load_valid = 1'b0;
    activation_load_addr = '0;
    activation_load_data = '0;
    requant_load_valid = 1'b0;
    requant_load_addr = '0;
    requant_scale_mul_load_data = '0;
    requant_bias_q_load_data = '0;
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

    for (out_index = 0; out_index < OUT_DIM; out_index = out_index + 1) begin
      requant_load_addr = OUT_ADDR_WIDTH'(out_index);
      requant_scale_mul_load_data = requant_scale_mul_values[out_index];
      requant_bias_q_load_data = requant_bias_q_values[out_index];
      requant_load_valid = 1'b1;
      @(negedge clock);
    end
    requant_load_valid = 1'b0;
    requant_load_addr = '0;
    requant_scale_mul_load_data = '0;
    requant_bias_q_load_data = '0;

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
      if (output_read_data !== expected_output_q_values[out_index]) begin
        $display(
          "FAIL: postgelu read addr %0d expected %0d got %0d",
          out_index,
          expected_output_q_values[out_index],
          output_read_data
        );
        $display(
          "DEBUG: postgelu samples %0d sample0 idx %0d acc %0d scale %0d bias %0d scaled %0d output %0d gemv_final %0d",
          debug_post_gelu_sample_count,
          debug_post_gelu_samples[0 +: 8],
          $signed(debug_post_gelu_samples[8 +: 32]),
          $signed(debug_post_gelu_samples[40 +: 32]),
          $signed(debug_post_gelu_samples[72 +: 32]),
          $signed(debug_post_gelu_samples[104 +: 32]),
          $signed(debug_post_gelu_samples[136 +: 8]),
          debug_gemv_final_acc
        );
        $display(
          "DEBUG: internal x %0d x_sq %0d quad %0d y %0d output_q %0d post_output %0d",
          dut.x_q_q,
          dut.x_sq_q,
          dut.quad_q_q,
          dut.y_q_q,
          dut.output_q_q,
          dut.post_output_w
        );
        for (sample_index = 0; sample_index < 8; sample_index = sample_index + 1) begin
          $display(
            "DEBUG: sample %0d idx %0d acc %0d scaled %0d output %0d",
            sample_index,
            debug_post_gelu_samples[sample_index * 144 + 0 +: 8],
            $signed(debug_post_gelu_samples[sample_index * 144 + 8 +: 32]),
            $signed(debug_post_gelu_samples[sample_index * 144 + 104 +: 32]),
            $signed(debug_post_gelu_samples[sample_index * 144 + 136 +: 8])
          );
        end
        $fatal(1);
      end
      read_count = read_count + 1;
      @(negedge clock);
    end

    $display(
      "PASS: task6 int8 L2 c_fc postgelu requant reads %0d outputs %0d compute_cycles %0d total_cycles %0d",
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
        $fatal(1, "Timeout waiting for task6 int8 L2 c_fc postgelu requant completion");
    end
  end
endmodule
