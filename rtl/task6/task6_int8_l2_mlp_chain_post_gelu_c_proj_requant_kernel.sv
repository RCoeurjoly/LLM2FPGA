`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel #(
  parameter int C_FC_IN_DIM = 64,
  parameter int HIDDEN_DIM = 256,
  parameter int C_PROJ_OUT_DIM = 64,
  parameter int TILE_OUT_DIM = 64,
  parameter int LANES = 4,
  parameter int ACC_WIDTH = 32,
  parameter int C_FC_PHASES = HIDDEN_DIM / TILE_OUT_DIM,
  parameter int C_FC_PACKED_WEIGHT_WORDS =
    C_FC_PHASES * (TILE_OUT_DIM / LANES) * C_FC_IN_DIM,
  parameter int C_PROJ_PACKED_WEIGHT_WORDS =
    (C_PROJ_OUT_DIM / LANES) * HIDDEN_DIM,
  parameter int C_FC_PACKED_WEIGHT_ADDR_WIDTH =
    (C_FC_PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(C_FC_PACKED_WEIGHT_WORDS),
  parameter int C_PROJ_PACKED_WEIGHT_ADDR_WIDTH =
    (C_PROJ_PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(C_PROJ_PACKED_WEIGHT_WORDS),
  parameter int C_FC_ACTIVATION_ADDR_WIDTH =
    (C_FC_IN_DIM <= 1) ? 1 : $clog2(C_FC_IN_DIM),
  parameter int HIDDEN_ADDR_WIDTH = (HIDDEN_DIM <= 1) ? 1 : $clog2(HIDDEN_DIM),
  parameter int C_PROJ_OUT_ADDR_WIDTH =
    (C_PROJ_OUT_DIM <= 1) ? 1 : $clog2(C_PROJ_OUT_DIM),
  parameter int X_FRAC = 12,
  parameter int SCALE_SHIFT = 24,
  parameter int GELU_QUAD_Q = 1634,
  parameter int OUTPUT_REQUANT_SHIFT = 16,
  parameter int OUTPUT_REQUANT_MULT = 8032,
  parameter int C_PROJ_OUTPUT_REQUANT_SHIFT = 24
)(
  input  logic clock,
  input  logic reset,

  input  logic c_fc_weight_load_valid,
  input  logic [C_FC_PACKED_WEIGHT_ADDR_WIDTH - 1:0] c_fc_weight_load_addr,
  input  logic [LANES * 8 - 1:0] c_fc_weight_load_data,

  input  logic c_fc_activation_load_valid,
  input  logic [C_FC_ACTIVATION_ADDR_WIDTH - 1:0] c_fc_activation_load_addr,
  input  logic signed [7:0] c_fc_activation_load_data,

  input  logic c_fc_requant_load_valid,
  input  logic [HIDDEN_ADDR_WIDTH - 1:0] c_fc_requant_load_addr,
  input  logic signed [31:0] c_fc_requant_scale_mul_load_data,
  input  logic signed [31:0] c_fc_requant_bias_q_load_data,

  input  logic c_proj_weight_load_valid,
  input  logic [C_PROJ_PACKED_WEIGHT_ADDR_WIDTH - 1:0] c_proj_weight_load_addr,
  input  logic [LANES * 8 - 1:0] c_proj_weight_load_data,

  input  logic c_proj_requant_load_valid,
  input  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] c_proj_requant_load_addr,
  input  logic signed [31:0] c_proj_requant_scale_mul_load_data,
  input  logic signed [31:0] c_proj_requant_bias_q_load_data,

  input  logic start,
  output logic busy,
  output logic done,

  input  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] output_read_addr,
  output logic signed [7:0] output_read_data,

  output logic debug_requant_valid,
  output logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] debug_requant_addr,
  output logic signed [ACC_WIDTH - 1:0] debug_requant_acc_q,
  output logic signed [31:0] debug_requant_scale_mul_q,
  output logic signed [31:0] debug_requant_bias_q,
  output logic signed [7:0] debug_requant_output_q
);
  localparam logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] LAST_C_PROJ_OUT_INDEX =
    C_PROJ_OUT_ADDR_WIDTH'(C_PROJ_OUT_DIM - 1);
  localparam logic [5:0] LAST_MUL_BIT = 6'd31;
  localparam logic [63:0] C_PROJ_ROUND_BIAS_U =
    (C_PROJ_OUTPUT_REQUANT_SHIFT == 0)
      ? 64'd0
      : (64'd1 << (C_PROJ_OUTPUT_REQUANT_SHIFT - 1));

  typedef enum logic [2:0] {
    POST_IDLE,
    POST_WAIT,
    POST_CAPTURE,
    POST_MUL_INIT,
    POST_MUL_STEP,
    POST_ROUND,
    POST_BIAS,
    POST_WRITE
  } post_state_t;

  logic chain_start;
  logic chain_busy;
  logic chain_done;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] chain_output_read_addr_q;
  logic signed [ACC_WIDTH - 1:0] chain_output_read_data;

  post_state_t post_state_q;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] post_addr_q;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] sidecar_read_addr_q;
  logic signed [31:0] scale_mul_read_data_q;
  logic signed [31:0] bias_q_read_data_q;
  logic signed [7:0] post_output_w;
  logic signed [31:0] requant_acc_q;
  logic signed [31:0] requant_scale_mul_q;
  logic signed [31:0] requant_bias_q;
  logic [31:0] acc_magnitude_w;
  logic [31:0] scale_magnitude_w;
  logic [31:0] mul_rhs_shift_q;
  logic [63:0] mul_addend_q;
  logic [63:0] mul_product_mag_q;
  logic [63:0] mul_product_next_w;
  logic [5:0] mul_bit_q;
  logic mul_negative_q;
  logic signed [63:0] scaled_product_q;
  logic [63:0] scaled_product_abs_w;
  logic [63:0] scaled_product_rounded_abs_w;
  logic [63:0] scaled_abs_shifted_w;
  logic signed [63:0] scaled_q_w;
  logic signed [63:0] scaled_q_q;
  logic signed [63:0] output_q_q;

  (* ram_style = "block" *)
  logic signed [31:0] scale_mul_mem [0:C_PROJ_OUT_DIM - 1];
  (* ram_style = "block" *)
  logic signed [31:0] bias_q_mem [0:C_PROJ_OUT_DIM - 1];
  (* ram_style = "distributed" *)
  logic signed [7:0] output_mem [0:C_PROJ_OUT_DIM - 1];

  assign chain_start = start && (post_state_q == POST_IDLE) && !chain_busy;
  assign busy = chain_busy || (post_state_q != POST_IDLE);
  assign acc_magnitude_w =
    requant_acc_q[31]
      ? (~requant_acc_q[31:0] + 32'd1)
      : requant_acc_q[31:0];
  assign scale_magnitude_w =
    requant_scale_mul_q[31]
      ? (~requant_scale_mul_q + 32'd1)
      : requant_scale_mul_q;
  assign mul_product_next_w =
    mul_rhs_shift_q[0] ? (mul_product_mag_q + mul_addend_q) : mul_product_mag_q;
  assign scaled_product_abs_w =
    scaled_product_q[63] ? (~scaled_product_q + 64'd1) : scaled_product_q;
  assign scaled_product_rounded_abs_w =
    (C_PROJ_OUTPUT_REQUANT_SHIFT == 0)
      ? scaled_product_abs_w
      : (scaled_product_abs_w + C_PROJ_ROUND_BIAS_U);
  assign scaled_abs_shifted_w =
    (C_PROJ_OUTPUT_REQUANT_SHIFT == 0)
      ? scaled_product_rounded_abs_w
      : (scaled_product_rounded_abs_w >> C_PROJ_OUTPUT_REQUANT_SHIFT);
  assign scaled_q_w =
    scaled_product_q[63]
      ? -$signed(scaled_abs_shifted_w)
      : $signed(scaled_abs_shifted_w);
  assign post_output_w =
    (output_q_q > 64'sd127)
      ? 8'sd127
      : ((output_q_q < -64'sd127) ? -8'sd127 : $signed(output_q_q[7:0]));

  always_ff @(posedge clock) begin
    if (c_proj_requant_load_valid) begin
      scale_mul_mem[c_proj_requant_load_addr] <= c_proj_requant_scale_mul_load_data;
      bias_q_mem[c_proj_requant_load_addr] <= c_proj_requant_bias_q_load_data;
    end

    scale_mul_read_data_q <= scale_mul_mem[sidecar_read_addr_q];
    bias_q_read_data_q <= bias_q_mem[sidecar_read_addr_q];
    output_read_data <= output_mem[output_read_addr];
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      post_state_q <= POST_IDLE;
      post_addr_q <= '0;
      sidecar_read_addr_q <= '0;
      chain_output_read_addr_q <= '0;
      requant_acc_q <= '0;
      requant_scale_mul_q <= '0;
      requant_bias_q <= '0;
      mul_rhs_shift_q <= '0;
      mul_addend_q <= '0;
      mul_product_mag_q <= '0;
      mul_bit_q <= '0;
      mul_negative_q <= 1'b0;
      scaled_product_q <= '0;
      scaled_q_q <= '0;
      output_q_q <= '0;
      done <= 1'b0;
      debug_requant_valid <= 1'b0;
      debug_requant_addr <= '0;
      debug_requant_acc_q <= '0;
      debug_requant_scale_mul_q <= '0;
      debug_requant_bias_q <= '0;
      debug_requant_output_q <= '0;
    end else begin
      done <= 1'b0;
      debug_requant_valid <= 1'b0;

      case (post_state_q)
        POST_IDLE: begin
          if (chain_done) begin
            post_addr_q <= '0;
            sidecar_read_addr_q <= '0;
            chain_output_read_addr_q <= '0;
            post_state_q <= POST_WAIT;
          end
        end

        POST_WAIT: begin
          post_state_q <= POST_CAPTURE;
        end

        POST_CAPTURE: begin
          requant_acc_q <= chain_output_read_data[31:0];
          requant_scale_mul_q <= scale_mul_read_data_q;
          requant_bias_q <= bias_q_read_data_q;
          post_state_q <= POST_MUL_INIT;
        end

        POST_MUL_INIT: begin
          mul_rhs_shift_q <= scale_magnitude_w;
          mul_addend_q <= {32'd0, acc_magnitude_w};
          mul_product_mag_q <= 64'd0;
          mul_bit_q <= 6'd0;
          mul_negative_q <= requant_acc_q[31] ^ requant_scale_mul_q[31];
          post_state_q <= POST_MUL_STEP;
        end

        POST_MUL_STEP: begin
          mul_product_mag_q <= mul_product_next_w;
          mul_rhs_shift_q <= {1'b0, mul_rhs_shift_q[31:1]};
          mul_addend_q <= {mul_addend_q[62:0], 1'b0};

          if (mul_bit_q == LAST_MUL_BIT) begin
            scaled_product_q <=
              mul_negative_q ? -$signed(mul_product_next_w)
                             : $signed(mul_product_next_w);
            post_state_q <= POST_ROUND;
          end else begin
            mul_bit_q <= mul_bit_q + 1'b1;
          end
        end

        POST_ROUND: begin
          scaled_q_q <= scaled_q_w;
          post_state_q <= POST_BIAS;
        end

        POST_BIAS: begin
          output_q_q <= scaled_q_q + $signed({{32{requant_bias_q[31]}}, requant_bias_q});
          post_state_q <= POST_WRITE;
        end

        POST_WRITE: begin
          output_mem[post_addr_q] <= post_output_w;
          debug_requant_valid <= 1'b1;
          debug_requant_addr <= post_addr_q;
          debug_requant_acc_q <= requant_acc_q;
          debug_requant_scale_mul_q <= requant_scale_mul_q;
          debug_requant_bias_q <= requant_bias_q;
          debug_requant_output_q <= post_output_w;

          if (post_addr_q == LAST_C_PROJ_OUT_INDEX) begin
            post_state_q <= POST_IDLE;
            done <= 1'b1;
          end else begin
            post_addr_q <= post_addr_q + 1'b1;
            sidecar_read_addr_q <= post_addr_q + 1'b1;
            chain_output_read_addr_q <= post_addr_q + 1'b1;
            post_state_q <= POST_WAIT;
          end
        end

        default: begin
          post_state_q <= POST_IDLE;
        end
      endcase
    end
  end

  task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel #(
    .C_FC_IN_DIM(C_FC_IN_DIM),
    .HIDDEN_DIM(HIDDEN_DIM),
    .C_PROJ_OUT_DIM(C_PROJ_OUT_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .C_FC_PHASES(C_FC_PHASES),
    .C_FC_PACKED_WEIGHT_WORDS(C_FC_PACKED_WEIGHT_WORDS),
    .C_PROJ_PACKED_WEIGHT_WORDS(C_PROJ_PACKED_WEIGHT_WORDS),
    .X_FRAC(X_FRAC),
    .SCALE_SHIFT(SCALE_SHIFT),
    .GELU_QUAD_Q(GELU_QUAD_Q),
    .OUTPUT_REQUANT_SHIFT(OUTPUT_REQUANT_SHIFT),
    .OUTPUT_REQUANT_MULT(OUTPUT_REQUANT_MULT)
  ) chain (
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
    .start(chain_start),
    .busy(chain_busy),
    .done(chain_done),
    .output_read_addr(chain_output_read_addr_q),
    .output_read_data(chain_output_read_data)
  );
endmodule
