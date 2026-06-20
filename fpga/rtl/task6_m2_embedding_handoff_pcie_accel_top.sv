`timescale 1ns/1ps

module task6_m2_embedding_handoff_pcie_accel_top #(
  parameter int M2_FULL_BLOCK_TOKEN_INDEX = 5
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
  output logic [127:0] pcie_output_hash_o,
  output logic [31:0] pcie_debug_o,
  output logic [31:0] pcie_debug1_o,
  output logic [31:0] pcie_debug2_o,
  output logic [31:0] pcie_debug3_o,
  output logic [31:0] pcie_provenance_o
);
  typedef enum logic [2:0] {
    M2_IDLE = 3'd0,
    M2_RUN = 3'd1,
    M2_START = 3'd2,
    M2_LATCH = 3'd4,
    M2_DONE = 3'd5,
    M2_ERROR = 3'd6
  } m2_state_t;

  localparam logic [2:0] EMBED_DONE = 3'd3;

  m2_state_t state_q;
  logic embed_start_q;
  logic pcie_clear_q;
  logic [95:0] token_ids_q;
  logic [31:0] cycle_count_q;
  logic [31:0] block_input_checksum_q;
  logic [31:0] ln_input_checksum_q;
  logic [127:0] block_input_hash_q;
  logic [511:0] block_input_vector_q;
  logic [31:0] debug_q;
  logic [31:0] debug1_q;
  logic [31:0] debug2_q;
  logic [31:0] debug3_q;
  logic [31:0] embed_status_w;
  logic [31:0] embed_cycle_count_w;
  logic [31:0] embed_block_input_checksum_w;
  logic [31:0] embed_ln_input_checksum_w;
  logic [511:0] embed_block_input_vector_w;
  logic [6143:0] embed_ln_input_q12_by_token_w;
  logic [31:0] embed_debug_w;
  wire unused_reserved = ^pcie_reserved_i;
  wire unused_ln_vector = ^embed_ln_input_q12_by_token_w;

  function automatic logic [127:0] vector_hash128(input logic [511:0] vector);
    logic [31:0] h0;
    logic [31:0] h1;
    logic [31:0] h2;
    logic [31:0] h3;
    logic [7:0] byte_value;
    logic [31:0] index_mix;
    begin
      h0 = 32'h811c9dc5;
      h1 = 32'h9e3779b9;
      h2 = 32'h85ebca6b;
      h3 = 32'hc2b2ae35;
      for (int index = 0; index < 64; index++) begin
        byte_value = vector[index * 8 +: 8];
        index_mix = 32'(index);
        h0 = {h0[26:0], h0[31:27]} ^ {24'd0, byte_value} ^ (32'h9e3779b9 + index_mix);
        h1 = {h1[6:0], h1[31:7]} + ({16'd0, byte_value, 8'd0} ^ (32'h85ebca6b + index_mix));
        h2 = {h2[28:0], h2[31:29]} ^ ({8'd0, byte_value, 16'd0} + 32'hc2b2ae35 + index_mix);
        h3 = h3 + ({24'd0, byte_value} ^ {index_mix[15:0], index_mix[15:0]} ^ {byte_value, byte_value, byte_value, byte_value});
      end
      vector_hash128 = {h3, h2, h1, h0};
    end
  endfunction

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

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= M2_IDLE;
      embed_start_q <= 1'b0;
      pcie_clear_q <= 1'b0;
      token_ids_q <= 96'd0;
      cycle_count_q <= 32'd0;
      block_input_checksum_q <= 32'd0;
      ln_input_checksum_q <= 32'd0;
      block_input_hash_q <= 128'd0;
      block_input_vector_q <= 512'd0;
      debug_q <= 32'd0;
      debug1_q <= 32'd0;
      debug2_q <= 32'd0;
      debug3_q <= 32'd0;
    end else begin
      pcie_clear_q <= pcie_clear_pulse_i;
      embed_start_q <= 1'b0;

      if (pcie_clear_q) begin
        state_q <= M2_IDLE;
        cycle_count_q <= 32'd0;
        block_input_checksum_q <= 32'd0;
        ln_input_checksum_q <= 32'd0;
        block_input_hash_q <= 128'd0;
        block_input_vector_q <= 512'd0;
        debug_q <= 32'd0;
        debug1_q <= 32'd0;
        debug2_q <= 32'd0;
        debug3_q <= 32'd0;
      end else begin
        unique case (state_q)
          M2_IDLE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_START;
              embed_start_q <= 1'b1;
              token_ids_q <= pcie_token_ids_i[95:0];
            end
          end

          M2_START: begin
            state_q <= M2_RUN;
          end

          M2_RUN: begin
            if (embed_status_w[2]) begin
              state_q <= M2_ERROR;
              cycle_count_q <= embed_cycle_count_w;
              debug_q <= embed_debug_w;
              debug1_q <= embed_block_input_checksum_w;
              debug2_q <= embed_ln_input_checksum_w;
              debug3_q <= {
                embed_block_input_checksum_w[15:0],
                embed_ln_input_checksum_w[15:0]
              };
            end else if (embed_status_w[6:4] == EMBED_DONE && embed_status_w[3]) begin
              state_q <= M2_LATCH;
            end
          end

          M2_LATCH: begin
            cycle_count_q <= embed_cycle_count_w;
            block_input_checksum_q <= embed_block_input_checksum_w;
            ln_input_checksum_q <= embed_ln_input_checksum_w;
            block_input_hash_q <= vector_hash128(embed_block_input_vector_w);
            block_input_vector_q <= embed_block_input_vector_w;
            debug_q <= embed_ln_input_checksum_w;
            debug1_q <= embed_block_input_checksum_w;
            debug2_q <= embed_ln_input_checksum_w;
            debug3_q <= {
              embed_block_input_checksum_w[15:0],
              embed_ln_input_checksum_w[15:0]
            };
            state_q <= M2_DONE;
          end

          M2_DONE: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_START;
              embed_start_q <= 1'b1;
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
      state_q == M2_START || state_q == M2_RUN || state_q == M2_LATCH,
      state_q == M2_IDLE || state_q == M2_DONE
    };
    pcie_cycle_count_o = cycle_count_q;
    pcie_output_checksum_o = block_input_checksum_q;
    pcie_output_sample0_o = {24'd0, block_input_vector_q[7:0]};
    pcie_output_sample1_o = {24'd0, block_input_vector_q[15:8]};
    pcie_output_count_o = 32'd64;
    pcie_output_vector_o = block_input_vector_q;
    pcie_output_hash_o = block_input_hash_q;
    pcie_debug_o = debug_q;
    pcie_debug1_o = debug1_q;
    pcie_debug2_o = debug2_q;
    pcie_debug3_o = debug3_q;
    pcie_provenance_o = 32'h4d32_3100 | {24'd0, M2_FULL_BLOCK_TOKEN_INDEX[7:0]};
  end
endmodule
