`timescale 1ns/1ps

module task6_int8_gemv64_lanes4_packed_sync_mem_kernel #(
  parameter int IN_DIM = 64,
  parameter int OUT_DIM = 64,
  parameter int LANES = 4,
  parameter int ACC_WIDTH = 32,
  parameter int PACKED_WEIGHT_WORDS = (OUT_DIM / LANES) * IN_DIM,
  parameter int PACKED_WEIGHT_ADDR_WIDTH =
    (PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(PACKED_WEIGHT_WORDS),
  parameter int LOAD_ADDR_WIDTH = PACKED_WEIGHT_ADDR_WIDTH
)(
  input  logic clock,
  input  logic reset,

  input  logic load_valid,
  input  logic [LOAD_ADDR_WIDTH - 1:0] load_addr,
  input  logic [LANES * 8 - 1:0] load_data,

  input  logic start,
  output logic busy,
  output logic done,

  output logic [5:0] activation_addr,
  input  logic signed [7:0] activation_data,

  output logic [5:0] out_addr,
  output logic signed [ACC_WIDTH - 1:0] out_data,
  output logic out_valid,
  input  logic out_ready
);
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] packed_weight_addr;
  logic [LANES * 8 - 1:0] packed_weight_data_q;

  (* ram_style = "block" *)
  logic [LANES * 8 - 1:0] packed_weight_mem [0:PACKED_WEIGHT_WORDS - 1];

  always_ff @(posedge clock) begin
    if (load_valid)
      packed_weight_mem[load_addr] <= load_data;
    packed_weight_data_q <= packed_weight_mem[packed_weight_addr];
  end

  task6_int8_gemv64_lanes4_packed_sync_kernel #(
    .IN_DIM(IN_DIM),
    .OUT_DIM(OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .PACKED_WEIGHT_WORDS(PACKED_WEIGHT_WORDS)
  ) core (
    .clock(clock),
    .reset(reset),
    .start(start),
    .busy(busy),
    .done(done),
    .activation_addr(activation_addr),
    .activation_data(activation_data),
    .packed_weight_addr(packed_weight_addr),
    .packed_weight_data(packed_weight_data_q),
    .out_addr(out_addr),
    .out_data(out_data),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .debug_lane0_samples(),
    .debug_lane0_sample_count(),
    .debug_lane0_final_acc()
  );
endmodule
