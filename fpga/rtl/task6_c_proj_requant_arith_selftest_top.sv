`timescale 1ns/1ps

module task6_c_proj_requant_arith_selftest_top(
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);
  localparam logic signed [31:0] TEST_ACC = 32'sh00001cb2;
  localparam logic signed [31:0] TEST_SCALE_MUL = 32'sh00005824;
  localparam logic signed [31:0] TEST_BIAS_Q = 32'sh00000000;
  localparam int TEST_SHIFT = 24;
  localparam logic signed [7:0] TEST_EXPECTED_Q = 8'sh0a;
  localparam logic [5:0] LAST_MUL_BIT = 6'd31;
  localparam logic [7:0] BOOT_RESET_CYCLES = 8'd16;
  localparam logic [63:0] ROUND_BIAS_U =
    (TEST_SHIFT == 0) ? 64'd0 : (64'd1 << (TEST_SHIFT - 1));

  typedef enum logic [2:0] {
    SELFTEST_BOOT,
    SELFTEST_MUL_INIT,
    SELFTEST_MUL_STEP,
    SELFTEST_ROUND,
    SELFTEST_BIAS,
    SELFTEST_CHECK,
    SELFTEST_PASS,
    SELFTEST_FAIL
  } selftest_state_t;

  selftest_state_t state_q;
  logic [7:0] config_reset_count_q = 8'd0;
  logic config_reset_done;
  logic selftest_reset;
  logic [28:0] blink_count_q;

  logic [31:0] acc_magnitude_w;
  logic [31:0] scale_magnitude_w;
  logic [31:0] mul_rhs_shift_q;
  logic [63:0] mul_addend_q;
  logic [63:0] mul_product_mag_q;
  logic [63:0] mul_product_next_w;
  logic [5:0] mul_bit_q;
  logic mul_negative_q;
  logic signed [63:0] scaled_product_q;
  logic [63:0] scaled_product_abs_w;
  logic [63:0] scaled_product_rounded_abs_w;
  logic [63:0] scaled_abs_shifted_w;
  logic signed [63:0] scaled_q_w;
  logic signed [63:0] scaled_q_q;
  logic signed [63:0] output_q_q;
  logic signed [7:0] observed_q;
  logic [3:0] value_debug_phase;
  logic [2:0] observed_high_leds;
  logic [2:0] expected_high_leds;

  assign config_reset_done = config_reset_count_q[7];
  assign selftest_reset = !SYS_RSTN || !config_reset_done;

  assign acc_magnitude_w =
    TEST_ACC[31] ? (~TEST_ACC[31:0] + 32'd1) : TEST_ACC[31:0];
  assign scale_magnitude_w =
    TEST_SCALE_MUL[31] ? (~TEST_SCALE_MUL + 32'd1) : TEST_SCALE_MUL;
  assign mul_product_next_w =
    mul_rhs_shift_q[0] ? (mul_product_mag_q + mul_addend_q) : mul_product_mag_q;
  assign scaled_product_abs_w =
    scaled_product_q[63] ? (~scaled_product_q + 64'd1) : scaled_product_q;
  assign scaled_product_rounded_abs_w =
    (TEST_SHIFT == 0) ? scaled_product_abs_w : (scaled_product_abs_w + ROUND_BIAS_U);
  assign scaled_abs_shifted_w =
    (TEST_SHIFT == 0)
      ? scaled_product_rounded_abs_w
      : (scaled_product_rounded_abs_w >> TEST_SHIFT);
  assign scaled_q_w =
    scaled_product_q[63]
      ? -$signed(scaled_abs_shifted_w)
      : $signed(scaled_abs_shifted_w);
  assign observed_q =
    (output_q_q > 64'sd127)
      ? 8'sd127
      : ((output_q_q < -64'sd127) ? -8'sd127 : $signed(output_q_q[7:0]));
  assign value_debug_phase = blink_count_q[28:25];
  assign observed_high_leds = {1'b0, observed_q[7:6]};
  assign expected_high_leds = {1'b0, TEST_EXPECTED_Q[7:6]};

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN)
      config_reset_count_q <= 8'd0;
    else if (!config_reset_done)
      config_reset_count_q <= config_reset_count_q + 8'd1;
  end

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= SELFTEST_BOOT;
      blink_count_q <= '0;
      mul_rhs_shift_q <= '0;
      mul_addend_q <= '0;
      mul_product_mag_q <= '0;
      mul_bit_q <= '0;
      mul_negative_q <= 1'b0;
      scaled_product_q <= '0;
      scaled_q_q <= '0;
      output_q_q <= '0;
    end else if (selftest_reset) begin
      state_q <= SELFTEST_BOOT;
      blink_count_q <= '0;
      mul_rhs_shift_q <= '0;
      mul_addend_q <= '0;
      mul_product_mag_q <= '0;
      mul_bit_q <= '0;
      mul_negative_q <= 1'b0;
      scaled_product_q <= '0;
      scaled_q_q <= '0;
      output_q_q <= '0;
    end else begin
      blink_count_q <= blink_count_q + 1'b1;

      unique case (state_q)
        SELFTEST_BOOT: begin
          state_q <= SELFTEST_MUL_INIT;
        end

        SELFTEST_MUL_INIT: begin
          mul_rhs_shift_q <= scale_magnitude_w;
          mul_addend_q <= {32'd0, acc_magnitude_w};
          mul_product_mag_q <= 64'd0;
          mul_bit_q <= 6'd0;
          mul_negative_q <= TEST_ACC[31] ^ TEST_SCALE_MUL[31];
          state_q <= SELFTEST_MUL_STEP;
        end

        SELFTEST_MUL_STEP: begin
          mul_product_mag_q <= mul_product_next_w;
          mul_rhs_shift_q <= {1'b0, mul_rhs_shift_q[31:1]};
          mul_addend_q <= {mul_addend_q[62:0], 1'b0};

          if (mul_bit_q == LAST_MUL_BIT) begin
            scaled_product_q <=
              mul_negative_q ? -$signed(mul_product_next_w)
                             : $signed(mul_product_next_w);
            state_q <= SELFTEST_ROUND;
          end else begin
            mul_bit_q <= mul_bit_q + 1'b1;
          end
        end

        SELFTEST_ROUND: begin
          scaled_q_q <= scaled_q_w;
          state_q <= SELFTEST_BIAS;
        end

        SELFTEST_BIAS: begin
          output_q_q <= scaled_q_q + $signed({{32{TEST_BIAS_Q[31]}}, TEST_BIAS_Q});
          state_q <= SELFTEST_CHECK;
        end

        SELFTEST_CHECK: begin
          state_q <= (observed_q == TEST_EXPECTED_Q) ? SELFTEST_PASS : SELFTEST_FAIL;
        end

        SELFTEST_PASS,
        SELFTEST_FAIL: begin
          state_q <= state_q;
        end

        default: begin
          state_q <= SELFTEST_FAIL;
        end
      endcase
    end
  end

  always_comb begin
    led_3bits_tri_o[0] = blink_count_q[25];
    led_3bits_tri_o[1] = 1'b0;
    led_3bits_tri_o[2] = 1'b0;

    unique case (state_q)
      SELFTEST_PASS: begin
        led_3bits_tri_o = 3'b010;
      end

      SELFTEST_FAIL: begin
        unique case (value_debug_phase)
          4'd0: led_3bits_tri_o = 3'b111;
          4'd1: led_3bits_tri_o = observed_q[2:0];
          4'd2: led_3bits_tri_o = observed_q[5:3];
          4'd3: led_3bits_tri_o = observed_high_leds;
          4'd4: led_3bits_tri_o = 3'b101;
          4'd5: led_3bits_tri_o = TEST_EXPECTED_Q[2:0];
          4'd6: led_3bits_tri_o = TEST_EXPECTED_Q[5:3];
          4'd7: led_3bits_tri_o = expected_high_leds;
          4'd8,
          4'd9,
          4'd10: led_3bits_tri_o = 3'b000;
          default: led_3bits_tri_o = 3'b111;
        endcase
      end

      default: begin
        led_3bits_tri_o[0] = blink_count_q[25];
        led_3bits_tri_o[1] = 1'b0;
        led_3bits_tri_o[2] = 1'b1;
      end
    endcase
  end
endmodule
