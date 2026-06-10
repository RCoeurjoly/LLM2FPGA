`timescale 1ns/1ps

module task6_m2_full_block_replay_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic [511:0] pcie_block_input_i,
  input logic [511:0] pcie_residual_after_attention_i,
  input logic pcie_start_pulse_i,
  input logic pcie_clear_pulse_i,
  output logic [31:0] pcie_status_o,
  output logic [31:0] pcie_cycle_count_o,
  output logic [31:0] pcie_output_checksum_o,
  output logic [31:0] pcie_output_sample0_o,
  output logic [31:0] pcie_output_sample1_o,
  output logic [31:0] pcie_output_count_o,
  output logic [511:0] pcie_output_vector_o
);
  `include "tb_data.sv"

  typedef enum logic [3:0] {
    M2_IDLE,
    M2_CAPTURE_INPUT,
    M2_RUN,
    M2_DONE,
    M2_ERROR
  } m2_state_t;

  localparam int INDEX_WIDTH = $clog2(M2_FULL_BLOCK_OUTPUT_COUNT);
  localparam int LAST_OUTPUT_INDEX = M2_FULL_BLOCK_OUTPUT_COUNT - 1;
  localparam int RUN_TIMEOUT_CYCLES = M2_FULL_BLOCK_OUTPUT_COUNT + 32;

  m2_state_t state_q;
  logic [INDEX_WIDTH - 1:0] index_q;
  logic [31:0] cycle_count_q;
  logic [31:0] run_watchdog_q;
  logic [31:0] start_count_q;
  logic output_valid_q;
  logic error_q;
  logic signed [7:0] current_value;
  logic [7:0] value_u8;
  logic [31:0] weighted_value;
  logic [31:0] next_checksum;
  logic [511:0] block_input_q;
  logic [511:0] residual_after_attention_q;

  assign current_value = m2_full_block_output_q[index_q];
  assign value_u8 = current_value[7:0];
  assign weighted_value =
    ({24'd0, value_u8} * ({{(32 - INDEX_WIDTH){1'b0}}, index_q} + 32'd1));
  assign next_checksum = pcie_output_checksum_o + weighted_value;

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= M2_IDLE;
      index_q <= '0;
      cycle_count_q <= 32'd0;
      run_watchdog_q <= 32'd0;
      start_count_q <= 32'd0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      pcie_output_checksum_o <= 32'd0;
      pcie_output_sample0_o <= 32'd0;
      pcie_output_sample1_o <= 32'd0;
      pcie_output_vector_o <= 512'd0;
      block_input_q <= 512'd0;
      residual_after_attention_q <= 512'd0;
    end else begin
      if (pcie_clear_pulse_i) begin
        state_q <= M2_IDLE;
        index_q <= '0;
        cycle_count_q <= 32'd0;
        run_watchdog_q <= 32'd0;
        output_valid_q <= 1'b0;
        error_q <= 1'b0;
        pcie_output_checksum_o <= 32'd0;
        pcie_output_sample0_o <= 32'd0;
        pcie_output_sample1_o <= 32'd0;
        pcie_output_vector_o <= 512'd0;
      end else begin
        unique case (state_q)
          M2_IDLE: begin
            if (pcie_start_pulse_i) begin
              start_count_q <= start_count_q + 32'd1;
              block_input_q <= pcie_block_input_i;
              residual_after_attention_q <= pcie_residual_after_attention_i;
              index_q <= '0;
              cycle_count_q <= 32'd0;
              run_watchdog_q <= 32'd0;
              output_valid_q <= 1'b0;
              error_q <= 1'b0;
              pcie_output_checksum_o <= 32'd0;
              pcie_output_sample0_o <= 32'd0;
              pcie_output_sample1_o <= 32'd0;
              pcie_output_vector_o <= 512'd0;
              state_q <= M2_CAPTURE_INPUT;
            end
          end

          M2_CAPTURE_INPUT: begin
            state_q <= M2_RUN;
          end

          M2_RUN: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            run_watchdog_q <= run_watchdog_q + 32'd1;
            pcie_output_checksum_o <= next_checksum;
            if (index_q < INDEX_WIDTH'(4)) begin
              pcie_output_sample0_o <=
                pcie_output_sample0_o | ({24'd0, value_u8} << (8 * index_q[1:0]));
            end else if (index_q < INDEX_WIDTH'(8)) begin
              pcie_output_sample1_o <=
                pcie_output_sample1_o | ({24'd0, value_u8} << (8 * index_q[1:0]));
            end
            if (index_q < INDEX_WIDTH'(64)) begin
              pcie_output_vector_o[index_q * 8 +: 8] <= current_value;
            end

            if (run_watchdog_q >= 32'(RUN_TIMEOUT_CYCLES)) begin
              error_q <= 1'b1;
              state_q <= M2_ERROR;
            end else if (index_q == INDEX_WIDTH'(LAST_OUTPUT_INDEX)) begin
              if (
                next_checksum == M2_FULL_BLOCK_EXPECTED_CHECKSUM &&
                pcie_output_sample0_o == M2_FULL_BLOCK_EXPECTED_SAMPLE0 &&
                pcie_output_sample1_o == M2_FULL_BLOCK_EXPECTED_SAMPLE1
              ) begin
                output_valid_q <= 1'b1;
                state_q <= M2_DONE;
              end else begin
                error_q <= 1'b1;
                state_q <= M2_ERROR;
              end
            end else begin
              index_q <= index_q + INDEX_WIDTH'(1);
            end
          end

          M2_DONE: begin
            if (pcie_start_pulse_i) begin
              start_count_q <= start_count_q + 32'd1;
              block_input_q <= pcie_block_input_i;
              residual_after_attention_q <= pcie_residual_after_attention_i;
              index_q <= '0;
              cycle_count_q <= 32'd0;
              run_watchdog_q <= 32'd0;
              output_valid_q <= 1'b0;
              error_q <= 1'b0;
              pcie_output_checksum_o <= 32'd0;
              pcie_output_sample0_o <= 32'd0;
              pcie_output_sample1_o <= 32'd0;
              pcie_output_vector_o <= 512'd0;
              state_q <= M2_CAPTURE_INPUT;
            end
          end

          M2_ERROR: begin
            if (pcie_start_pulse_i) begin
              state_q <= M2_IDLE;
            end
          end

          default: begin
            error_q <= 1'b1;
            state_q <= M2_ERROR;
          end
        endcase
      end
    end
  end

  always_comb begin
    pcie_status_o = {
      16'h4d32,
      6'd0,
      state_q,
      output_valid_q,
      error_q,
      state_q == M2_RUN,
      state_q == M2_IDLE || state_q == M2_DONE
    };
    pcie_cycle_count_o = cycle_count_q;
    pcie_output_count_o = M2_FULL_BLOCK_OUTPUT_COUNT;
  end

endmodule
