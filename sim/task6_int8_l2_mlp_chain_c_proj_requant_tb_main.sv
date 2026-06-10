`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_c_proj_requant_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES =
    20000 + ((C_FC_PACKED_WEIGHT_WORDS + C_PROJ_PACKED_WEIGHT_WORDS) * 16);

  logic clock;
  logic reset;
  logic c_fc_weight_load_valid;
  logic [C_FC_PACKED_WEIGHT_ADDR_WIDTH - 1:0] c_fc_weight_load_addr;
  logic [LANES * 8 - 1:0] c_fc_weight_load_data;
  logic c_fc_activation_load_valid;
  logic [C_FC_ACTIVATION_ADDR_WIDTH - 1:0] c_fc_activation_load_addr;
  logic signed [7:0] c_fc_activation_load_data;
  logic c_fc_requant_load_valid;
  logic [HIDDEN_ADDR_WIDTH - 1:0] c_fc_requant_load_addr;
  logic signed [31:0] c_fc_requant_scale_mul_load_data;
  logic signed [31:0] c_fc_requant_bias_q_load_data;
  logic c_proj_weight_load_valid;
  logic [C_PROJ_PACKED_WEIGHT_ADDR_WIDTH - 1:0] c_proj_weight_load_addr;
  logic [LANES * 8 - 1:0] c_proj_weight_load_data;
  logic c_proj_requant_load_valid;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] c_proj_requant_load_addr;
  logic signed [31:0] c_proj_requant_scale_mul_load_data;
  logic signed [31:0] c_proj_requant_bias_q_load_data;
  logic start;
  wire busy;
  wire done;

  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] output_read_addr;
  wire signed [7:0] output_read_data;
  wire debug_requant_valid;
  wire [C_PROJ_OUT_ADDR_WIDTH - 1:0] debug_requant_addr;
  wire signed [31:0] debug_requant_acc_q;
  wire signed [31:0] debug_requant_scale_mul_q;
  wire signed [31:0] debug_requant_bias_q;
  wire signed [63:0] debug_requant_product_q;
  wire signed [63:0] debug_requant_scaled_q;
  wire signed [63:0] debug_requant_biased_q;
  wire signed [7:0] debug_requant_output_q;
  wire [8 * 128 - 1:0] debug_c_proj_gemv_lane0_samples;
  wire [3:0] debug_c_proj_gemv_lane0_sample_count;
  wire signed [31:0] debug_c_proj_gemv_lane0_final_acc;
  wire [8 * 8 - 1:0] debug_c_proj_transfer_post_gelu_samples;
  wire [8 * 144 - 1:0] debug_c_fc_post_gelu_samples;
  wire [3:0] debug_c_fc_post_gelu_sample_count;
  wire [8 * 128 - 1:0] debug_c_fc_gemv_samples;
  wire [3:0] debug_c_fc_gemv_sample_count;
  wire signed [31:0] debug_c_fc_gemv_final_acc;

  integer cycles;
  integer compute_cycles;
  integer read_count;

  task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel #(
    .C_FC_IN_DIM(C_FC_IN_DIM),
    .HIDDEN_DIM(HIDDEN_DIM),
    .C_PROJ_OUT_DIM(C_PROJ_OUT_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(32),
    .C_FC_PHASES(HIDDEN_DIM / TILE_OUT_DIM),
    .C_FC_PACKED_WEIGHT_WORDS(C_FC_PACKED_WEIGHT_WORDS),
    .C_PROJ_PACKED_WEIGHT_WORDS(C_PROJ_PACKED_WEIGHT_WORDS),
    .X_FRAC(X_FRAC),
    .SCALE_SHIFT(SCALE_SHIFT),
    .GELU_QUAD_Q(GELU_QUAD_Q),
    .GELU_APPROX_MODE(GELU_APPROX_MODE),
    .GELU_PWL_X0(GELU_PWL_X0),
    .GELU_PWL_X1(GELU_PWL_X1),
    .GELU_PWL_X2(GELU_PWL_X2),
    .GELU_PWL_X3(GELU_PWL_X3),
    .GELU_PWL_X4(GELU_PWL_X4),
    .GELU_PWL_X5(GELU_PWL_X5),
    .GELU_PWL_X6(GELU_PWL_X6),
    .GELU_PWL_X7(GELU_PWL_X7),
    .GELU_PWL_X8(GELU_PWL_X8),
    .GELU_PWL_X9(GELU_PWL_X9),
    .GELU_PWL_X10(GELU_PWL_X10),
    .GELU_PWL_X11(GELU_PWL_X11),
    .GELU_PWL_X12(GELU_PWL_X12),
    .GELU_PWL_X13(GELU_PWL_X13),
    .GELU_PWL_X14(GELU_PWL_X14),
    .GELU_PWL_X15(GELU_PWL_X15),
    .GELU_PWL_Y0(GELU_PWL_Y0),
    .GELU_PWL_Y1(GELU_PWL_Y1),
    .GELU_PWL_Y2(GELU_PWL_Y2),
    .GELU_PWL_Y3(GELU_PWL_Y3),
    .GELU_PWL_Y4(GELU_PWL_Y4),
    .GELU_PWL_Y5(GELU_PWL_Y5),
    .GELU_PWL_Y6(GELU_PWL_Y6),
    .GELU_PWL_Y7(GELU_PWL_Y7),
    .GELU_PWL_Y8(GELU_PWL_Y8),
    .GELU_PWL_Y9(GELU_PWL_Y9),
    .GELU_PWL_Y10(GELU_PWL_Y10),
    .GELU_PWL_Y11(GELU_PWL_Y11),
    .GELU_PWL_Y12(GELU_PWL_Y12),
    .GELU_PWL_Y13(GELU_PWL_Y13),
    .GELU_PWL_Y14(GELU_PWL_Y14),
    .GELU_PWL_Y15(GELU_PWL_Y15),
    .OUTPUT_REQUANT_SHIFT(OUTPUT_REQUANT_SHIFT),
    .OUTPUT_REQUANT_MULT(OUTPUT_REQUANT_MULT),
    .C_PROJ_OUTPUT_REQUANT_SHIFT(C_PROJ_OUTPUT_REQUANT_SHIFT),
    .C_PROJ_GEMV_DEBUG_SAMPLE_COUNT(8),
    .C_PROJ_GEMV_DEBUG_SAMPLE_WIDTH(128),
    .C_PROJ_GEMV_DEBUG_LANE_INDEX(0),
    .C_FC_POST_GELU_DEBUG_SAMPLE_COUNT(8),
    .C_FC_POST_GELU_DEBUG_SAMPLE_WIDTH(144),
    .C_FC_GEMV_DEBUG_SAMPLE_COUNT(8),
    .C_FC_GEMV_DEBUG_SAMPLE_WIDTH(128),
    .C_FC_GEMV_DEBUG_LANE_INDEX(1)
  ) dut (
    .clock(clock),
    .reset(reset),
    .c_fc_weight_load_valid(c_fc_weight_load_valid),
    .c_fc_weight_load_addr(c_fc_weight_load_addr),
    .c_fc_weight_load_data(c_fc_weight_load_data),
    .c_fc_activation_load_valid(c_fc_activation_load_valid),
    .c_fc_activation_load_addr(c_fc_activation_load_addr),
    .c_fc_activation_load_data(c_fc_activation_load_data),
    .c_fc_requant_load_valid(c_fc_requant_load_valid),
    .c_fc_requant_load_addr(c_fc_requant_load_addr),
    .c_fc_requant_scale_mul_load_data(c_fc_requant_scale_mul_load_data),
    .c_fc_requant_bias_q_load_data(c_fc_requant_bias_q_load_data),
    .c_proj_weight_load_valid(c_proj_weight_load_valid),
    .c_proj_weight_load_addr(c_proj_weight_load_addr),
    .c_proj_weight_load_data(c_proj_weight_load_data),
    .c_proj_requant_load_valid(c_proj_requant_load_valid),
    .c_proj_requant_load_addr(c_proj_requant_load_addr),
    .c_proj_requant_scale_mul_load_data(c_proj_requant_scale_mul_load_data),
    .c_proj_requant_bias_q_load_data(c_proj_requant_bias_q_load_data),
    .start(start),
    .busy(busy),
    .done(done),
    .output_read_addr(output_read_addr),
    .output_read_data(output_read_data),
    .debug_requant_valid(debug_requant_valid),
    .debug_requant_addr(debug_requant_addr),
    .debug_requant_acc_q(debug_requant_acc_q),
    .debug_requant_scale_mul_q(debug_requant_scale_mul_q),
    .debug_requant_bias_q(debug_requant_bias_q),
    .debug_requant_product_q(debug_requant_product_q),
    .debug_requant_scaled_q(debug_requant_scaled_q),
    .debug_requant_biased_q(debug_requant_biased_q),
    .debug_requant_output_q(debug_requant_output_q),
    .debug_c_proj_gemv_lane0_samples(debug_c_proj_gemv_lane0_samples),
    .debug_c_proj_gemv_lane0_sample_count(debug_c_proj_gemv_lane0_sample_count),
    .debug_c_proj_gemv_lane0_final_acc(debug_c_proj_gemv_lane0_final_acc),
    .debug_c_proj_transfer_post_gelu_samples(debug_c_proj_transfer_post_gelu_samples),
    .debug_c_fc_post_gelu_samples(debug_c_fc_post_gelu_samples),
    .debug_c_fc_post_gelu_sample_count(debug_c_fc_post_gelu_sample_count),
    .debug_c_fc_gemv_samples(debug_c_fc_gemv_samples),
    .debug_c_fc_gemv_sample_count(debug_c_fc_gemv_sample_count),
    .debug_c_fc_gemv_final_acc(debug_c_fc_gemv_final_acc)
  );

  always #5 clock = ~clock;

  initial begin : init_control
    integer in_index;
    integer word_index;
    integer hidden_index;
    integer out_index;

    clock = 1'b0;
    reset = 1'b1;
    c_fc_weight_load_valid = 1'b0;
    c_fc_weight_load_addr = '0;
    c_fc_weight_load_data = '0;
    c_fc_activation_load_valid = 1'b0;
    c_fc_activation_load_addr = '0;
    c_fc_activation_load_data = '0;
    c_fc_requant_load_valid = 1'b0;
    c_fc_requant_load_addr = '0;
    c_fc_requant_scale_mul_load_data = '0;
    c_fc_requant_bias_q_load_data = '0;
    c_proj_weight_load_valid = 1'b0;
    c_proj_weight_load_addr = '0;
    c_proj_weight_load_data = '0;
    c_proj_requant_load_valid = 1'b0;
    c_proj_requant_load_addr = '0;
    c_proj_requant_scale_mul_load_data = '0;
    c_proj_requant_bias_q_load_data = '0;
    start = 1'b0;
    output_read_addr = '0;
    cycles = 0;
    compute_cycles = 0;
    read_count = 0;

    repeat (2) @(negedge clock);
    for (in_index = 0; in_index < C_FC_IN_DIM; in_index = in_index + 1) begin
      c_fc_activation_load_addr = C_FC_ACTIVATION_ADDR_WIDTH'(in_index);
      c_fc_activation_load_data = c_fc_activation_values[in_index];
      c_fc_activation_load_valid = 1'b1;
      @(negedge clock);
    end
    c_fc_activation_load_valid = 1'b0;
    c_fc_activation_load_addr = '0;
    c_fc_activation_load_data = '0;

    for (word_index = 0; word_index < C_FC_PACKED_WEIGHT_WORDS; word_index = word_index + 1) begin
      c_fc_weight_load_addr = C_FC_PACKED_WEIGHT_ADDR_WIDTH'(word_index);
      c_fc_weight_load_data = c_fc_packed_weight_values[word_index];
      c_fc_weight_load_valid = 1'b1;
      @(negedge clock);
    end
    c_fc_weight_load_valid = 1'b0;
    c_fc_weight_load_addr = '0;
    c_fc_weight_load_data = '0;

    for (hidden_index = 0; hidden_index < HIDDEN_DIM; hidden_index = hidden_index + 1) begin
      c_fc_requant_load_addr = HIDDEN_ADDR_WIDTH'(hidden_index);
      c_fc_requant_scale_mul_load_data = c_fc_requant_scale_mul_values[hidden_index];
      c_fc_requant_bias_q_load_data = c_fc_requant_bias_q_values[hidden_index];
      c_fc_requant_load_valid = 1'b1;
      @(negedge clock);
    end
    c_fc_requant_load_valid = 1'b0;
    c_fc_requant_load_addr = '0;
    c_fc_requant_scale_mul_load_data = '0;
    c_fc_requant_bias_q_load_data = '0;

    for (word_index = 0; word_index < C_PROJ_PACKED_WEIGHT_WORDS; word_index = word_index + 1) begin
      c_proj_weight_load_addr = C_PROJ_PACKED_WEIGHT_ADDR_WIDTH'(word_index);
      c_proj_weight_load_data = c_proj_packed_weight_values[word_index];
      c_proj_weight_load_valid = 1'b1;
      @(negedge clock);
    end
    c_proj_weight_load_valid = 1'b0;
    c_proj_weight_load_addr = '0;
    c_proj_weight_load_data = '0;

    for (out_index = 0; out_index < C_PROJ_OUT_DIM; out_index = out_index + 1) begin
      c_proj_requant_load_addr = C_PROJ_OUT_ADDR_WIDTH'(out_index);
      c_proj_requant_scale_mul_load_data = c_proj_requant_scale_mul_values[out_index];
      c_proj_requant_bias_q_load_data = c_proj_requant_bias_q_values[out_index];
      c_proj_requant_load_valid = 1'b1;
      @(negedge clock);
    end
    c_proj_requant_load_valid = 1'b0;
    c_proj_requant_load_addr = '0;
    c_proj_requant_scale_mul_load_data = '0;
    c_proj_requant_bias_q_load_data = '0;

    repeat (2) @(negedge clock);
    reset = 1'b0;
    @(negedge clock);
    start = 1'b1;
    @(negedge clock);
    start = 1'b0;

    wait (done);
    compute_cycles = cycles;
    @(negedge clock);

    for (out_index = 0; out_index < C_PROJ_OUT_DIM; out_index = out_index + 1) begin
      output_read_addr = C_PROJ_OUT_ADDR_WIDTH'(out_index);
      @(posedge clock);
      #1;
      if (output_read_data !== expected_c_proj_output_q_values[out_index]) begin
        $display(
          "FAIL: mlp chain c_proj requant read addr %0d expected %0d got %0d",
          out_index,
          expected_c_proj_output_q_values[out_index],
          output_read_data
        );
        $display(
          "C_PROJ_REQUANT_DEBUG: output_mem0=%0d expected0=%0d acc_mem0=%0d expected_acc0=%0d scale0=%0d bias0=%0d transfer=%016x",
          dut.output_mem[0],
          expected_c_proj_output_q_values[0],
          dut.chain.c_proj.output_mem[0],
          expected_c_proj_acc_values[0],
          c_proj_requant_scale_mul_values[0],
          c_proj_requant_bias_q_values[0],
          debug_c_proj_transfer_post_gelu_samples
        );
        $display(
          "POST_GELU_DEBUG: expected0=%0d expected1=%0d expected2=%0d expected3=%0d transfer0=%0d transfer1=%0d transfer2=%0d transfer3=%0d",
          expected_post_gelu_q_values[0],
          expected_post_gelu_q_values[1],
          expected_post_gelu_q_values[2],
          expected_post_gelu_q_values[3],
          $signed(debug_c_proj_transfer_post_gelu_samples[0 +: 8]),
          $signed(debug_c_proj_transfer_post_gelu_samples[8 +: 8]),
          $signed(debug_c_proj_transfer_post_gelu_samples[16 +: 8]),
          $signed(debug_c_proj_transfer_post_gelu_samples[24 +: 8])
        );
        $fatal(1);
      end
      read_count = read_count + 1;
      @(negedge clock);
    end

    $display(
      "PASS: task6 int8 L2 mlp chain c_proj requant reads %0d outputs %0d compute_cycles %0d total_cycles %0d",
      read_count,
      C_PROJ_OUT_DIM,
      compute_cycles,
      cycles
    );
    $display(
      "C_PROJ_REQUANT_DEBUG: output_mem0=%0d expected0=%0d transfer=%016x",
      dut.output_mem[0],
      expected_c_proj_output_q_values[0],
      debug_c_proj_transfer_post_gelu_samples
    );
    $finish;
  end

  always_ff @(posedge clock) begin
    if (!reset) begin
      cycles <= cycles + 1;
      if (cycles > TIMEOUT_CYCLES)
        $fatal(1, "Timeout waiting for task6 int8 L2 mlp chain c_proj requant completion");
    end
  end
endmodule
