`timescale 1ns/1ps

module task6_ternary_vocab_output_head_top1_kernel #(
  parameter int IN_DIM = 64,
  parameter int VOCAB_SIZE = 4096,
  parameter int VALID_VOCAB_SIZE = VOCAB_SIZE,
  parameter int TILE_OUT_DIM = 64,
  parameter int WEIGHTS_PER_WORD = 16,
  parameter int ACC_WIDTH = 32,
  parameter int PHASES = VOCAB_SIZE / TILE_OUT_DIM,
  parameter int GROUPS_PER_TILE = TILE_OUT_DIM / WEIGHTS_PER_WORD,
  parameter int TILE_PACKED_WEIGHT_WORDS = GROUPS_PER_TILE * IN_DIM,
  parameter int PACKED_WEIGHT_WORDS = PHASES * TILE_PACKED_WEIGHT_WORDS,
  parameter int TILE_PACKED_WEIGHT_ADDR_WIDTH =
    (TILE_PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(TILE_PACKED_WEIGHT_WORDS),
  parameter int GROUP_ADDR_WIDTH =
    (GROUPS_PER_TILE <= 1) ? 1 : $clog2(GROUPS_PER_TILE),
  parameter int ACTIVATION_ADDR_WIDTH = (IN_DIM <= 1) ? 1 : $clog2(IN_DIM),
  parameter int PHASE_WIDTH = (PHASES <= 1) ? 1 : $clog2(PHASES),
  parameter int OUT_ADDR_WIDTH = (VOCAB_SIZE <= 1) ? 1 : $clog2(VOCAB_SIZE),
  parameter int PACKED_WEIGHT_ADDR_WIDTH =
    (PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(PACKED_WEIGHT_WORDS)
)(
  input  logic clock,
  input  logic reset,

  input  logic weight_load_valid,
  input  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] weight_load_addr,
  input  logic [31:0] weight_load_data,

  input  logic activation_load_valid,
  input  logic [ACTIVATION_ADDR_WIDTH - 1:0] activation_load_addr,
  input  logic signed [7:0] activation_load_data,

  input  logic start,
  output logic busy,
  output logic done,

  output logic [OUT_ADDR_WIDTH - 1:0] top_index,
  output logic signed [ACC_WIDTH - 1:0] top_acc
);
  localparam logic signed [ACC_WIDTH - 1:0] MIN_ACC =
    {1'b1, {(ACC_WIDTH - 1){1'b0}}};
  localparam logic [PHASE_WIDTH - 1:0] LAST_PHASE = PHASE_WIDTH'(PHASES - 1);
  localparam logic [ACTIVATION_ADDR_WIDTH - 1:0] LAST_IN =
    ACTIVATION_ADDR_WIDTH'(IN_DIM - 1);
  localparam logic [GROUP_ADDR_WIDTH - 1:0] LAST_GROUP =
    GROUP_ADDR_WIDTH'(GROUPS_PER_TILE - 1);

  typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_CLEAR,
    STATE_RUN,
    STATE_DRAIN,
    STATE_EMIT
  } state_t;

  state_t state_q;
  logic [PHASE_WIDTH - 1:0] phase_q;
  logic [ACTIVATION_ADDR_WIDTH - 1:0] in_index_q;
  logic [GROUP_ADDR_WIDTH - 1:0] group_q;
  logic [GROUP_ADDR_WIDTH - 1:0] emit_group_q;
  logic [$clog2(TILE_OUT_DIM) - 1:0] clear_index_q;
  logic [31:0] packed_weight_data_q;
  logic [GROUP_ADDR_WIDTH - 1:0] apply_group_q;
  logic signed [7:0] apply_activation_q;
  logic apply_valid_q;
  logic [PHASE_WIDTH - 1:0] load_phase;
  logic [TILE_PACKED_WEIGHT_ADDR_WIDTH - 1:0] load_tile_addr;
  logic [TILE_PACKED_WEIGHT_ADDR_WIDTH - 1:0] read_tile_addr;
  logic [OUT_ADDR_WIDTH - 1:0] phase_base_out_addr;
  logic signed [ACC_WIDTH - 1:0] acc_q [0:TILE_OUT_DIM - 1];
  logic signed [7:0] activation_mem [0:IN_DIM - 1];
  logic [31:0] packed_weight_phase_data [0:PHASES - 1];

  assign busy = state_q != STATE_IDLE;
  assign load_phase = PHASE_WIDTH'(weight_load_addr / TILE_PACKED_WEIGHT_WORDS);
  assign load_tile_addr =
    TILE_PACKED_WEIGHT_ADDR_WIDTH'(weight_load_addr % TILE_PACKED_WEIGHT_WORDS);
  assign read_tile_addr =
    TILE_PACKED_WEIGHT_ADDR_WIDTH'(
      GROUP_ADDR_WIDTH'(group_q) * IN_DIM + ACTIVATION_ADDR_WIDTH'(in_index_q)
    );
  assign phase_base_out_addr =
    OUT_ADDR_WIDTH'(phase_q) * OUT_ADDR_WIDTH'(TILE_OUT_DIM);

  function automatic signed [1:0] decode_ternary(input logic [1:0] code);
    unique case (code)
      2'b01: decode_ternary = 2'sd1;
      2'b11: decode_ternary = -2'sd1;
      default: decode_ternary = 2'sd0;
    endcase
  endfunction

  always_ff @(posedge clock) begin
    if (activation_load_valid)
      activation_mem[activation_load_addr] <= activation_load_data;
  end

  generate
    for (genvar weight_phase = 0; weight_phase < PHASES; weight_phase = weight_phase + 1) begin : gen_weight_phase_mem
      (* ram_style = "block" *)
      logic [31:0] packed_weight_phase_mem [0:TILE_PACKED_WEIGHT_WORDS - 1];

      always_ff @(posedge clock) begin
        if (weight_load_valid && load_phase == PHASE_WIDTH'(weight_phase))
          packed_weight_phase_mem[load_tile_addr] <= weight_load_data;
        packed_weight_phase_data[weight_phase] <= packed_weight_phase_mem[read_tile_addr];
      end
    end
  endgenerate

  always_comb begin
    packed_weight_data_q = packed_weight_phase_data[phase_q];
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      state_q <= STATE_IDLE;
      phase_q <= '0;
      in_index_q <= '0;
      group_q <= '0;
      emit_group_q <= '0;
      clear_index_q <= '0;
      apply_group_q <= '0;
      apply_activation_q <= '0;
      apply_valid_q <= 1'b0;
      top_index <= '0;
      top_acc <= MIN_ACC;
      done <= 1'b0;
      for (int index = 0; index < TILE_OUT_DIM; index = index + 1)
        acc_q[index] <= '0;
    end else begin
      done <= 1'b0;

      if (apply_valid_q) begin
        for (int lane = 0; lane < WEIGHTS_PER_WORD; lane = lane + 1) begin
          unique case (decode_ternary(packed_weight_data_q[lane * 2 +: 2]))
            2'sd1: begin
              acc_q[apply_group_q * WEIGHTS_PER_WORD + lane] <=
                acc_q[apply_group_q * WEIGHTS_PER_WORD + lane] +
                apply_activation_q;
            end
            -2'sd1: begin
              acc_q[apply_group_q * WEIGHTS_PER_WORD + lane] <=
                acc_q[apply_group_q * WEIGHTS_PER_WORD + lane] -
                apply_activation_q;
            end
            default: begin
              acc_q[apply_group_q * WEIGHTS_PER_WORD + lane] <=
                acc_q[apply_group_q * WEIGHTS_PER_WORD + lane];
            end
          endcase
        end
      end

      apply_valid_q <= 1'b0;

      unique case (state_q)
        STATE_IDLE: begin
          phase_q <= '0;
          in_index_q <= '0;
          group_q <= '0;
          emit_group_q <= '0;
          clear_index_q <= '0;
          if (start) begin
            top_index <= '0;
            top_acc <= MIN_ACC;
            state_q <= STATE_CLEAR;
          end
        end

        STATE_CLEAR: begin
          acc_q[clear_index_q] <= '0;
          if (clear_index_q == $clog2(TILE_OUT_DIM)'(TILE_OUT_DIM - 1)) begin
            clear_index_q <= '0;
            in_index_q <= '0;
            group_q <= '0;
            state_q <= STATE_RUN;
          end else begin
            clear_index_q <= clear_index_q + 1'b1;
          end
        end

        STATE_RUN: begin
          apply_valid_q <= 1'b1;
          apply_group_q <= group_q;
          apply_activation_q <= activation_mem[in_index_q];

          if (group_q == LAST_GROUP) begin
            group_q <= '0;
            if (in_index_q == LAST_IN) begin
              in_index_q <= '0;
              state_q <= STATE_DRAIN;
            end else begin
              in_index_q <= in_index_q + 1'b1;
            end
          end else begin
            group_q <= group_q + 1'b1;
          end
        end

        STATE_DRAIN: begin
          state_q <= STATE_EMIT;
          emit_group_q <= '0;
        end

        STATE_EMIT: begin
          for (int lane = 0; lane < WEIGHTS_PER_WORD; lane = lane + 1) begin
            if ((phase_base_out_addr +
                 OUT_ADDR_WIDTH'(emit_group_q * WEIGHTS_PER_WORD + lane)) <
                OUT_ADDR_WIDTH'(VALID_VOCAB_SIZE) &&
                acc_q[emit_group_q * WEIGHTS_PER_WORD + lane] > top_acc) begin
              top_acc <= acc_q[emit_group_q * WEIGHTS_PER_WORD + lane];
              top_index <= phase_base_out_addr +
                OUT_ADDR_WIDTH'(emit_group_q * WEIGHTS_PER_WORD + lane);
            end
          end

          if (emit_group_q == LAST_GROUP) begin
            if (phase_q == LAST_PHASE) begin
              done <= 1'b1;
              state_q <= STATE_IDLE;
            end else begin
              phase_q <= phase_q + 1'b1;
              clear_index_q <= '0;
              state_q <= STATE_CLEAR;
            end
          end else begin
            emit_group_q <= emit_group_q + 1'b1;
          end
        end

        default: state_q <= STATE_IDLE;
      endcase
    end
  end
endmodule
