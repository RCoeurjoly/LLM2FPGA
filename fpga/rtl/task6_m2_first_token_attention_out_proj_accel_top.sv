`timescale 1ns/1ps

module task6_m2_first_token_attention_out_proj_accel_top #(
  parameter bit ENABLE_INTERNAL_CHECKS = 1'b0
) (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  input logic use_external_context_i,
  input logic [511:0] external_context_vector_i,
  input logic use_external_block_input_i,
  input logic [511:0] external_block_input_vector_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] output_checksum_o,
  output logic [31:0] output_sample0_o,
  output logic [31:0] output_sample1_o,
  output logic [511:0] output_vector_o,
  output logic [31:0] residual_checksum_o,
  output logic [31:0] residual_sample0_o,
  output logic [31:0] residual_sample1_o,
  output logic [511:0] residual_vector_o,
  output logic [31:0] ln2_checksum_o,
  output logic [31:0] ln2_sample0_o,
  output logic [31:0] ln2_sample1_o,
  output logic [511:0] ln2_vector_o,
  output logic [31:0] debug_o
);
  `include "tb_data.sv"

  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_PREFETCH = 3'd1,
    ST_RUN = 3'd2,
    ST_CHECK = 3'd3,
    ST_DONE = 3'd4,
    ST_ERROR = 3'd5,
    ST_LN2_MEAN = 3'd6,
    ST_LN2_RUN = 3'd7
  } state_t;

  localparam int INDEX_WIDTH = $clog2(OUT_PROJ_DIM);
  localparam int OUT_PROJ_WEIGHT_ADDR_WIDTH = $clog2(OUT_PROJ_DIM * OUT_PROJ_DIM);

  state_t state_q;
  logic [INDEX_WIDTH - 1:0] out_index_q;
  logic [INDEX_WIDTH - 1:0] in_index_q;
  logic signed [31:0] acc_q;
  logic signed [31:0] next_acc_w;
  logic signed [7:0] selected_context_q_w;
  logic signed [31:0] out_proj_context_ext_w;
  logic signed [7:0] selected_block_input_q_w;
  logic signed [31:0] out_proj_weight_ext_w;
  logic signed [31:0] out_proj_product_w;
  logic signed [63:0] product_w;
  logic signed [63:0] shifted_w;
  logic signed [7:0] output_q_w;
  logic [7:0] output_u8_w;
  logic signed [63:0] residual_product_w;
  logic signed [63:0] residual_shifted_w;
  logic signed [7:0] residual_q_w;
  logic [7:0] residual_u8_w;
  logic signed [63:0] residual_bias_ext_w;
  logic [31:0] weighted_value_w;
  logic [31:0] residual_weighted_value_w;
  logic [31:0] cycle_count_q;
  logic [31:0] checksum_q;
  logic [31:0] sample0_q;
  logic [31:0] sample1_q;
  logic [511:0] output_vector_q;
  logic [31:0] residual_checksum_q;
  logic [31:0] residual_sample0_q;
  logic [31:0] residual_sample1_q;
  logic [511:0] residual_vector_q;
  logic [31:0] ln2_checksum_q;
  logic [31:0] ln2_sample0_q;
  logic [31:0] ln2_sample1_q;
  logic [511:0] ln2_vector_q;
  logic [INDEX_WIDTH - 1:0] ln2_mean_index_q;
  logic [INDEX_WIDTH - 1:0] ln2_index_q;
  logic signed [31:0] ln2_mean_acc_q12;
  logic signed [31:0] ln2_mean_latched_q12;
  logic signed [31:0] ln2_mean_next_acc_q12;
  logic signed [63:0] ln2_mean_next_acc_q12_s64_w;
  logic signed [63:0] ln2_mean_rounded_q12_s64_w;
  logic signed [31:0] ln2_mean_rounded_q12_w;
  logic signed [7:0] ln2_input_q_w;
  logic signed [7:0] ln2_mean_input_q_w;
  logic signed [63:0] ln2_input_product_w;
  logic signed [63:0] ln2_mean_input_product_w;
  logic signed [63:0] ln2_input_shifted_w;
  logic signed [63:0] ln2_mean_input_shifted_w;
  logic signed [31:0] ln2_input_q12_w;
  logic signed [31:0] ln2_mean_input_q12_w;
  logic signed [31:0] ln2_centered_q12;
  logic signed [63:0] ln2_norm_product_w;
  logic signed [63:0] ln2_norm_shifted_w;
  logic signed [31:0] ln2_norm_q12_w;
  logic signed [63:0] ln2_affine_product_w;
  logic signed [63:0] ln2_affine_shifted_w;
  logic signed [31:0] ln2_affine_q12_w;
  logic signed [63:0] ln2_output_product_w;
  logic signed [63:0] ln2_output_shifted_w;
  logic signed [7:0] ln2_q_w;
  logic [7:0] ln2_u8_w;
  logic [31:0] ln2_index_u32_w;
  logic [31:0] ln2_weighted_value_w;
  logic output_valid_q;
  logic error_q;
  logic [31:0] out_index_u32_w;
  logic [31:0] in_index_u32_w;
  logic [3:0] out_index_detail_w;
  logic signed [7:0] out_proj_weight_read_q;
  logic [OUT_PROJ_WEIGHT_ADDR_WIDTH - 1:0] out_proj_weight_addr_q;

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

  assign selected_context_q_w =
    use_external_context_i
      ? $signed(external_context_vector_i[in_index_q * 8 +: 8])
      : $signed(out_proj_context_q[in_index_q]);
  assign out_proj_context_ext_w =
    $signed({{24{selected_context_q_w[7]}}, selected_context_q_w});
  assign selected_block_input_q_w =
    use_external_block_input_i
      ? $signed(external_block_input_vector_i[out_index_q * 8 +: 8])
      : $signed(out_proj_block_input_q[out_index_q]);
  assign out_proj_weight_ext_w =
    $signed({{24{out_proj_weight_read_q[7]}}, out_proj_weight_read_q});
  assign out_proj_product_w = out_proj_context_ext_w * out_proj_weight_ext_w;
  assign next_acc_w = acc_q + out_proj_product_w;
  assign product_w = $signed(acc_q) * $signed(out_proj_mul_q20[out_index_q]);
  assign shifted_w = round_shift_signed64(product_w, 20);
  assign output_q_w = saturate_i8($signed(shifted_w[31:0]));
  assign output_u8_w = output_q_w[7:0];
  assign residual_product_w =
    ($signed(output_q_w) * $signed(attn_residual_projected_mul_q20[out_index_q])) +
    ($signed(selected_block_input_q_w) * $signed(attn_residual_block_input_mul_q20[out_index_q])) +
    residual_bias_ext_w;
  assign residual_bias_ext_w =
    $signed({{32{attn_residual_bias_q20[out_index_q][31]}},
             attn_residual_bias_q20[out_index_q]});
  assign residual_shifted_w = round_shift_signed64(residual_product_w, 20);
  assign residual_q_w = saturate_i8($signed(residual_shifted_w[31:0]));
  assign residual_u8_w = residual_q_w[7:0];
  assign out_index_u32_w = {{(32 - INDEX_WIDTH){1'b0}}, out_index_q};
  assign in_index_u32_w = {{(32 - INDEX_WIDTH){1'b0}}, in_index_q};
  assign out_index_detail_w = out_index_u32_w[3:0];
  assign weighted_value_w = {24'd0, output_u8_w} * (out_index_u32_w + 32'd1);
  assign residual_weighted_value_w =
    {24'd0, residual_u8_w} * (out_index_u32_w + 32'd1);
  assign ln2_mean_next_acc_q12 =
    ln2_mean_acc_q12 +
    ln2_mean_input_q12_w;
  assign ln2_mean_input_q_w =
    $signed(residual_vector_q[ln2_mean_index_q * 8 +: 8]);
  assign ln2_input_q_w =
    $signed(residual_vector_q[ln2_index_q * 8 +: 8]);
  assign ln2_mean_input_product_w =
    $signed(ln2_mean_input_q_w) * $signed(LN2_INPUT_SCALE_MUL_Q20);
  assign ln2_input_product_w =
    $signed(ln2_input_q_w) * $signed(LN2_INPUT_SCALE_MUL_Q20);
  assign ln2_mean_input_shifted_w = round_shift_signed64(ln2_mean_input_product_w, 20);
  assign ln2_input_shifted_w = round_shift_signed64(ln2_input_product_w, 20);
  assign ln2_mean_input_q12_w = $signed(ln2_mean_input_shifted_w[31:0]);
  assign ln2_input_q12_w = $signed(ln2_input_shifted_w[31:0]);
  assign ln2_mean_next_acc_q12_s64_w =
    $signed({{32{ln2_mean_next_acc_q12[31]}}, ln2_mean_next_acc_q12});
  assign ln2_mean_rounded_q12_s64_w =
    round_shift_signed64(ln2_mean_next_acc_q12_s64_w, 6);
  assign ln2_mean_rounded_q12_w =
    $signed(ln2_mean_rounded_q12_s64_w[31:0]);
  assign ln2_centered_q12 =
    $signed(ln2_input_q12_w) -
    $signed(ln2_mean_latched_q12);
  assign ln2_norm_product_w = $signed(ln2_centered_q12) * $signed(LN2_INV_STD_Q16);
  assign ln2_norm_shifted_w = round_shift_signed64(ln2_norm_product_w, 16);
  assign ln2_norm_q12_w = $signed(ln2_norm_shifted_w[31:0]);
  assign ln2_affine_product_w = $signed(ln2_norm_q12_w) * $signed(ln2_gamma_q16[ln2_index_q]);
  assign ln2_affine_shifted_w = round_shift_signed64(ln2_affine_product_w, 16);
  assign ln2_affine_q12_w =
    $signed(ln2_affine_shifted_w[31:0]) +
    $signed({{16{ln2_beta_q12[ln2_index_q][15]}}, ln2_beta_q12[ln2_index_q]});
  assign ln2_output_product_w = $signed(ln2_affine_q12_w) * $signed(LN2_OUTPUT_SCALE_MUL_Q20);
  assign ln2_output_shifted_w = round_shift_signed64(ln2_output_product_w, 20);
  assign ln2_q_w = saturate_i8($signed(ln2_output_shifted_w[31:0]));
  assign ln2_u8_w = ln2_q_w[7:0];
  assign ln2_index_u32_w = {{(32 - INDEX_WIDTH){1'b0}}, ln2_index_q};
  assign ln2_weighted_value_w = {24'd0, ln2_u8_w} * (ln2_index_u32_w + 32'd1);

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= ST_IDLE;
      out_index_q <= '0;
      in_index_q <= '0;
      acc_q <= 32'sd0;
      cycle_count_q <= 32'd0;
      checksum_q <= 32'd0;
      sample0_q <= 32'd0;
      sample1_q <= 32'd0;
      output_vector_q <= 512'd0;
      residual_checksum_q <= 32'd0;
      residual_sample0_q <= 32'd0;
      residual_sample1_q <= 32'd0;
      residual_vector_q <= 512'd0;
      ln2_checksum_q <= 32'd0;
      ln2_sample0_q <= 32'd0;
      ln2_sample1_q <= 32'd0;
      ln2_vector_q <= 512'd0;
      ln2_mean_index_q <= '0;
      ln2_index_q <= '0;
      ln2_mean_acc_q12 <= 32'sd0;
      ln2_mean_latched_q12 <= 32'sd0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      debug_o <= 32'd0;
    end else begin
      unique case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q <= ST_PREFETCH;
            out_index_q <= '0;
            in_index_q <= '0;
            acc_q <= 32'sd0;
            cycle_count_q <= 32'd0;
            checksum_q <= 32'd0;
            sample0_q <= 32'd0;
            sample1_q <= 32'd0;
            output_vector_q <= 512'd0;
            residual_checksum_q <= 32'd0;
            residual_sample0_q <= 32'd0;
            residual_sample1_q <= 32'd0;
            residual_vector_q <= 512'd0;
            ln2_checksum_q <= 32'd0;
            ln2_sample0_q <= 32'd0;
            ln2_sample1_q <= 32'd0;
            ln2_vector_q <= 512'd0;
            ln2_mean_index_q <= '0;
            ln2_index_q <= '0;
            ln2_mean_acc_q12 <= 32'sd0;
            ln2_mean_latched_q12 <= 32'sd0;
            out_proj_weight_read_q <= 8'sd0;
            out_proj_weight_addr_q <= '0;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            debug_o <= 32'd0;
          end
        end

        ST_PREFETCH: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          out_proj_weight_read_q <= out_proj_weight_q[out_proj_weight_addr_q];
          out_proj_weight_addr_q <= out_proj_weight_addr_q + OUT_PROJ_WEIGHT_ADDR_WIDTH'(1);
          state_q <= ST_RUN;
        end

        ST_RUN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          acc_q <= next_acc_w;
          if (in_index_q == INDEX_WIDTH'(OUT_PROJ_DIM - 1)) begin
            state_q <= ST_CHECK;
          end else begin
            out_proj_weight_read_q <= out_proj_weight_q[out_proj_weight_addr_q];
            out_proj_weight_addr_q <= out_proj_weight_addr_q + OUT_PROJ_WEIGHT_ADDR_WIDTH'(1);
            in_index_q <= in_index_q + INDEX_WIDTH'(1);
          end
        end

        ST_CHECK: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (ENABLE_INTERNAL_CHECKS && acc_q != out_proj_expected_acc[out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {
              8'h01,
              out_index_detail_w,
              4'd0,
              out_proj_expected_acc[out_index_q][7:0],
              acc_q[7:0]
            };
          end else if (ENABLE_INTERNAL_CHECKS && output_q_w != out_proj_expected_q[out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {
              8'h02,
              out_index_detail_w,
              4'd0,
              out_proj_expected_q[out_index_q][7:0],
              output_q_w
            };
          end else if (ENABLE_INTERNAL_CHECKS && residual_q_w != attn_residual_expected_q[out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {
              8'h03,
              out_index_detail_w,
              4'd0,
              attn_residual_expected_q[out_index_q][7:0],
              residual_q_w
            };
          end else begin
            checksum_q <= checksum_q + weighted_value_w;
            output_vector_q[out_index_q * 8 +: 8] <= output_q_w;
            residual_checksum_q <= residual_checksum_q + residual_weighted_value_w;
            residual_vector_q[out_index_q * 8 +: 8] <= residual_q_w;
            if (out_index_u32_w < 32'd4) begin
              sample0_q <= sample0_q | ({24'd0, output_u8_w} << (8 * out_index_q[1:0]));
              residual_sample0_q <=
                residual_sample0_q | ({24'd0, residual_u8_w} << (8 * out_index_q[1:0]));
            end else if (out_index_u32_w < 32'd8) begin
              sample1_q <= sample1_q | ({24'd0, output_u8_w} << (8 * out_index_q[1:0]));
              residual_sample1_q <=
                residual_sample1_q | ({24'd0, residual_u8_w} << (8 * out_index_q[1:0]));
            end

            if (out_index_q == INDEX_WIDTH'(OUT_PROJ_DIM - 1)) begin
              state_q <= ST_LN2_MEAN;
              ln2_mean_index_q <= '0;
              ln2_mean_acc_q12 <= 32'sd0;
            end else begin
              out_index_q <= out_index_q + INDEX_WIDTH'(1);
              in_index_q <= '0;
              acc_q <= 32'sd0;
              state_q <= ST_PREFETCH;
            end
          end
        end

        ST_LN2_MEAN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          ln2_mean_acc_q12 <= ln2_mean_next_acc_q12;
          if (ln2_mean_index_q == INDEX_WIDTH'(OUT_PROJ_DIM - 1)) begin
            ln2_mean_latched_q12 <= ln2_mean_rounded_q12_w;
            ln2_index_q <= '0;
            state_q <= ST_LN2_RUN;
          end else begin
            ln2_mean_index_q <= ln2_mean_index_q + INDEX_WIDTH'(1);
          end
        end

        ST_LN2_RUN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (ENABLE_INTERNAL_CHECKS && ln2_q_w != ln2_expected_q[ln2_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h04, ln2_index_u32_w[3:0], 4'd0, 8'd0, ln2_q_w};
          end else begin
            ln2_checksum_q <= ln2_checksum_q + ln2_weighted_value_w;
            ln2_vector_q[ln2_index_q * 8 +: 8] <= ln2_q_w;
            if (ln2_index_u32_w < 32'd4) begin
              ln2_sample0_q <=
                ln2_sample0_q | ({24'd0, ln2_u8_w} << (8 * ln2_index_q[1:0]));
            end else if (ln2_index_u32_w < 32'd8) begin
              ln2_sample1_q <=
                ln2_sample1_q | ({24'd0, ln2_u8_w} << (8 * ln2_index_q[1:0]));
            end
            if (ln2_index_q == INDEX_WIDTH'(OUT_PROJ_DIM - 1)) begin
              state_q <= ST_DONE;
              output_valid_q <= 1'b1;
            end else begin
              ln2_index_q <= ln2_index_q + INDEX_WIDTH'(1);
            end
          end
        end

        ST_DONE: begin
          if (start_i) begin
            state_q <= ST_PREFETCH;
            out_index_q <= '0;
            in_index_q <= '0;
            acc_q <= 32'sd0;
            cycle_count_q <= 32'd0;
            checksum_q <= 32'd0;
            sample0_q <= 32'd0;
            sample1_q <= 32'd0;
            output_vector_q <= 512'd0;
            residual_checksum_q <= 32'd0;
            residual_sample0_q <= 32'd0;
            residual_sample1_q <= 32'd0;
            residual_vector_q <= 512'd0;
            ln2_checksum_q <= 32'd0;
            ln2_sample0_q <= 32'd0;
            ln2_sample1_q <= 32'd0;
            ln2_vector_q <= 512'd0;
            ln2_mean_index_q <= '0;
            ln2_index_q <= '0;
            ln2_mean_acc_q12 <= 32'sd0;
            ln2_mean_latched_q12 <= 32'sd0;
            out_proj_weight_read_q <= 8'sd0;
            out_proj_weight_addr_q <= '0;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            debug_o <= 32'd0;
          end
        end

        default: begin
          state_q <= ST_ERROR;
          error_q <= 1'b1;
        end
      endcase
    end
  end

  always_comb begin
    status_o = {
      16'h4f50,
      8'd0,
      1'b0,
      state_q,
      output_valid_q,
      error_q,
      state_q == ST_RUN || state_q == ST_CHECK,
      state_q == ST_IDLE || state_q == ST_DONE
    };
    cycle_count_o = cycle_count_q;
    output_checksum_o = checksum_q;
    output_sample0_o = sample0_q;
    output_sample1_o = sample1_q;
    output_vector_o = output_vector_q;
    residual_checksum_o = residual_checksum_q;
    residual_sample0_o = residual_sample0_q;
    residual_sample1_o = residual_sample1_q;
    residual_vector_o = residual_vector_q;
    ln2_checksum_o = ln2_checksum_q;
    ln2_sample0_o = ln2_sample0_q;
    ln2_sample1_o = ln2_sample1_q;
    ln2_vector_o = ln2_vector_q;
  end
endmodule
