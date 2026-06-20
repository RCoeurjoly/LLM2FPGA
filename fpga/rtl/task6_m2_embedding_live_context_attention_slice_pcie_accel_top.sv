`timescale 1ns/1ps

module task6_m2_embedding_live_context_attention_slice_pcie_accel_top #(
  parameter int M2_FULL_BLOCK_TOKEN_INDEX = 5,
  parameter bit ENABLE_CONTEXT_INTERNAL_CHECKS = 1'b1
) (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic [511:0] pcie_token_ids_i,
  input logic [511:0] pcie_reserved_i,
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
  output logic [31:0] pcie_debug2_o,
  output logic [31:0] pcie_debug3_o,
  output logic [31:0] pcie_provenance_o
);
  typedef enum logic [2:0] {
    M2_IDLE = 3'd0,
    M2_EMBED_START = 3'd1,
    M2_EMBED = 3'd2,
    M2_CONTEXT_ARM = 3'd3,
    M2_CONTEXT = 3'd4,
    M2_DONE = 3'd5,
    M2_ERROR = 3'd6
  } m2_state_t;

  localparam logic [2:0] EMBED_DONE = 3'd3;
  localparam logic [2:0] CONTEXT_DONE = 3'd6;

  m2_state_t state_q;
  logic embed_start_q;
  logic context_start_q;
  logic pcie_clear_q;
  logic [95:0] token_ids_q;
  logic [31:0] cycle_count_q;
  logic [31:0] block_input_checksum_q;
  logic [31:0] ln_input_checksum_q;
  logic [31:0] context_checksum_q;
  logic [31:0] context_sample0_q;
  logic [31:0] context_sample1_q;
  logic [511:0] context_vector_q;
  logic [31:0] debug_q;
  logic [31:0] debug1_q;
  logic [31:0] debug2_q;
  logic [31:0] debug3_q;
  logic [511:0] block_input_vector_q;

  logic [31:0] embed_status_w;
  logic [31:0] embed_cycle_count_w;
  logic [31:0] embed_block_input_checksum_w;
  logic [31:0] embed_ln_input_checksum_w;
  logic [511:0] embed_block_input_vector_w;
  logic [6143:0] embed_ln_input_q12_by_token_w;
  logic [31:0] embed_debug_w;

  logic [31:0] context_status_w;
  logic [31:0] context_cycle_count_w;
  logic [31:0] context_output_checksum_w;
  logic [31:0] context_output_sample0_w;
  logic [31:0] context_output_sample1_w;
  logic [511:0] context_output_vector_w;
  logic [31:0] context_debug_w;
  logic [31:0] context_debug1_w;
  logic [31:0] context_debug2_w;
  logic [31:0] context_fixture_signature_w;
  wire unused_reserved = ^pcie_reserved_i;

  task6_m2_embedding_block_input_accel_top embed_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(embed_start_q),
    .clear_i(pcie_clear_q),
    .token_ids_i(token_ids_q),
    .status_o(embed_status_w),
    .cycle_count_o(embed_cycle_count_w),
    .block_input_checksum_o(embed_block_input_checksum_w),
    .ln_input_checksum_o(embed_ln_input_checksum_w),
    .block_input_vector_o(embed_block_input_vector_w),
    .ln_input_q12_by_token_o(embed_ln_input_q12_by_token_w),
    .debug_o(embed_debug_w)
  );

  task6_m2_ln_attn_live_kv_all_heads_context_accel_top #(
    .ENABLE_INTERNAL_CHECKS(ENABLE_CONTEXT_INTERNAL_CHECKS)
  ) context_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(context_start_q),
    .clear_i(pcie_clear_q),
    .use_external_ln_input_i(1'b1),
    .external_ln_input_q12_by_token_i(embed_ln_input_q12_by_token_w),
    .status_o(context_status_w),
    .cycle_count_o(context_cycle_count_w),
    .output_checksum_o(context_output_checksum_w),
    .output_sample0_o(context_output_sample0_w),
    .output_sample1_o(context_output_sample1_w),
    .output_vector_o(context_output_vector_w),
    .debug_o(context_debug_w),
    .debug1_o(context_debug1_w),
    .debug2_o(context_debug2_w),
    .fixture_signature_o(context_fixture_signature_w)
  );

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= M2_IDLE;
      embed_start_q <= 1'b0;
      context_start_q <= 1'b0;
      pcie_clear_q <= 1'b0;
      token_ids_q <= 96'd0;
      cycle_count_q <= 32'd0;
      block_input_checksum_q <= 32'd0;
      ln_input_checksum_q <= 32'd0;
      context_checksum_q <= 32'd0;
      context_sample0_q <= 32'd0;
      context_sample1_q <= 32'd0;
      context_vector_q <= 512'd0;
      debug_q <= 32'd0;
      debug1_q <= 32'd0;
      debug2_q <= 32'd0;
      debug3_q <= 32'd0;
      block_input_vector_q <= 512'd0;
    end else begin
      pcie_clear_q <= pcie_clear_pulse_i;
      embed_start_q <= 1'b0;
      context_start_q <= 1'b0;

      if (pcie_clear_q) begin
        state_q <= M2_IDLE;
        cycle_count_q <= 32'd0;
        block_input_checksum_q <= 32'd0;
        ln_input_checksum_q <= 32'd0;
        context_checksum_q <= 32'd0;
        context_sample0_q <= 32'd0;
        context_sample1_q <= 32'd0;
        context_vector_q <= 512'd0;
        debug_q <= 32'd0;
        debug1_q <= 32'd0;
        debug2_q <= 32'd0;
        debug3_q <= 32'd0;
        block_input_vector_q <= 512'd0;
      end else begin
        unique case (state_q)
          M2_IDLE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_EMBED_START;
              embed_start_q <= 1'b1;
              token_ids_q <= pcie_token_ids_i[95:0];
              cycle_count_q <= 32'd0;
            end
          end

          M2_EMBED_START: begin
            state_q <= M2_EMBED;
            cycle_count_q <= cycle_count_q + 32'd1;
          end

          M2_EMBED: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (embed_status_w[2]) begin
              state_q <= M2_ERROR;
              debug_q <= embed_debug_w;
              debug1_q <= embed_status_w;
              debug2_q <= embed_cycle_count_w;
            end else if (embed_status_w[6:4] == EMBED_DONE && embed_status_w[3]) begin
              block_input_checksum_q <= embed_block_input_checksum_w;
              ln_input_checksum_q <= embed_ln_input_checksum_w;
              block_input_vector_q <= embed_block_input_vector_w;
              debug3_q <= {
                embed_block_input_checksum_w[15:0],
                embed_ln_input_checksum_w[15:0]
              };
              state_q <= M2_CONTEXT_ARM;
            end
          end

          M2_CONTEXT_ARM: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            context_start_q <= 1'b1;
            state_q <= M2_CONTEXT;
          end

          M2_CONTEXT: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            debug_q <= context_debug_w;
            debug1_q <= context_debug1_w;
            debug2_q <= context_debug2_w;
            if (context_status_w[2]) begin
              state_q <= M2_ERROR;
              debug_q <= context_debug_w;
              debug1_q <= context_debug1_w;
              debug2_q <= context_debug2_w;
            end else if (context_status_w[6:4] == CONTEXT_DONE && context_status_w[3]) begin
              state_q <= M2_DONE;
              cycle_count_q <= cycle_count_q + context_cycle_count_w;
              context_checksum_q <= context_output_checksum_w;
              context_sample0_q <= context_output_sample0_w;
              context_sample1_q <= context_output_sample1_w;
              context_vector_q <= context_output_vector_w;
              debug_q <= embed_ln_input_checksum_w;
              debug1_q <= {
                block_input_checksum_q[15:0],
                context_output_checksum_w[15:0]
              };
              debug2_q <= context_debug2_w;
            end
          end

          M2_DONE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_EMBED_START;
              embed_start_q <= 1'b1;
              token_ids_q <= pcie_token_ids_i[95:0];
              cycle_count_q <= 32'd0;
              context_checksum_q <= 32'd0;
              context_sample0_q <= 32'd0;
              context_sample1_q <= 32'd0;
              context_vector_q <= 512'd0;
            end
          end

          default: begin
            state_q <= M2_ERROR;
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
      state_q == M2_DONE,
      state_q == M2_ERROR,
      state_q == M2_EMBED_START || state_q == M2_EMBED ||
        state_q == M2_CONTEXT_ARM || state_q == M2_CONTEXT,
      state_q == M2_IDLE || state_q == M2_DONE
    };
    pcie_cycle_count_o = cycle_count_q;
    pcie_output_checksum_o = context_checksum_q;
    pcie_output_sample0_o = context_sample0_q;
    pcie_output_sample1_o = context_sample1_q;
    pcie_output_count_o = 32'd64;
    pcie_output_vector_o = context_vector_q;
    pcie_debug_o = debug_q;
    pcie_debug1_o = debug1_q;
    pcie_debug2_o = debug2_q;
    pcie_debug3_o = (state_q == M2_IDLE) ? context_fixture_signature_w : debug3_q;
    pcie_provenance_o = 32'h4d32_4100 | {24'd0, M2_FULL_BLOCK_TOKEN_INDEX[7:0]};
  end
endmodule
