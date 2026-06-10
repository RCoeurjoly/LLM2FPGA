`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_tb;
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
  logic residual_load_valid;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] residual_load_addr;
  logic signed [7:0] residual_load_data;
  logic start;
  wire busy;
  wire done;

  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] output_read_addr;
  wire signed [7:0] output_read_data;
  wire debug_add_valid;
  wire [C_PROJ_OUT_ADDR_WIDTH - 1:0] debug_add_addr;
  wire signed [7:0] debug_add_residual_q;
  wire signed [7:0] debug_add_c_proj_q;
  wire signed [7:0] debug_add_output_q;
  wire debug_c_proj_requant_valid;
  wire [C_PROJ_OUT_ADDR_WIDTH - 1:0] debug_c_proj_requant_addr;
  wire signed [31:0] debug_c_proj_requant_acc_q;
  wire signed [31:0] debug_c_proj_requant_scale_mul_q;
  wire signed [31:0] debug_c_proj_requant_bias_q;
  wire signed [63:0] debug_c_proj_requant_product_q;
  wire signed [63:0] debug_c_proj_requant_scaled_q;
  wire signed [63:0] debug_c_proj_requant_biased_q;
  wire signed [7:0] debug_c_proj_requant_output_q;
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
  logic first_add_seen;
  logic signed [7:0] first_add_residual_q;
  logic signed [7:0] first_add_c_proj_q;
  logic signed [7:0] first_add_output_q;
  logic first_requant_seen;
  logic signed [31:0] first_requant_acc_q;
  logic signed [7:0] first_requant_output_q;

  task6_int8_l2_mlp_chain_residual_add_kernel #(
    .C_FC_IN_DIM(C_FC_IN_DIM),
    .HIDDEN_DIM(HIDDEN_DIM),
    .C_PROJ_OUT_DIM(C_PROJ_OUT_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .LANES(LANES),
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
    .RESIDUAL_ADD_REQUANT_SHIFT(RESIDUAL_ADD_REQUANT_SHIFT),
    .RESIDUAL_REQUANT_MULT(RESIDUAL_REQUANT_MULT),
    .C_PROJ_RESIDUAL_ADD_REQUANT_MULT(C_PROJ_RESIDUAL_ADD_REQUANT_MULT)
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
    .residual_load_valid(residual_load_valid),
    .residual_load_addr(residual_load_addr),
    .residual_load_data(residual_load_data),
    .start(start),
    .busy(busy),
    .done(done),
    .output_read_addr(output_read_addr),
    .output_read_data(output_read_data),
    .debug_add_valid(debug_add_valid),
    .debug_add_addr(debug_add_addr),
    .debug_add_residual_q(debug_add_residual_q),
    .debug_add_c_proj_q(debug_add_c_proj_q),
    .debug_add_output_q(debug_add_output_q),
    .debug_c_proj_requant_valid(debug_c_proj_requant_valid),
    .debug_c_proj_requant_addr(debug_c_proj_requant_addr),
    .debug_c_proj_requant_acc_q(debug_c_proj_requant_acc_q),
    .debug_c_proj_requant_scale_mul_q(debug_c_proj_requant_scale_mul_q),
    .debug_c_proj_requant_bias_q(debug_c_proj_requant_bias_q),
    .debug_c_proj_requant_product_q(debug_c_proj_requant_product_q),
    .debug_c_proj_requant_scaled_q(debug_c_proj_requant_scaled_q),
    .debug_c_proj_requant_biased_q(debug_c_proj_requant_biased_q),
    .debug_c_proj_requant_output_q(debug_c_proj_requant_output_q),
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
    residual_load_valid = 1'b0;
    residual_load_addr = '0;
    residual_load_data = '0;
    start = 1'b0;
    output_read_addr = '0;
    cycles = 0;
    compute_cycles = 0;
    read_count = 0;
    first_add_seen = 1'b0;
    first_add_residual_q = '0;
    first_add_c_proj_q = '0;
    first_add_output_q = '0;
    first_requant_seen = 1'b0;
    first_requant_acc_q = '0;
    first_requant_output_q = '0;

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

    for (out_index = 0; out_index < C_PROJ_OUT_DIM; out_index = out_index + 1) begin
      residual_load_addr = C_PROJ_OUT_ADDR_WIDTH'(out_index);
      residual_load_data = residual_q_values[out_index];
      residual_load_valid = 1'b1;
      @(negedge clock);
    end
    residual_load_valid = 1'b0;
    residual_load_addr = '0;
    residual_load_data = '0;

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
      if (output_read_data !== expected_residual_add_output_q_values[out_index]) begin
        $display(
          "FAIL: mlp chain residual add read addr %0d expected %0d got %0d",
          out_index,
          expected_residual_add_output_q_values[out_index],
          output_read_data
        );
        $display(
          "C_PROJ_REQUANT: addr=%0d acc=%0d expected_acc0=%0d out=%0d expected_out0=%0d first_acc=%0d first_out=%0d",
          debug_c_proj_requant_addr,
          debug_c_proj_requant_acc_q,
          expected_c_proj_acc_values[0],
          debug_c_proj_requant_output_q,
          expected_c_proj_output_q_values[0],
          first_requant_acc_q,
          first_requant_output_q
        );
        $display(
          "C_PROJ_TRANSFER: observed=%016x",
          debug_c_proj_transfer_post_gelu_samples
        );
        $display(
          "MEM_DEBUG: c_proj_output_mem0=%0d residual_output_mem0=%0d expected_c_proj0=%0d expected_residual0=%0d",
          dut.chain.output_mem[0],
          dut.output_mem[0],
          expected_c_proj_output_q_values[0],
          expected_residual_add_output_q_values[0]
        );
        $display(
          "ADD_DEBUG: addr=%0d residual=%0d c_proj=%0d output=%0d first_residual=%0d first_c_proj=%0d first_output=%0d",
          debug_add_addr,
          debug_add_residual_q,
          debug_add_c_proj_q,
          debug_add_output_q,
          first_add_residual_q,
          first_add_c_proj_q,
          first_add_output_q
        );
        $fatal(1);
      end
      read_count = read_count + 1;
      @(negedge clock);
    end

    $display(
      "PASS: task6 int8 L2 mlp chain residual add reads %0d outputs %0d compute_cycles %0d total_cycles %0d",
      read_count,
      C_PROJ_OUT_DIM,
      compute_cycles,
      cycles
    );
    $finish;
  end

  always_ff @(posedge clock) begin
    if (debug_add_valid && debug_add_addr == '0 && !first_add_seen) begin
      first_add_seen <= 1'b1;
      first_add_residual_q <= debug_add_residual_q;
      first_add_c_proj_q <= debug_add_c_proj_q;
      first_add_output_q <= debug_add_output_q;
    end
    if (debug_c_proj_requant_valid &&
        debug_c_proj_requant_addr == '0 &&
        !first_requant_seen) begin
      first_requant_seen <= 1'b1;
      first_requant_acc_q <= debug_c_proj_requant_acc_q;
      first_requant_output_q <= debug_c_proj_requant_output_q;
    end
    if (!reset) begin
      cycles <= cycles + 1;
      if (cycles > TIMEOUT_CYCLES)
        $fatal(1, "Timeout waiting for task6 int8 L2 mlp chain residual add completion");
    end
  end
endmodule
