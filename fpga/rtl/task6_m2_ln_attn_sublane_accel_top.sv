`timescale 1ns/1ps

module task6_m2_ln_attn_sublane_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic [511:0] pcie_block_input_i,
  input logic [511:0] pcie_residual_after_attention_i,
  input logic pcie_use_external_kv_i,
  input logic [4095:0] pcie_external_k_vector_i,
  input logic [4095:0] pcie_external_v_vector_i,
  input logic pcie_start_pulse_i,
  input logic pcie_clear_pulse_i,
  output logic [31:0] pcie_status_o,
  output logic [31:0] pcie_cycle_count_o,
  output logic [31:0] pcie_output_checksum_o,
  output logic [31:0] pcie_output_sample0_o,
  output logic [31:0] pcie_output_sample1_o,
  output logic [31:0] pcie_output_count_o,
  output logic [511:0] pcie_output_vector_o,
  output logic [31:0] pcie_debug_o,
  output logic [31:0] pcie_debug1_o,
  output logic [31:0] pcie_debug2_o
);
  `include "tb_data.sv"

  typedef enum logic [2:0] {
    M2_IDLE = 3'd0,
    M2_RUN_Q_PROJ = 3'd1,
    M2_RUN_LN = 3'd2,
    M2_RUN_ATTN_SCORE = 3'd3,
    M2_RUN_ATTN_VALUE = 3'd4,
    M2_DONE = 3'd5,
    M2_ERROR = 3'd6,
    M2_ACCUM_MEAN = 3'd7
  } m2_state_t;

  localparam int LN_INDEX_WIDTH = $clog2(LN_DIM);
  localparam int ATTN_SRC_WIDTH = (ATTN_SEQ <= 1) ? 1 : $clog2(ATTN_SEQ);
  localparam int ATTN_DIM_WIDTH = $clog2(ATTN_HEAD_DIM);
  localparam int OUTPUT_COUNT = 64;

  m2_state_t state_q;
  logic [LN_INDEX_WIDTH - 1:0] ln_index_q;
  logic [LN_INDEX_WIDTH - 1:0] mean_index_q;
  logic [LN_INDEX_WIDTH - 1:0] proj_index_q;
  logic [ATTN_SRC_WIDTH - 1:0] src_index_q;
  logic [ATTN_DIM_WIDTH - 1:0] dim_index_q;
  logic [31:0] cycle_count_q;
  logic [31:0] fail_detail_q;
  logic [31:0] fail_detail1_q;
  logic [31:0] fail_detail2_q;
  logic [511:0] block_input_q;
  logic [511:0] residual_input_q;
  logic output_valid_q;
  logic error_q;

  logic signed [31:0] ln_mean_latched_q12;
  logic signed [31:0] ln_mean_acc_q12;
  logic signed [15:0] ln_mean_input_q12;
  logic signed [15:0] ln_current_input_q12;
  logic signed [31:0] ln_mean_next_acc_q12;
  logic signed [31:0] ln_centered_q12;
  logic signed [63:0] ln_norm_product_q;
  logic signed [63:0] ln_norm_shifted_q;
  logic signed [31:0] ln_norm_q12;
  logic signed [63:0] ln_affine_product_q;
  logic signed [63:0] ln_affine_shifted_q;
  logic signed [31:0] ln_affine_q12;
  logic signed [63:0] ln_output_product_q;
  logic signed [63:0] ln_output_shifted_q;
  logic signed [31:0] ln_output_scaled_q;
  logic signed [7:0] ln_output_q;
  logic [7:0] ln_output_u8;
  logic [31:0] ln_weighted_value;
  logic signed [31:0] score_acc_q;
  logic signed [31:0] q_proj_acc_q;
  logic signed [31:0] k_proj_acc_q;
  logic signed [31:0] v_proj_acc_q;
  logic signed [31:0] q_proj_next_acc_q;
  logic signed [31:0] k_proj_next_acc_q;
  logic signed [31:0] v_proj_next_acc_q;
  logic signed [63:0] q_proj_output_product_q;
  logic signed [63:0] k_proj_output_product_q;
  logic signed [63:0] v_proj_output_product_q;
  logic signed [63:0] q_proj_output_shifted_q;
  logic signed [63:0] k_proj_output_shifted_q;
  logic signed [63:0] v_proj_output_shifted_q;
  logic signed [7:0] q_proj_output_q;
  logic signed [7:0] k_proj_output_q;
  logic signed [7:0] v_proj_output_q;
  logic signed [7:0] q_proj_live_q [0:ATTN_HEAD_DIM-1];
  logic signed [7:0] k_proj_live_q [0:ATTN_HEAD_DIM-1];
  logic signed [7:0] v_proj_live_q [0:ATTN_HEAD_DIM-1];
  logic signed [31:0] value_acc_q;
  logic signed [63:0] value_shifted_q;
  logic signed [7:0] value_q;
  logic [31:0] src_index_u32_w;
  logic [31:0] dim_index_u32_w;
  logic [3:0] src_index_detail_w;
  logic [3:0] dim_index_detail_w;

  function automatic signed [15:0] select_host_input_q12(
    input logic [511:0] low_half,
    input logic [511:0] high_half,
    input logic [LN_INDEX_WIDTH - 1:0] index
  );
    begin
      if (index < LN_INDEX_WIDTH'(32)) begin
        select_host_input_q12 = low_half[index * 16 +: 16];
      end else begin
        select_host_input_q12 = high_half[(index - LN_INDEX_WIDTH'(32)) * 16 +: 16];
      end
    end
  endfunction

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

  function automatic signed [7:0] select_attn_k(
    input int src_index,
    input int dim_index
  );
    int packed_index;
    begin
      packed_index = ((src_index * ATTN_HEAD_DIM) + dim_index) * 8;
      if (src_index == (ATTN_SEQ - 1)) begin
        select_attn_k = k_proj_live_q[dim_index];
      end else if (pcie_use_external_kv_i) begin
        select_attn_k = pcie_external_k_vector_i[packed_index +: 8];
      end else begin
        select_attn_k = attn_k_q[src_index][dim_index];
      end
    end
  endfunction

  function automatic signed [7:0] select_attn_v(
    input int src_index,
    input int dim_index
  );
    int packed_index;
    begin
      packed_index = ((src_index * ATTN_HEAD_DIM) + dim_index) * 8;
      if (src_index == (ATTN_SEQ - 1)) begin
        select_attn_v = v_proj_live_q[dim_index];
      end else if (pcie_use_external_kv_i) begin
        select_attn_v = pcie_external_v_vector_i[packed_index +: 8];
      end else begin
        select_attn_v = attn_v_q[src_index][dim_index];
      end
    end
  endfunction

  assign ln_mean_input_q12 =
    select_host_input_q12(block_input_q, residual_input_q, mean_index_q);
  assign ln_mean_next_acc_q12 =
    ln_mean_acc_q12 +
    $signed({{16{ln_mean_input_q12[15]}}, ln_mean_input_q12});
  assign ln_current_input_q12 =
    select_host_input_q12(block_input_q, residual_input_q, ln_index_q);
  assign ln_centered_q12 =
    $signed({{16{ln_current_input_q12[15]}}, ln_current_input_q12}) -
    $signed(ln_mean_latched_q12);
  assign ln_norm_product_q = $signed(ln_centered_q12) * $signed(LN_INV_STD_Q16);
  assign ln_norm_shifted_q = round_shift_signed64(ln_norm_product_q, 16);
  assign ln_norm_q12 = $signed(ln_norm_shifted_q[31:0]);
  assign ln_affine_product_q = $signed(ln_norm_q12) * $signed(ln_gamma_q16[ln_index_q]);
  assign ln_affine_shifted_q = round_shift_signed64(ln_affine_product_q, 16);
  assign ln_affine_q12 =
    $signed(ln_affine_shifted_q[31:0]) +
    $signed({{16{ln_beta_q12[ln_index_q][15]}}, ln_beta_q12[ln_index_q]});
  assign ln_output_product_q =
    $signed(ln_affine_q12) * $signed(LN_OUTPUT_SCALE_MUL_Q20);
  assign ln_output_shifted_q = round_shift_signed64(ln_output_product_q, 20);
  assign ln_output_scaled_q = $signed(ln_output_shifted_q[31:0]);
  assign ln_output_q = saturate_i8(ln_output_scaled_q);
  assign ln_output_u8 = ln_output_q[7:0];
  assign ln_weighted_value =
    ({24'd0, ln_output_u8} * ({{(32 - LN_INDEX_WIDTH){1'b0}}, ln_index_q} + 32'd1));

  integer d;
  always_comb begin
    score_acc_q = 32'sd0;
    for (d = 0; d < ATTN_HEAD_DIM; d = d + 1) begin
      score_acc_q =
        score_acc_q +
        (
          $signed(q_proj_live_q[d]) *
          $signed(select_attn_k(src_index_u32_w, d))
        );
    end
  end
  assign q_proj_output_product_q =
    $signed(q_proj_next_acc_q) * $signed(q_proj_output_mul_q20[dim_index_q]);
  assign k_proj_output_product_q =
    $signed(k_proj_next_acc_q) * $signed(k_proj_output_mul_q20[dim_index_q]);
  assign v_proj_output_product_q =
    $signed(v_proj_next_acc_q) * $signed(v_proj_output_mul_q20[dim_index_q]);
  assign q_proj_output_shifted_q = round_shift_signed64(q_proj_output_product_q, 20);
  assign k_proj_output_shifted_q = round_shift_signed64(k_proj_output_product_q, 20);
  assign v_proj_output_shifted_q = round_shift_signed64(v_proj_output_product_q, 20);
  assign q_proj_output_q = saturate_i8($signed(q_proj_output_shifted_q[31:0]));
  assign k_proj_output_q = saturate_i8($signed(k_proj_output_shifted_q[31:0]));
  assign v_proj_output_q = saturate_i8($signed(v_proj_output_shifted_q[31:0]));

  assign q_proj_next_acc_q =
    q_proj_acc_q +
    ($signed(pcie_output_vector_o[proj_index_q * 8 +: 8]) *
     $signed(q_proj_weight_q[dim_index_q][proj_index_q]));
  assign k_proj_next_acc_q =
    k_proj_acc_q +
    ($signed(pcie_output_vector_o[proj_index_q * 8 +: 8]) *
     $signed(k_proj_weight_q[dim_index_q][proj_index_q]));
  assign v_proj_next_acc_q =
    v_proj_acc_q +
    ($signed(pcie_output_vector_o[proj_index_q * 8 +: 8]) *
     $signed(v_proj_weight_q[dim_index_q][proj_index_q]));

  integer s;
  always_comb begin
    value_acc_q = 32'sd0;
    for (s = 0; s < ATTN_SEQ; s = s + 1) begin
      value_acc_q =
        value_acc_q +
        (
          $signed({1'b0, attn_prob_q15[s]}) *
          $signed(select_attn_v(s, dim_index_u32_w))
        );
    end
  end
  assign value_shifted_q =
    round_shift_signed64({{32{value_acc_q[31]}}, value_acc_q}, 15);
  assign value_q = saturate_i8($signed(value_shifted_q[31:0]));
  assign src_index_u32_w = {{(32 - ATTN_SRC_WIDTH){1'b0}}, src_index_q};
  assign dim_index_u32_w = {{(32 - ATTN_DIM_WIDTH){1'b0}}, dim_index_q};
  assign src_index_detail_w = src_index_u32_w[3:0];
  assign dim_index_detail_w = dim_index_u32_w[3:0];

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= M2_IDLE;
      ln_index_q <= '0;
      mean_index_q <= '0;
      proj_index_q <= '0;
      src_index_q <= '0;
      dim_index_q <= '0;
      cycle_count_q <= 32'd0;
      fail_detail_q <= 32'd0;
      fail_detail1_q <= 32'd0;
      fail_detail2_q <= 32'd0;
      ln_mean_latched_q12 <= 32'sd0;
      ln_mean_acc_q12 <= 32'sd0;
      q_proj_acc_q <= 32'sd0;
      k_proj_acc_q <= 32'sd0;
      v_proj_acc_q <= 32'sd0;
      block_input_q <= 512'd0;
      residual_input_q <= 512'd0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      pcie_output_checksum_o <= 32'd0;
      pcie_output_sample0_o <= 32'd0;
      pcie_output_sample1_o <= 32'd0;
      pcie_output_vector_o <= 512'd0;
      for (int reset_dim = 0; reset_dim < ATTN_HEAD_DIM; reset_dim = reset_dim + 1) begin
        q_proj_live_q[reset_dim] <= 8'sd0;
        k_proj_live_q[reset_dim] <= 8'sd0;
        v_proj_live_q[reset_dim] <= 8'sd0;
      end
    end else begin
      if (pcie_clear_pulse_i) begin
        state_q <= M2_IDLE;
        ln_index_q <= '0;
        mean_index_q <= '0;
        proj_index_q <= '0;
        src_index_q <= '0;
        dim_index_q <= '0;
        cycle_count_q <= 32'd0;
        fail_detail_q <= 32'd0;
        fail_detail1_q <= 32'd0;
        fail_detail2_q <= 32'd0;
        ln_mean_latched_q12 <= 32'sd0;
        ln_mean_acc_q12 <= 32'sd0;
        q_proj_acc_q <= 32'sd0;
        k_proj_acc_q <= 32'sd0;
        v_proj_acc_q <= 32'sd0;
        output_valid_q <= 1'b0;
        error_q <= 1'b0;
        pcie_output_checksum_o <= 32'd0;
        pcie_output_sample0_o <= 32'd0;
        pcie_output_sample1_o <= 32'd0;
        pcie_output_vector_o <= 512'd0;
        for (int clear_dim = 0; clear_dim < ATTN_HEAD_DIM; clear_dim = clear_dim + 1) begin
          q_proj_live_q[clear_dim] <= 8'sd0;
          k_proj_live_q[clear_dim] <= 8'sd0;
          v_proj_live_q[clear_dim] <= 8'sd0;
        end
      end else begin
        unique case (state_q)
          M2_IDLE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_ACCUM_MEAN;
              block_input_q <= pcie_block_input_i;
              residual_input_q <= pcie_residual_after_attention_i;
              ln_index_q <= '0;
              mean_index_q <= '0;
              proj_index_q <= '0;
              src_index_q <= '0;
              dim_index_q <= '0;
              cycle_count_q <= 32'd0;
              fail_detail_q <= 32'd0;
              fail_detail1_q <= 32'd0;
              fail_detail2_q <= 32'd0;
              ln_mean_latched_q12 <= 32'sd0;
              ln_mean_acc_q12 <= 32'sd0;
              q_proj_acc_q <= 32'sd0;
              k_proj_acc_q <= 32'sd0;
              v_proj_acc_q <= 32'sd0;
              output_valid_q <= 1'b0;
              error_q <= 1'b0;
              pcie_output_checksum_o <= 32'd0;
              pcie_output_sample0_o <= 32'd0;
              pcie_output_sample1_o <= 32'd0;
              pcie_output_vector_o <= 512'd0;
              for (int start_dim = 0; start_dim < ATTN_HEAD_DIM; start_dim = start_dim + 1) begin
                q_proj_live_q[start_dim] <= 8'sd0;
                k_proj_live_q[start_dim] <= 8'sd0;
                v_proj_live_q[start_dim] <= 8'sd0;
              end
            end
          end

          M2_ACCUM_MEAN: begin
            ln_mean_acc_q12 <= ln_mean_next_acc_q12;
            if (mean_index_q == LN_INDEX_WIDTH'(LN_DIM - 1)) begin
              ln_mean_latched_q12 <= ln_mean_next_acc_q12 >>> 6;
              ln_index_q <= '0;
              state_q <= M2_RUN_LN;
            end else begin
              mean_index_q <= mean_index_q + LN_INDEX_WIDTH'(1);
            end
          end

          M2_RUN_LN: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (ln_output_q != ln_expected_q[ln_index_q]) begin
              state_q <= M2_ERROR;
              error_q <= 1'b1;
              fail_detail_q <= {
                8'h01,
                ln_index_q,
                2'b00,
                ln_expected_q[ln_index_q],
                ln_output_q
              };
              fail_detail1_q <= {
                ln_current_input_q12[15:0],
                ln_mean_latched_q12[15:0]
              };
              fail_detail2_q <= {
                ln_centered_q12[15:0],
                ln_norm_q12[15:0]
              };
            end else begin
              pcie_output_checksum_o <= pcie_output_checksum_o + ln_weighted_value;
              pcie_output_vector_o[ln_index_q * 8 +: 8] <= ln_output_q;
              if (ln_index_q < LN_INDEX_WIDTH'(4)) begin
                pcie_output_sample0_o <=
                  pcie_output_sample0_o | ({24'd0, ln_output_u8} << (8 * ln_index_q[1:0]));
              end else if (ln_index_q < LN_INDEX_WIDTH'(8)) begin
                pcie_output_sample1_o <=
                  pcie_output_sample1_o | ({24'd0, ln_output_u8} << (8 * ln_index_q[1:0]));
              end

              if (ln_index_q == LN_INDEX_WIDTH'(LN_DIM - 1)) begin
                dim_index_q <= '0;
                proj_index_q <= '0;
                q_proj_acc_q <= 32'sd0;
                k_proj_acc_q <= 32'sd0;
                v_proj_acc_q <= 32'sd0;
                state_q <= M2_RUN_Q_PROJ;
              end else begin
                ln_index_q <= ln_index_q + LN_INDEX_WIDTH'(1);
              end
            end
          end

          M2_RUN_Q_PROJ: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            q_proj_acc_q <= q_proj_next_acc_q;
            k_proj_acc_q <= k_proj_next_acc_q;
            v_proj_acc_q <= v_proj_next_acc_q;
            if (proj_index_q == LN_INDEX_WIDTH'(LN_DIM - 1)) begin
              if (q_proj_next_acc_q != q_proj_expected_acc[dim_index_q]) begin
                state_q <= M2_ERROR;
                error_q <= 1'b1;
                fail_detail_q <= {8'h04, 4'd0, dim_index_detail_w, q_proj_next_acc_q[15:0]};
              end else if (k_proj_next_acc_q != k_proj_expected_acc[dim_index_q]) begin
                state_q <= M2_ERROR;
                error_q <= 1'b1;
                fail_detail_q <= {8'h05, 4'd0, dim_index_detail_w, k_proj_next_acc_q[15:0]};
              end else if (v_proj_next_acc_q != v_proj_expected_acc[dim_index_q]) begin
                state_q <= M2_ERROR;
                error_q <= 1'b1;
                fail_detail_q <= {8'h06, 4'd0, dim_index_detail_w, v_proj_next_acc_q[15:0]};
              end else if (q_proj_output_q != q_proj_expected_q[dim_index_q]) begin
                state_q <= M2_ERROR;
                error_q <= 1'b1;
                fail_detail_q <= {8'h07, 4'd0, dim_index_detail_w, 8'd0, q_proj_output_q};
              end else if (k_proj_output_q != k_proj_expected_q[dim_index_q]) begin
                state_q <= M2_ERROR;
                error_q <= 1'b1;
                fail_detail_q <= {8'h08, 4'd0, dim_index_detail_w, 8'd0, k_proj_output_q};
              end else if (v_proj_output_q != v_proj_expected_q[dim_index_q]) begin
                state_q <= M2_ERROR;
                error_q <= 1'b1;
                fail_detail_q <= {8'h09, 4'd0, dim_index_detail_w, 8'd0, v_proj_output_q};
              end else if (dim_index_q == ATTN_DIM_WIDTH'(ATTN_HEAD_DIM - 1)) begin
                q_proj_live_q[dim_index_q] <= q_proj_output_q;
                k_proj_live_q[dim_index_q] <= k_proj_output_q;
                v_proj_live_q[dim_index_q] <= v_proj_output_q;
                dim_index_q <= '0;
                proj_index_q <= '0;
                q_proj_acc_q <= 32'sd0;
                k_proj_acc_q <= 32'sd0;
                v_proj_acc_q <= 32'sd0;
                src_index_q <= '0;
                state_q <= M2_RUN_ATTN_SCORE;
              end else begin
                q_proj_live_q[dim_index_q] <= q_proj_output_q;
                k_proj_live_q[dim_index_q] <= k_proj_output_q;
                v_proj_live_q[dim_index_q] <= v_proj_output_q;
                dim_index_q <= dim_index_q + ATTN_DIM_WIDTH'(1);
                proj_index_q <= '0;
                q_proj_acc_q <= 32'sd0;
                k_proj_acc_q <= 32'sd0;
                v_proj_acc_q <= 32'sd0;
              end
            end else begin
              proj_index_q <= proj_index_q + LN_INDEX_WIDTH'(1);
            end
          end

          M2_RUN_ATTN_SCORE: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (score_acc_q != attn_expected_score_acc[src_index_q]) begin
              state_q <= M2_ERROR;
              error_q <= 1'b1;
              fail_detail_q <= {8'h02, 4'd0, src_index_detail_w, score_acc_q[15:0]};
            end else if (src_index_q == ATTN_SRC_WIDTH'(ATTN_SEQ - 1)) begin
              state_q <= M2_RUN_ATTN_VALUE;
              dim_index_q <= '0;
              pcie_output_checksum_o <= 32'd0;
              pcie_output_sample0_o <= 32'd0;
              pcie_output_sample1_o <= 32'd0;
              pcie_output_vector_o <= 512'd0;
            end else begin
              src_index_q <= src_index_q + ATTN_SRC_WIDTH'(1);
            end
          end

          M2_RUN_ATTN_VALUE: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (
              value_acc_q != attn_expected_value_acc[dim_index_q] ||
              value_q != attn_expected_value_q[dim_index_q]
            ) begin
              state_q <= M2_ERROR;
              error_q <= 1'b1;
              fail_detail_q <= {8'h03, 4'd0, dim_index_detail_w, value_acc_q[15:0]};
            end else begin
              pcie_output_checksum_o <=
                pcie_output_checksum_o +
                ({24'd0, value_q[7:0]} * ({{(32 - ATTN_DIM_WIDTH){1'b0}}, dim_index_q} + 32'd1));
              pcie_output_vector_o[dim_index_q * 8 +: 8] <= value_q;
              if ({{(32 - ATTN_DIM_WIDTH){1'b0}}, dim_index_q} < 32'd4) begin
                pcie_output_sample0_o <=
                  pcie_output_sample0_o | ({24'd0, value_q[7:0]} << (8 * dim_index_q[1:0]));
              end else if ({{(32 - ATTN_DIM_WIDTH){1'b0}}, dim_index_q} < 32'd8) begin
                pcie_output_sample1_o <=
                  pcie_output_sample1_o | ({24'd0, value_q[7:0]} << (8 * dim_index_q[1:0]));
              end

              if (dim_index_q == ATTN_DIM_WIDTH'(ATTN_HEAD_DIM - 1)) begin
                state_q <= M2_DONE;
                output_valid_q <= 1'b1;
              end else begin
                dim_index_q <= dim_index_q + ATTN_DIM_WIDTH'(1);
              end
            end
          end

          M2_DONE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_ACCUM_MEAN;
              block_input_q <= pcie_block_input_i;
              residual_input_q <= pcie_residual_after_attention_i;
              ln_index_q <= '0;
              mean_index_q <= '0;
              proj_index_q <= '0;
              src_index_q <= '0;
              dim_index_q <= '0;
              cycle_count_q <= 32'd0;
              fail_detail_q <= 32'd0;
              fail_detail1_q <= 32'd0;
              fail_detail2_q <= 32'd0;
              ln_mean_latched_q12 <= 32'sd0;
              ln_mean_acc_q12 <= 32'sd0;
              q_proj_acc_q <= 32'sd0;
              k_proj_acc_q <= 32'sd0;
              v_proj_acc_q <= 32'sd0;
              output_valid_q <= 1'b0;
              error_q <= 1'b0;
              pcie_output_checksum_o <= 32'd0;
              pcie_output_sample0_o <= 32'd0;
              pcie_output_sample1_o <= 32'd0;
              pcie_output_vector_o <= 512'd0;
              for (int restart_dim = 0; restart_dim < ATTN_HEAD_DIM; restart_dim = restart_dim + 1) begin
                q_proj_live_q[restart_dim] <= 8'sd0;
                k_proj_live_q[restart_dim] <= 8'sd0;
                v_proj_live_q[restart_dim] <= 8'sd0;
              end
            end
          end

          default: begin
            state_q <= M2_ERROR;
            error_q <= 1'b1;
          end
        endcase
      end
    end
  end

  always_comb begin
    pcie_status_o = {
      16'h4d32,
      8'd0,
      1'b0,
      state_q,
      output_valid_q,
      error_q,
      state_q == M2_ACCUM_MEAN || state_q == M2_RUN_LN || state_q == M2_RUN_Q_PROJ || state_q == M2_RUN_ATTN_SCORE || state_q == M2_RUN_ATTN_VALUE,
      state_q == M2_IDLE || state_q == M2_DONE
    };
    pcie_cycle_count_o = cycle_count_q;
    pcie_output_count_o = OUTPUT_COUNT;
    pcie_debug_o = fail_detail_q;
    pcie_debug1_o = fail_detail1_q;
    pcie_debug2_o = fail_detail2_q;
  end

endmodule
