`timescale 1ns/1ps

module task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel #(
  parameter int IN_DIM = 64,
  parameter int TILE_OUT_DIM = 64,
  parameter int OUT_DIM = 256,
  parameter int LANES = 4,
  parameter int ACC_WIDTH = 32,
  parameter int PHASES = OUT_DIM / TILE_OUT_DIM,
  parameter int TILE_PACKED_WEIGHT_WORDS = (TILE_OUT_DIM / LANES) * IN_DIM,
  parameter int PACKED_WEIGHT_WORDS = PHASES * TILE_PACKED_WEIGHT_WORDS,
  parameter int TILE_PACKED_WEIGHT_ADDR_WIDTH =
    (TILE_PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(TILE_PACKED_WEIGHT_WORDS),
  parameter int PACKED_WEIGHT_ADDR_WIDTH =
    (PACKED_WEIGHT_WORDS <= 1) ? 1 : $clog2(PACKED_WEIGHT_WORDS),
  parameter int PHASE_WIDTH = (PHASES <= 1) ? 1 : $clog2(PHASES),
  parameter int OUT_ADDR_WIDTH = (OUT_DIM <= 1) ? 1 : $clog2(OUT_DIM)
)(
  input  logic clock,
  input  logic reset,

  input  logic load_valid,
  input  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] load_addr,
  input  logic [LANES * 8 - 1:0] load_data,

  input  logic start,
  output logic busy,
  output logic done,

  output logic [5:0] activation_addr,
  input  logic signed [7:0] activation_data,

  output logic [OUT_ADDR_WIDTH - 1:0] out_addr,
  output logic signed [ACC_WIDTH - 1:0] out_data,
  output logic out_valid,
  input  logic out_ready
);
  localparam logic [PHASE_WIDTH - 1:0] LAST_PHASE = PHASE_WIDTH'(PHASES - 1);

  logic active_q;
  logic core_start_q;
  logic [PHASE_WIDTH - 1:0] phase_q;
  logic core_busy;
  logic core_done;
  logic [5:0] core_out_addr;
  logic signed [ACC_WIDTH - 1:0] core_out_data;
  logic core_out_valid;
  logic [TILE_PACKED_WEIGHT_ADDR_WIDTH - 1:0] core_packed_weight_addr;
  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] packed_weight_read_addr;
  logic [LANES * 8 - 1:0] packed_weight_data_q;

  (* ram_style = "block" *)
  logic [LANES * 8 - 1:0] packed_weight_mem [0:PACKED_WEIGHT_WORDS - 1];

  assign busy = active_q || core_busy || core_start_q;
  assign out_addr = {phase_q, core_out_addr};
  assign out_data = core_out_data;
  assign out_valid = core_out_valid;
  assign packed_weight_read_addr = {phase_q, core_packed_weight_addr};

  always_ff @(posedge clock) begin
    if (load_valid)
      packed_weight_mem[load_addr] <= load_data;
    packed_weight_data_q <= packed_weight_mem[packed_weight_read_addr];
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      active_q <= 1'b0;
      core_start_q <= 1'b0;
      phase_q <= '0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      core_start_q <= 1'b0;

      if (!active_q) begin
        phase_q <= '0;
        if (start) begin
          active_q <= 1'b1;
          core_start_q <= 1'b1;
        end
      end else if (core_done) begin
        if (phase_q == LAST_PHASE) begin
          active_q <= 1'b0;
          phase_q <= '0;
          done <= 1'b1;
        end else begin
          phase_q <= phase_q + 1'b1;
          core_start_q <= 1'b1;
        end
      end
    end
  end

  task6_int8_gemv64_lanes4_packed_sync_kernel #(
    .IN_DIM(IN_DIM),
    .OUT_DIM(TILE_OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .PACKED_WEIGHT_WORDS(TILE_PACKED_WEIGHT_WORDS)
  ) core (
    .clock(clock),
    .reset(reset),
    .start(core_start_q),
    .busy(core_busy),
    .done(core_done),
    .activation_addr(activation_addr),
    .activation_data(activation_data),
    .packed_weight_addr(core_packed_weight_addr),
    .packed_weight_data(packed_weight_data_q),
    .out_addr(core_out_addr),
    .out_data(core_out_data),
    .out_valid(core_out_valid),
    .out_ready(out_ready)
  );
endmodule
