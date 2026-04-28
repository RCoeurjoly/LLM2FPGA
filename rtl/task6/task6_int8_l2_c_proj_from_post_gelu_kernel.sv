`timescale 1ns/1ps

module task6_int8_l2_c_proj_from_post_gelu_kernel #(
  parameter int IN_DIM = 256,
  parameter int OUT_DIM = 64,
  parameter int LANES = 4,
  parameter int ACC_WIDTH = 32,
  parameter int PACKED_WEIGHT_WORDS = (OUT_DIM / LANES) * IN_DIM,
  parameter int PACKED_WEIGHT_ADDR_WIDTH =
    (PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(PACKED_WEIGHT_WORDS),
  parameter int ACTIVATION_ADDR_WIDTH = (IN_DIM <= 1) ? 1 : $clog2(IN_DIM),
  parameter int OUT_ADDR_WIDTH = (OUT_DIM <= 1) ? 1 : $clog2(OUT_DIM)
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
  output logic signed [ACC_WIDTH - 1:0] output_read_data
);
  logic [ACTIVATION_ADDR_WIDTH - 1:0] core_activation_addr;
  logic signed [7:0] core_activation_data;
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] core_packed_weight_addr;
  logic [LANES * 8 - 1:0] core_packed_weight_data_q;
  logic [OUT_ADDR_WIDTH - 1:0] core_out_addr;
  logic signed [ACC_WIDTH - 1:0] core_out_data;
  logic core_out_valid;

  (* ram_style = "distributed" *)
  logic signed [7:0] activation_mem [0:IN_DIM - 1];

  (* ram_style = "block" *)
  logic [LANES * 8 - 1:0] packed_weight_mem [0:PACKED_WEIGHT_WORDS - 1];

  (* ram_style = "block" *)
  logic signed [ACC_WIDTH - 1:0] output_mem [0:OUT_DIM - 1];

  assign core_activation_data = activation_mem[core_activation_addr];

  always_ff @(posedge clock) begin
    if (activation_load_valid)
      activation_mem[activation_load_addr] <= activation_load_data;
    if (weight_load_valid)
      packed_weight_mem[weight_load_addr] <= weight_load_data;
    core_packed_weight_data_q <= packed_weight_mem[core_packed_weight_addr];
    if (core_out_valid)
      output_mem[core_out_addr] <= core_out_data;
    output_read_data <= output_mem[output_read_addr];
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
    .activation_addr(core_activation_addr),
    .activation_data(core_activation_data),
    .packed_weight_addr(core_packed_weight_addr),
    .packed_weight_data(core_packed_weight_data_q),
    .out_addr(core_out_addr),
    .out_data(core_out_data),
    .out_valid(core_out_valid),
    .out_ready(1'b1)
  );
endmodule
