`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel #(
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
  parameter int OUTPUT_REQUANT_MULT = 8032
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

  input  logic start,
  output logic busy,
  output logic done,

  input  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] output_read_addr,
  output logic signed [ACC_WIDTH - 1:0] output_read_data
);
  localparam logic [HIDDEN_ADDR_WIDTH - 1:0] LAST_HIDDEN_INDEX =
    HIDDEN_ADDR_WIDTH'(HIDDEN_DIM - 1);

  typedef enum logic [2:0] {
    CHAIN_IDLE,
    CHAIN_START_C_FC,
    CHAIN_WAIT_C_FC,
    CHAIN_TRANSFER_WAIT,
    CHAIN_TRANSFER_WRITE,
    CHAIN_START_C_PROJ,
    CHAIN_WAIT_C_PROJ
  } chain_state_t;

  chain_state_t state_q;
  logic [HIDDEN_ADDR_WIDTH - 1:0] transfer_addr_q;

  logic c_fc_start;
  logic c_fc_busy;
  logic c_fc_done;
  logic [HIDDEN_ADDR_WIDTH - 1:0] c_fc_output_read_addr_q;
  logic signed [7:0] c_fc_output_read_data;

  logic c_proj_start;
  logic c_proj_busy;
  logic c_proj_done;
  logic c_proj_activation_load_valid;
  logic [HIDDEN_ADDR_WIDTH - 1:0] c_proj_activation_load_addr;
  logic signed [7:0] c_proj_activation_load_data;

  assign c_fc_start = state_q == CHAIN_START_C_FC;
  assign c_proj_start = state_q == CHAIN_START_C_PROJ;
  assign busy = (state_q != CHAIN_IDLE) || c_fc_busy || c_proj_busy;

  assign c_proj_activation_load_valid = state_q == CHAIN_TRANSFER_WRITE;
  assign c_proj_activation_load_addr = transfer_addr_q;
  assign c_proj_activation_load_data = c_fc_output_read_data;

  always_ff @(posedge clock) begin
    if (reset) begin
      state_q <= CHAIN_IDLE;
      transfer_addr_q <= '0;
      c_fc_output_read_addr_q <= '0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      case (state_q)
        CHAIN_IDLE: begin
          transfer_addr_q <= '0;
          c_fc_output_read_addr_q <= '0;
          if (start)
            state_q <= CHAIN_START_C_FC;
        end

        CHAIN_START_C_FC: begin
          state_q <= CHAIN_WAIT_C_FC;
        end

        CHAIN_WAIT_C_FC: begin
          if (c_fc_done) begin
            transfer_addr_q <= '0;
            c_fc_output_read_addr_q <= '0;
            state_q <= CHAIN_TRANSFER_WAIT;
          end
        end

        CHAIN_TRANSFER_WAIT: begin
          state_q <= CHAIN_TRANSFER_WRITE;
        end

        CHAIN_TRANSFER_WRITE: begin
          if (transfer_addr_q == LAST_HIDDEN_INDEX) begin
            transfer_addr_q <= '0;
            c_fc_output_read_addr_q <= '0;
            state_q <= CHAIN_START_C_PROJ;
          end else begin
            transfer_addr_q <= transfer_addr_q + 1'b1;
            c_fc_output_read_addr_q <= transfer_addr_q + 1'b1;
            state_q <= CHAIN_TRANSFER_WAIT;
          end
        end

        CHAIN_START_C_PROJ: begin
          state_q <= CHAIN_WAIT_C_PROJ;
        end

        CHAIN_WAIT_C_PROJ: begin
          if (c_proj_done) begin
            state_q <= CHAIN_IDLE;
            done <= 1'b1;
          end
        end

        default: begin
          state_q <= CHAIN_IDLE;
        end
      endcase
    end
  end

  task6_int8_l2_c_fc_post_gelu_requant_kernel #(
    .IN_DIM(C_FC_IN_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .OUT_DIM(HIDDEN_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .PHASES(C_FC_PHASES),
    .PACKED_WEIGHT_WORDS(C_FC_PACKED_WEIGHT_WORDS),
    .X_FRAC(X_FRAC),
    .SCALE_SHIFT(SCALE_SHIFT),
    .GELU_QUAD_Q(GELU_QUAD_Q),
    .OUTPUT_REQUANT_SHIFT(OUTPUT_REQUANT_SHIFT),
    .OUTPUT_REQUANT_MULT(OUTPUT_REQUANT_MULT)
  ) c_fc (
    .clock(clock),
    .reset(reset),
    .weight_load_valid(c_fc_weight_load_valid),
    .weight_load_addr(c_fc_weight_load_addr),
    .weight_load_data(c_fc_weight_load_data),
    .activation_load_valid(c_fc_activation_load_valid),
    .activation_load_addr(c_fc_activation_load_addr),
    .activation_load_data(c_fc_activation_load_data),
    .requant_load_valid(c_fc_requant_load_valid),
    .requant_load_addr(c_fc_requant_load_addr),
    .requant_scale_mul_load_data(c_fc_requant_scale_mul_load_data),
    .requant_bias_q_load_data(c_fc_requant_bias_q_load_data),
    .start(c_fc_start),
    .busy(c_fc_busy),
    .done(c_fc_done),
    .output_read_addr(c_fc_output_read_addr_q),
    .output_read_data(c_fc_output_read_data)
  );

  task6_int8_l2_c_proj_from_post_gelu_kernel #(
    .IN_DIM(HIDDEN_DIM),
    .OUT_DIM(C_PROJ_OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .PACKED_WEIGHT_WORDS(C_PROJ_PACKED_WEIGHT_WORDS)
  ) c_proj (
    .clock(clock),
    .reset(reset),
    .weight_load_valid(c_proj_weight_load_valid),
    .weight_load_addr(c_proj_weight_load_addr),
    .weight_load_data(c_proj_weight_load_data),
    .activation_load_valid(c_proj_activation_load_valid),
    .activation_load_addr(c_proj_activation_load_addr),
    .activation_load_data(c_proj_activation_load_data),
    .start(c_proj_start),
    .busy(c_proj_busy),
    .done(c_proj_done),
    .output_read_addr(output_read_addr),
    .output_read_data(output_read_data)
  );
endmodule
