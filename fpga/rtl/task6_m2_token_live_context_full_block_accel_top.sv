`timescale 1ns/1ps

module task6_m2_token_live_context_full_block_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic start_i,
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
  output logic [31:0] debug_o
);
  typedef enum logic [3:0] {
    ST_IDLE = 4'd0,
    ST_TOKEN_START = 4'd1,
    ST_TOKEN = 4'd2,
    ST_BLOCK_START = 4'd3,
    ST_BLOCK = 4'd4,
    ST_DONE = 4'd5,
    ST_ERROR = 4'd6
  } state_t;

  localparam logic [2:0] TOKEN_ST_DONE = 3'd4;
  localparam logic [3:0] BLOCK_ST_DONE = 4'd8;

  state_t state_q;
  logic [31:0] cycle_count_q;
  logic token_start_q;
  logic block_start_q;
  logic output_valid_q;
  logic error_q;

  logic [31:0] token_status_w;
  logic [31:0] token_cycle_count_w;
  logic [31:0] token_block_input_checksum_w;
  logic [511:0] token_block_input_vector_w;
  logic [6143:0] token_ln_input_q12_by_token_w;
  logic [31:0] token_debug_w;

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

  task6_m2_token_block_input_accel_top token_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(token_start_q),
    .clear_i(1'b0),
    .token_ids_i(token_ids_i),
    .status_o(token_status_w),
    .cycle_count_o(token_cycle_count_w),
    .block_input_checksum_o(token_block_input_checksum_w),
    .block_input_vector_o(token_block_input_vector_w),
    .ln_input_q12_by_token_o(token_ln_input_q12_by_token_w),
    .debug_o(token_debug_w)
  );

  task6_m2_live_context_full_block_accel_top block_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(block_start_q),
    .use_external_ln_input_i(1'b1),
    .external_ln_input_q12_by_token_i(token_ln_input_q12_by_token_w),
    .use_external_block_input_i(1'b1),
    .external_block_input_vector_i(token_block_input_vector_w),
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
      token_start_q <= 1'b0;
      block_start_q <= 1'b0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      debug_o <= 32'd0;
    end else begin
      token_start_q <= 1'b0;
      block_start_q <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q <= ST_TOKEN_START;
            cycle_count_q <= 32'd0;
            token_start_q <= 1'b1;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            debug_o <= 32'd0;
          end
        end

        ST_TOKEN_START: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          state_q <= ST_TOKEN;
        end

        ST_TOKEN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (token_status_w[2]) begin
            state_q <= ST_ERROR;
            error_q <= 1'b1;
            debug_o <= {8'he1, token_debug_w[23:0]};
          end else if (token_status_w[6:4] == TOKEN_ST_DONE && token_status_w[3]) begin
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
            debug_o <= {8'he2, block_debug_w[23:0]};
          end else if (block_status_w[7:4] == BLOCK_ST_DONE && block_status_w[3]) begin
            state_q <= ST_DONE;
            output_valid_q <= 1'b1;
          end
        end

        ST_DONE: begin
          if (start_i) begin
            state_q <= ST_TOKEN_START;
            cycle_count_q <= 32'd0;
            token_start_q <= 1'b1;
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
      16'h5446,
      8'd0,
      1'b0,
      state_q[2:0],
      output_valid_q,
      error_q,
      state_q == ST_TOKEN_START || state_q == ST_TOKEN || state_q == ST_BLOCK_START || state_q == ST_BLOCK,
      state_q == ST_IDLE || state_q == ST_DONE
    };
    cycle_count_o = cycle_count_q;
    block_input_checksum_o = token_block_input_checksum_w;
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
  end
endmodule
