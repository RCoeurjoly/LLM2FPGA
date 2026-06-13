`timescale 1ns/1ps

module task6_m2_live_context_full_block_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  input logic clear_i,
  input logic use_external_ln_input_i,
  input logic [6143:0] external_ln_input_q12_by_token_i,
  input logic use_external_block_input_i,
  input logic [511:0] external_block_input_vector_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] context_checksum_o,
  output logic [31:0] attn_out_checksum_o,
  output logic [31:0] attn_residual_checksum_o,
  output logic [31:0] ln2_checksum_o,
  output logic [31:0] post_gelu_checksum_o,
  output logic [31:0] c_proj_checksum_o,
  output logic [31:0] final_checksum_o,
  output logic [31:0] final_sample0_o,
  output logic [31:0] final_sample1_o,
  output logic [511:0] final_vector_o,
  output logic [31:0] debug_o,
  output logic [31:0] debug1_o,
  output logic [31:0] debug2_o
);
  typedef enum logic [3:0] {
    ST_IDLE = 4'd0,
    ST_CONTEXT_START = 4'd1,
    ST_CONTEXT = 4'd2,
    ST_ATTN_START = 4'd3,
    ST_ATTN = 4'd4,
    ST_MLP_START = 4'd5,
    ST_MLP_ARM = 4'd6,
    ST_MLP = 4'd7,
    ST_DONE = 4'd8,
    ST_ERROR = 4'd9
  } state_t;

  localparam logic [2:0] CONTEXT_ST_DONE = 3'd6;
  localparam logic [2:0] ATTN_ST_DONE = 3'd4;
  localparam logic [2:0] MLP_ST_DONE = 3'd7;

  state_t state_q;
  logic [31:0] cycle_count_q;
  logic context_start_q;
  logic attn_start_q;
  logic mlp_start_q;
  logic output_valid_q;
  logic error_q;

  logic [31:0] context_status_w;
  logic [31:0] context_cycle_count_w;
  logic [31:0] context_checksum_w;
  logic [31:0] context_sample0_w;
  logic [31:0] context_sample1_w;
  logic [511:0] context_vector_w;
  logic [31:0] context_debug_w;
  logic [31:0] context_debug1_w;
  logic [31:0] context_debug2_w;

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

  task6_m2_ln_attn_live_kv_all_heads_context_accel_top context_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(context_start_q),
    .clear_i(clear_i),
    .use_external_ln_input_i(use_external_ln_input_i),
    .external_ln_input_q12_by_token_i(external_ln_input_q12_by_token_i),
    .status_o(context_status_w),
    .cycle_count_o(context_cycle_count_w),
    .output_checksum_o(context_checksum_w),
    .output_sample0_o(context_sample0_w),
    .output_sample1_o(context_sample1_w),
    .output_vector_o(context_vector_w),
    .debug_o(context_debug_w),
    .debug1_o(context_debug1_w),
    .debug2_o(context_debug2_w)
  );

  task6_m2_first_token_attention_out_proj_accel_top attention_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(attn_start_q),
    .use_external_context_i(1'b1),
    .external_context_vector_i(context_vector_w),
    .use_external_block_input_i(use_external_block_input_i),
    .external_block_input_vector_i(external_block_input_vector_i),
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
      context_start_q <= 1'b0;
      attn_start_q <= 1'b0;
      mlp_start_q <= 1'b0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      debug_o <= 32'd0;
    end else if (clear_i) begin
      state_q <= ST_IDLE;
      cycle_count_q <= 32'd0;
      context_start_q <= 1'b0;
      attn_start_q <= 1'b0;
      mlp_start_q <= 1'b0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      debug_o <= 32'd0;
    end else begin
      context_start_q <= 1'b0;
      attn_start_q <= 1'b0;
      mlp_start_q <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q <= ST_CONTEXT_START;
            cycle_count_q <= 32'd0;
            context_start_q <= 1'b1;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            debug_o <= 32'd0;
          end
        end

        ST_CONTEXT_START: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          state_q <= ST_CONTEXT;
        end

        ST_CONTEXT: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (context_status_w[2]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {4'hc, context_debug_w[27:0]};
          end else if (context_status_w[6:4] == CONTEXT_ST_DONE && context_status_w[3]) begin
            state_q <= ST_ATTN_START;
            attn_start_q <= 1'b1;
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
            debug_o <= {4'ha, attn_debug_w[27:0]};
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
            debug_o <= {4'hb, mlp_debug_w[27:0]};
          end else if (mlp_status_w[6:4] == MLP_ST_DONE && mlp_status_w[3]) begin
            state_q <= ST_DONE;
            output_valid_q <= 1'b1;
          end
        end

        ST_DONE: begin
          if (start_i) begin
            state_q <= ST_CONTEXT_START;
            cycle_count_q <= 32'd0;
            context_start_q <= 1'b1;
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
      16'h4c42,
      8'd0,
      state_q,
      output_valid_q,
      error_q,
      state_q == ST_CONTEXT_START || state_q == ST_CONTEXT || state_q == ST_ATTN_START ||
        state_q == ST_ATTN || state_q == ST_MLP_START || state_q == ST_MLP_ARM || state_q == ST_MLP,
      state_q == ST_IDLE || state_q == ST_DONE
    };
    cycle_count_o = cycle_count_q;
    context_checksum_o = context_checksum_w;
    attn_out_checksum_o = attn_output_checksum_w;
    attn_residual_checksum_o = attn_residual_checksum_w;
    ln2_checksum_o = attn_ln2_checksum_w;
    post_gelu_checksum_o = mlp_post_gelu_checksum_w;
    c_proj_checksum_o = mlp_c_proj_checksum_w;
    final_checksum_o = mlp_final_checksum_w;
    final_sample0_o = mlp_final_sample0_w;
    final_sample1_o = mlp_final_sample1_w;
    final_vector_o = mlp_final_vector_w;
    debug1_o = context_debug1_w;
    debug2_o = context_debug2_w;
  end
endmodule
