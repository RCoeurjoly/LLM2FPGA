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
  wire row_fire = row_valid && row_ready;
  logic signed [ACC_WIDTH - 1:0] row_acc;
  logic seen_row_q;

  function automatic logic signed [ACC_WIDTH - 1:0] dot_acc(
    input logic [HIDDEN_SIZE * 8 - 1:0] weights,
    input logic [HIDDEN_SIZE * 8 - 1:0] hidden
  );
    logic signed [ACC_WIDTH - 1:0] acc;
    logic signed [7:0] weight_value;
    logic signed [7:0] hidden_value;
    logic signed [15:0] product;
    int index;
    begin
      acc = '0;
      for (index = 0; index < HIDDEN_SIZE; index = index + 1) begin
        weight_value = weights[index * 8 +: 8];
        hidden_value = hidden[index * 8 +: 8];
        product = weight_value * hidden_value;
        acc = acc + {{(ACC_WIDTH - 16){product[15]}}, product};
      end
      dot_acc = acc;
    end
  endfunction

  assign row_ready = 1'b1;
  assign row_acc = dot_acc(row_weight_q_i8, hidden_q_i8);

  task6_q024_topk_score_compare comparator (
    .clk(clock),
    .rst(reset),
    .in_valid(row_fire),
    .in_token_id(row_token_id),
    .in_acc_signed(row_acc),
    .in_sidecar_word(row_sidecar_word),
    .out_valid(out_valid),
    .out_error_reserved_bits(out_error_reserved_bits),
    .out_top_token_id(out_top_token_id),
    .out_top_score_signed_q024(out_top_score_signed_q024)
  );

  always_ff @(posedge clock) begin
    if (reset) begin
      out_done <= 1'b0;
      out_busy <= 1'b0;
      out_rows_scanned <= 32'd0;
      out_cycle_count <= 32'd0;
      seen_row_q <= 1'b0;
    end else begin
      if (row_valid || out_busy)
        out_cycle_count <= out_cycle_count + 32'd1;

      if (row_fire) begin
        seen_row_q <= 1'b1;
        if (row_last)
          out_done <= 1'b1;
        out_busy <= !row_last;
        out_rows_scanned <= out_rows_scanned + 32'd1;
      end else if (row_valid) begin
        out_busy <= 1'b1;
      end else if (!seen_row_q) begin
        out_busy <= 1'b0;
      end
    end
  end
endmodule
