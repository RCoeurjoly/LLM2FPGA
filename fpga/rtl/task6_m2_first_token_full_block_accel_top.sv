`timescale 1ns/1ps

module task6_m2_first_token_full_block_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] attn_out_checksum_o,
  output logic [31:0] attn_residual_checksum_o,
  output logic [31:0] ln2_checksum_o,
  output logic [31:0] post_gelu_checksum_o,
  output logic [31:0] c_proj_checksum_o,
  output logic [31:0] final_checksum_o,
  output logic [31:0] final_sample0_o,
  output logic [31:0] final_sample1_o,
  output logic [511:0] final_vector_o,
  output logic [31:0] debug_o
);
  typedef enum logic [2:0] {
    ST_IDLE = 3'd0,
    ST_ATTN_START = 3'd1,
    ST_ATTN = 3'd2,
    ST_MLP_START = 3'd3,
    ST_MLP_ARM = 3'd4,
    ST_MLP = 3'd5,
    ST_DONE = 3'd6,
    ST_ERROR = 3'd7
  } state_t;

  localparam logic [2:0] ATTN_ST_DONE = 3'd3;
  localparam logic [2:0] MLP_ST_DONE = 3'd5;

  state_t state_q;
  logic [31:0] cycle_count_q;
  logic attn_start_q;
  logic mlp_start_q;
  logic output_valid_q;
  logic error_q;

  logic [31:0] attn_status_w;
  logic [31:0] attn_cycle_count_w;
  logic [31:0] attn_output_checksum_w;
  logic [31:0] attn_output_sample0_w;
  logic [31:0] attn_output_sample1_w;
  logic [511:0] attn_output_vector_w;
  logic [31:0] attn_residual_checksum_w;
  logic [31:0] attn_residual_sample0_w;
  logic [31:0] attn_residual_sample1_w;
  logic [511:0] attn_residual_vector_w;
  logic [31:0] attn_ln2_checksum_w;
  logic [31:0] attn_ln2_sample0_w;
  logic [31:0] attn_ln2_sample1_w;
  logic [511:0] attn_ln2_vector_w;
  logic [31:0] attn_debug_w;

  logic [31:0] mlp_status_w;
  logic [31:0] mlp_cycle_count_w;
  logic [31:0] mlp_post_gelu_checksum_w;
  logic [31:0] mlp_c_proj_checksum_w;
  logic [31:0] mlp_final_checksum_w;
  logic [31:0] mlp_final_sample0_w;
  logic [31:0] mlp_final_sample1_w;
  logic [511:0] mlp_final_vector_w;
  logic [31:0] mlp_debug_w;

  task6_m2_first_token_attention_out_proj_accel_top attention_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(attn_start_q),
    .status_o(attn_status_w),
    .cycle_count_o(attn_cycle_count_w),
    .output_checksum_o(attn_output_checksum_w),
    .output_sample0_o(attn_output_sample0_w),
    .output_sample1_o(attn_output_sample1_w),
    .output_vector_o(attn_output_vector_w),
    .residual_checksum_o(attn_residual_checksum_w),
    .residual_sample0_o(attn_residual_sample0_w),
    .residual_sample1_o(attn_residual_sample1_w),
    .residual_vector_o(attn_residual_vector_w),
    .ln2_checksum_o(attn_ln2_checksum_w),
    .ln2_sample0_o(attn_ln2_sample0_w),
    .ln2_sample1_o(attn_ln2_sample1_w),
    .ln2_vector_o(attn_ln2_vector_w),
    .debug_o(attn_debug_w)
  );

  task6_m2_first_token_mlp_integrated_accel_top mlp_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(mlp_start_q),
    .use_external_ln2_i(1'b1),
    .external_ln2_vector_i(attn_ln2_vector_w),
    .use_external_residual_i(1'b1),
    .external_residual_vector_i(attn_residual_vector_w),
    .status_o(mlp_status_w),
    .cycle_count_o(mlp_cycle_count_w),
    .post_gelu_checksum_o(mlp_post_gelu_checksum_w),
    .c_proj_checksum_o(mlp_c_proj_checksum_w),
    .final_checksum_o(mlp_final_checksum_w),
    .final_sample0_o(mlp_final_sample0_w),
    .final_sample1_o(mlp_final_sample1_w),
    .final_vector_o(mlp_final_vector_w),
    .debug_o(mlp_debug_w)
  );

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= ST_IDLE;
      cycle_count_q <= 32'd0;
      attn_start_q <= 1'b0;
      mlp_start_q <= 1'b0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      debug_o <= 32'd0;
    end else begin
      attn_start_q <= 1'b0;
      mlp_start_q <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q <= ST_ATTN_START;
            cycle_count_q <= 32'd0;
            attn_start_q <= 1'b1;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            debug_o <= 32'd0;
          end
        end

        ST_ATTN_START: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          state_q <= ST_ATTN;
        end

        ST_ATTN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (attn_status_w[2]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'ha1, attn_debug_w[23:0]};
          end else if (attn_status_w[6:4] == ATTN_ST_DONE && attn_status_w[3]) begin
            state_q <= ST_MLP_START;
          end
        end

        ST_MLP_START: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          mlp_start_q <= 1'b1;
          state_q <= ST_MLP_ARM;
        end

        ST_MLP_ARM: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          state_q <= ST_MLP;
        end

        ST_MLP: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (mlp_status_w[2]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'hb1, mlp_debug_w[23:0]};
          end else if (mlp_status_w[6:4] == MLP_ST_DONE && mlp_status_w[3]) begin
            state_q <= ST_DONE;
            output_valid_q <= 1'b1;
          end
        end

        ST_DONE: begin
          if (start_i) begin
            state_q <= ST_ATTN_START;
            cycle_count_q <= 32'd0;
            attn_start_q <= 1'b1;
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
      16'h4642,
      8'd0,
      1'b0,
      state_q,
      output_valid_q,
      error_q,
      state_q == ST_ATTN_START || state_q == ST_ATTN || state_q == ST_MLP_START || state_q == ST_MLP_ARM || state_q == ST_MLP,
      state_q == ST_IDLE || state_q == ST_DONE
    };
    cycle_count_o = cycle_count_q;
    attn_out_checksum_o = attn_output_checksum_w;
    attn_residual_checksum_o = attn_residual_checksum_w;
    ln2_checksum_o = attn_ln2_checksum_w;
    post_gelu_checksum_o = mlp_post_gelu_checksum_w;
    c_proj_checksum_o = mlp_c_proj_checksum_w;
    final_checksum_o = mlp_final_checksum_w;
    final_sample0_o = mlp_final_sample0_w;
    final_sample1_o = mlp_final_sample1_w;
    final_vector_o = mlp_final_vector_w;
  end
endmodule
