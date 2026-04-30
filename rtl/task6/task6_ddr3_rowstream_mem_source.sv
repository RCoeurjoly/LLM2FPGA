`timescale 1ns/1ps

module task6_ddr3_rowstream_mem_source #(
  parameter int HIDDEN_SIZE = 64,
  parameter int VOCAB_SIZE = 50257,
  parameter int PADDED_ROWS = 50272,
  parameter int ROW_BYTES = 68,
  parameter string ROW_MEM_HEX = "rowstream_rows.mem",
  parameter int ADDR_WIDTH = (PADDED_ROWS <= 1) ? 1 : $clog2(PADDED_ROWS)
)(
  input  logic clock,
  input  logic reset,
  input  logic start,
  output logic busy,
  output logic done,

  output logic row_valid,
  input  logic row_ready,
  output logic [15:0] row_token_id,
  output logic [HIDDEN_SIZE * 8 - 1:0] row_weight_q_i8,
  output logic [31:0] row_sidecar_word,
  output logic row_last
);
  localparam int ROW_BITS = ROW_BYTES * 8;

  logic [ADDR_WIDTH - 1:0] row_index_q;
  logic [ROW_BITS - 1:0] row_mem [0:PADDED_ROWS - 1];
  wire [ROW_BITS - 1:0] row_word = row_mem[row_index_q];
  wire final_valid_row = row_index_q == ADDR_WIDTH'(VOCAB_SIZE - 1);
  wire row_fire = row_valid && row_ready;

  initial begin
    $readmemh(ROW_MEM_HEX, row_mem);
  end

  assign row_valid = busy;
  assign row_token_id = row_index_q[15:0];
  assign row_weight_q_i8 = row_word[HIDDEN_SIZE * 8 - 1:0];
  assign row_sidecar_word = row_word[HIDDEN_SIZE * 8 +: 32];
  assign row_last = row_valid && final_valid_row;

  always_ff @(posedge clock) begin
    if (reset) begin
      busy <= 1'b0;
      done <= 1'b0;
      row_index_q <= '0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        busy <= 1'b1;
        row_index_q <= '0;
      end else if (row_fire) begin
        if (final_valid_row) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          row_index_q <= row_index_q + ADDR_WIDTH'(1);
        end
      end
    end
  end
endmodule
