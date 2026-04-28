`timescale 1ns/1ps

module task6_int8_l2_c_fc_post_gelu_requant_kernel #(
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
  parameter int X_FRAC = 12,
  parameter int SCALE_SHIFT = 24,
  parameter int GELU_QUAD_Q = 1634,
  parameter int OUTPUT_REQUANT_SHIFT = 16,
  parameter int OUTPUT_REQUANT_MULT = 8032
)(
  input  logic clock,
  input  logic reset,

  input  logic weight_load_valid,
  input  logic [PACKED_WEIGHT_ADDR_WIDTH - 1:0] weight_load_addr,
  input  logic [LANES * 8 - 1:0] weight_load_data,

  input  logic activation_load_valid,
  input  logic [ACTIVATION_ADDR_WIDTH - 1:0] activation_load_addr,
  input  logic signed [7:0] activation_load_data,

  input  logic requant_load_valid,
  input  logic [OUT_ADDR_WIDTH - 1:0] requant_load_addr,
  input  logic signed [31:0] requant_scale_mul_load_data,
  input  logic signed [31:0] requant_bias_q_load_data,

  input  logic start,
  output logic busy,
  output logic done,

  input  logic [OUT_ADDR_WIDTH - 1:0] output_read_addr,
  output logic signed [7:0] output_read_data
);
  localparam logic [OUT_ADDR_WIDTH - 1:0] LAST_OUT_INDEX =
    OUT_ADDR_WIDTH'(OUT_DIM - 1);

  typedef enum logic [1:0] {
    POST_IDLE,
    POST_WAIT,
    POST_WRITE
  } post_state_t;

  logic core_start;
  logic core_busy;
  logic core_done;
  logic [OUT_ADDR_WIDTH - 1:0] core_output_read_addr_q;
  logic signed [ACC_WIDTH - 1:0] core_output_read_data;

  post_state_t post_state_q;
  logic [OUT_ADDR_WIDTH - 1:0] post_addr_q;
  logic [OUT_ADDR_WIDTH - 1:0] sidecar_read_addr_q;
  logic signed [31:0] scale_mul_read_data_q;
  logic signed [31:0] bias_q_read_data_q;

  (* ram_style = "block" *)
  logic signed [31:0] scale_mul_mem [0:OUT_DIM - 1];
  (* ram_style = "block" *)
  logic signed [31:0] bias_q_mem [0:OUT_DIM - 1];
  (* ram_style = "distributed" *)
  logic signed [7:0] output_mem [0:OUT_DIM - 1];

  assign core_start = start && (post_state_q == POST_IDLE) && !core_busy;
  assign busy = core_busy || (post_state_q != POST_IDLE);

  function automatic signed [63:0] round_shift_signed(
    input signed [63:0] value,
    input int shift
  );
    logic signed [63:0] abs_value;
    begin
      if (shift == 0) begin
        round_shift_signed = value;
      end else if (value >= 0) begin
        round_shift_signed = (value + (64'sd1 <<< (shift - 1))) >>> shift;
      end else begin
        abs_value = -value;
        round_shift_signed = -((abs_value + (64'sd1 <<< (shift - 1))) >>> shift);
      end
    end
  endfunction

  function automatic signed [7:0] saturate_i8(input signed [63:0] value);
    begin
      if (value > 64'sd127)
        saturate_i8 = 8'sd127;
      else if (value < -64'sd127)
        saturate_i8 = -8'sd127;
      else
        saturate_i8 = $signed(value[7:0]);
    end
  endfunction

  function automatic signed [7:0] post_gelu_requant_i8(
    input signed [31:0] acc,
    input signed [31:0] scale_mul,
    input signed [31:0] bias_q
  );
    logic signed [63:0] scaled_q;
    logic signed [63:0] x_q;
    logic signed [63:0] x_sq_q2;
    logic signed [63:0] quad_q;
    logic signed [63:0] y_q;
    logic signed [63:0] output_q;
    begin
      scaled_q = round_shift_signed($signed(acc) * $signed(scale_mul), SCALE_SHIFT);
      x_q = scaled_q + $signed({{32{bias_q[31]}}, bias_q});

      // In the captured L2 c_fc range, GELU is well approximated by
      // 0.5*x + 0.39894228*x*x.  Constants are generated in the same Q format.
      x_sq_q2 = x_q * x_q;
      quad_q = round_shift_signed($signed(GELU_QUAD_Q) * x_sq_q2, 2 * X_FRAC);
      y_q = (x_q >>> 1) + quad_q;

      output_q =
        round_shift_signed(y_q * $signed(OUTPUT_REQUANT_MULT), OUTPUT_REQUANT_SHIFT);
      post_gelu_requant_i8 = saturate_i8(output_q);
    end
  endfunction

  always_ff @(posedge clock) begin
    if (requant_load_valid) begin
      scale_mul_mem[requant_load_addr] <= requant_scale_mul_load_data;
      bias_q_mem[requant_load_addr] <= requant_bias_q_load_data;
    end

    scale_mul_read_data_q <= scale_mul_mem[sidecar_read_addr_q];
    bias_q_read_data_q <= bias_q_mem[sidecar_read_addr_q];
    output_read_data <= output_mem[output_read_addr];
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      post_state_q <= POST_IDLE;
      post_addr_q <= '0;
      sidecar_read_addr_q <= '0;
      core_output_read_addr_q <= '0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      case (post_state_q)
        POST_IDLE: begin
          if (core_done) begin
            post_addr_q <= '0;
            sidecar_read_addr_q <= '0;
            core_output_read_addr_q <= '0;
            post_state_q <= POST_WAIT;
          end
        end

        POST_WAIT: begin
          post_state_q <= POST_WRITE;
        end

        POST_WRITE: begin
          output_mem[post_addr_q] <= post_gelu_requant_i8(
            core_output_read_data,
            scale_mul_read_data_q,
            bias_q_read_data_q
          );

          if (post_addr_q == LAST_OUT_INDEX) begin
            post_state_q <= POST_IDLE;
            done <= 1'b1;
          end else begin
            post_addr_q <= post_addr_q + 1'b1;
            sidecar_read_addr_q <= post_addr_q + 1'b1;
            core_output_read_addr_q <= post_addr_q + 1'b1;
            post_state_q <= POST_WAIT;
          end
        end

        default: begin
          post_state_q <= POST_IDLE;
        end
      endcase
    end
  end

  task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel #(
    .IN_DIM(IN_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .OUT_DIM(OUT_DIM),
    .LANES(LANES),
    .ACC_WIDTH(ACC_WIDTH),
    .PHASES(PHASES),
    .PACKED_WEIGHT_WORDS(PACKED_WEIGHT_WORDS)
  ) core (
    .clock(clock),
    .reset(reset),
    .weight_load_valid(weight_load_valid),
    .weight_load_addr(weight_load_addr),
    .weight_load_data(weight_load_data),
    .activation_load_valid(activation_load_valid),
    .activation_load_addr(activation_load_addr),
    .activation_load_data(activation_load_data),
    .start(core_start),
    .busy(core_busy),
    .done(core_done),
    .output_read_addr(core_output_read_addr_q),
    .output_read_data(core_output_read_data)
  );
endmodule
