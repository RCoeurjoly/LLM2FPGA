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
  parameter int OUTPUT_REQUANT_MULT = 8032,
  parameter int DEBUG_SAMPLE_COUNT = 8,
  parameter int DEBUG_SAMPLE_WIDTH = 144,
  parameter int DEBUG_GEMV_SAMPLE_COUNT = 8,
  parameter int DEBUG_GEMV_SAMPLE_WIDTH = 128,
  parameter int DEBUG_GEMV_LANE_INDEX = 1
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
  output logic signed [7:0] output_read_data,

  output logic [DEBUG_SAMPLE_COUNT * DEBUG_SAMPLE_WIDTH - 1:0]
    debug_post_gelu_samples,
  output logic [3:0] debug_post_gelu_sample_count,

  output logic [DEBUG_GEMV_SAMPLE_COUNT * DEBUG_GEMV_SAMPLE_WIDTH - 1:0]
    debug_gemv_samples,
  output logic [3:0] debug_gemv_sample_count,
  output logic signed [ACC_WIDTH - 1:0] debug_gemv_final_acc
);
  localparam logic [OUT_ADDR_WIDTH - 1:0] LAST_OUT_INDEX =
    OUT_ADDR_WIDTH'(OUT_DIM - 1);
  localparam logic [OUT_ADDR_WIDTH - 1:0] DEBUG_INDEX_Q1 =
    OUT_ADDR_WIDTH'((OUT_DIM / 4) - 1);
  localparam logic [OUT_ADDR_WIDTH - 1:0] DEBUG_INDEX_Q2 =
    OUT_ADDR_WIDTH'((OUT_DIM / 2) - 1);
  localparam logic [OUT_ADDR_WIDTH - 1:0] DEBUG_INDEX_Q3 =
    OUT_ADDR_WIDTH'(((OUT_DIM * 3) / 4) - 1);
  localparam logic [3:0] DEBUG_SAMPLE_LIMIT = 4'(DEBUG_SAMPLE_COUNT);

  typedef enum logic [3:0] {
    POST_IDLE,
    POST_WAIT,
    POST_CAPTURE,
    POST_SCALE_MUL_INIT,
    POST_SCALE_MUL_STEP,
    POST_BIAS,
    POST_SQUARE_MUL_INIT,
    POST_SQUARE_MUL_STEP,
    POST_QUAD_MUL_INIT,
    POST_QUAD_MUL_STEP,
    POST_GELU_Y,
    POST_OUTPUT_MUL_INIT,
    POST_OUTPUT_MUL_STEP,
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
  logic signed [31:0] requant_acc_q;
  logic signed [31:0] requant_scale_mul_q;
  logic signed [31:0] requant_bias_q;
  logic signed [63:0] scaled_q_q;
  logic signed [63:0] x_q_q;
  logic [127:0] x_sq_q;
  logic signed [63:0] quad_q_q;
  logic signed [63:0] y_q_q;
  logic signed [63:0] output_q_q;
  logic [63:0] mul_rhs_shift_q;
  logic [127:0] mul_addend_q;
  logic [127:0] mul_product_mag_q;
  logic [127:0] mul_product_next_w;
  logic [6:0] mul_bit_q;
  logic [6:0] mul_last_bit_q;
  logic mul_negative_q;
  logic signed [127:0] mul_signed_next_w;
  logic signed [7:0] post_output_w;
  logic debug_take_post_gelu_sample_w;
  logic [DEBUG_SAMPLE_WIDTH - 1:0] debug_post_gelu_sample_w;

  (* ram_style = "block" *)
  logic signed [31:0] scale_mul_mem [0:OUT_DIM - 1];
  (* ram_style = "block" *)
  logic signed [31:0] bias_q_mem [0:OUT_DIM - 1];
  (* ram_style = "distributed" *)
  logic signed [7:0] output_mem [0:OUT_DIM - 1];

  assign core_start = start && (post_state_q == POST_IDLE) && !core_busy;
  assign busy = core_busy || (post_state_q != POST_IDLE);
  assign mul_product_next_w =
    mul_rhs_shift_q[0]
      ? (mul_product_mag_q + mul_addend_q)
      : mul_product_mag_q;
  assign mul_signed_next_w =
    mul_negative_q ? -$signed(mul_product_next_w) : $signed(mul_product_next_w);
  assign post_output_w = saturate_i8(output_q_q);
  assign debug_take_post_gelu_sample_w =
    (post_state_q == POST_WRITE) &&
    (debug_post_gelu_sample_count < DEBUG_SAMPLE_LIMIT) &&
    ((post_addr_q == OUT_ADDR_WIDTH'(0)) ||
     (post_addr_q == OUT_ADDR_WIDTH'(1)) ||
     (post_addr_q == OUT_ADDR_WIDTH'(2)) ||
     (post_addr_q == OUT_ADDR_WIDTH'(3)) ||
     (post_addr_q == DEBUG_INDEX_Q1) ||
     (post_addr_q == DEBUG_INDEX_Q2) ||
     (post_addr_q == DEBUG_INDEX_Q3) ||
     (post_addr_q == LAST_OUT_INDEX));

  function automatic [31:0] abs32(input signed [31:0] value);
    begin
      abs32 = value[31] ? (~value + 32'd1) : value;
    end
  endfunction

  function automatic [63:0] abs64(input signed [63:0] value);
    begin
      abs64 = value[63] ? (~value + 64'd1) : value;
    end
  endfunction

  function automatic signed [63:0] round_shift_signed128(
    input signed [127:0] value,
    input int shift
  );
    logic signed [127:0] abs_value;
    logic signed [127:0] shifted_value;
    begin
      if (shift == 0) begin
        shifted_value = value;
      end else if (value >= 0) begin
        shifted_value = (value + (128'sd1 <<< (shift - 1))) >>> shift;
      end else begin
        abs_value = -value;
        shifted_value = -((abs_value + (128'sd1 <<< (shift - 1))) >>> shift);
      end
      round_shift_signed128 = shifted_value[63:0];
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

  always_comb begin
    debug_post_gelu_sample_w = '0;
    debug_post_gelu_sample_w[0 +: 8] = {{(8 - OUT_ADDR_WIDTH){1'b0}}, post_addr_q};
    debug_post_gelu_sample_w[8 +: 32] = requant_acc_q;
    debug_post_gelu_sample_w[40 +: 32] = requant_scale_mul_q;
    debug_post_gelu_sample_w[72 +: 32] = requant_bias_q;
    debug_post_gelu_sample_w[104 +: 32] = scaled_q_q[31:0];
    debug_post_gelu_sample_w[136 +: 8] = post_output_w;
  end

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
      requant_acc_q <= '0;
      requant_scale_mul_q <= '0;
      requant_bias_q <= '0;
      scaled_q_q <= '0;
      x_q_q <= '0;
      x_sq_q <= '0;
      quad_q_q <= '0;
      y_q_q <= '0;
      output_q_q <= '0;
      mul_rhs_shift_q <= '0;
      mul_addend_q <= '0;
      mul_product_mag_q <= '0;
      mul_bit_q <= '0;
      mul_last_bit_q <= '0;
      mul_negative_q <= 1'b0;
      done <= 1'b0;
      debug_post_gelu_samples <= '0;
      debug_post_gelu_sample_count <= '0;
    end else begin
      done <= 1'b0;

      case (post_state_q)
        POST_IDLE: begin
          if (core_done) begin
            post_addr_q <= '0;
            sidecar_read_addr_q <= '0;
            core_output_read_addr_q <= '0;
            debug_post_gelu_samples <= '0;
            debug_post_gelu_sample_count <= '0;
            post_state_q <= POST_WAIT;
          end
        end

        POST_WAIT: begin
          post_state_q <= POST_CAPTURE;
        end

        POST_CAPTURE: begin
          requant_acc_q <= core_output_read_data;
          requant_scale_mul_q <= scale_mul_read_data_q;
          requant_bias_q <= bias_q_read_data_q;
          post_state_q <= POST_SCALE_MUL_INIT;
        end

        POST_SCALE_MUL_INIT: begin
          mul_rhs_shift_q <= {32'd0, abs32(requant_scale_mul_q)};
          mul_addend_q <= {96'd0, abs32(requant_acc_q)};
          mul_product_mag_q <= '0;
          mul_bit_q <= '0;
          mul_last_bit_q <= 7'd31;
          mul_negative_q <= requant_acc_q[31] ^ requant_scale_mul_q[31];
          post_state_q <= POST_SCALE_MUL_STEP;
        end

        POST_SCALE_MUL_STEP: begin
          mul_product_mag_q <= mul_product_next_w;
          mul_rhs_shift_q <= {1'b0, mul_rhs_shift_q[63:1]};
          mul_addend_q <= {mul_addend_q[126:0], 1'b0};

          if (mul_bit_q == mul_last_bit_q) begin
            scaled_q_q <= round_shift_signed128(mul_signed_next_w, SCALE_SHIFT);
            post_state_q <= POST_BIAS;
          end else begin
            mul_bit_q <= mul_bit_q + 1'b1;
          end
        end

        POST_BIAS: begin
          x_q_q <=
            scaled_q_q + $signed({{32{requant_bias_q[31]}}, requant_bias_q});
          post_state_q <= POST_SQUARE_MUL_INIT;
        end

        POST_SQUARE_MUL_INIT: begin
          mul_rhs_shift_q <= abs64(x_q_q);
          mul_addend_q <= {64'd0, abs64(x_q_q)};
          mul_product_mag_q <= '0;
          mul_bit_q <= '0;
          mul_last_bit_q <= 7'd63;
          mul_negative_q <= 1'b0;
          post_state_q <= POST_SQUARE_MUL_STEP;
        end

        POST_SQUARE_MUL_STEP: begin
          mul_product_mag_q <= mul_product_next_w;
          mul_rhs_shift_q <= {1'b0, mul_rhs_shift_q[63:1]};
          mul_addend_q <= {mul_addend_q[126:0], 1'b0};

          if (mul_bit_q == mul_last_bit_q) begin
            x_sq_q <= mul_product_next_w;
            post_state_q <= POST_QUAD_MUL_INIT;
          end else begin
            mul_bit_q <= mul_bit_q + 1'b1;
          end
        end

        POST_QUAD_MUL_INIT: begin
          mul_rhs_shift_q <= 64'(GELU_QUAD_Q);
          mul_addend_q <= x_sq_q;
          mul_product_mag_q <= '0;
          mul_bit_q <= '0;
          mul_last_bit_q <= 7'd31;
          mul_negative_q <= 1'b0;
          post_state_q <= POST_QUAD_MUL_STEP;
        end

        POST_QUAD_MUL_STEP: begin
          mul_product_mag_q <= mul_product_next_w;
          mul_rhs_shift_q <= {1'b0, mul_rhs_shift_q[63:1]};
          mul_addend_q <= {mul_addend_q[126:0], 1'b0};

          if (mul_bit_q == mul_last_bit_q) begin
            quad_q_q <= round_shift_signed128(mul_signed_next_w, 2 * X_FRAC);
            post_state_q <= POST_GELU_Y;
          end else begin
            mul_bit_q <= mul_bit_q + 1'b1;
          end
        end

        POST_GELU_Y: begin
          y_q_q <= (x_q_q >>> 1) + quad_q_q;
          post_state_q <= POST_OUTPUT_MUL_INIT;
        end

        POST_OUTPUT_MUL_INIT: begin
          mul_rhs_shift_q <= 64'(OUTPUT_REQUANT_MULT);
          mul_addend_q <= {64'd0, abs64(y_q_q)};
          mul_product_mag_q <= '0;
          mul_bit_q <= '0;
          mul_last_bit_q <= 7'd31;
          mul_negative_q <= y_q_q[63];
          post_state_q <= POST_OUTPUT_MUL_STEP;
        end

        POST_OUTPUT_MUL_STEP: begin
          mul_product_mag_q <= mul_product_next_w;
          mul_rhs_shift_q <= {1'b0, mul_rhs_shift_q[63:1]};
          mul_addend_q <= {mul_addend_q[126:0], 1'b0};

          if (mul_bit_q == mul_last_bit_q) begin
            output_q_q <=
              round_shift_signed128(mul_signed_next_w, OUTPUT_REQUANT_SHIFT);
            post_state_q <= POST_WRITE;
          end else begin
            mul_bit_q <= mul_bit_q + 1'b1;
          end
        end

        POST_WRITE: begin
          output_mem[post_addr_q] <= post_output_w;

          if (debug_take_post_gelu_sample_w) begin
            unique case (debug_post_gelu_sample_count)
              4'd0: debug_post_gelu_samples[0 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              4'd1: debug_post_gelu_samples[144 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              4'd2: debug_post_gelu_samples[288 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              4'd3: debug_post_gelu_samples[432 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              4'd4: debug_post_gelu_samples[576 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              4'd5: debug_post_gelu_samples[720 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              4'd6: debug_post_gelu_samples[864 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              4'd7: debug_post_gelu_samples[1008 +: DEBUG_SAMPLE_WIDTH] <=
                debug_post_gelu_sample_w;
              default: begin
              end
            endcase
            debug_post_gelu_sample_count <= debug_post_gelu_sample_count + 1'b1;
          end

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
    .PACKED_WEIGHT_WORDS(PACKED_WEIGHT_WORDS),
    .DEBUG_SAMPLE_COUNT(DEBUG_GEMV_SAMPLE_COUNT),
    .DEBUG_SAMPLE_WIDTH(DEBUG_GEMV_SAMPLE_WIDTH),
    .DEBUG_LANE_INDEX(DEBUG_GEMV_LANE_INDEX)
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
    .output_read_data(core_output_read_data),
    .debug_lane_samples(debug_gemv_samples),
    .debug_lane_sample_count(debug_gemv_sample_count),
    .debug_lane_final_acc(debug_gemv_final_acc)
  );
endmodule
