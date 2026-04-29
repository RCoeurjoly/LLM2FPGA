`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = 100000;

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

  integer cycles;
  integer compute_cycles;
  integer read_count;

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
    .output_read_data(output_read_data)
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
    if (!reset) begin
      cycles <= cycles + 1;
      if (cycles > TIMEOUT_CYCLES)
        $fatal(1, "Timeout waiting for task6 int8 L2 mlp chain residual add completion");
    end
  end
endmodule
