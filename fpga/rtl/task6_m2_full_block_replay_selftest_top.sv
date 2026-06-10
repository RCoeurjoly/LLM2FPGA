`timescale 1ns/1ps

module task6_m2_full_block_replay_selftest_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o,
  output logic [31:0] status_o,
  output logic [31:0] cycle_count_o,
  output logic [31:0] output_checksum_o,
  output logic [31:0] output_sample0_o,
  output logic [31:0] output_sample1_o,
  output logic [31:0] fail_detail_o
);
  `include "tb_data.sv"

  localparam logic [1:0] ST_BOOT = 2'd0;
  localparam logic [1:0] ST_RUN = 2'd1;
  localparam logic [1:0] ST_PASS = 2'd2;
  localparam logic [1:0] ST_FAIL = 2'd3;
  localparam logic [31:0] TIMEOUT_CYCLES = 32'd20000;
  localparam int INDEX_WIDTH = $clog2(M2_FULL_BLOCK_OUTPUT_COUNT);
  localparam int LAST_OUTPUT_INDEX = M2_FULL_BLOCK_OUTPUT_COUNT - 1;

  logic [1:0] state_q;
  logic [7:0] boot_q;
  logic [INDEX_WIDTH - 1:0] index_q;
  logic [31:0] checksum_q;
  logic [31:0] sample0_q;
  logic [31:0] sample1_q;
  logic [31:0] cycle_q;
  logic [31:0] fail_detail_q;
  logic signed [7:0] current_value;
  logic [7:0] value_u8;
  logic [31:0] weighted_value;
  logic [31:0] next_checksum;

  assign current_value = m2_full_block_output_q[index_q];
  assign value_u8 = current_value[7:0];
  assign weighted_value =
    ({24'd0, value_u8} * ({{(32 - INDEX_WIDTH){1'b0}}, index_q} + 32'd1));
  assign next_checksum = checksum_q + weighted_value;

  assign led_3bits_tri_o = {
    state_q == ST_FAIL,
    state_q == ST_PASS,
    state_q == ST_RUN
  };
  assign status_o = {
    16'h4d32,
    10'd0,
    state_q == ST_FAIL,
    state_q == ST_PASS,
    state_q == ST_RUN,
    state_q == ST_BOOT,
    state_q
  };
  assign cycle_count_o = cycle_q;
  assign output_checksum_o = checksum_q;
  assign output_sample0_o = sample0_q;
  assign output_sample1_o = sample1_q;
  assign fail_detail_o = fail_detail_q;

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= ST_BOOT;
      boot_q <= 8'd0;
      index_q <= '0;
      checksum_q <= 32'd0;
      sample0_q <= 32'd0;
      sample1_q <= 32'd0;
      cycle_q <= 32'd0;
      fail_detail_q <= 32'd0;
    end else begin
      cycle_q <= cycle_q + 32'd1;
      unique case (state_q)
        ST_BOOT: begin
          boot_q <= boot_q + 8'd1;
          if (boot_q == 8'd15) begin
            state_q <= ST_RUN;
            index_q <= '0;
            checksum_q <= 32'd0;
            sample0_q <= 32'd0;
            sample1_q <= 32'd0;
          end
        end
        ST_RUN: begin
          checksum_q <= next_checksum;
          if (index_q < INDEX_WIDTH'(4)) begin
            sample0_q <= sample0_q | ({24'd0, value_u8} << (8 * index_q[1:0]));
          end else if (index_q < INDEX_WIDTH'(8)) begin
            sample1_q <= sample1_q | ({24'd0, value_u8} << (8 * index_q[1:0]));
          end

          if (cycle_q > TIMEOUT_CYCLES) begin
            state_q <= ST_FAIL;
            fail_detail_q <= 32'h00000001;
          end else if (index_q == INDEX_WIDTH'(LAST_OUTPUT_INDEX)) begin
            if (
              next_checksum == M2_FULL_BLOCK_EXPECTED_CHECKSUM &&
              sample0_q == M2_FULL_BLOCK_EXPECTED_SAMPLE0 &&
              sample1_q == M2_FULL_BLOCK_EXPECTED_SAMPLE1
            ) begin
              checksum_q <= next_checksum;
              state_q <= ST_PASS;
            end else begin
              checksum_q <= next_checksum;
              state_q <= ST_FAIL;
              fail_detail_q <= {
                8'h02,
                next_checksum[7:0],
                M2_FULL_BLOCK_EXPECTED_SAMPLE0[7:0],
                sample0_q[7:0]
              };
            end
          end else begin
            index_q <= index_q + INDEX_WIDTH'(1);
          end
        end
        ST_PASS: begin
          state_q <= ST_PASS;
        end
        default: begin
          state_q <= ST_FAIL;
        end
      endcase
    end
  end
endmodule
