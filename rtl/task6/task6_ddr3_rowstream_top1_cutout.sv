`timescale 1ns/1ps

module task6_ddr3_rowstream_top1_cutout #(
  parameter int HIDDEN_SIZE = 64,
  parameter int ACC_WIDTH = 22
)(
  input  logic clock,
  input  logic reset,

  input  logic row_valid,
  output logic row_ready,
  input  logic [15:0] row_token_id,
  input  logic [HIDDEN_SIZE * 8 - 1:0] row_weight_q_i8,
  input  logic [31:0] row_sidecar_word,
  input  logic row_last,

  input  logic [HIDDEN_SIZE * 8 - 1:0] hidden_q_i8,

  output logic out_valid,
  output logic out_done,
  output logic out_busy,
  output logic out_error_reserved_bits,
  output logic [15:0] out_top_token_id,
  output logic signed [45:0] out_top_score_signed_q024,
  output logic [31:0] out_rows_scanned,
  output logic [31:0] out_cycle_count
);
  localparam logic signed [45:0] SCORE_MIN = {1'b1, 45'd0};
  localparam int INDEX_WIDTH = (HIDDEN_SIZE <= 1) ? 1 : $clog2(HIDDEN_SIZE);

  typedef enum logic [1:0] {
    S_IDLE = 2'd0,
    S_ACCUM = 2'd1,
    S_SCORE = 2'd2,
    S_DONE = 2'd3
  } state_t;

  state_t state_q;
  logic [15:0] token_q;
  logic last_q;
  logic [31:0] sidecar_q;
  logic [HIDDEN_SIZE * 8 - 1:0] weights_q;
  logic [INDEX_WIDTH - 1:0] index_q;
  logic signed [ACC_WIDTH - 1:0] acc_q;
  logic signed [45:0] top_score_q;
  logic [15:0] top_token_q;
  logic seen_row_q;

  wire row_fire = row_valid && row_ready;
  wire signed [7:0] weight_value = weights_q[index_q * 8 +: 8];
  wire signed [7:0] hidden_value = hidden_q_i8[index_q * 8 +: 8];
  wire signed [15:0] product = weight_value * hidden_value;
  wire signed [ACC_WIDTH - 1:0] product_ext = {{(ACC_WIDTH - 16){product[15]}}, product};
  wire signed [ACC_WIDTH - 1:0] acc_next = acc_q + product_ext;
  wire [23:0] scale_q0_24 = sidecar_q[23:0];
  wire reserved_nonzero = |sidecar_q[31:24];
  wire signed [46:0] acc_ext = {{25{acc_q[ACC_WIDTH - 1]}}, acc_q};
  wire signed [46:0] scale_ext = {23'd0, scale_q0_24};
  wire signed [46:0] candidate_score_full = acc_ext * scale_ext;
  wire signed [46:0] top_score_ext = {top_score_q[45], top_score_q};
  wire candidate_wins =
    (candidate_score_full > top_score_ext) ||
    ((candidate_score_full == top_score_ext) && (token_q < top_token_q));

  assign row_ready = (state_q == S_IDLE);
  assign out_top_token_id = top_token_q;
  assign out_top_score_signed_q024 = top_score_q;

  always_ff @(posedge clock) begin
    if (reset) begin
      state_q <= S_IDLE;
      token_q <= 16'd0;
      last_q <= 1'b0;
      sidecar_q <= 32'd0;
      weights_q <= '0;
      index_q <= '0;
      acc_q <= '0;
      top_score_q <= SCORE_MIN;
      top_token_q <= 16'hffff;
      seen_row_q <= 1'b0;
      out_valid <= 1'b0;
      out_done <= 1'b0;
      out_busy <= 1'b0;
      out_error_reserved_bits <= 1'b0;
      out_rows_scanned <= 32'd0;
      out_cycle_count <= 32'd0;
    end else begin
      out_valid <= 1'b0;

      if (row_valid || out_busy)
        out_cycle_count <= out_cycle_count + 32'd1;

      case (state_q)
      S_IDLE: begin
        if (row_fire) begin
          token_q <= row_token_id;
          last_q <= row_last;
          sidecar_q <= row_sidecar_word;
          weights_q <= row_weight_q_i8;
          index_q <= '0;
          acc_q <= '0;
          seen_row_q <= 1'b1;
          out_busy <= 1'b1;
          state_q <= S_ACCUM;
        end else if (!seen_row_q) begin
          out_busy <= 1'b0;
        end
      end

      S_ACCUM: begin
        acc_q <= acc_next;
        if (index_q == INDEX_WIDTH'(HIDDEN_SIZE - 1)) begin
          state_q <= S_SCORE;
        end else begin
          index_q <= index_q + 1'b1;
        end
      end

      S_SCORE: begin
        out_valid <= 1'b1;
        out_rows_scanned <= out_rows_scanned + 32'd1;
        if (reserved_nonzero) begin
          out_error_reserved_bits <= 1'b1;
        end else if (candidate_wins) begin
          top_score_q <= candidate_score_full[45:0];
          top_token_q <= token_q;
        end

        if (last_q) begin
          out_done <= 1'b1;
          out_busy <= 1'b0;
          state_q <= S_DONE;
        end else begin
          state_q <= S_IDLE;
        end
      end

      S_DONE: begin
        out_busy <= 1'b0;
      end

      default: state_q <= S_IDLE;
      endcase
    end
  end
endmodule
