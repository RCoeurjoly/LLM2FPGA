`timescale 1ns/1ps

module task6_int8_vocab_output_head_top1_kernel #(
  parameter int IN_DIM = 64,
  parameter int VOCAB_SIZE = 4096,
  parameter int VALID_VOCAB_SIZE = VOCAB_SIZE,
  parameter int TILE_OUT_DIM = 64,
  parameter int LANES = 4,
  parameter int ACC_WIDTH = 32,
  parameter int PACKED_WEIGHT_WORDS = (VOCAB_SIZE / LANES) * IN_DIM,
  parameter int PHASE_BANKED_WEIGHT_MEMORY = 0,
  parameter int PACKED_WEIGHT_ADDR_WIDTH =
    (PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(PACKED_WEIGHT_WORDS),
  parameter int ACTIVATION_ADDR_WIDTH = (IN_DIM <= 1) ? 1 : $clog2(IN_DIM),
  parameter int VOCAB_ADDR_WIDTH = (VOCAB_SIZE <= 1) ? 1 : $clog2(VOCAB_SIZE)
)(
  input  logic clock,
  input  logic reset,

  input  logic weight_load_valid,
  input  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] weight_load_addr,
  input  logic [LANES * 8 - 1:0] weight_load_data,

  input  logic activation_load_valid,
  input  logic [ACTIVATION_ADDR_WIDTH - 1:0] activation_load_addr,
  input  logic signed [7:0] activation_load_data,

  input  logic start,
  output logic busy,
  output logic done,

  output logic [VOCAB_ADDR_WIDTH - 1:0] top_index,
  output logic signed [ACC_WIDTH - 1:0] top_acc
);
  localparam logic signed [ACC_WIDTH - 1:0] MIN_ACC =
    {1'b1, {(ACC_WIDTH - 1){1'b0}}};

  logic [ACTIVATION_ADDR_WIDTH - 1:0] core_activation_addr;
  logic signed [7:0] core_activation_data;
  logic [VOCAB_ADDR_WIDTH - 1:0] core_out_addr;
  logic signed [ACC_WIDTH - 1:0] core_out_data;
  logic core_out_valid;
  logic core_busy;
  logic core_done;
  logic seen_output_q;
  logic core_out_valid_vocab;

  logic signed [7:0] activation_mem [0:IN_DIM - 1];

  assign core_activation_data = activation_mem[core_activation_addr];
  assign busy = core_busy;
  assign core_out_valid_vocab =
    core_out_addr < VOCAB_ADDR_WIDTH'(VALID_VOCAB_SIZE);

  always_ff @(posedge clock) begin
    if (activation_load_valid)
      activation_mem[activation_load_addr] <= activation_load_data;
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      done <= 1'b0;
      top_index <= '0;
      top_acc <= MIN_ACC;
      seen_output_q <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start) begin
        top_index <= '0;
        top_acc <= MIN_ACC;
        seen_output_q <= 1'b0;
      end
      if (core_out_valid && core_out_valid_vocab) begin
        if (!seen_output_q || (core_out_data > top_acc)) begin
          top_index <= core_out_addr;
          top_acc <= core_out_data;
        end
        seen_output_q <= 1'b1;
      end
      if (core_done)
        done <= 1'b1;
    end
  end

  task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel #(
    .IN_DIM(IN_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .OUT_DIM(VOCAB_SIZE),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .PACKED_WEIGHT_WORDS(PACKED_WEIGHT_WORDS),
    .PHASE_BANKED_WEIGHT_MEMORY(PHASE_BANKED_WEIGHT_MEMORY)
  ) core (
    .clock(clock),
    .reset(reset),
    .load_valid(weight_load_valid),
    .load_addr(weight_load_addr),
    .load_data(weight_load_data),
    .start(start),
    .busy(core_busy),
    .done(core_done),
    .activation_addr(core_activation_addr),
    .activation_data(core_activation_data),
    .out_addr(core_out_addr),
    .out_data(core_out_data),
    .out_valid(core_out_valid),
    .out_ready(1'b1),
    .debug_lane_samples(),
    .debug_lane_sample_count(),
    .debug_lane_final_acc()
  );
endmodule
