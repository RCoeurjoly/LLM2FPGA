`timescale 1ns/1ps

module task6_m2_first_token_mlp_c_proj_residual_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] c_proj_checksum_o,
  output logic [31:0] c_proj_sample0_o,
  output logic [31:0] c_proj_sample1_o,
  output logic [511:0] c_proj_vector_o,
  output logic [31:0] final_checksum_o,
  output logic [31:0] final_sample0_o,
  output logic [31:0] final_sample1_o,
  output logic [511:0] final_vector_o,
  output logic [31:0] debug_o
);
  `include "tb_data.sv"

  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_RUN = 3'd1,
    ST_CHECK = 3'd2,
    ST_DONE = 3'd3,
    ST_ERROR = 3'd4
  } state_t;

  localparam int OUT_INDEX_WIDTH = $clog2(MLP_C_PROJ_OUT_DIM);
  localparam int IN_INDEX_WIDTH = $clog2(MLP_C_PROJ_IN_DIM);

  state_t state_q;
  logic [OUT_INDEX_WIDTH - 1:0] out_index_q;
  logic [IN_INDEX_WIDTH - 1:0] in_index_q;
  logic signed [31:0] acc_q;
  logic signed [31:0] next_acc_w;
  logic signed [63:0] c_proj_product_w;
  logic signed [63:0] c_proj_shifted_w;
  logic signed [31:0] c_proj_with_bias_w;
  logic signed [7:0] c_proj_q_w;
  logic [7:0] c_proj_u8_w;
  logic signed [63:0] final_product_w;
  logic signed [63:0] final_shifted_w;
  logic signed [7:0] final_q_w;
  logic [7:0] final_u8_w;
  logic [31:0] out_index_u32_w;
  logic [31:0] c_proj_weighted_value_w;
  logic [31:0] final_weighted_value_w;
  logic [31:0] cycle_count_q;
  logic [31:0] c_proj_checksum_q;
  logic [31:0] c_proj_sample0_q;
  logic [31:0] c_proj_sample1_q;
  logic [511:0] c_proj_vector_q;
  logic [31:0] final_checksum_q;
  logic [31:0] final_sample0_q;
  logic [31:0] final_sample1_q;
  logic [511:0] final_vector_q;
  logic output_valid_q;
  logic error_q;

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

  assign next_acc_w =
    acc_q +
    ($signed(mlp_post_gelu_q[in_index_q]) *
     $signed(mlp_c_proj_weight_q[(out_index_q * MLP_C_PROJ_IN_DIM) + in_index_q]));
  assign c_proj_product_w =
    $signed(acc_q) * $signed(mlp_c_proj_scale_mul_q[out_index_q]);
  assign c_proj_shifted_w =
    round_shift_signed64(c_proj_product_w, MLP_C_PROJ_REQUANT_SHIFT);
  assign c_proj_with_bias_w =
    $signed(c_proj_shifted_w[31:0]) + $signed(mlp_c_proj_bias_q[out_index_q]);
  assign c_proj_q_w = saturate_i8(c_proj_with_bias_w);
  assign c_proj_u8_w = c_proj_q_w[7:0];
  assign final_product_w =
    ($signed(mlp_residual_q[out_index_q]) * $signed(MLP_FINAL_RESIDUAL_MUL_Q)) +
    ($signed(c_proj_q_w) * $signed(MLP_FINAL_C_PROJ_MUL_Q));
  assign final_shifted_w =
    round_shift_signed64(final_product_w, MLP_C_PROJ_REQUANT_SHIFT);
  assign final_q_w = saturate_i8($signed(final_shifted_w[31:0]));
  assign final_u8_w = final_q_w[7:0];
  assign out_index_u32_w = {{(32 - OUT_INDEX_WIDTH){1'b0}}, out_index_q};
  assign c_proj_weighted_value_w =
    {24'd0, c_proj_u8_w} * (out_index_u32_w + 32'd1);
  assign final_weighted_value_w =
    {24'd0, final_u8_w} * (out_index_u32_w + 32'd1);

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= ST_IDLE;
      out_index_q <= '0;
      in_index_q <= '0;
      acc_q <= 32'sd0;
      cycle_count_q <= 32'd0;
      c_proj_checksum_q <= 32'd0;
      c_proj_sample0_q <= 32'd0;
      c_proj_sample1_q <= 32'd0;
      c_proj_vector_q <= 512'd0;
      final_checksum_q <= 32'd0;
      final_sample0_q <= 32'd0;
      final_sample1_q <= 32'd0;
      final_vector_q <= 512'd0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      debug_o <= 32'd0;
    end else begin
      unique case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q <= ST_RUN;
            out_index_q <= '0;
            in_index_q <= '0;
            acc_q <= 32'sd0;
            cycle_count_q <= 32'd0;
            c_proj_checksum_q <= 32'd0;
            c_proj_sample0_q <= 32'd0;
            c_proj_sample1_q <= 32'd0;
            c_proj_vector_q <= 512'd0;
            final_checksum_q <= 32'd0;
            final_sample0_q <= 32'd0;
            final_sample1_q <= 32'd0;
            final_vector_q <= 512'd0;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            debug_o <= 32'd0;
          end
        end

        ST_RUN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          acc_q <= next_acc_w;
          if (in_index_q == IN_INDEX_WIDTH'(MLP_C_PROJ_IN_DIM - 1)) begin
            state_q <= ST_CHECK;
          end else begin
            in_index_q <= in_index_q + IN_INDEX_WIDTH'(1);
          end
        end

        ST_CHECK: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (acc_q != mlp_c_proj_expected_acc[out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h01, out_index_u32_w[7:0], acc_q[15:0]};
          end else if (c_proj_q_w != mlp_c_proj_expected_q[out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h02, out_index_u32_w[7:0], 8'd0, c_proj_q_w};
          end else if (final_q_w != mlp_final_expected_q[out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h03, out_index_u32_w[7:0], 8'd0, final_q_w};
          end else begin
            c_proj_checksum_q <= c_proj_checksum_q + c_proj_weighted_value_w;
            final_checksum_q <= final_checksum_q + final_weighted_value_w;
            c_proj_vector_q[out_index_q * 8 +: 8] <= c_proj_q_w;
            final_vector_q[out_index_q * 8 +: 8] <= final_q_w;
            if (out_index_u32_w < 32'd4) begin
              c_proj_sample0_q <=
                c_proj_sample0_q | ({24'd0, c_proj_u8_w} << (8 * out_index_q[1:0]));
              final_sample0_q <=
                final_sample0_q | ({24'd0, final_u8_w} << (8 * out_index_q[1:0]));
            end else if (out_index_u32_w < 32'd8) begin
              c_proj_sample1_q <=
                c_proj_sample1_q | ({24'd0, c_proj_u8_w} << (8 * out_index_q[1:0]));
              final_sample1_q <=
                final_sample1_q | ({24'd0, final_u8_w} << (8 * out_index_q[1:0]));
            end
            if (out_index_q == OUT_INDEX_WIDTH'(MLP_C_PROJ_OUT_DIM - 1)) begin
              state_q <= ST_DONE;
              output_valid_q <= 1'b1;
            end else begin
              out_index_q <= out_index_q + OUT_INDEX_WIDTH'(1);
              in_index_q <= '0;
              acc_q <= 32'sd0;
              state_q <= ST_RUN;
            end
          end
        end

        ST_DONE: begin
          state_q <= ST_DONE;
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
      16'h4d50,
      8'd0,
      1'b0,
      state_q,
      output_valid_q,
      error_q,
      state_q == ST_RUN || state_q == ST_CHECK,
      state_q == ST_IDLE || state_q == ST_DONE
    };
    cycle_count_o = cycle_count_q;
    c_proj_checksum_o = c_proj_checksum_q;
    c_proj_sample0_o = c_proj_sample0_q;
    c_proj_sample1_o = c_proj_sample1_q;
    c_proj_vector_o = c_proj_vector_q;
    final_checksum_o = final_checksum_q;
    final_sample0_o = final_sample0_q;
    final_sample1_o = final_sample1_q;
    final_vector_o = final_vector_q;
  end
endmodule
