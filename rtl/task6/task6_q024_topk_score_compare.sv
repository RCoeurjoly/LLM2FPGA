`timescale 1ns/1ps

module task6_q024_topk_score_compare (
  input  logic               clk,
  input  logic               rst,
  input  logic               in_valid,
  input  logic [15:0]        in_token_id,
  input  logic signed [21:0] in_acc_signed,
  input  logic [31:0]        in_sidecar_word,
  output logic               out_valid,
  output logic               out_error_reserved_bits,
  output logic [15:0]        out_top_token_id,
  output logic signed [45:0] out_top_score_signed_q024
);
  localparam logic signed [45:0] SCORE_MIN = {1'b1, 45'd0};

  logic signed [45:0] top_score_q;
  logic [15:0] top_token_q;
  logic error_q;

  wire [23:0] scale_q0_24 = in_sidecar_word[23:0];
  wire reserved_nonzero = |in_sidecar_word[31:24];
  wire signed [46:0] acc_ext = {{25{in_acc_signed[21]}}, in_acc_signed};
  wire signed [46:0] scale_ext = {23'd0, scale_q0_24};
  wire signed [46:0] candidate_score_full = acc_ext * scale_ext;
  wire signed [46:0] top_score_ext = {top_score_q[45], top_score_q};

  wire candidate_wins =
    (candidate_score_full > top_score_ext) ||
    ((candidate_score_full == top_score_ext) && (in_token_id < top_token_q));

  always_ff @(posedge clk) begin
    if (rst) begin
      top_score_q <= SCORE_MIN;
      top_token_q <= 16'hffff;
      error_q <= 1'b0;
      out_valid <= 1'b0;
    end else begin
      out_valid <= in_valid;
      if (in_valid) begin
        if (reserved_nonzero) begin
          error_q <= 1'b1;
        end else if (candidate_wins) begin
          top_score_q <= candidate_score_full[45:0];
          top_token_q <= in_token_id;
        end
      end
    end
  end

  assign out_error_reserved_bits = error_q;
  assign out_top_token_id = top_token_q;
  assign out_top_score_signed_q024 = top_score_q;
endmodule
