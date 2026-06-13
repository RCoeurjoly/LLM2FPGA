`timescale 1ns/1ps

module task6_m2_ln_attn_live_kv_all_heads_context_accel_top #(
  parameter bit ENABLE_INTERNAL_CHECKS = 1'b0
) (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  input logic clear_i,
  input logic use_external_ln_input_i,
  input logic [CACHE_SEQ*LN_DIM*16-1:0] external_ln_input_q12_by_token_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] output_checksum_o,
  output logic [31:0] output_sample0_o,
  output logic [31:0] output_sample1_o,
  output logic [511:0] output_vector_o,
  output logic [31:0] debug_o,
  output logic [31:0] debug1_o,
  output logic [31:0] debug2_o
);
  `include "task6_m2_ln_attn_live_kv_all_heads_context_tb_data.sv"

  typedef enum logic [3:0] {
    S_IDLE = 4'd0,
    S_ACCUM_MEAN = 4'd1,
    S_RUN_LN = 4'd2,
    S_RUN_PROJ = 4'd3,
    S_RUN_SCORE = 4'd4,
    S_RUN_VALUE = 4'd5,
    S_DONE = 4'd6,
    S_ERROR = 4'd7,
    S_RUN_PROB_WEIGHT = 4'd8,
    S_RUN_PROB_NORM = 4'd9,
    S_RUN_PROB_DIV = 4'd10,
    S_RUN_PROB_CHECK = 4'd11
  } state_t;

  localparam int TOKEN_WIDTH = (CACHE_SEQ <= 1) ? 1 : $clog2(CACHE_SEQ);
  localparam int LN_INDEX_WIDTH = $clog2(LN_DIM);
  localparam int ATTN_DIM_WIDTH = $clog2(ATTN_HEAD_DIM);
  localparam int HEAD_WIDTH = (NUM_HEADS <= 1) ? 1 : $clog2(NUM_HEADS);
  localparam int CONTEXT_INDEX_WIDTH = $clog2(CONTEXT_DIM);

  state_t state_q;
  logic [HEAD_WIDTH - 1:0] head_index_q;
  logic [TOKEN_WIDTH - 1:0] token_index_q;
  logic [TOKEN_WIDTH - 1:0] src_index_q;
  logic [LN_INDEX_WIDTH - 1:0] mean_index_q;
  logic [LN_INDEX_WIDTH - 1:0] ln_index_q;
  logic [LN_INDEX_WIDTH - 1:0] proj_index_q;
  logic [ATTN_DIM_WIDTH - 1:0] dim_index_q;
  logic [31:0] cycle_count_q;
  logic [31:0] debug_q;

  logic signed [31:0] ln_mean_acc_q12;
  logic signed [31:0] ln_mean_latched_q12;
  logic signed [31:0] k_proj_acc_q;
  logic signed [31:0] v_proj_acc_q;
  logic signed [31:0] q_proj_acc_q;
  logic signed [7:0] ln_output_cache_q [0:LN_DIM-1];
  logic signed [7:0] k_cache_q [0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];
  logic signed [7:0] v_cache_q [0:CACHE_SEQ-1][0:ATTN_HEAD_DIM-1];
  logic signed [7:0] q_final_q [0:ATTN_HEAD_DIM-1];
  logic signed [31:0] score_cache_q [0:CACHE_SEQ-1];
  logic signed [31:0] max_score_q;
  logic [31:0] weight_cache_q [0:CACHE_SEQ-1];
  logic [15:0] prob_cache_q [0:CACHE_SEQ-1];
  logic [31:0] softmax_denom_q;
  logic [31:0] prob_sum_q;
  logic [31:0] prob_norm_q;
  logic [31:0] div_numer_q;
  logic [31:0] div_denom_q;
  logic [32:0] div_remainder_q;
  logic [31:0] div_quotient_q;
  logic [5:0] div_bit_q;

  logic signed [15:0] ln_input_q12_w;
  logic signed [15:0] ln_current_input_q12_w;
  logic signed [15:0] ln_center_input_q12_w;
  logic signed [31:0] ln_mean_next_acc_q12_w;
  logic signed [63:0] ln_mean_next_shifted_w;
  logic signed [31:0] ln_centered_q12_w;
  logic signed [63:0] ln_norm_product_w;
  logic signed [63:0] ln_norm_shifted_w;
  logic signed [31:0] ln_norm_q12_w;
  logic signed [63:0] ln_affine_product_w;
  logic signed [63:0] ln_affine_shifted_w;
  logic signed [31:0] ln_affine_q12_w;
  logic signed [63:0] ln_output_product_w;
  logic signed [63:0] ln_output_shifted_w;
  logic signed [31:0] ln_output_scaled_w;
  logic signed [7:0] ln_output_w;
  logic signed [31:0] k_proj_next_acc_w;
  logic signed [31:0] v_proj_next_acc_w;
  logic signed [31:0] q_proj_next_acc_w;
  logic signed [63:0] k_proj_output_product_w;
  logic signed [63:0] v_proj_output_product_w;
  logic signed [63:0] q_proj_output_product_w;
  logic signed [63:0] k_proj_output_shifted_w;
  logic signed [63:0] v_proj_output_shifted_w;
  logic signed [63:0] q_proj_output_shifted_w;
  logic signed [7:0] k_proj_output_w;
  logic signed [7:0] v_proj_output_w;
  logic signed [7:0] q_proj_output_w;
  logic signed [31:0] score_acc_w;
  logic signed [31:0] value_acc_w;
  logic signed [63:0] value_shifted_w;
  logic signed [7:0] value_q_w;
  logic signed [63:0] context_requant_product_w;
  logic signed [63:0] context_requant_shifted_w;
  logic signed [7:0] context_q_w;
  logic signed [31:0] score_delta_w;
  logic signed [63:0] score_delta_scaled_w;
  logic signed [63:0] softmax_x_q12_w;
  logic signed [63:0] softmax_term1_w;
  logic signed [63:0] softmax_term2_w;
  logic signed [63:0] softmax_weight_raw_w;
  logic [31:0] softmax_weight_w;
  logic [31:0] prob_numer_w;
  logic [15:0] prob_current_w;
  logic [5:0] div_next_bit_w;
  logic [32:0] div_trial_remainder_w;
  logic div_subtract_w;
  logic [31:0] head_index_u32_w;
  logic [31:0] token_index_u32_w;
  logic [31:0] src_index_u32_w;
  logic [31:0] dim_index_u32_w;
  logic [31:0] context_index_u32_w;
  logic [31:0] ln_mean_flat_index_w;
  logic [31:0] ln_center_flat_index_w;
  logic [CONTEXT_INDEX_WIDTH - 1:0] context_index_w;

  function automatic signed [63:0] round_shift_signed64(
    input signed [63:0] value,
    input int shift
  );
    logic signed [63:0] abs_value;
    begin
      if (shift == 0) begin
        round_shift_signed64 = value;
      end else if (value >= 0) begin
        round_shift_signed64 = (value + (64'sd1 <<< (shift - 1))) >>> shift;
      end else begin
        abs_value = -value;
        round_shift_signed64 =
          -((abs_value + (64'sd1 <<< (shift - 1))) >>> shift);
      end
    end
  endfunction

  function automatic signed [7:0] saturate_i8(input signed [31:0] value);
    begin
      if (value > 32'sd127) begin
        saturate_i8 = 8'sd127;
      end else if (value < -32'sd127) begin
        saturate_i8 = -8'sd127;
      end else begin
        saturate_i8 = value[7:0];
      end
    end
  endfunction

  assign head_index_u32_w = {{(32 - HEAD_WIDTH){1'b0}}, head_index_q};
  assign token_index_u32_w = {{(32 - TOKEN_WIDTH){1'b0}}, token_index_q};
  assign src_index_u32_w = {{(32 - TOKEN_WIDTH){1'b0}}, src_index_q};
  assign dim_index_u32_w = {{(32 - ATTN_DIM_WIDTH){1'b0}}, dim_index_q};
  assign context_index_w =
    (head_index_q * CONTEXT_INDEX_WIDTH'(ATTN_HEAD_DIM)) +
    {{(CONTEXT_INDEX_WIDTH - ATTN_DIM_WIDTH){1'b0}}, dim_index_q};
  assign context_index_u32_w = {{(32 - CONTEXT_INDEX_WIDTH){1'b0}}, context_index_w};
  assign ln_mean_flat_index_w = (token_index_u32_w * 32'(LN_DIM)) +
    {{(32 - LN_INDEX_WIDTH){1'b0}}, mean_index_q};
  assign ln_center_flat_index_w = (token_index_u32_w * 32'(LN_DIM)) +
    {{(32 - LN_INDEX_WIDTH){1'b0}}, ln_index_q};
  assign ln_current_input_q12_w = use_external_ln_input_i ?
    $signed(external_ln_input_q12_by_token_i[(ln_mean_flat_index_w * 32'd16) +: 16]) :
    ln_input_q12_by_token[token_index_q][mean_index_q];
  assign ln_center_input_q12_w = use_external_ln_input_i ?
    $signed(external_ln_input_q12_by_token_i[(ln_center_flat_index_w * 32'd16) +: 16]) :
    ln_input_q12_by_token[token_index_q][ln_index_q];
  assign ln_input_q12_w = ln_current_input_q12_w;
  assign ln_mean_next_acc_q12_w =
    ln_mean_acc_q12 + $signed({{16{ln_input_q12_w[15]}}, ln_input_q12_w});
  assign ln_mean_next_shifted_w =
    round_shift_signed64({{32{ln_mean_next_acc_q12_w[31]}}, ln_mean_next_acc_q12_w}, 6);
  assign ln_centered_q12_w =
    $signed({{16{ln_center_input_q12_w[15]}}, ln_center_input_q12_w}) -
    $signed(ln_mean_latched_q12);
  assign ln_norm_product_w =
    $signed(ln_centered_q12_w) *
    $signed(ln_inv_std_q16_by_token[token_index_q]);
  assign ln_norm_shifted_w = round_shift_signed64(ln_norm_product_w, 16);
  assign ln_norm_q12_w = $signed(ln_norm_shifted_w[31:0]);
  assign ln_affine_product_w =
    $signed(ln_norm_q12_w) * $signed(ln_gamma_q16[ln_index_q]);
  assign ln_affine_shifted_w = round_shift_signed64(ln_affine_product_w, 16);
  assign ln_affine_q12_w =
    $signed(ln_affine_shifted_w[31:0]) +
    $signed({{16{ln_beta_q12[ln_index_q][15]}}, ln_beta_q12[ln_index_q]});
  assign ln_output_product_w =
    $signed(ln_affine_q12_w) *
    $signed(ln_output_scale_mul_q20_by_token[token_index_q]);
  assign ln_output_shifted_w = round_shift_signed64(ln_output_product_w, 20);
  assign ln_output_scaled_w = $signed(ln_output_shifted_w[31:0]);
  assign ln_output_w = saturate_i8(ln_output_scaled_w);
  assign debug1_o = {ln_mean_latched_q12[15:0], ln_centered_q12_w[15:0]};
  assign debug2_o = {ln_norm_q12_w[15:0], ln_affine_q12_w[15:0]};

  assign k_proj_next_acc_w =
    k_proj_acc_q +
    ($signed(ln_output_cache_q[proj_index_q]) *
     $signed(k_proj_weight_q[head_index_q][dim_index_q][proj_index_q]));
  assign v_proj_next_acc_w =
    v_proj_acc_q +
    ($signed(ln_output_cache_q[proj_index_q]) *
     $signed(v_proj_weight_q[head_index_q][dim_index_q][proj_index_q]));
  assign q_proj_next_acc_w =
    q_proj_acc_q +
    ($signed(ln_output_cache_q[proj_index_q]) *
     $signed(q_proj_weight_q[head_index_q][dim_index_q][proj_index_q]));
  assign k_proj_output_product_w =
    $signed(k_proj_next_acc_w) *
    $signed(k_proj_output_mul_q20_by_token[head_index_q][token_index_q][dim_index_q]);
  assign v_proj_output_product_w =
    $signed(v_proj_next_acc_w) *
    $signed(v_proj_output_mul_q20_by_token[head_index_q][token_index_q][dim_index_q]);
  assign q_proj_output_product_w =
    $signed(q_proj_next_acc_w) *
    $signed(q_proj_output_mul_q20_final[head_index_q][dim_index_q]);
  assign k_proj_output_shifted_w = round_shift_signed64(k_proj_output_product_w, 20);
  assign v_proj_output_shifted_w = round_shift_signed64(v_proj_output_product_w, 20);
  assign q_proj_output_shifted_w = round_shift_signed64(q_proj_output_product_w, 20);
  assign k_proj_output_w = saturate_i8($signed(k_proj_output_shifted_w[31:0]));
  assign v_proj_output_w = saturate_i8($signed(v_proj_output_shifted_w[31:0]));
  assign q_proj_output_w = saturate_i8($signed(q_proj_output_shifted_w[31:0]));

  integer score_dim;
  always_comb begin
    score_acc_w = 32'sd0;
    for (score_dim = 0; score_dim < ATTN_HEAD_DIM; score_dim = score_dim + 1) begin
      score_acc_w =
        score_acc_w +
        ($signed(q_final_q[score_dim]) *
         $signed(k_cache_q[src_index_q][score_dim]));
    end
  end

  integer value_src;
  always_comb begin
    value_acc_w = 32'sd0;
    for (value_src = 0; value_src < CACHE_SEQ; value_src = value_src + 1) begin
      value_acc_w =
        value_acc_w +
        ($signed({1'b0, prob_cache_q[value_src]}) *
         $signed(v_cache_q[value_src][dim_index_q]));
    end
  end
  assign value_shifted_w =
    round_shift_signed64({{32{value_acc_w[31]}}, value_acc_w}, 15);
  assign value_q_w = saturate_i8($signed(value_shifted_w[31:0]));
  assign context_requant_product_w =
    $signed(value_q_w) * $signed(context_requant_mul_q20_by_head[head_index_q]);
  assign context_requant_shifted_w = round_shift_signed64(context_requant_product_w, 20);
  assign context_q_w = saturate_i8($signed(context_requant_shifted_w[31:0]));
  assign score_delta_w = max_score_q - score_cache_q[src_index_q];
  assign score_delta_scaled_w =
    $signed({{32{score_delta_w[31]}}, score_delta_w}) *
    $signed(softmax_score_scale_q20_by_head[head_index_q]);
  assign softmax_x_q12_w = round_shift_signed64(score_delta_scaled_w, 8);
  assign softmax_term1_w =
    round_shift_signed64($signed(softmax_x_q12_w) * 64'sd32768, 12);
  assign softmax_term2_w =
    round_shift_signed64($signed(softmax_x_q12_w) * $signed(softmax_x_q12_w) * 64'sd32768, 25);
  assign softmax_weight_raw_w =
    64'sd32768 - softmax_term1_w + softmax_term2_w;
  always_comb begin
    if (softmax_weight_raw_w < 64'sd1) begin
      softmax_weight_w = 32'd1;
    end else if (softmax_weight_raw_w > 64'sd65535) begin
      softmax_weight_w = 32'd65535;
    end else begin
      softmax_weight_w = softmax_weight_raw_w[31:0];
    end
  end
  assign prob_numer_w =
    (weight_cache_q[src_index_q] * 32'd32768) + (softmax_denom_q >> 1);
  assign div_next_bit_w = div_bit_q - 6'd1;
  assign div_trial_remainder_w = {div_remainder_q[31:0], div_numer_q[div_next_bit_w[4:0]]};
  assign div_subtract_w = div_trial_remainder_w >= {1'b0, div_denom_q};
  always_comb begin
    if (src_index_q == TOKEN_WIDTH'(CACHE_SEQ - 1)) begin
      prob_current_w = (prob_sum_q >= 32'd32768) ? 16'd0 : (16'd32768 - prob_sum_q[15:0]);
    end else if (prob_norm_q > 32'd65535) begin
      prob_current_w = 16'hffff;
    end else begin
      prob_current_w = prob_norm_q[15:0];
    end
  end

  task automatic reset_head_work;
    begin
      token_index_q <= '0;
      src_index_q <= '0;
      mean_index_q <= '0;
      ln_index_q <= '0;
      proj_index_q <= '0;
      dim_index_q <= '0;
      ln_mean_acc_q12 <= 32'sd0;
      ln_mean_latched_q12 <= 32'sd0;
      k_proj_acc_q <= 32'sd0;
      v_proj_acc_q <= 32'sd0;
      q_proj_acc_q <= 32'sd0;
      max_score_q <= -32'sd2147483647 - 32'sd1;
      softmax_denom_q <= 32'd0;
      prob_sum_q <= 32'd0;
      prob_norm_q <= 32'd0;
      div_numer_q <= 32'd0;
      div_denom_q <= 32'd0;
      div_remainder_q <= 33'd0;
      div_quotient_q <= 32'd0;
      div_bit_q <= 6'd0;
    end
  endtask

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= S_IDLE;
      head_index_q <= '0;
      reset_head_work();
      cycle_count_q <= 32'd0;
      debug_q <= 32'd0;
      output_checksum_o <= 32'd0;
      output_sample0_o <= 32'd0;
      output_sample1_o <= 32'd0;
      output_vector_o <= 512'd0;
      for (int r_dim = 0; r_dim < LN_DIM; r_dim = r_dim + 1) begin
        ln_output_cache_q[r_dim] <= 8'sd0;
      end
      for (int r_src = 0; r_src < CACHE_SEQ; r_src = r_src + 1) begin
        for (int r_head = 0; r_head < ATTN_HEAD_DIM; r_head = r_head + 1) begin
          k_cache_q[r_src][r_head] <= 8'sd0;
          v_cache_q[r_src][r_head] <= 8'sd0;
        end
        score_cache_q[r_src] <= 32'sd0;
        weight_cache_q[r_src] <= 32'd0;
        prob_cache_q[r_src] <= 16'd0;
      end
      for (int r_q = 0; r_q < ATTN_HEAD_DIM; r_q = r_q + 1) begin
        q_final_q[r_q] <= 8'sd0;
      end
    end else if (clear_i) begin
      state_q <= S_IDLE;
      head_index_q <= '0;
      reset_head_work();
      cycle_count_q <= 32'd0;
      debug_q <= 32'd0;
      output_checksum_o <= 32'd0;
      output_sample0_o <= 32'd0;
      output_sample1_o <= 32'd0;
      output_vector_o <= 512'd0;
    end else begin
      unique case (state_q)
        S_IDLE: begin
          if (start_i) begin
            state_q <= S_ACCUM_MEAN;
            head_index_q <= '0;
            reset_head_work();
            cycle_count_q <= 32'd0;
            debug_q <= 32'd0;
            output_checksum_o <= 32'd0;
            output_sample0_o <= 32'd0;
            output_sample1_o <= 32'd0;
            output_vector_o <= 512'd0;
          end
        end

        S_ACCUM_MEAN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          ln_mean_acc_q12 <= ln_mean_next_acc_q12_w;
          if (mean_index_q == LN_INDEX_WIDTH'(LN_DIM - 1)) begin
            ln_mean_latched_q12 <= $signed(ln_mean_next_shifted_w[31:0]);
            ln_index_q <= '0;
            state_q <= S_RUN_LN;
          end else begin
            mean_index_q <= mean_index_q + LN_INDEX_WIDTH'(1);
          end
        end

        S_RUN_LN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (ENABLE_INTERNAL_CHECKS && ln_output_w != ln_expected_q_by_token[token_index_q][ln_index_q]) begin
            state_q <= S_ERROR;
            debug_q <= {
              4'd0,
              4'h1,
              ln_index_q,
              ln_expected_q_by_token[token_index_q][ln_index_q],
              2'd0,
              ln_output_w
            };
          end else begin
            ln_output_cache_q[ln_index_q] <= ln_output_w;
            if (ln_index_q == LN_INDEX_WIDTH'(LN_DIM - 1)) begin
              proj_index_q <= '0;
              dim_index_q <= '0;
              k_proj_acc_q <= 32'sd0;
              v_proj_acc_q <= 32'sd0;
              q_proj_acc_q <= 32'sd0;
              state_q <= S_RUN_PROJ;
            end else begin
              ln_index_q <= ln_index_q + LN_INDEX_WIDTH'(1);
            end
          end
        end

        S_RUN_PROJ: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          k_proj_acc_q <= k_proj_next_acc_w;
          v_proj_acc_q <= v_proj_next_acc_w;
          q_proj_acc_q <= q_proj_next_acc_w;
          if (proj_index_q == LN_INDEX_WIDTH'(LN_DIM - 1)) begin
            if (ENABLE_INTERNAL_CHECKS &&
                k_proj_output_w != k_proj_expected_q_by_token[head_index_q][token_index_q][dim_index_q]) begin
              state_q <= S_ERROR;
              debug_q <= {8'h02, head_index_u32_w[3:0], dim_index_u32_w[3:0], 8'd0, k_proj_output_w};
            end else if (ENABLE_INTERNAL_CHECKS &&
                         v_proj_output_w != v_proj_expected_q_by_token[head_index_q][token_index_q][dim_index_q]) begin
              state_q <= S_ERROR;
              debug_q <= {8'h03, head_index_u32_w[3:0], dim_index_u32_w[3:0], 8'd0, v_proj_output_w};
            end else if (
              ENABLE_INTERNAL_CHECKS &&
              token_index_q == TOKEN_WIDTH'(CACHE_SEQ - 1) &&
              q_proj_output_w != q_proj_expected_q_final[head_index_q][dim_index_q]
            ) begin
              state_q <= S_ERROR;
              debug_q <= {8'h04, head_index_u32_w[3:0], dim_index_u32_w[3:0], 8'd0, q_proj_output_w};
            end else begin
              k_cache_q[token_index_q][dim_index_q] <= k_proj_output_w;
              v_cache_q[token_index_q][dim_index_q] <= v_proj_output_w;
              if (token_index_q == TOKEN_WIDTH'(CACHE_SEQ - 1)) begin
                q_final_q[dim_index_q] <= q_proj_output_w;
              end

              if (dim_index_q == ATTN_DIM_WIDTH'(ATTN_HEAD_DIM - 1)) begin
                if (token_index_q == TOKEN_WIDTH'(CACHE_SEQ - 1)) begin
                  src_index_q <= '0;
                  max_score_q <= -32'sd2147483647 - 32'sd1;
                  softmax_denom_q <= 32'd0;
                  prob_sum_q <= 32'd0;
                  state_q <= S_RUN_SCORE;
                end else begin
                  token_index_q <= token_index_q + TOKEN_WIDTH'(1);
                  mean_index_q <= '0;
                  ln_index_q <= '0;
                  proj_index_q <= '0;
                  dim_index_q <= '0;
                  ln_mean_acc_q12 <= 32'sd0;
                  ln_mean_latched_q12 <= 32'sd0;
                  k_proj_acc_q <= 32'sd0;
                  v_proj_acc_q <= 32'sd0;
                  q_proj_acc_q <= 32'sd0;
                  state_q <= S_ACCUM_MEAN;
                end
              end else begin
                dim_index_q <= dim_index_q + ATTN_DIM_WIDTH'(1);
                proj_index_q <= '0;
                k_proj_acc_q <= 32'sd0;
                v_proj_acc_q <= 32'sd0;
                q_proj_acc_q <= 32'sd0;
              end
            end
          end else begin
            proj_index_q <= proj_index_q + LN_INDEX_WIDTH'(1);
          end
        end

        S_RUN_SCORE: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (ENABLE_INTERNAL_CHECKS && score_acc_w != attn_expected_score_acc[head_index_q][src_index_q]) begin
            state_q <= S_ERROR;
            debug_q <= {8'h05, head_index_u32_w[3:0], src_index_u32_w[3:0], score_acc_w[15:0]};
          end else if (src_index_q == TOKEN_WIDTH'(CACHE_SEQ - 1)) begin
            score_cache_q[src_index_q] <= score_acc_w;
            if (score_acc_w > max_score_q) begin
              max_score_q <= score_acc_w;
            end
            src_index_q <= '0;
            softmax_denom_q <= 32'd0;
            state_q <= S_RUN_PROB_WEIGHT;
          end else begin
            score_cache_q[src_index_q] <= score_acc_w;
            if (score_acc_w > max_score_q) begin
              max_score_q <= score_acc_w;
            end
            src_index_q <= src_index_q + TOKEN_WIDTH'(1);
          end
        end

        S_RUN_PROB_WEIGHT: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (ENABLE_INTERNAL_CHECKS &&
              softmax_weight_w != {16'd0, attn_expected_weight_q15[head_index_q][src_index_q]}) begin
            state_q <= S_ERROR;
            debug_q <= {8'h07, head_index_u32_w[3:0], src_index_u32_w[3:0], softmax_weight_w[15:0]};
          end else if (src_index_q == TOKEN_WIDTH'(CACHE_SEQ - 1)) begin
            weight_cache_q[src_index_q] <= softmax_weight_w;
            softmax_denom_q <= softmax_denom_q + softmax_weight_w;
            src_index_q <= '0;
            prob_sum_q <= 32'd0;
            state_q <= S_RUN_PROB_NORM;
          end else begin
            weight_cache_q[src_index_q] <= softmax_weight_w;
            softmax_denom_q <= softmax_denom_q + softmax_weight_w;
            src_index_q <= src_index_q + TOKEN_WIDTH'(1);
          end
        end

        S_RUN_PROB_NORM: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          div_numer_q <= prob_numer_w;
          div_denom_q <= softmax_denom_q;
          div_remainder_q <= 33'd0;
          div_quotient_q <= 32'd0;
          div_bit_q <= 6'd32;
          if (softmax_denom_q == 32'd0) begin
            prob_norm_q <= 32'd0;
            state_q <= S_RUN_PROB_CHECK;
          end else begin
            state_q <= S_RUN_PROB_DIV;
          end
        end

        S_RUN_PROB_DIV: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (div_bit_q == 6'd0) begin
            prob_norm_q <= div_quotient_q;
            state_q <= S_RUN_PROB_CHECK;
          end else begin
            div_bit_q <= div_next_bit_w;
            if (div_subtract_w) begin
              div_remainder_q <= div_trial_remainder_w - {1'b0, div_denom_q};
              div_quotient_q[div_next_bit_w[4:0]] <= 1'b1;
            end else begin
              div_remainder_q <= div_trial_remainder_w;
            end
          end
        end

        S_RUN_PROB_CHECK: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (ENABLE_INTERNAL_CHECKS && prob_current_w != attn_prob_q15[head_index_q][src_index_q]) begin
            state_q <= S_ERROR;
            debug_q <= {8'h08, head_index_u32_w[3:0], src_index_u32_w[3:0], prob_current_w};
          end else if (src_index_q == TOKEN_WIDTH'(CACHE_SEQ - 1)) begin
            prob_cache_q[src_index_q] <= prob_current_w;
            dim_index_q <= '0;
            state_q <= S_RUN_VALUE;
          end else begin
            prob_cache_q[src_index_q] <= prob_current_w;
            prob_sum_q <= prob_sum_q + {16'd0, prob_current_w};
            src_index_q <= src_index_q + TOKEN_WIDTH'(1);
            state_q <= S_RUN_PROB_NORM;
          end
        end

        S_RUN_VALUE: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (ENABLE_INTERNAL_CHECKS && (
            value_acc_w != attn_expected_value_acc[head_index_q][dim_index_q] ||
            value_q_w != attn_expected_value_q[head_index_q][dim_index_q]
          )) begin
            state_q <= S_ERROR;
            debug_q <= {8'h06, head_index_u32_w[3:0], dim_index_u32_w[3:0], value_acc_w[15:0]};
          end else if (ENABLE_INTERNAL_CHECKS && context_q_w != context_expected_q[context_index_w]) begin
            state_q <= S_ERROR;
            debug_q <= {8'h09, head_index_u32_w[3:0], dim_index_u32_w[3:0], 8'd0, context_q_w};
          end else begin
            output_checksum_o <=
              output_checksum_o +
              ({24'd0, context_q_w[7:0]} * (context_index_u32_w + 32'd1));
            output_vector_o[context_index_w * 8 +: 8] <= context_q_w;
            if (context_index_u32_w < 32'd4) begin
              output_sample0_o <=
                output_sample0_o | ({24'd0, context_q_w[7:0]} << (8 * context_index_w[1:0]));
            end else if (context_index_u32_w < 32'd8) begin
              output_sample1_o <=
                output_sample1_o | ({24'd0, context_q_w[7:0]} << (8 * context_index_w[1:0]));
            end

            if (dim_index_q == ATTN_DIM_WIDTH'(ATTN_HEAD_DIM - 1)) begin
              if (head_index_q == HEAD_WIDTH'(NUM_HEADS - 1)) begin
                state_q <= S_DONE;
              end else begin
                head_index_q <= head_index_q + HEAD_WIDTH'(1);
                reset_head_work();
                state_q <= S_ACCUM_MEAN;
              end
            end else begin
              dim_index_q <= dim_index_q + ATTN_DIM_WIDTH'(1);
            end
          end
        end

        S_DONE: begin
          if (start_i) begin
            state_q <= S_ACCUM_MEAN;
            head_index_q <= '0;
            reset_head_work();
            cycle_count_q <= 32'd0;
            debug_q <= 32'd0;
            output_checksum_o <= 32'd0;
            output_sample0_o <= 32'd0;
            output_sample1_o <= 32'd0;
            output_vector_o <= 512'd0;
          end
        end

        default: begin
          state_q <= S_ERROR;
          debug_q <= 32'hff000000;
        end
      endcase
    end
  end

  always_comb begin
    status_o = {
      16'h4b41,
      8'd0,
      1'b0,
      state_q[2:0],
      state_q == S_DONE,
      state_q == S_ERROR,
      state_q != S_IDLE && state_q != S_DONE && state_q != S_ERROR,
      state_q == S_IDLE || state_q == S_DONE
    };
    cycle_count_o = cycle_count_q;
    debug_o = debug_q;
  end
endmodule
