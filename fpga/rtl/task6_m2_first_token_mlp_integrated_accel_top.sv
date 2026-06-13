`timescale 1ns/1ps

module task6_m2_first_token_mlp_integrated_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  input logic use_external_ln2_i,
  input logic [511:0] external_ln2_vector_i,
  input logic use_external_residual_i,
  input logic [511:0] external_residual_vector_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] post_gelu_checksum_o,
  output logic [31:0] c_proj_checksum_o,
  output logic [31:0] final_checksum_o,
  output logic [31:0] final_sample0_o,
  output logic [31:0] final_sample1_o,
  output logic [511:0] final_vector_o,
  output logic [31:0] debug_o
);
  `include "tb_data.sv"

  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_CFC_RUN = 3'd1,
    ST_CFC_CHECK = 3'd2,
    ST_CPROJ_RUN = 3'd3,
    ST_CPROJ_CHECK = 3'd4,
    ST_DONE = 3'd5,
    ST_ERROR = 3'd6
  } state_t;

  localparam int CFC_OUT_WIDTH = $clog2(MLP_C_FC_OUT_DIM);
  localparam int CFC_IN_WIDTH = $clog2(MLP_C_FC_IN_DIM);
  localparam int CPROJ_OUT_WIDTH = $clog2(MLP_C_PROJ_OUT_DIM);
  localparam int CPROJ_IN_WIDTH = $clog2(MLP_C_PROJ_IN_DIM);

  state_t state_q;
  logic [CFC_OUT_WIDTH - 1:0] cfc_out_index_q;
  logic [CFC_IN_WIDTH - 1:0] cfc_in_index_q;
  logic [CPROJ_OUT_WIDTH - 1:0] cproj_out_index_q;
  logic [CPROJ_IN_WIDTH - 1:0] cproj_in_index_q;
  logic signed [31:0] acc_q;
  logic signed [31:0] cfc_next_acc_w;
  logic signed [31:0] cproj_next_acc_w;
  logic signed [7:0] cfc_ln2_q_w;
  logic signed [7:0] final_residual_q_w;
  logic signed [63:0] cfc_x_product_w;
  logic signed [63:0] cfc_x_shifted_w;
  logic signed [31:0] cfc_x_q_w;
  logic signed [7:0] post_gelu_q_w;
  logic signed [63:0] cproj_product_w;
  logic signed [63:0] cproj_shifted_w;
  logic signed [31:0] cproj_with_bias_w;
  logic signed [7:0] c_proj_q_w;
  logic signed [63:0] final_product_w;
  logic signed [63:0] final_shifted_w;
  logic signed [7:0] final_q_w;
  logic [31:0] cycle_count_q;
  logic [31:0] post_gelu_checksum_q;
  logic [31:0] c_proj_checksum_q;
  logic [31:0] final_checksum_q;
  logic [31:0] final_sample0_q;
  logic [31:0] final_sample1_q;
  logic [511:0] final_vector_q;
  logic output_valid_q;
  logic error_q;
  logic busy_w;
  logic [31:0] cfc_out_index_u32_w;
  logic [31:0] cproj_out_index_u32_w;
  logic signed [7:0] post_gelu_mem [0:MLP_C_FC_OUT_DIM-1];

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

  function automatic signed [7:0] fixed_post_gelu_pwl(input signed [31:0] x_q);
    int segment;
    logic signed [31:0] x0;
    logic signed [31:0] x1;
    logic signed [31:0] y0;
    logic signed [31:0] y1;
    logic signed [63:0] numerator;
    logic signed [31:0] denominator;
    logic signed [31:0] recip_q;
    logic signed [63:0] delta_product;
    logic signed [63:0] delta_q;
    begin
      segment = 0;
      for (int idx = 0; idx < MLP_GELU_PWL_NODE_COUNT - 1; idx = idx + 1) begin
        if (x_q >= mlp_gelu_pwl_x_nodes[idx]) begin
          segment = idx;
        end
      end
      if (segment >= MLP_GELU_PWL_NODE_COUNT - 1) begin
        segment = MLP_GELU_PWL_NODE_COUNT - 2;
      end
      x0 = mlp_gelu_pwl_x_nodes[segment];
      x1 = mlp_gelu_pwl_x_nodes[segment + 1];
      y0 = {{24{mlp_gelu_pwl_y_nodes[segment][7]}}, mlp_gelu_pwl_y_nodes[segment]};
      y1 = {{24{mlp_gelu_pwl_y_nodes[segment + 1][7]}}, mlp_gelu_pwl_y_nodes[segment + 1]};
      numerator = $signed(x_q - x0) * $signed(y1 - y0);
      denominator = x1 - x0;
      recip_q = ((32'sd1 <<< 16) + (denominator >>> 1)) / denominator;
      delta_product = numerator * $signed(recip_q);
      delta_q = round_shift_signed64(delta_product, 16);
      fixed_post_gelu_pwl = saturate_i8($signed(y0 + delta_q[31:0]));
    end
  endfunction

  assign cfc_next_acc_w =
    acc_q +
    ($signed(cfc_ln2_q_w) *
     $signed(mlp_c_fc_weight_q[cfc_out_index_q][cfc_in_index_q]));
  assign cfc_ln2_q_w =
    use_external_ln2_i
      ? $signed(external_ln2_vector_i[cfc_in_index_q * 8 +: 8])
      : $signed(mlp_ln2_q[cfc_in_index_q]);
  assign cfc_x_product_w =
    $signed(acc_q) * $signed(mlp_c_fc_scale_mul_q[cfc_out_index_q]);
  assign cfc_x_shifted_w = round_shift_signed64(cfc_x_product_w, MLP_C_FC_SCALE_SHIFT);
  assign cfc_x_q_w = $signed(cfc_x_shifted_w[31:0]) + $signed(mlp_c_fc_bias_q[cfc_out_index_q]);
  assign post_gelu_q_w = fixed_post_gelu_pwl(cfc_x_q_w);

  assign cproj_next_acc_w =
    acc_q +
    ($signed(post_gelu_mem[cproj_in_index_q]) *
     $signed(mlp_c_proj_weight_q[cproj_out_index_q][cproj_in_index_q]));
  assign cproj_product_w =
    $signed(acc_q) * $signed(mlp_c_proj_scale_mul_q[cproj_out_index_q]);
  assign cproj_shifted_w =
    round_shift_signed64(cproj_product_w, MLP_C_PROJ_REQUANT_SHIFT);
  assign cproj_with_bias_w =
    $signed(cproj_shifted_w[31:0]) + $signed(mlp_c_proj_bias_q[cproj_out_index_q]);
  assign c_proj_q_w = saturate_i8(cproj_with_bias_w);
  assign final_product_w =
    ($signed(final_residual_q_w) * $signed(MLP_FINAL_RESIDUAL_MUL_Q)) +
    ($signed(c_proj_q_w) * $signed(MLP_FINAL_C_PROJ_MUL_Q));
  assign final_residual_q_w =
    use_external_residual_i
      ? $signed(external_residual_vector_i[cproj_out_index_q * 8 +: 8])
      : $signed(mlp_residual_q[cproj_out_index_q]);
  assign final_shifted_w =
    round_shift_signed64(final_product_w, MLP_C_PROJ_REQUANT_SHIFT);
  assign final_q_w = saturate_i8($signed(final_shifted_w[31:0]));
  assign busy_w =
    state_q == ST_CFC_RUN ||
    state_q == ST_CFC_CHECK ||
    state_q == ST_CPROJ_RUN ||
    state_q == ST_CPROJ_CHECK;
  assign cfc_out_index_u32_w = {{(32 - CFC_OUT_WIDTH){1'b0}}, cfc_out_index_q};
  assign cproj_out_index_u32_w = {{(32 - CPROJ_OUT_WIDTH){1'b0}}, cproj_out_index_q};

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= ST_IDLE;
      cfc_out_index_q <= '0;
      cfc_in_index_q <= '0;
      cproj_out_index_q <= '0;
      cproj_in_index_q <= '0;
      acc_q <= 32'sd0;
      cycle_count_q <= 32'd0;
      post_gelu_checksum_q <= 32'd0;
      c_proj_checksum_q <= 32'd0;
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
            state_q <= ST_CFC_RUN;
            cfc_out_index_q <= '0;
            cfc_in_index_q <= '0;
            cproj_out_index_q <= '0;
            cproj_in_index_q <= '0;
            acc_q <= 32'sd0;
            cycle_count_q <= 32'd0;
            post_gelu_checksum_q <= 32'd0;
            c_proj_checksum_q <= 32'd0;
            final_checksum_q <= 32'd0;
            final_sample0_q <= 32'd0;
            final_sample1_q <= 32'd0;
            final_vector_q <= 512'd0;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            debug_o <= 32'd0;
          end
        end

        ST_CFC_RUN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          acc_q <= cfc_next_acc_w;
          if (cfc_in_index_q == CFC_IN_WIDTH'(MLP_C_FC_IN_DIM - 1)) begin
            state_q <= ST_CFC_CHECK;
          end else begin
            cfc_in_index_q <= cfc_in_index_q + CFC_IN_WIDTH'(1);
          end
        end

        ST_CFC_CHECK: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (acc_q != mlp_c_fc_expected_acc[cfc_out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h11, cfc_out_index_u32_w[7:0], acc_q[15:0]};
          end else if (cfc_x_q_w != mlp_c_fc_expected_x_q[cfc_out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h12, cfc_out_index_u32_w[7:0], cfc_x_q_w[15:0]};
          end else if (post_gelu_q_w != mlp_post_gelu_q[cfc_out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h13, cfc_out_index_u32_w[7:0], 8'd0, post_gelu_q_w};
          end else begin
            post_gelu_mem[cfc_out_index_q] <= post_gelu_q_w;
            post_gelu_checksum_q <=
              post_gelu_checksum_q +
              ({24'd0, post_gelu_q_w[7:0]} * ({{(32 - CFC_OUT_WIDTH){1'b0}}, cfc_out_index_q} + 32'd1));
            if (cfc_out_index_q == CFC_OUT_WIDTH'(MLP_C_FC_OUT_DIM - 1)) begin
              state_q <= ST_CPROJ_RUN;
              cproj_out_index_q <= '0;
              cproj_in_index_q <= '0;
              acc_q <= 32'sd0;
            end else begin
              cfc_out_index_q <= cfc_out_index_q + CFC_OUT_WIDTH'(1);
              cfc_in_index_q <= '0;
              acc_q <= 32'sd0;
              state_q <= ST_CFC_RUN;
            end
          end
        end

        ST_CPROJ_RUN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          acc_q <= cproj_next_acc_w;
          if (cproj_in_index_q == CPROJ_IN_WIDTH'(MLP_C_PROJ_IN_DIM - 1)) begin
            state_q <= ST_CPROJ_CHECK;
          end else begin
            cproj_in_index_q <= cproj_in_index_q + CPROJ_IN_WIDTH'(1);
          end
        end

        ST_CPROJ_CHECK: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (acc_q != mlp_c_proj_expected_acc[cproj_out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h21, cproj_out_index_u32_w[7:0], acc_q[15:0]};
          end else if (c_proj_q_w != mlp_c_proj_expected_q[cproj_out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h22, cproj_out_index_u32_w[7:0], 8'd0, c_proj_q_w};
          end else if (final_q_w != mlp_final_expected_q[cproj_out_index_q]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'h23, cproj_out_index_u32_w[7:0], 8'd0, final_q_w};
          end else begin
            c_proj_checksum_q <=
              c_proj_checksum_q +
              ({24'd0, c_proj_q_w[7:0]} * ({{(32 - CPROJ_OUT_WIDTH){1'b0}}, cproj_out_index_q} + 32'd1));
            final_checksum_q <=
              final_checksum_q +
              ({24'd0, final_q_w[7:0]} * ({{(32 - CPROJ_OUT_WIDTH){1'b0}}, cproj_out_index_q} + 32'd1));
            final_vector_q[cproj_out_index_q * 8 +: 8] <= final_q_w;
            if (cproj_out_index_q < CPROJ_OUT_WIDTH'(4)) begin
              final_sample0_q <=
                final_sample0_q | ({24'd0, final_q_w[7:0]} << (8 * cproj_out_index_q[1:0]));
            end else if (cproj_out_index_q < CPROJ_OUT_WIDTH'(8)) begin
              final_sample1_q <=
                final_sample1_q | ({24'd0, final_q_w[7:0]} << (8 * cproj_out_index_q[1:0]));
            end
            if (cproj_out_index_q == CPROJ_OUT_WIDTH'(MLP_C_PROJ_OUT_DIM - 1)) begin
              state_q <= ST_DONE;
              output_valid_q <= 1'b1;
            end else begin
              cproj_out_index_q <= cproj_out_index_q + CPROJ_OUT_WIDTH'(1);
              cproj_in_index_q <= '0;
              acc_q <= 32'sd0;
              state_q <= ST_CPROJ_RUN;
            end
          end
        end

        ST_DONE: begin
          if (start_i) begin
            state_q <= ST_CFC_RUN;
            cfc_out_index_q <= '0;
            cfc_in_index_q <= '0;
            cproj_out_index_q <= '0;
            cproj_in_index_q <= '0;
            acc_q <= 32'sd0;
            cycle_count_q <= 32'd0;
            post_gelu_checksum_q <= 32'd0;
            c_proj_checksum_q <= 32'd0;
            final_checksum_q <= 32'd0;
            final_sample0_q <= 32'd0;
            final_sample1_q <= 32'd0;
            final_vector_q <= 512'd0;
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
      16'h4d49,
      8'd0,
      1'b0,
      state_q,
      output_valid_q,
      error_q,
      busy_w,
      state_q == ST_IDLE || state_q == ST_DONE
    };
    cycle_count_o = cycle_count_q;
    post_gelu_checksum_o = post_gelu_checksum_q;
    c_proj_checksum_o = c_proj_checksum_q;
    final_checksum_o = final_checksum_q;
    final_sample0_o = final_sample0_q;
    final_sample1_o = final_sample1_q;
    final_vector_o = final_vector_q;
  end
endmodule
