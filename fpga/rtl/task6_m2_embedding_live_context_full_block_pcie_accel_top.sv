`timescale 1ns/1ps

module task6_m2_embedding_live_context_full_block_pcie_accel_top #(
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
  output logic [31:0] pcie_provenance_o
);
  typedef enum logic [2:0] {
    M2_IDLE = 3'd0,
    M2_RUN = 3'd1,
    M2_START = 3'd2,
    M2_FINISH = 3'd3,
    M2_LATCH = 3'd4,
    M2_DONE = 3'd5,
    M2_ERROR = 3'd6
  } m2_state_t;

  localparam logic [2:0] CORE_DONE = 3'd5;

  m2_state_t state_q;
  logic core_start_q;
  logic [95:0] token_ids_q;
  logic [31:0] cycle_count_q;
  logic [31:0] final_checksum_q;
  logic [31:0] final_sample0_q;
  logic [31:0] final_sample1_q;
  logic [511:0] final_vector_q;
  logic [31:0] debug_q;
  logic [31:0] debug1_q;
  logic [31:0] debug2_q;
  logic pcie_clear_q;
  logic core_clear_w;
  logic [31:0] core_status_w;
  logic [31:0] core_cycle_count_w;
  logic [31:0] core_block_input_checksum_w;
  logic [31:0] core_context_checksum_w;
  logic [31:0] core_attn_out_checksum_w;
  logic [31:0] core_attn_residual_checksum_w;
  logic [31:0] core_ln2_checksum_w;
  logic [31:0] core_post_gelu_checksum_w;
  logic [31:0] core_c_proj_checksum_w;
  logic [31:0] core_final_checksum_w;
  logic [31:0] core_final_sample0_w;
  logic [31:0] core_final_sample1_w;
  logic [511:0] core_final_vector_w;
  logic [31:0] core_debug_w;
  logic [31:0] core_debug1_w;
  logic [31:0] core_debug2_w;
  wire unused_reserved = ^pcie_reserved_i;

  // The BAR clear path is host-visible wrapper control. Forwarding it into the
  // full compute core creates a high-fanout timing path across the M2 datapath.
  assign core_clear_w = 1'b0;

  task6_m2_embedding_live_context_full_block_accel_top #(
    .ENABLE_CONTEXT_INTERNAL_CHECKS(ENABLE_CONTEXT_INTERNAL_CHECKS)
  ) core_i (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(core_start_q),
    .clear_i(core_clear_w),
    .token_ids_i(token_ids_q),
    .status_o(core_status_w),
    .cycle_count_o(core_cycle_count_w),
    .block_input_checksum_o(core_block_input_checksum_w),
    .context_checksum_o(core_context_checksum_w),
    .attn_out_checksum_o(core_attn_out_checksum_w),
    .attn_residual_checksum_o(core_attn_residual_checksum_w),
    .ln2_checksum_o(core_ln2_checksum_w),
    .post_gelu_checksum_o(core_post_gelu_checksum_w),
    .c_proj_checksum_o(core_c_proj_checksum_w),
    .final_checksum_o(core_final_checksum_w),
    .final_sample0_o(core_final_sample0_w),
    .final_sample1_o(core_final_sample1_w),
    .final_vector_o(core_final_vector_w),
    .debug_o(core_debug_w),
    .debug1_o(core_debug1_w),
    .debug2_o(core_debug2_w)
  );

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= M2_IDLE;
      core_start_q <= 1'b0;
      token_ids_q <= 96'd0;
      cycle_count_q <= 32'd0;
      final_checksum_q <= 32'd0;
      final_sample0_q <= 32'd0;
      final_sample1_q <= 32'd0;
      final_vector_q <= 512'd0;
      debug_q <= 32'd0;
      debug1_q <= 32'd0;
      debug2_q <= 32'd0;
      pcie_clear_q <= 1'b0;
    end else begin
      pcie_clear_q <= pcie_clear_pulse_i;
      core_start_q <= 1'b0;

      if (pcie_clear_q) begin
        state_q <= M2_IDLE;
        cycle_count_q <= 32'd0;
        final_checksum_q <= 32'd0;
        final_sample0_q <= 32'd0;
        final_sample1_q <= 32'd0;
        final_vector_q <= 512'd0;
        debug_q <= 32'd0;
        debug1_q <= 32'd0;
        debug2_q <= 32'd0;
      end else begin
        unique case (state_q)
          M2_IDLE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_START;
              core_start_q <= 1'b1;
              token_ids_q <= pcie_token_ids_i[95:0];
            end
          end

          M2_START: begin
            state_q <= M2_RUN;
          end

          M2_RUN: begin
            if (core_status_w[2]) begin
              state_q <= M2_ERROR;
              cycle_count_q <= core_cycle_count_w;
              debug_q <= core_debug_w;
              debug1_q <= core_debug1_w;
              debug2_q <= core_debug2_w;
            end else if (core_status_w[6:4] == CORE_DONE && core_status_w[3]) begin
              state_q <= M2_FINISH;
            end
          end

          M2_FINISH: begin
            state_q <= M2_LATCH;
          end

          M2_LATCH: begin
            cycle_count_q <= core_cycle_count_w;
            final_checksum_q <= core_final_checksum_w;
            final_sample0_q <= core_final_sample0_w;
            final_sample1_q <= core_final_sample1_w;
            final_vector_q <= core_final_vector_w;
            debug_q <= core_debug_w;
            debug1_q <= {
              core_block_input_checksum_w[15:0],
              core_context_checksum_w[15:0]
            };
            debug2_q <= {
              core_attn_out_checksum_w[7:0],
              core_attn_residual_checksum_w[7:0],
              core_ln2_checksum_w[7:0],
              core_c_proj_checksum_w[7:0]
            };
            state_q <= M2_DONE;
          end

          M2_DONE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_START;
              core_start_q <= 1'b1;
              token_ids_q <= pcie_token_ids_i[95:0];
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
      state_q == M2_START || state_q == M2_RUN || state_q == M2_FINISH || state_q == M2_LATCH,
      state_q == M2_IDLE || state_q == M2_DONE
    };
    pcie_cycle_count_o = cycle_count_q;
    pcie_output_checksum_o = final_checksum_q;
    pcie_output_sample0_o = final_sample0_q;
    pcie_output_sample1_o = final_sample1_q;
    pcie_output_count_o = 32'd64;
    pcie_output_vector_o = final_vector_q;
    pcie_debug_o = debug_q;
    pcie_debug1_o = debug1_q;
    pcie_debug2_o = debug2_q;
    pcie_provenance_o = 32'h4d32_3000 | {24'd0, M2_FULL_BLOCK_TOKEN_INDEX[7:0]};
  end
endmodule
