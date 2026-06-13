`timescale 1ns/1ps

module task6_m2_embedding_block_input_accel_top (
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
  `include "task6_m2_embedding_block_input_tb_data.sv"

  typedef enum logic [2:0] {
    S_IDLE = 3'd0,
    S_CHECK_TOKENS = 3'd1,
    S_EMIT_ADD = 3'd2,
    S_DONE = 3'd3,
    S_ERROR = 3'd4,
    S_EMIT_REQUANT_PARTS = 3'd5,
    S_EMIT_REQUANT_PRODUCT = 3'd6,
    S_EMIT_WRITE = 3'd7
  } state_t;

  localparam int TOKEN_INDEX_WIDTH = $clog2(EMBED_BLOCK_SEQ);
  localparam int DIM_INDEX_WIDTH = $clog2(EMBED_BLOCK_DIM);

  state_t state_q;
  logic [TOKEN_INDEX_WIDTH - 1:0] token_index_q;
  logic [TOKEN_INDEX_WIDTH - 1:0] emit_token_index_q;
  logic [DIM_INDEX_WIDTH - 1:0] dim_index_q;
  logic [31:0] cycle_count_q;
  logic [31:0] block_input_checksum_q;
  logic [15:0] selected_token_id_w;
  logic [6:0] checksum_weight_w;
  logic [31:0] block_input_checksum_inc_w;
  logic [3:0] token_index_debug_w;
  logic [3:0] emit_token_index_debug_w;
  logic [7:0] dim_index_debug_w;
  logic signed [31:0] added_q20_w;
  logic signed [31:0] added_q20_q;
  logic signed [63:0] added_q20_ext_w;
  logic signed [63:0] added_q20_q_ext_w;
  logic signed [63:0] requant_hi_q;
  logic signed [63:0] requant_lo_q;
  logic signed [63:0] requant_product_q;
  logic signed [63:0] ln_input_q12_full_w;
  logic signed [63:0] block_input_full_w;
  logic signed [15:0] ln_input_q12_w;
  logic signed [7:0] block_input_q_w;

  assign selected_token_id_w = token_ids_i[token_index_q * 16 +: 16];
  assign checksum_weight_w = {{(7 - DIM_INDEX_WIDTH){1'b0}}, dim_index_q} + 7'd1;
  assign token_index_debug_w = {{(4 - TOKEN_INDEX_WIDTH){1'b0}}, token_index_q};
  assign emit_token_index_debug_w = {{(4 - TOKEN_INDEX_WIDTH){1'b0}}, emit_token_index_q};
  assign dim_index_debug_w = {{(8 - DIM_INDEX_WIDTH){1'b0}}, dim_index_q};
  assign added_q20_w =
    embed_block_token_embedding_q20[emit_token_index_q][dim_index_q] +
    embed_block_position_embedding_q20[emit_token_index_q][dim_index_q];
  assign added_q20_ext_w = {{32{added_q20_w[31]}}, added_q20_w};
  assign added_q20_q_ext_w = {{32{added_q20_q[31]}}, added_q20_q};

  function automatic logic signed [63:0] round_shift_signed_64(
    input logic signed [63:0] value,
    input int shift
  );
    logic signed [63:0] half;
    begin
      if (shift == 0) begin
        round_shift_signed_64 = value;
      end else begin
        half = 64'sd1 <<< (shift - 1);
        if (value >= 64'sd0) begin
          round_shift_signed_64 = (value + half) >>> shift;
        end else begin
          round_shift_signed_64 = -(((-value) + half) >>> shift);
        end
      end
    end
  endfunction

  function automatic logic signed [7:0] clamp_i8(input logic signed [63:0] value);
    begin
      if (value > 64'sd127) begin
        clamp_i8 = 8'sd127;
      end else if (value < -64'sd127) begin
        clamp_i8 = -8'sd127;
      end else begin
        clamp_i8 = value[7:0];
      end
    end
  endfunction

  assign ln_input_q12_full_w = round_shift_signed_64(added_q20_q_ext_w, EMBED_BLOCK_TO_LN_Q12_SHIFT);
  assign ln_input_q12_w = ln_input_q12_full_w[15:0];
  assign block_input_full_w = round_shift_signed_64(
    requant_product_q,
    EMBED_BLOCK_REQUANT_SHIFT
  );
  assign block_input_q_w = clamp_i8(block_input_full_w);

  always_comb begin
    block_input_checksum_inc_w = 32'd0;
    for (int checksum_bit = 0; checksum_bit < 7; checksum_bit++) begin
      if (checksum_weight_w[checksum_bit]) begin
        block_input_checksum_inc_w =
          block_input_checksum_inc_w + ({24'd0, block_input_q_w[7:0]} << checksum_bit);
      end
    end
  end

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= S_IDLE;
      token_index_q <= '0;
      emit_token_index_q <= '0;
      dim_index_q <= '0;
      cycle_count_q <= 32'd0;
      block_input_checksum_q <= 32'd0;
      added_q20_q <= 32'sd0;
      requant_hi_q <= 64'sd0;
      requant_lo_q <= 64'sd0;
      requant_product_q <= 64'sd0;
      block_input_vector_o <= 512'd0;
      ln_input_q12_by_token_o <= '0;
      debug_o <= 32'd0;
    end else if (clear_i) begin
      state_q <= S_IDLE;
      token_index_q <= '0;
      emit_token_index_q <= '0;
      dim_index_q <= '0;
      cycle_count_q <= 32'd0;
      block_input_checksum_q <= 32'd0;
      added_q20_q <= 32'sd0;
      requant_hi_q <= 64'sd0;
      requant_lo_q <= 64'sd0;
      requant_product_q <= 64'sd0;
      block_input_vector_o <= 512'd0;
      ln_input_q12_by_token_o <= '0;
      debug_o <= 32'd0;
    end else begin
      unique case (state_q)
        S_IDLE: begin
          if (start_i) begin
            state_q <= S_CHECK_TOKENS;
            token_index_q <= '0;
            emit_token_index_q <= '0;
            dim_index_q <= '0;
            cycle_count_q <= 32'd0;
            block_input_checksum_q <= 32'd0;
            added_q20_q <= 32'sd0;
            requant_hi_q <= 64'sd0;
            requant_lo_q <= 64'sd0;
            requant_product_q <= 64'sd0;
            block_input_vector_o <= 512'd0;
            ln_input_q12_by_token_o <= '0;
            debug_o <= 32'd0;
          end
        end

        S_CHECK_TOKENS: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (selected_token_id_w != embed_block_expected_token_ids[token_index_q]) begin
            state_q <= S_ERROR;
            debug_o <= {8'h01, 4'd0, token_index_debug_w, selected_token_id_w};
          end else if (token_index_q == TOKEN_INDEX_WIDTH'(EMBED_BLOCK_SEQ - 1)) begin
            emit_token_index_q <= '0;
            dim_index_q <= '0;
            state_q <= S_EMIT_ADD;
          end else begin
            token_index_q <= token_index_q + TOKEN_INDEX_WIDTH'(1);
          end
        end

        S_EMIT_ADD: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          added_q20_q <= added_q20_w;
          state_q <= S_EMIT_REQUANT_PARTS;
        end

        S_EMIT_REQUANT_PARTS: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (EMBED_BLOCK_REQUANT_MUL_Q20 == 32'sd415) begin
            requant_hi_q <= (added_q20_q_ext_w <<< 9) - (added_q20_q_ext_w <<< 6);
            requant_lo_q <= (added_q20_q_ext_w <<< 5) + added_q20_q_ext_w;
          end else begin
            requant_hi_q <=
              added_q20_q_ext_w * {{32{EMBED_BLOCK_REQUANT_MUL_Q20[31]}}, EMBED_BLOCK_REQUANT_MUL_Q20};
            requant_lo_q <= 64'sd0;
          end
          ln_input_q12_by_token_o[((emit_token_index_q * EMBED_BLOCK_DIM + dim_index_q) * 16) +: 16] <=
            ln_input_q12_w;
          if (ln_input_q12_w != embed_block_expected_ln_input_q12_by_token[emit_token_index_q][dim_index_q]) begin
            state_q <= S_ERROR;
            debug_o <= {8'h02, 4'd0, emit_token_index_debug_w, dim_index_debug_w, 8'd0};
          end else begin
            state_q <= S_EMIT_REQUANT_PRODUCT;
          end
        end

        S_EMIT_REQUANT_PRODUCT: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          requant_product_q <= requant_hi_q - requant_lo_q;
          state_q <= S_EMIT_WRITE;
        end

        S_EMIT_WRITE: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (emit_token_index_q == TOKEN_INDEX_WIDTH'(EMBED_BLOCK_SEQ - 1)) begin
            block_input_vector_o[dim_index_q * 8 +: 8] <= block_input_q_w;
            block_input_checksum_q <= block_input_checksum_q + block_input_checksum_inc_w;
            if (block_input_q_w != embed_block_expected_last_input_q[dim_index_q]) begin
              state_q <= S_ERROR;
              debug_o <= {8'h03, 8'd0, dim_index_debug_w, block_input_q_w};
            end else if (dim_index_q == DIM_INDEX_WIDTH'(EMBED_BLOCK_DIM - 1)) begin
              state_q <= S_DONE;
            end else begin
              dim_index_q <= dim_index_q + DIM_INDEX_WIDTH'(1);
              state_q <= S_EMIT_ADD;
            end
          end else if (dim_index_q == DIM_INDEX_WIDTH'(EMBED_BLOCK_DIM - 1)) begin
            emit_token_index_q <= emit_token_index_q + TOKEN_INDEX_WIDTH'(1);
            dim_index_q <= '0;
            state_q <= S_EMIT_ADD;
          end else begin
            dim_index_q <= dim_index_q + DIM_INDEX_WIDTH'(1);
            state_q <= S_EMIT_ADD;
          end
        end

        S_DONE: begin
          if (start_i) begin
            state_q <= S_CHECK_TOKENS;
            token_index_q <= '0;
            emit_token_index_q <= '0;
            dim_index_q <= '0;
            cycle_count_q <= 32'd0;
            block_input_checksum_q <= 32'd0;
            added_q20_q <= 32'sd0;
            requant_hi_q <= 64'sd0;
            requant_lo_q <= 64'sd0;
            requant_product_q <= 64'sd0;
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
      16'h4542,
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
