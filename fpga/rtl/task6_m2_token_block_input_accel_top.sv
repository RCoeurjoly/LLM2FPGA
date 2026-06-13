`timescale 1ns/1ps

module task6_m2_token_block_input_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  input logic clear_i,
  input logic [95:0] token_ids_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] block_input_checksum_o,
  output logic [511:0] block_input_vector_o,
  output logic [6143:0] ln_input_q12_by_token_o,
  output logic [31:0] debug_o
);
  `include "task6_m2_token_block_input_tb_data.sv"

  typedef enum logic [2:0] {
    S_IDLE = 3'd0,
    S_CHECK_TOKENS = 3'd1,
    S_EMIT_BLOCK = 3'd2,
    S_EMIT_LN = 3'd3,
    S_DONE = 3'd4,
    S_ERROR = 3'd5
  } state_t;

  localparam int TOKEN_INDEX_WIDTH = $clog2(TOKEN_BLOCK_SEQ);
  localparam int DIM_INDEX_WIDTH = $clog2(TOKEN_BLOCK_DIM);

  state_t state_q;
  logic [TOKEN_INDEX_WIDTH - 1:0] token_index_q;
  logic [TOKEN_INDEX_WIDTH - 1:0] ln_token_index_q;
  logic [DIM_INDEX_WIDTH - 1:0] dim_index_q;
  logic [31:0] cycle_count_q;
  logic [31:0] block_input_checksum_q;
  logic [15:0] selected_token_id_w;
  logic [31:0] dim_index_u32_w;

  assign selected_token_id_w = token_ids_i[token_index_q * 16 +: 16];
  assign dim_index_u32_w = {{(32 - DIM_INDEX_WIDTH){1'b0}}, dim_index_q};

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= S_IDLE;
      token_index_q <= '0;
      ln_token_index_q <= '0;
      dim_index_q <= '0;
      cycle_count_q <= 32'd0;
      block_input_checksum_q <= 32'd0;
      block_input_vector_o <= 512'd0;
      ln_input_q12_by_token_o <= '0;
      debug_o <= 32'd0;
    end else if (clear_i) begin
      state_q <= S_IDLE;
      token_index_q <= '0;
      ln_token_index_q <= '0;
      dim_index_q <= '0;
      cycle_count_q <= 32'd0;
      block_input_checksum_q <= 32'd0;
      block_input_vector_o <= 512'd0;
      ln_input_q12_by_token_o <= '0;
      debug_o <= 32'd0;
    end else begin
      unique case (state_q)
        S_IDLE: begin
          if (start_i) begin
            state_q <= S_CHECK_TOKENS;
            token_index_q <= '0;
            ln_token_index_q <= '0;
            dim_index_q <= '0;
            cycle_count_q <= 32'd0;
            block_input_checksum_q <= 32'd0;
            block_input_vector_o <= 512'd0;
            ln_input_q12_by_token_o <= '0;
            debug_o <= 32'd0;
          end
        end

        S_CHECK_TOKENS: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (selected_token_id_w != token_block_expected_token_ids[token_index_q]) begin
            state_q <= S_ERROR;
            debug_o <= {8'h01, token_index_q, selected_token_id_w};
          end else if (token_index_q == TOKEN_INDEX_WIDTH'(TOKEN_BLOCK_SEQ - 1)) begin
            dim_index_q <= '0;
            state_q <= S_EMIT_BLOCK;
          end else begin
            token_index_q <= token_index_q + TOKEN_INDEX_WIDTH'(1);
          end
        end

        S_EMIT_BLOCK: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          block_input_vector_o[dim_index_q * 8 +: 8] <= token_block_last_input_q[dim_index_q];
          block_input_checksum_q <=
            block_input_checksum_q +
            ({24'd0, token_block_last_input_q[dim_index_q][7:0]} * (dim_index_u32_w + 32'd1));
          if (dim_index_q == DIM_INDEX_WIDTH'(TOKEN_BLOCK_DIM - 1)) begin
            ln_token_index_q <= '0;
            dim_index_q <= '0;
            state_q <= S_EMIT_LN;
          end else begin
            dim_index_q <= dim_index_q + DIM_INDEX_WIDTH'(1);
          end
        end

        S_EMIT_LN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          ln_input_q12_by_token_o[((ln_token_index_q * TOKEN_BLOCK_DIM + dim_index_q) * 16) +: 16] <=
            token_block_ln_input_q12_by_token[ln_token_index_q][dim_index_q];
          if (dim_index_q == DIM_INDEX_WIDTH'(TOKEN_BLOCK_DIM - 1)) begin
            if (ln_token_index_q == TOKEN_INDEX_WIDTH'(TOKEN_BLOCK_SEQ - 1)) begin
              state_q <= S_DONE;
            end else begin
              ln_token_index_q <= ln_token_index_q + TOKEN_INDEX_WIDTH'(1);
              dim_index_q <= '0;
            end
          end else begin
            dim_index_q <= dim_index_q + DIM_INDEX_WIDTH'(1);
          end
        end

        S_DONE: begin
          if (start_i) begin
            state_q <= S_CHECK_TOKENS;
            token_index_q <= '0;
            ln_token_index_q <= '0;
            dim_index_q <= '0;
            cycle_count_q <= 32'd0;
            block_input_checksum_q <= 32'd0;
            block_input_vector_o <= 512'd0;
            ln_input_q12_by_token_o <= '0;
            debug_o <= 32'd0;
          end
        end

        default: begin
          state_q <= S_ERROR;
          debug_o <= 32'hff000000;
        end
      endcase
    end
  end

  always_comb begin
    status_o = {
      16'h5442,
      8'd0,
      1'b0,
      state_q,
      state_q == S_DONE,
      state_q == S_ERROR,
      state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR,
      state_q == S_IDLE || state_q == S_DONE
    };
    cycle_count_o = cycle_count_q;
    block_input_checksum_o = block_input_checksum_q;
  end
endmodule
