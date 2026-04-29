`timescale 1ns/1ps

module task6_int8_gemv64_lanes4_packed_sync_kernel #(
  parameter int IN_DIM = 64,
  parameter int OUT_DIM = 64,
  parameter int LANES = 4,
  parameter int ACC_WIDTH = 32,
  parameter int IN_ADDR_WIDTH = (IN_DIM <= 1) ? 1 : $clog2(IN_DIM),
  parameter int PACKED_WEIGHT_WORDS = (OUT_DIM / LANES) * IN_DIM,
  parameter int PACKED_WEIGHT_ADDR_WIDTH =
    (PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(PACKED_WEIGHT_WORDS),
  parameter int OUT_ADDR_WIDTH = (OUT_DIM <= 1) ? 1 : $clog2(OUT_DIM),
  parameter int LANE_ADDR_WIDTH = (LANES <= 1) ? 1 : $clog2(LANES),
  parameter int DEBUG_SAMPLE_COUNT = 8,
  parameter int DEBUG_SAMPLE_WIDTH = 128,
  parameter int DEBUG_LANE_INDEX = 0
)(
  input  logic clock,
  input  logic reset,
  input  logic start,
  output logic busy,
  output logic done,

  output logic [IN_ADDR_WIDTH - 1:0] activation_addr,
  input  logic signed [7:0] activation_data,

  output logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] packed_weight_addr,
  input  logic [LANES * 8 - 1:0] packed_weight_data,

  output logic [OUT_ADDR_WIDTH - 1:0] out_addr,
  output logic signed [ACC_WIDTH - 1:0] out_data,
  output logic out_valid,
  input  logic out_ready,

  output logic [DEBUG_SAMPLE_COUNT * DEBUG_SAMPLE_WIDTH - 1:0] debug_lane0_samples,
  output logic [3:0] debug_lane0_sample_count,
  output logic signed [ACC_WIDTH - 1:0] debug_lane0_final_acc
);
  localparam int PRODUCT_WIDTH = 16;
  localparam logic [IN_ADDR_WIDTH - 1:0] LAST_IN_INDEX = IN_ADDR_WIDTH'(IN_DIM - 1);
  localparam logic [IN_ADDR_WIDTH - 1:0] DEBUG_INDEX_Q1 =
    IN_ADDR_WIDTH'((IN_DIM / 4) - 1);
  localparam logic [IN_ADDR_WIDTH - 1:0] DEBUG_INDEX_Q2 =
    IN_ADDR_WIDTH'((IN_DIM / 2) - 1);
  localparam logic [IN_ADDR_WIDTH - 1:0] DEBUG_INDEX_Q3 =
    IN_ADDR_WIDTH'(((IN_DIM * 3) / 4) - 1);
  localparam logic [3:0] DEBUG_SAMPLE_LIMIT = 4'(DEBUG_SAMPLE_COUNT);
  localparam logic [LANE_ADDR_WIDTH - 1:0] DEBUG_LANE =
    LANE_ADDR_WIDTH'(DEBUG_LANE_INDEX);
  localparam logic [OUT_ADDR_WIDTH - 1:0] LAST_OUT_BASE = OUT_ADDR_WIDTH'(OUT_DIM - LANES);
  localparam logic [LANE_ADDR_WIDTH - 1:0] LAST_LANE_INDEX = LANE_ADDR_WIDTH'(LANES - 1);
  localparam logic [OUT_ADDR_WIDTH - 1:0] OUT_TILE_STRIDE = OUT_ADDR_WIDTH'(LANES);
  localparam logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] PACKED_TILE_STRIDE =
    PACKED_WEIGHT_ADDR_WIDTH'(IN_DIM);

  typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_PRIME,
    STATE_RUN,
    STATE_EMIT
  } state_t;

  state_t state_q;
  logic [IN_ADDR_WIDTH - 1:0] issue_index_q;
  logic [IN_ADDR_WIDTH - 1:0] mac_index_q;
  logic [OUT_ADDR_WIDTH - 1:0] out_base_q;
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] packed_base_q;
  logic [LANE_ADDR_WIDTH - 1:0] emit_lane_q;
  logic [LANE_ADDR_WIDTH - 1:0] emit_lane_next_w;
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] issue_index_ext_w;
  logic signed [ACC_WIDTH - 1:0] acc_q [LANES];
  logic signed [PRODUCT_WIDTH - 1:0] product_w [LANES];
  logic signed [ACC_WIDTH - 1:0] product_ext_w [LANES];
  logic signed [ACC_WIDTH - 1:0] acc_next_w [LANES];
  logic debug_take_lane0_sample_w;
  logic [DEBUG_SAMPLE_WIDTH - 1:0] debug_lane0_sample_w;
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] debug_packed_weight_data_addr_w;
  logic [7:0] debug_mac_index_w;
  logic [7:0] debug_issue_index_w;
  logic [15:0] debug_weight_addr_w;

  assign busy = state_q != STATE_IDLE;
  assign activation_addr = mac_index_q;
  assign packed_weight_addr = packed_base_q + issue_index_ext_w;
  assign emit_lane_next_w = emit_lane_q + 1'b1;
  assign issue_index_ext_w = PACKED_WEIGHT_ADDR_WIDTH'(issue_index_q);
  assign debug_packed_weight_data_addr_w =
    packed_base_q + PACKED_WEIGHT_ADDR_WIDTH'(mac_index_q);
  assign debug_mac_index_w = 8'(mac_index_q);
  assign debug_issue_index_w = 8'(issue_index_q);
  assign debug_weight_addr_w = 16'(debug_packed_weight_data_addr_w);
  assign debug_take_lane0_sample_w =
    (state_q == STATE_RUN) &&
    (out_base_q == '0) &&
    (debug_lane0_sample_count < DEBUG_SAMPLE_LIMIT) &&
    ((mac_index_q == IN_ADDR_WIDTH'(0)) ||
     (mac_index_q == IN_ADDR_WIDTH'(1)) ||
     (mac_index_q == IN_ADDR_WIDTH'(2)) ||
     (mac_index_q == IN_ADDR_WIDTH'(3)) ||
     (mac_index_q == DEBUG_INDEX_Q1) ||
     (mac_index_q == DEBUG_INDEX_Q2) ||
     (mac_index_q == DEBUG_INDEX_Q3) ||
     (mac_index_q == LAST_IN_INDEX));

  genvar lane;
  generate
    for (lane = 0; lane < LANES; lane = lane + 1) begin : gen_lane
      assign product_w[lane] =
        activation_data * $signed(packed_weight_data[lane * 8 +: 8]);
      assign product_ext_w[lane] =
        {{(ACC_WIDTH - PRODUCT_WIDTH){product_w[lane][PRODUCT_WIDTH - 1]}}, product_w[lane]};
      assign acc_next_w[lane] = acc_q[lane] + product_ext_w[lane];
    end
  endgenerate

  always_comb begin
    debug_lane0_sample_w = '0;
    debug_lane0_sample_w[0 +: 8] = debug_mac_index_w;
    debug_lane0_sample_w[8 +: 8] = debug_issue_index_w;
    debug_lane0_sample_w[16 +: 16] = debug_weight_addr_w;
    debug_lane0_sample_w[32 +: 8] = activation_data;
    debug_lane0_sample_w[40 +: 8] =
      packed_weight_data[DEBUG_LANE_INDEX * 8 +: 8];
    debug_lane0_sample_w[48 +: 16] = product_w[DEBUG_LANE_INDEX];
    debug_lane0_sample_w[64 +: 32] = acc_q[DEBUG_LANE_INDEX];
    debug_lane0_sample_w[96 +: 32] = acc_next_w[DEBUG_LANE_INDEX];
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      state_q <= STATE_IDLE;
      done <= 1'b0;
      issue_index_q <= '0;
      mac_index_q <= '0;
      out_base_q <= '0;
      packed_base_q <= '0;
      emit_lane_q <= '0;
      out_addr <= '0;
      out_data <= '0;
      out_valid <= 1'b0;
      debug_lane0_samples <= '0;
      debug_lane0_sample_count <= '0;
      debug_lane0_final_acc <= '0;
      for (int lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
        acc_q[lane_index] <= '0;
    end else begin
      done <= 1'b0;
      case (state_q)
        STATE_IDLE: begin
          out_valid <= 1'b0;
          if (start) begin
            state_q <= STATE_PRIME;
            issue_index_q <= '0;
            mac_index_q <= '0;
            out_base_q <= '0;
            packed_base_q <= '0;
            emit_lane_q <= '0;
            debug_lane0_samples <= '0;
            debug_lane0_sample_count <= '0;
            debug_lane0_final_acc <= '0;
            for (int lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
              acc_q[lane_index] <= '0;
          end
        end

        STATE_PRIME: begin
          issue_index_q <= IN_ADDR_WIDTH'(1);
          mac_index_q <= '0;
          state_q <= STATE_RUN;
        end

        STATE_RUN: begin
          for (int lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
            acc_q[lane_index] <= acc_next_w[lane_index];
          if (debug_take_lane0_sample_w) begin
            unique case (debug_lane0_sample_count)
              4'd0: debug_lane0_samples[0 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              4'd1: debug_lane0_samples[128 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              4'd2: debug_lane0_samples[256 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              4'd3: debug_lane0_samples[384 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              4'd4: debug_lane0_samples[512 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              4'd5: debug_lane0_samples[640 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              4'd6: debug_lane0_samples[768 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              4'd7: debug_lane0_samples[896 +: DEBUG_SAMPLE_WIDTH] <= debug_lane0_sample_w;
              default: begin
              end
            endcase
            debug_lane0_sample_count <= debug_lane0_sample_count + 1'b1;
          end
          if ((out_base_q == '0) && (mac_index_q == LAST_IN_INDEX))
            debug_lane0_final_acc <= acc_next_w[DEBUG_LANE_INDEX];
          if (mac_index_q == LAST_IN_INDEX) begin
            out_addr <= out_base_q;
            out_data <= acc_next_w[0];
            out_valid <= 1'b1;
            issue_index_q <= '0;
            mac_index_q <= '0;
            emit_lane_q <= '0;
            state_q <= STATE_EMIT;
          end else begin
            mac_index_q <= mac_index_q + 1'b1;
            if (issue_index_q != LAST_IN_INDEX)
              issue_index_q <= issue_index_q + 1'b1;
          end
        end

        STATE_EMIT: begin
          if (out_valid && out_ready) begin
            if (emit_lane_q == LAST_LANE_INDEX) begin
              out_valid <= 1'b0;
              for (int lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
                acc_q[lane_index] <= '0;
              if (out_base_q == LAST_OUT_BASE) begin
                done <= 1'b1;
                state_q <= STATE_IDLE;
              end else begin
                out_base_q <= out_base_q + OUT_TILE_STRIDE;
                packed_base_q <= packed_base_q + PACKED_TILE_STRIDE;
                issue_index_q <= '0;
                mac_index_q <= '0;
                state_q <= STATE_PRIME;
              end
            end else begin
              emit_lane_q <= emit_lane_next_w;
              out_addr <= out_base_q + OUT_ADDR_WIDTH'(emit_lane_next_w);
              out_data <= acc_q[emit_lane_next_w];
            end
          end
        end

        default: begin
          state_q <= STATE_IDLE;
        end
      endcase
    end
  end
endmodule
