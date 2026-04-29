`timescale 1ns/1ps

module task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel #(
  parameter int IN_DIM = 64,
  parameter int TILE_OUT_DIM = 64,
  parameter int OUT_DIM = 256,
  parameter int LANES = 4,
  parameter int ACC_WIDTH = 32,
  parameter int PHASES = OUT_DIM / TILE_OUT_DIM,
  parameter int PACKED_WEIGHT_WORDS = PHASES * (TILE_OUT_DIM / LANES) * IN_DIM,
  parameter int PACKED_WEIGHT_ADDR_WIDTH =
    (PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(PACKED_WEIGHT_WORDS),
  parameter int ACTIVATION_ADDR_WIDTH = (IN_DIM <= 1) ? 1 : $clog2(IN_DIM),
  parameter int OUT_ADDR_WIDTH = (OUT_DIM <= 1) ? 1 : $clog2(OUT_DIM),
  parameter int DEBUG_SAMPLE_COUNT = 8,
  parameter int DEBUG_SAMPLE_WIDTH = 128,
  parameter int DEBUG_LANE_INDEX = 0
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

  input  logic [OUT_ADDR_WIDTH - 1:0] output_read_addr,
  output logic signed [ACC_WIDTH - 1:0] output_read_data,

  output logic [DEBUG_SAMPLE_COUNT * DEBUG_SAMPLE_WIDTH - 1:0] debug_lane_samples,
  output logic [3:0] debug_lane_sample_count,
  output logic signed [ACC_WIDTH - 1:0] debug_lane_final_acc
);
  logic [ACTIVATION_ADDR_WIDTH - 1:0] core_activation_addr;
  logic signed [7:0] core_activation_data;
  logic [OUT_ADDR_WIDTH - 1:0] core_out_addr;
  logic signed [ACC_WIDTH - 1:0] core_out_data;
  logic core_out_valid;

  logic signed [7:0] activation_mem [0:IN_DIM - 1];

  (* ram_style = "block" *)
  logic signed [ACC_WIDTH - 1:0] output_mem [0:OUT_DIM - 1];

  assign core_activation_data = activation_mem[core_activation_addr];

  always_ff @(posedge clock) begin
    if (activation_load_valid)
      activation_mem[activation_load_addr] <= activation_load_data;
    if (core_out_valid)
      output_mem[core_out_addr] <= core_out_data;
    output_read_data <= output_mem[output_read_addr];
  end

  task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel #(
    .IN_DIM(IN_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .OUT_DIM(OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .PHASES(PHASES),
    .PACKED_WEIGHT_WORDS(PACKED_WEIGHT_WORDS),
    .DEBUG_SAMPLE_COUNT(DEBUG_SAMPLE_COUNT),
    .DEBUG_SAMPLE_WIDTH(DEBUG_SAMPLE_WIDTH),
    .DEBUG_LANE_INDEX(DEBUG_LANE_INDEX)
  ) core (
    .clock(clock),
    .reset(reset),
    .load_valid(weight_load_valid),
    .load_addr(weight_load_addr),
    .load_data(weight_load_data),
    .start(start),
    .busy(busy),
    .done(done),
    .activation_addr(core_activation_addr),
    .activation_data(core_activation_data),
    .out_addr(core_out_addr),
    .out_data(core_out_data),
    .out_valid(core_out_valid),
    .out_ready(1'b1),
    .debug_lane_samples(debug_lane_samples),
    .debug_lane_sample_count(debug_lane_sample_count),
    .debug_lane_final_acc(debug_lane_final_acc)
  );
endmodule
