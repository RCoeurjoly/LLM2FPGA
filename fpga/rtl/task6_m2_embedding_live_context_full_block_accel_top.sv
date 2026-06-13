`timescale 1ns/1ps

module task6_m2_embedding_live_context_full_block_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
  input logic clear_i,
  input logic [95:0] token_ids_i,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] block_input_checksum_o,
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
    ST_EMBED_START = 4'd1,
    ST_EMBED = 4'd2,
    ST_BLOCK_START = 4'd3,
    ST_BLOCK = 4'd4,
    ST_DONE = 4'd5,
    ST_ERROR = 4'd6
  } state_t;

  localparam logic [2:0] EMBED_ST_DONE = 3'd3;
  localparam logic [3:0] BLOCK_ST_DONE = 4'd8;

  state_t state_q;
  logic [31:0] cycle_count_q;
  logic embed_start_q;
  logic block_start_q;
  logic output_valid_q;
  logic error_q;

  logic [31:0] embed_status_w;
  logic [31:0] embed_cycle_count_w;
  logic [31:0] embed_block_input_checksum_w;
  logic [511:0] embed_block_input_vector_w;
  logic [6143:0] embed_ln_input_q12_by_token_w;
  logic [31:0] embed_debug_w;
  logic [31:0] embed_block_input_checksum_q;
  logic [511:0] embed_block_input_vector_q;
  logic [6143:0] embed_ln_input_q12_by_token_q;

  logic [31:0] block_status_w;
  logic [31:0] block_cycle_count_w;
  logic [31:0] block_context_checksum_w;
  logic [31:0] block_attn_out_checksum_w;
  logic [31:0] block_attn_residual_checksum_w;
  logic [31:0] block_ln2_checksum_w;
  logic [31:0] block_post_gelu_checksum_w;
  logic [31:0] block_c_proj_checksum_w;
  logic [31:0] block_final_checksum_w;
  logic [31:0] block_final_sample0_w;
  logic [31:0] block_final_sample1_w;
  logic [511:0] block_final_vector_w;
  logic [31:0] block_debug_w;

  task6_m2_embedding_block_input_accel_top embed_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(embed_start_q),
    .clear_i(clear_i),
    .token_ids_i(token_ids_i),
    .status_o(embed_status_w),
    .cycle_count_o(embed_cycle_count_w),
    .block_input_checksum_o(embed_block_input_checksum_w),
    .block_input_vector_o(embed_block_input_vector_w),
    .ln_input_q12_by_token_o(embed_ln_input_q12_by_token_w),
    .debug_o(embed_debug_w)
  );

  task6_m2_live_context_full_block_accel_top block_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(block_start_q),
    .clear_i(clear_i),
    .use_external_ln_input_i(1'b1),
    .external_ln_input_q12_by_token_i(embed_ln_input_q12_by_token_q),
    .use_external_block_input_i(1'b1),
    .external_block_input_vector_i(embed_block_input_vector_q),
    .status_o(block_status_w),
    .cycle_count_o(block_cycle_count_w),
    .context_checksum_o(block_context_checksum_w),
    .attn_out_checksum_o(block_attn_out_checksum_w),
    .attn_residual_checksum_o(block_attn_residual_checksum_w),
    .ln2_checksum_o(block_ln2_checksum_w),
    .post_gelu_checksum_o(block_post_gelu_checksum_w),
    .c_proj_checksum_o(block_c_proj_checksum_w),
    .final_checksum_o(block_final_checksum_w),
    .final_sample0_o(block_final_sample0_w),
    .final_sample1_o(block_final_sample1_w),
    .final_vector_o(block_final_vector_w),
    .debug_o(block_debug_w)
  );

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= ST_IDLE;
      cycle_count_q <= 32'd0;
      embed_start_q <= 1'b0;
      block_start_q <= 1'b0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      embed_block_input_checksum_q <= 32'd0;
      embed_block_input_vector_q <= 512'd0;
      embed_ln_input_q12_by_token_q <= '0;
      debug_o <= 32'd0;
    end else if (clear_i) begin
      state_q <= ST_IDLE;
      cycle_count_q <= 32'd0;
      embed_start_q <= 1'b0;
      block_start_q <= 1'b0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      embed_block_input_checksum_q <= 32'd0;
      embed_block_input_vector_q <= 512'd0;
      embed_ln_input_q12_by_token_q <= '0;
      debug_o <= 32'd0;
    end else begin
      embed_start_q <= 1'b0;
      block_start_q <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q <= ST_EMBED_START;
            cycle_count_q <= 32'd0;
            embed_start_q <= 1'b1;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            embed_block_input_checksum_q <= 32'd0;
            embed_block_input_vector_q <= 512'd0;
            embed_ln_input_q12_by_token_q <= '0;
            debug_o <= 32'd0;
          end
        end

        ST_EMBED_START: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          state_q <= ST_EMBED;
        end

        ST_EMBED: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (embed_status_w[2]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= embed_debug_w;
          end else if (embed_status_w[6:4] == EMBED_ST_DONE && embed_status_w[3]) begin
            embed_block_input_checksum_q <= embed_block_input_checksum_w;
            embed_block_input_vector_q <= embed_block_input_vector_w;
            embed_ln_input_q12_by_token_q <= embed_ln_input_q12_by_token_w;
            state_q <= ST_BLOCK_START;
            block_start_q <= 1'b1;
          end
        end

        ST_BLOCK_START: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          state_q <= ST_BLOCK;
        end

        ST_BLOCK: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (block_status_w[2]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= block_debug_w;
          end else if (block_status_w[7:4] == BLOCK_ST_DONE && block_status_w[3]) begin
            state_q <= ST_DONE;
            output_valid_q <= 1'b1;
          end
        end

        ST_DONE: begin
          if (start_i) begin
            state_q <= ST_EMBED_START;
            cycle_count_q <= 32'd0;
            embed_start_q <= 1'b1;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            embed_block_input_checksum_q <= 32'd0;
            embed_block_input_vector_q <= 512'd0;
            embed_ln_input_q12_by_token_q <= '0;
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
      16'h4546,
      8'd0,
      1'b0,
      state_q[2:0],
      output_valid_q,
      error_q,
      state_q == ST_EMBED_START || state_q == ST_EMBED || state_q == ST_BLOCK_START || state_q == ST_BLOCK,
      state_q == ST_IDLE || state_q == ST_DONE
    };
    cycle_count_o = cycle_count_q;
    block_input_checksum_o = embed_block_input_checksum_q;
    context_checksum_o = block_context_checksum_w;
    attn_out_checksum_o = block_attn_out_checksum_w;
    attn_residual_checksum_o = block_attn_residual_checksum_w;
    ln2_checksum_o = block_ln2_checksum_w;
    post_gelu_checksum_o = block_post_gelu_checksum_w;
    c_proj_checksum_o = block_c_proj_checksum_w;
    final_checksum_o = block_final_checksum_w;
    final_sample0_o = block_final_sample0_w;
    final_sample1_o = block_final_sample1_w;
    final_vector_o = block_final_vector_w;
    debug1_o = {
      embed_ln_input_q12_by_token_q[15:0],
      embed_ln_input_q12_by_token_q[31:16]
    };
    debug2_o = {
      embed_ln_input_q12_by_token_q[47:32],
      embed_ln_input_q12_by_token_q[63:48]
    };
  end
endmodule
