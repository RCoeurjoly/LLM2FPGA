`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_selftest_top #(
  parameter int DEBUG_LEDS = 0,
  parameter int ENABLE_JTAG_DEBUG = 0
)(
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);
  `include "tb_data.sv"

  localparam int C_PROJ_ACC_WIDTH = 32;
  localparam logic [31:0] TIMEOUT_CYCLES = 32'd50000000;
  localparam logic [7:0] BOOT_RESET_CYCLES = 8'd16;
  localparam logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] LAST_C_PROJ_OUT_INDEX =
    C_PROJ_OUT_ADDR_WIDTH'(C_PROJ_OUT_DIM - 1);
  localparam logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] DEBUG_INDEX_ONE =
    C_PROJ_OUT_ADDR_WIDTH'(1);
  localparam logic [1:0] FAIL_REASON_TIMEOUT = 2'd1;
  localparam logic [1:0] FAIL_REASON_MISMATCH = 2'd2;
  localparam logic [1:0] FAIL_REASON_DEFAULT = 2'd3;
  localparam logic [2:0] C_PROJ_STAGE_OK_OR_DOWNSTREAM = 3'd0;
  localparam logic [2:0] C_PROJ_STAGE_ACC = 3'd1;
  localparam logic [2:0] C_PROJ_STAGE_SCALE = 3'd2;
  localparam logic [2:0] C_PROJ_STAGE_BIAS = 3'd3;
  localparam logic [2:0] C_PROJ_STAGE_PRODUCT = 3'd4;
  localparam logic [2:0] C_PROJ_STAGE_SHIFT = 3'd5;
  localparam logic [2:0] C_PROJ_STAGE_BIASED = 3'd6;
  localparam logic [2:0] C_PROJ_STAGE_OUTPUT = 3'd7;
  localparam logic signed [63:0] EXPECTED_C_PROJ_PRODUCT_Q0 =
    64'sh0000000009e13908;
  localparam logic signed [63:0] EXPECTED_C_PROJ_SCALED_Q0 = 64'sd10;
  localparam logic signed [63:0] EXPECTED_C_PROJ_BIASED_Q0 = 64'sd10;
  localparam int C_PROJ_GEMV_DEBUG_SAMPLE_COUNT = 8;
  localparam int C_PROJ_GEMV_DEBUG_SAMPLE_WIDTH = 128;
  localparam int C_PROJ_GEMV_DEBUG_SAMPLE_BITS =
    C_PROJ_GEMV_DEBUG_SAMPLE_COUNT * C_PROJ_GEMV_DEBUG_SAMPLE_WIDTH;
  localparam int C_PROJ_GEMV_DEBUG_LANE_INDEX = 1;
  localparam int C_FC_POST_GELU_DEBUG_SAMPLE_COUNT = 8;
  localparam int C_FC_POST_GELU_DEBUG_SAMPLE_WIDTH = 144;
  localparam int C_FC_POST_GELU_DEBUG_SAMPLE_BITS =
    C_FC_POST_GELU_DEBUG_SAMPLE_COUNT * C_FC_POST_GELU_DEBUG_SAMPLE_WIDTH;
  localparam int C_FC_GEMV_DEBUG_SAMPLE_COUNT = 8;
  localparam int C_FC_GEMV_DEBUG_SAMPLE_WIDTH = 128;
  localparam int C_FC_GEMV_DEBUG_SAMPLE_BITS =
    C_FC_GEMV_DEBUG_SAMPLE_COUNT * C_FC_GEMV_DEBUG_SAMPLE_WIDTH;
  localparam int C_FC_GEMV_DEBUG_LANE_INDEX = 1;
  localparam int JTAG_DEBUG_WIDTH = 2048;
  localparam logic [31:0] JTAG_DEBUG_MAGIC = 32'h54364a44;
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd9;
  localparam logic [63:0] EXPECTED_C_PROJ_ACTIVATION_SAMPLES = {
    8'h10, 8'hd6, 8'h0a, 8'he7, 8'h18, 8'hd8, 8'hf0, 8'hde
  };

  typedef enum logic [3:0] {
    SELFTEST_BOOT,
    SELFTEST_LOAD_C_FC_ACTIVATION,
    SELFTEST_LOAD_C_FC_WEIGHT,
    SELFTEST_LOAD_C_FC_REQUANT,
    SELFTEST_LOAD_C_PROJ_WEIGHT,
    SELFTEST_LOAD_C_PROJ_REQUANT,
    SELFTEST_LOAD_RESIDUAL,
    SELFTEST_START,
    SELFTEST_RUN,
    SELFTEST_READ_SETUP,
    SELFTEST_READ_CHECK,
    SELFTEST_PASS,
    SELFTEST_FAIL
  } selftest_state_t;

  selftest_state_t state_q;
  logic [7:0] boot_count_q;
  logic [12:0] load_index_q;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] check_index_q;
  logic [31:0] cycle_count_q;
  logic [28:0] blink_count_q;
  logic [7:0] config_reset_count_q = 8'd0;
  logic config_reset_done;
  logic selftest_reset;
  logic [1:0] fail_reason_q;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] fail_index_q;
  logic signed [7:0] fail_expected_q;
  logic signed [7:0] fail_observed_q;
  logic signed [7:0] fail_expected_c_proj_q;
  logic [3:0] value_debug_phase;
  logic [2:0] fail_expected_high_leds;
  logic [2:0] fail_observed_high_leds;
  logic [2:0] fail_expected_c_proj_high_leds;
  logic [2:0] first_add_c_proj_high_leds;
  logic [2:0] first_c_proj_requant_output_high_leds;
  logic [2:0] first_c_proj_requant_acc_match_leds;
  logic [2:0] first_c_proj_requant_scale_match_leds;
  logic [2:0] first_c_proj_requant_bias_match_leds;

  logic dut_reset;
  logic start;
  logic busy;
  logic done;

  logic c_fc_weight_load_valid;
  logic [C_FC_PACKED_WEIGHT_ADDR_WIDTH - 1:0] c_fc_weight_load_addr;
  logic [LANES * 8 - 1:0] c_fc_weight_load_data;
  logic c_fc_activation_load_valid;
  logic [C_FC_ACTIVATION_ADDR_WIDTH - 1:0] c_fc_activation_load_addr;
  logic signed [7:0] c_fc_activation_load_data;
  logic c_fc_requant_load_valid;
  logic [HIDDEN_ADDR_WIDTH - 1:0] c_fc_requant_load_addr;
  logic signed [31:0] c_fc_requant_scale_mul_load_data;
  logic signed [31:0] c_fc_requant_bias_q_load_data;
  logic c_proj_weight_load_valid;
  logic [C_PROJ_PACKED_WEIGHT_ADDR_WIDTH - 1:0] c_proj_weight_load_addr;
  logic [LANES * 8 - 1:0] c_proj_weight_load_data;
  logic c_proj_requant_load_valid;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] c_proj_requant_load_addr;
  logic signed [31:0] c_proj_requant_scale_mul_load_data;
  logic signed [31:0] c_proj_requant_bias_q_load_data;
  logic residual_load_valid;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] residual_load_addr;
  logic signed [7:0] residual_load_data;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] output_read_addr;
  logic signed [7:0] output_read_data;
  logic debug_add_valid;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] debug_add_addr;
  logic signed [7:0] debug_add_residual_q;
  logic signed [7:0] debug_add_c_proj_q;
  logic signed [7:0] debug_add_output_q;
  logic first_add_seen_q;
  logic signed [7:0] first_add_residual_q;
  logic signed [7:0] first_add_c_proj_q;
  logic signed [7:0] first_add_output_q;
  logic second_add_seen_q;
  logic signed [7:0] second_add_residual_q;
  logic signed [7:0] second_add_c_proj_q;
  logic signed [7:0] second_add_output_q;
  logic debug_c_proj_requant_valid;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] debug_c_proj_requant_addr;
  logic signed [C_PROJ_ACC_WIDTH - 1:0] debug_c_proj_requant_acc_q;
  logic signed [31:0] debug_c_proj_requant_scale_mul_q;
  logic signed [31:0] debug_c_proj_requant_bias_q;
  logic signed [63:0] debug_c_proj_requant_product_q;
  logic signed [63:0] debug_c_proj_requant_scaled_q;
  logic signed [63:0] debug_c_proj_requant_biased_q;
  logic signed [7:0] debug_c_proj_requant_output_q;
  logic first_c_proj_requant_seen_q;
  logic signed [C_PROJ_ACC_WIDTH - 1:0] first_c_proj_requant_acc_q;
  logic signed [31:0] first_c_proj_requant_scale_mul_q;
  logic signed [31:0] first_c_proj_requant_bias_q;
  logic signed [63:0] first_c_proj_requant_product_q;
  logic signed [63:0] first_c_proj_requant_scaled_q;
  logic signed [63:0] first_c_proj_requant_biased_q;
  logic signed [7:0] first_c_proj_requant_output_q;
  logic second_c_proj_requant_seen_q;
  logic signed [C_PROJ_ACC_WIDTH - 1:0] second_c_proj_requant_acc_q;
  logic signed [31:0] second_c_proj_requant_scale_mul_q;
  logic signed [31:0] second_c_proj_requant_bias_q;
  logic signed [63:0] second_c_proj_requant_product_q;
  logic signed [63:0] second_c_proj_requant_scaled_q;
  logic signed [63:0] second_c_proj_requant_biased_q;
  logic signed [7:0] second_c_proj_requant_output_q;
  logic [C_PROJ_GEMV_DEBUG_SAMPLE_BITS - 1:0] debug_c_proj_gemv_lane0_samples;
  logic [3:0] debug_c_proj_gemv_lane0_sample_count;
  logic signed [C_PROJ_ACC_WIDTH - 1:0] debug_c_proj_gemv_lane0_final_acc;
  logic [C_PROJ_GEMV_DEBUG_SAMPLE_COUNT * 8 - 1:0]
    debug_c_proj_transfer_post_gelu_samples;
  logic [C_FC_POST_GELU_DEBUG_SAMPLE_BITS - 1:0]
    debug_c_fc_post_gelu_samples;
  logic [3:0] debug_c_fc_post_gelu_sample_count;
  logic [C_FC_GEMV_DEBUG_SAMPLE_BITS - 1:0] debug_c_fc_gemv_samples;
  logic [3:0] debug_c_fc_gemv_sample_count;
  logic signed [C_PROJ_ACC_WIDTH - 1:0] debug_c_fc_gemv_final_acc;
  logic [63:0] expected_c_proj_gemv_lane0_weights;
  logic [2:0] c_proj_requant_stage_code;
  logic [3:0] jtag_debug_status;
  logic [JTAG_DEBUG_WIDTH - 1:0] jtag_debug_payload;

  assign value_debug_phase = blink_count_q[28:25];
  assign fail_expected_high_leds = {1'b0, fail_expected_q[7:6]};
  assign fail_observed_high_leds = {1'b0, fail_observed_q[7:6]};
  assign fail_expected_c_proj_high_leds = {1'b0, fail_expected_c_proj_q[7:6]};
  assign first_add_c_proj_high_leds = {1'b0, first_add_c_proj_q[7:6]};
  assign first_c_proj_requant_output_high_leds =
    {1'b0, first_c_proj_requant_output_q[7:6]};
  assign first_c_proj_requant_acc_match_leds =
    first_c_proj_requant_seen_q &&
    (first_c_proj_requant_acc_q == expected_c_proj_acc_values[0])
      ? 3'b010 : 3'b101;
  assign first_c_proj_requant_scale_match_leds =
    first_c_proj_requant_seen_q &&
    (first_c_proj_requant_scale_mul_q == c_proj_requant_scale_mul_values[0])
      ? 3'b010 : 3'b101;
  assign first_c_proj_requant_bias_match_leds =
    first_c_proj_requant_seen_q &&
    (first_c_proj_requant_bias_q == c_proj_requant_bias_q_values[0])
      ? 3'b010 : 3'b101;
  assign jtag_debug_status = {
    first_c_proj_requant_seen_q,
    first_add_seen_q,
    state_q == SELFTEST_FAIL,
    state_q == SELFTEST_PASS
  };
  assign expected_c_proj_gemv_lane0_weights = {
    c_proj_packed_weight_values[255][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8],
    c_proj_packed_weight_values[191][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8],
    c_proj_packed_weight_values[127][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8],
    c_proj_packed_weight_values[63][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8],
    c_proj_packed_weight_values[3][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8],
    c_proj_packed_weight_values[2][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8],
    c_proj_packed_weight_values[1][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8],
    c_proj_packed_weight_values[0][C_PROJ_GEMV_DEBUG_LANE_INDEX * 8 +: 8]
  };

  always_comb begin
    c_proj_requant_stage_code = C_PROJ_STAGE_OUTPUT;
    if (first_c_proj_requant_seen_q) begin
      if (first_c_proj_requant_acc_q != expected_c_proj_acc_values[0])
        c_proj_requant_stage_code = C_PROJ_STAGE_ACC;
      else if (first_c_proj_requant_scale_mul_q != c_proj_requant_scale_mul_values[0])
        c_proj_requant_stage_code = C_PROJ_STAGE_SCALE;
      else if (first_c_proj_requant_bias_q != c_proj_requant_bias_q_values[0])
        c_proj_requant_stage_code = C_PROJ_STAGE_BIAS;
      else if (first_c_proj_requant_product_q != EXPECTED_C_PROJ_PRODUCT_Q0)
        c_proj_requant_stage_code = C_PROJ_STAGE_PRODUCT;
      else if (first_c_proj_requant_scaled_q != EXPECTED_C_PROJ_SCALED_Q0)
        c_proj_requant_stage_code = C_PROJ_STAGE_SHIFT;
      else if (first_c_proj_requant_biased_q != EXPECTED_C_PROJ_BIASED_Q0)
        c_proj_requant_stage_code = C_PROJ_STAGE_BIASED;
      else if (first_c_proj_requant_output_q != expected_c_proj_output_q_values[0])
        c_proj_requant_stage_code = C_PROJ_STAGE_OUTPUT;
      else
        c_proj_requant_stage_code = C_PROJ_STAGE_OK_OR_DOWNSTREAM;
    end
  end

  always_comb begin
    jtag_debug_payload = '0;
    jtag_debug_payload[0 +: 32] = JTAG_DEBUG_MAGIC;
    jtag_debug_payload[32 +: 8] = JTAG_DEBUG_VERSION;
    jtag_debug_payload[40 +: 4] = state_q;
    jtag_debug_payload[44 +: 4] = jtag_debug_status;
    jtag_debug_payload[48 +: 32] = cycle_count_q;
    jtag_debug_payload[80 +: 8] = {6'd0, fail_reason_q};
    jtag_debug_payload[88 +: 8] = {{(8 - C_PROJ_OUT_ADDR_WIDTH){1'b0}}, fail_index_q};
    jtag_debug_payload[96 +: 8] = fail_expected_q;
    jtag_debug_payload[104 +: 8] = fail_observed_q;
    jtag_debug_payload[112 +: 8] = fail_expected_c_proj_q;
    jtag_debug_payload[120 +: 8] = first_add_residual_q;
    jtag_debug_payload[128 +: 8] = first_add_c_proj_q;
    jtag_debug_payload[136 +: 8] = first_add_output_q;
    jtag_debug_payload[144 +: 8] = {7'd0, first_add_seen_q};
    jtag_debug_payload[152 +: 8] = {5'd0, c_proj_requant_stage_code};
    jtag_debug_payload[160 +: 8] = first_c_proj_requant_output_q;
    jtag_debug_payload[168 +: 8] = expected_c_proj_output_q_values[0];
    jtag_debug_payload[176 +: 8] = expected_residual_add_output_q_values[0];
    jtag_debug_payload[184 +: 8] = {7'd0, first_c_proj_requant_seen_q};
    jtag_debug_payload[192 +: 32] = expected_c_proj_acc_values[DEBUG_INDEX_ONE];
    jtag_debug_payload[224 +: 32] = c_proj_requant_scale_mul_values[0];
    jtag_debug_payload[256 +: 32] = c_proj_requant_bias_q_values[0];
    jtag_debug_payload[288 +: 64] = EXPECTED_C_PROJ_PRODUCT_Q0;
    jtag_debug_payload[352 +: 64] = EXPECTED_C_PROJ_SCALED_Q0;
    jtag_debug_payload[416 +: 64] = EXPECTED_C_PROJ_BIASED_Q0;
    jtag_debug_payload[480 +: 32] = first_c_proj_requant_acc_q;
    jtag_debug_payload[512 +: 32] = first_c_proj_requant_scale_mul_q;
    jtag_debug_payload[544 +: 32] = first_c_proj_requant_bias_q;
    jtag_debug_payload[576 +: 64] = first_c_proj_requant_product_q;
    jtag_debug_payload[640 +: 64] = first_c_proj_requant_scaled_q;
    jtag_debug_payload[704 +: 64] = first_c_proj_requant_biased_q;
    jtag_debug_payload[768 +: 8] = {4'd0, debug_c_proj_gemv_lane0_sample_count};
    jtag_debug_payload[776 +: 32] = debug_c_proj_gemv_lane0_final_acc;
    jtag_debug_payload[808 +: 64] = expected_c_proj_gemv_lane0_weights;
    jtag_debug_payload[896 +: C_PROJ_GEMV_DEBUG_SAMPLE_BITS] =
      debug_c_proj_gemv_lane0_samples;
    jtag_debug_payload[1920 +: 64] = EXPECTED_C_PROJ_ACTIVATION_SAMPLES;
    jtag_debug_payload[1984 +: 64] = debug_c_proj_transfer_post_gelu_samples;
  end

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN)
      config_reset_count_q <= 8'd0;
    else if (!config_reset_done)
      config_reset_count_q <= config_reset_count_q + 8'd1;
  end

  assign config_reset_done = config_reset_count_q[7];
  assign selftest_reset = !SYS_RSTN || !config_reset_done;

  always_comb begin
    dut_reset = selftest_reset;
    unique case (state_q)
      SELFTEST_BOOT,
      SELFTEST_LOAD_C_FC_ACTIVATION,
      SELFTEST_LOAD_C_FC_WEIGHT,
      SELFTEST_LOAD_C_FC_REQUANT,
      SELFTEST_LOAD_C_PROJ_WEIGHT,
      SELFTEST_LOAD_C_PROJ_REQUANT,
      SELFTEST_LOAD_RESIDUAL: dut_reset = 1'b1;
      default: dut_reset = selftest_reset;
    endcase
  end

  assign start = (state_q == SELFTEST_START);

  always_comb begin
    c_fc_weight_load_valid = 1'b0;
    c_fc_weight_load_addr = '0;
    c_fc_weight_load_data = '0;
    c_fc_activation_load_valid = 1'b0;
    c_fc_activation_load_addr = '0;
    c_fc_activation_load_data = '0;
    c_fc_requant_load_valid = 1'b0;
    c_fc_requant_load_addr = '0;
    c_fc_requant_scale_mul_load_data = '0;
    c_fc_requant_bias_q_load_data = '0;
    c_proj_weight_load_valid = 1'b0;
    c_proj_weight_load_addr = '0;
    c_proj_weight_load_data = '0;
    c_proj_requant_load_valid = 1'b0;
    c_proj_requant_load_addr = '0;
    c_proj_requant_scale_mul_load_data = '0;
    c_proj_requant_bias_q_load_data = '0;
    residual_load_valid = 1'b0;
    residual_load_addr = '0;
    residual_load_data = '0;
    output_read_addr = check_index_q;

    unique case (state_q)
      SELFTEST_LOAD_C_FC_ACTIVATION: begin
        c_fc_activation_load_valid = 1'b1;
        c_fc_activation_load_addr =
          C_FC_ACTIVATION_ADDR_WIDTH'(load_index_q);
        c_fc_activation_load_data =
          c_fc_activation_values[load_index_q[C_FC_ACTIVATION_ADDR_WIDTH - 1:0]];
      end

      SELFTEST_LOAD_C_FC_WEIGHT: begin
        c_fc_weight_load_valid = 1'b1;
        c_fc_weight_load_addr =
          C_FC_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q);
        c_fc_weight_load_data =
          c_fc_packed_weight_values[load_index_q[C_FC_PACKED_WEIGHT_ADDR_WIDTH - 1:0]];
      end

      SELFTEST_LOAD_C_FC_REQUANT: begin
        c_fc_requant_load_valid = 1'b1;
        c_fc_requant_load_addr = HIDDEN_ADDR_WIDTH'(load_index_q);
        c_fc_requant_scale_mul_load_data =
          c_fc_requant_scale_mul_values[load_index_q[HIDDEN_ADDR_WIDTH - 1:0]];
        c_fc_requant_bias_q_load_data =
          c_fc_requant_bias_q_values[load_index_q[HIDDEN_ADDR_WIDTH - 1:0]];
      end

      SELFTEST_LOAD_C_PROJ_WEIGHT: begin
        c_proj_weight_load_valid = 1'b1;
        c_proj_weight_load_addr =
          C_PROJ_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q);
        c_proj_weight_load_data =
          c_proj_packed_weight_values[load_index_q[C_PROJ_PACKED_WEIGHT_ADDR_WIDTH - 1:0]];
      end

      SELFTEST_LOAD_C_PROJ_REQUANT: begin
        c_proj_requant_load_valid = 1'b1;
        c_proj_requant_load_addr = C_PROJ_OUT_ADDR_WIDTH'(load_index_q);
        c_proj_requant_scale_mul_load_data =
          c_proj_requant_scale_mul_values[load_index_q[C_PROJ_OUT_ADDR_WIDTH - 1:0]];
        c_proj_requant_bias_q_load_data =
          c_proj_requant_bias_q_values[load_index_q[C_PROJ_OUT_ADDR_WIDTH - 1:0]];
      end

      SELFTEST_LOAD_RESIDUAL: begin
        residual_load_valid = 1'b1;
        residual_load_addr = C_PROJ_OUT_ADDR_WIDTH'(load_index_q);
        residual_load_data =
          residual_q_values[load_index_q[C_PROJ_OUT_ADDR_WIDTH - 1:0]];
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= SELFTEST_BOOT;
      boot_count_q <= 8'd0;
      load_index_q <= 13'd0;
      check_index_q <= '0;
      cycle_count_q <= 32'd0;
      blink_count_q <= 29'd0;
      fail_reason_q <= 2'd0;
      fail_index_q <= '0;
      fail_expected_q <= '0;
      fail_observed_q <= '0;
      fail_expected_c_proj_q <= '0;
      first_add_seen_q <= 1'b0;
      first_add_residual_q <= '0;
      first_add_c_proj_q <= '0;
      first_add_output_q <= '0;
      second_add_seen_q <= 1'b0;
      second_add_residual_q <= '0;
      second_add_c_proj_q <= '0;
      second_add_output_q <= '0;
      first_c_proj_requant_seen_q <= 1'b0;
      first_c_proj_requant_acc_q <= '0;
      first_c_proj_requant_scale_mul_q <= '0;
      first_c_proj_requant_bias_q <= '0;
      first_c_proj_requant_product_q <= '0;
      first_c_proj_requant_scaled_q <= '0;
      first_c_proj_requant_biased_q <= '0;
      first_c_proj_requant_output_q <= '0;
      second_c_proj_requant_seen_q <= 1'b0;
      second_c_proj_requant_acc_q <= '0;
      second_c_proj_requant_scale_mul_q <= '0;
      second_c_proj_requant_bias_q <= '0;
      second_c_proj_requant_product_q <= '0;
      second_c_proj_requant_scaled_q <= '0;
      second_c_proj_requant_biased_q <= '0;
      second_c_proj_requant_output_q <= '0;
    end else if (!config_reset_done) begin
      state_q <= SELFTEST_BOOT;
      boot_count_q <= 8'd0;
      load_index_q <= 13'd0;
      check_index_q <= '0;
      cycle_count_q <= 32'd0;
      blink_count_q <= 29'd0;
      fail_reason_q <= 2'd0;
      fail_index_q <= '0;
      fail_expected_q <= '0;
      fail_observed_q <= '0;
      fail_expected_c_proj_q <= '0;
      first_add_seen_q <= 1'b0;
      first_add_residual_q <= '0;
      first_add_c_proj_q <= '0;
      first_add_output_q <= '0;
      second_add_seen_q <= 1'b0;
      second_add_residual_q <= '0;
      second_add_c_proj_q <= '0;
      second_add_output_q <= '0;
      first_c_proj_requant_seen_q <= 1'b0;
      first_c_proj_requant_acc_q <= '0;
      first_c_proj_requant_scale_mul_q <= '0;
      first_c_proj_requant_bias_q <= '0;
      first_c_proj_requant_product_q <= '0;
      first_c_proj_requant_scaled_q <= '0;
      first_c_proj_requant_biased_q <= '0;
      first_c_proj_requant_output_q <= '0;
      second_c_proj_requant_seen_q <= 1'b0;
      second_c_proj_requant_acc_q <= '0;
      second_c_proj_requant_scale_mul_q <= '0;
      second_c_proj_requant_bias_q <= '0;
      second_c_proj_requant_product_q <= '0;
      second_c_proj_requant_scaled_q <= '0;
      second_c_proj_requant_biased_q <= '0;
      second_c_proj_requant_output_q <= '0;
    end else begin
      blink_count_q <= blink_count_q + 29'd1;

      if (debug_c_proj_requant_valid &&
          debug_c_proj_requant_addr == '0 &&
          !first_c_proj_requant_seen_q) begin
        first_c_proj_requant_seen_q <= 1'b1;
        first_c_proj_requant_acc_q <= debug_c_proj_requant_acc_q;
        first_c_proj_requant_scale_mul_q <= debug_c_proj_requant_scale_mul_q;
        first_c_proj_requant_bias_q <= debug_c_proj_requant_bias_q;
        first_c_proj_requant_product_q <= debug_c_proj_requant_product_q;
        first_c_proj_requant_scaled_q <= debug_c_proj_requant_scaled_q;
        first_c_proj_requant_biased_q <= debug_c_proj_requant_biased_q;
        first_c_proj_requant_output_q <= debug_c_proj_requant_output_q;
      end

      if (debug_c_proj_requant_valid &&
          debug_c_proj_requant_addr == DEBUG_INDEX_ONE &&
          !second_c_proj_requant_seen_q) begin
        second_c_proj_requant_seen_q <= 1'b1;
        second_c_proj_requant_acc_q <= debug_c_proj_requant_acc_q;
        second_c_proj_requant_scale_mul_q <= debug_c_proj_requant_scale_mul_q;
        second_c_proj_requant_bias_q <= debug_c_proj_requant_bias_q;
        second_c_proj_requant_product_q <= debug_c_proj_requant_product_q;
        second_c_proj_requant_scaled_q <= debug_c_proj_requant_scaled_q;
        second_c_proj_requant_biased_q <= debug_c_proj_requant_biased_q;
        second_c_proj_requant_output_q <= debug_c_proj_requant_output_q;
      end

      if (debug_add_valid && debug_add_addr == '0 && !first_add_seen_q) begin
        first_add_seen_q <= 1'b1;
        first_add_residual_q <= debug_add_residual_q;
        first_add_c_proj_q <= debug_add_c_proj_q;
        first_add_output_q <= debug_add_output_q;
      end

      if (debug_add_valid &&
          debug_add_addr == DEBUG_INDEX_ONE &&
          !second_add_seen_q) begin
        second_add_seen_q <= 1'b1;
        second_add_residual_q <= debug_add_residual_q;
        second_add_c_proj_q <= debug_add_c_proj_q;
        second_add_output_q <= debug_add_output_q;
      end

      if (boot_count_q <= BOOT_RESET_CYCLES)
        boot_count_q <= boot_count_q + 8'd1;

      if ((state_q == SELFTEST_RUN ||
           state_q == SELFTEST_READ_SETUP ||
          state_q == SELFTEST_READ_CHECK) &&
          cycle_count_q >= TIMEOUT_CYCLES) begin
        fail_reason_q <= FAIL_REASON_TIMEOUT;
        fail_index_q <= check_index_q;
        fail_expected_q <= expected_residual_add_output_q_values[check_index_q];
        fail_observed_q <= output_read_data;
        fail_expected_c_proj_q <= expected_c_proj_output_q_values[check_index_q];
        state_q <= SELFTEST_FAIL;
      end else begin
        unique case (state_q)
          SELFTEST_BOOT: begin
            load_index_q <= 13'd0;
            check_index_q <= '0;
            cycle_count_q <= 32'd0;
            if (boot_count_q > BOOT_RESET_CYCLES)
              state_q <= SELFTEST_LOAD_C_FC_ACTIVATION;
          end

          SELFTEST_LOAD_C_FC_ACTIVATION: begin
            if (load_index_q == 13'(C_FC_IN_DIM - 1)) begin
              load_index_q <= 13'd0;
              state_q <= SELFTEST_LOAD_C_FC_WEIGHT;
            end else begin
              load_index_q <= load_index_q + 13'd1;
            end
          end

          SELFTEST_LOAD_C_FC_WEIGHT: begin
            if (load_index_q == 13'(C_FC_PACKED_WEIGHT_WORDS - 1)) begin
              load_index_q <= 13'd0;
              state_q <= SELFTEST_LOAD_C_FC_REQUANT;
            end else begin
              load_index_q <= load_index_q + 13'd1;
            end
          end

          SELFTEST_LOAD_C_FC_REQUANT: begin
            if (load_index_q == 13'(HIDDEN_DIM - 1)) begin
              load_index_q <= 13'd0;
              state_q <= SELFTEST_LOAD_C_PROJ_WEIGHT;
            end else begin
              load_index_q <= load_index_q + 13'd1;
            end
          end

          SELFTEST_LOAD_C_PROJ_WEIGHT: begin
            if (load_index_q == 13'(C_PROJ_PACKED_WEIGHT_WORDS - 1)) begin
              load_index_q <= 13'd0;
              state_q <= SELFTEST_LOAD_C_PROJ_REQUANT;
            end else begin
              load_index_q <= load_index_q + 13'd1;
            end
          end

          SELFTEST_LOAD_C_PROJ_REQUANT: begin
            if (load_index_q == 13'(C_PROJ_OUT_DIM - 1)) begin
              load_index_q <= 13'd0;
              state_q <= SELFTEST_LOAD_RESIDUAL;
            end else begin
              load_index_q <= load_index_q + 13'd1;
            end
          end

          SELFTEST_LOAD_RESIDUAL: begin
            if (load_index_q == 13'(C_PROJ_OUT_DIM - 1)) begin
              load_index_q <= 13'd0;
              check_index_q <= '0;
              cycle_count_q <= 32'd0;
              state_q <= SELFTEST_START;
            end else begin
              load_index_q <= load_index_q + 13'd1;
            end
          end

          SELFTEST_START: begin
            cycle_count_q <= 32'd0;
            state_q <= SELFTEST_RUN;
          end

          SELFTEST_RUN: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (done) begin
              check_index_q <= '0;
              state_q <= SELFTEST_READ_SETUP;
            end
          end

          SELFTEST_READ_SETUP: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            state_q <= SELFTEST_READ_CHECK;
          end

          SELFTEST_READ_CHECK: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (output_read_data != expected_residual_add_output_q_values[check_index_q]) begin
              fail_reason_q <= FAIL_REASON_MISMATCH;
              fail_index_q <= check_index_q;
              fail_expected_q <= expected_residual_add_output_q_values[check_index_q];
              fail_observed_q <= output_read_data;
              fail_expected_c_proj_q <= expected_c_proj_output_q_values[check_index_q];
              state_q <= SELFTEST_FAIL;
            end else if (check_index_q == LAST_C_PROJ_OUT_INDEX) begin
              state_q <= SELFTEST_PASS;
            end else begin
              check_index_q <= check_index_q + 1'b1;
              state_q <= SELFTEST_READ_SETUP;
            end
          end

          SELFTEST_PASS,
          SELFTEST_FAIL: begin
            state_q <= state_q;
          end

          default: begin
            fail_reason_q <= FAIL_REASON_DEFAULT;
            fail_index_q <= check_index_q;
            fail_expected_q <= expected_residual_add_output_q_values[check_index_q];
            fail_observed_q <= output_read_data;
            fail_expected_c_proj_q <= expected_c_proj_output_q_values[check_index_q];
            state_q <= SELFTEST_FAIL;
          end
        endcase
      end
    end
  end

  always_comb begin
    led_3bits_tri_o[0] = blink_count_q[25];
    led_3bits_tri_o[1] = (state_q == SELFTEST_PASS);
    led_3bits_tri_o[2] = (state_q == SELFTEST_FAIL);

    if (DEBUG_LEDS != 0) begin
      unique case (state_q)
        SELFTEST_PASS: begin
          led_3bits_tri_o = 3'b010;
        end

        SELFTEST_FAIL: begin
          if (DEBUG_LEDS == 5) begin
            unique case (value_debug_phase)
              4'd0: led_3bits_tri_o = 3'b111;
              4'd1: led_3bits_tri_o = {1'b1, fail_reason_q};
              4'd2: led_3bits_tri_o = fail_index_q[2:0];
              4'd3: led_3bits_tri_o = fail_index_q[5:3];
              4'd4: led_3bits_tri_o = 3'b101;
              4'd5: led_3bits_tri_o = c_proj_requant_stage_code;
              4'd6: led_3bits_tri_o = 3'b011;
              4'd7: led_3bits_tri_o = first_c_proj_requant_output_q[2:0];
              4'd8: led_3bits_tri_o = first_c_proj_requant_output_q[5:3];
              4'd9: led_3bits_tri_o = first_c_proj_requant_output_high_leds;
              4'd10: led_3bits_tri_o = 3'b101;
              4'd11: led_3bits_tri_o = first_add_c_proj_q[2:0];
              4'd12: led_3bits_tri_o = first_add_c_proj_q[5:3];
              4'd13: led_3bits_tri_o = first_add_c_proj_high_leds;
              4'd14: led_3bits_tri_o = 3'b000;
              default: led_3bits_tri_o = 3'b111;
            endcase
          end else if (DEBUG_LEDS == 4) begin
            unique case (value_debug_phase)
              4'd0: led_3bits_tri_o = 3'b111;
              4'd1: led_3bits_tri_o = {1'b1, fail_reason_q};
              4'd2: led_3bits_tri_o = fail_index_q[2:0];
              4'd3: led_3bits_tri_o = fail_index_q[5:3];
              4'd4: led_3bits_tri_o = 3'b101;
              4'd5: led_3bits_tri_o = first_c_proj_requant_acc_match_leds;
              4'd6: led_3bits_tri_o = first_c_proj_requant_scale_match_leds;
              4'd7: led_3bits_tri_o = first_c_proj_requant_bias_match_leds;
              4'd8: led_3bits_tri_o = 3'b011;
              4'd9: led_3bits_tri_o = first_c_proj_requant_output_q[2:0];
              4'd10: led_3bits_tri_o = first_c_proj_requant_output_q[5:3];
              4'd11: led_3bits_tri_o = first_c_proj_requant_output_high_leds;
              4'd12,
              4'd13,
              4'd14: led_3bits_tri_o = 3'b000;
              default: led_3bits_tri_o = 3'b111;
            endcase
          end else if (DEBUG_LEDS == 3) begin
            unique case (value_debug_phase)
              4'd0: led_3bits_tri_o = 3'b111;
              4'd1: led_3bits_tri_o = {1'b1, fail_reason_q};
              4'd2: led_3bits_tri_o = fail_index_q[2:0];
              4'd3: led_3bits_tri_o = fail_index_q[5:3];
              4'd4: led_3bits_tri_o = 3'b101;
              4'd5: led_3bits_tri_o = fail_expected_c_proj_q[2:0];
              4'd6: led_3bits_tri_o = fail_expected_c_proj_q[5:3];
              4'd7: led_3bits_tri_o = fail_expected_c_proj_high_leds;
              4'd8: led_3bits_tri_o = 3'b011;
              4'd9: led_3bits_tri_o = first_add_c_proj_q[2:0];
              4'd10: led_3bits_tri_o = first_add_c_proj_q[5:3];
              4'd11: led_3bits_tri_o = first_add_c_proj_high_leds;
              4'd12,
              4'd13,
              4'd14: led_3bits_tri_o = 3'b000;
              default: led_3bits_tri_o = 3'b111;
            endcase
          end else if (DEBUG_LEDS == 2) begin
            unique case (value_debug_phase)
              4'd0: led_3bits_tri_o = 3'b111;
              4'd1: led_3bits_tri_o = {1'b1, fail_reason_q};
              4'd2: led_3bits_tri_o = fail_index_q[2:0];
              4'd3: led_3bits_tri_o = fail_index_q[5:3];
              4'd4: led_3bits_tri_o = 3'b101;
              4'd5: led_3bits_tri_o = fail_expected_q[2:0];
              4'd6: led_3bits_tri_o = fail_expected_q[5:3];
              4'd7: led_3bits_tri_o = fail_expected_high_leds;
              4'd8: led_3bits_tri_o = 3'b011;
              4'd9: led_3bits_tri_o = fail_observed_q[2:0];
              4'd10: led_3bits_tri_o = fail_observed_q[5:3];
              4'd11: led_3bits_tri_o = fail_observed_high_leds;
              4'd12,
              4'd13,
              4'd14: led_3bits_tri_o = 3'b000;
              default: led_3bits_tri_o = 3'b111;
            endcase
          end else begin
            unique case (blink_count_q[25:24])
              2'd0: led_3bits_tri_o = {1'b1, fail_reason_q};
              2'd1: led_3bits_tri_o = fail_index_q[2:0];
              2'd2: led_3bits_tri_o = fail_index_q[5:3];
              default: led_3bits_tri_o = 3'b111;
            endcase
          end
        end

        default: begin
          led_3bits_tri_o[0] = blink_count_q[25];
          led_3bits_tri_o[1] = (state_q == SELFTEST_READ_CHECK);
          led_3bits_tri_o[2] = (state_q == SELFTEST_RUN);
        end
      endcase
    end
  end

  task6_int8_l2_mlp_chain_residual_add_kernel #(
    .C_FC_IN_DIM(C_FC_IN_DIM),
    .HIDDEN_DIM(HIDDEN_DIM),
    .C_PROJ_OUT_DIM(C_PROJ_OUT_DIM),
    .TILE_OUT_DIM(TILE_OUT_DIM),
    .LANES(LANES),
    .C_FC_PACKED_WEIGHT_WORDS(C_FC_PACKED_WEIGHT_WORDS),
    .C_PROJ_PACKED_WEIGHT_WORDS(C_PROJ_PACKED_WEIGHT_WORDS),
    .X_FRAC(X_FRAC),
    .SCALE_SHIFT(SCALE_SHIFT),
    .GELU_QUAD_Q(GELU_QUAD_Q),
    .OUTPUT_REQUANT_SHIFT(OUTPUT_REQUANT_SHIFT),
    .OUTPUT_REQUANT_MULT(OUTPUT_REQUANT_MULT),
    .C_PROJ_OUTPUT_REQUANT_SHIFT(C_PROJ_OUTPUT_REQUANT_SHIFT),
    .RESIDUAL_ADD_REQUANT_SHIFT(RESIDUAL_ADD_REQUANT_SHIFT),
    .RESIDUAL_REQUANT_MULT(RESIDUAL_REQUANT_MULT),
    .C_PROJ_RESIDUAL_ADD_REQUANT_MULT(C_PROJ_RESIDUAL_ADD_REQUANT_MULT),
    .C_PROJ_GEMV_DEBUG_SAMPLE_COUNT(C_PROJ_GEMV_DEBUG_SAMPLE_COUNT),
    .C_PROJ_GEMV_DEBUG_SAMPLE_WIDTH(C_PROJ_GEMV_DEBUG_SAMPLE_WIDTH),
    .C_PROJ_GEMV_DEBUG_LANE_INDEX(C_PROJ_GEMV_DEBUG_LANE_INDEX),
    .C_FC_POST_GELU_DEBUG_SAMPLE_COUNT(C_FC_POST_GELU_DEBUG_SAMPLE_COUNT),
    .C_FC_POST_GELU_DEBUG_SAMPLE_WIDTH(C_FC_POST_GELU_DEBUG_SAMPLE_WIDTH),
    .C_FC_GEMV_DEBUG_SAMPLE_COUNT(C_FC_GEMV_DEBUG_SAMPLE_COUNT),
    .C_FC_GEMV_DEBUG_SAMPLE_WIDTH(C_FC_GEMV_DEBUG_SAMPLE_WIDTH),
    .C_FC_GEMV_DEBUG_LANE_INDEX(C_FC_GEMV_DEBUG_LANE_INDEX)
  ) dut (
    .clock(SYS_CLK),
    .reset(dut_reset),
    .c_fc_weight_load_valid(c_fc_weight_load_valid),
    .c_fc_weight_load_addr(c_fc_weight_load_addr),
    .c_fc_weight_load_data(c_fc_weight_load_data),
    .c_fc_activation_load_valid(c_fc_activation_load_valid),
    .c_fc_activation_load_addr(c_fc_activation_load_addr),
    .c_fc_activation_load_data(c_fc_activation_load_data),
    .c_fc_requant_load_valid(c_fc_requant_load_valid),
    .c_fc_requant_load_addr(c_fc_requant_load_addr),
    .c_fc_requant_scale_mul_load_data(c_fc_requant_scale_mul_load_data),
    .c_fc_requant_bias_q_load_data(c_fc_requant_bias_q_load_data),
    .c_proj_weight_load_valid(c_proj_weight_load_valid),
    .c_proj_weight_load_addr(c_proj_weight_load_addr),
    .c_proj_weight_load_data(c_proj_weight_load_data),
    .c_proj_requant_load_valid(c_proj_requant_load_valid),
    .c_proj_requant_load_addr(c_proj_requant_load_addr),
    .c_proj_requant_scale_mul_load_data(c_proj_requant_scale_mul_load_data),
    .c_proj_requant_bias_q_load_data(c_proj_requant_bias_q_load_data),
    .residual_load_valid(residual_load_valid),
    .residual_load_addr(residual_load_addr),
    .residual_load_data(residual_load_data),
    .start(start),
    .busy(busy),
    .done(done),
    .output_read_addr(output_read_addr),
    .output_read_data(output_read_data),
    .debug_add_valid(debug_add_valid),
    .debug_add_addr(debug_add_addr),
    .debug_add_residual_q(debug_add_residual_q),
    .debug_add_c_proj_q(debug_add_c_proj_q),
    .debug_add_output_q(debug_add_output_q),
    .debug_c_proj_requant_valid(debug_c_proj_requant_valid),
    .debug_c_proj_requant_addr(debug_c_proj_requant_addr),
    .debug_c_proj_requant_acc_q(debug_c_proj_requant_acc_q),
    .debug_c_proj_requant_scale_mul_q(debug_c_proj_requant_scale_mul_q),
    .debug_c_proj_requant_bias_q(debug_c_proj_requant_bias_q),
    .debug_c_proj_requant_product_q(debug_c_proj_requant_product_q),
    .debug_c_proj_requant_scaled_q(debug_c_proj_requant_scaled_q),
    .debug_c_proj_requant_biased_q(debug_c_proj_requant_biased_q),
    .debug_c_proj_requant_output_q(debug_c_proj_requant_output_q),
    .debug_c_proj_gemv_lane0_samples(debug_c_proj_gemv_lane0_samples),
    .debug_c_proj_gemv_lane0_sample_count(debug_c_proj_gemv_lane0_sample_count),
    .debug_c_proj_gemv_lane0_final_acc(debug_c_proj_gemv_lane0_final_acc),
    .debug_c_proj_transfer_post_gelu_samples(debug_c_proj_transfer_post_gelu_samples),
    .debug_c_fc_post_gelu_samples(debug_c_fc_post_gelu_samples),
    .debug_c_fc_post_gelu_sample_count(debug_c_fc_post_gelu_sample_count),
    .debug_c_fc_gemv_samples(debug_c_fc_gemv_samples),
    .debug_c_fc_gemv_sample_count(debug_c_fc_gemv_sample_count),
    .debug_c_fc_gemv_final_acc(debug_c_fc_gemv_final_acc)
  );

  generate
    if (ENABLE_JTAG_DEBUG != 0) begin : gen_jtag_debug
      task6_jtag_debug_shift #(
        .WIDTH(JTAG_DEBUG_WIDTH),
        .JTAG_CHAIN(1)
      ) jtag_debug_shift (
        .payload_i(jtag_debug_payload)
      );
    end
  endgenerate
endmodule

module task6_jtag_debug_shift #(
  parameter int WIDTH = 768,
  parameter int JTAG_CHAIN = 1
)(
  input logic [WIDTH - 1:0] payload_i
);
  logic capture;
  logic drck;
  logic reset;
  logic runtest;
  logic sel;
  logic shift;
  logic tck;
  logic tdi;
  logic tms;
  logic update;
  logic tdo;
  logic [WIDTH - 1:0] shift_q;

  assign tdo = shift_q[0];

  always_ff @(posedge drck or posedge reset) begin
    if (reset) begin
      shift_q <= '0;
    end else if (sel && capture) begin
      shift_q <= payload_i;
    end else if (sel && shift) begin
      shift_q <= {tdi, shift_q[WIDTH - 1:1]};
    end
  end

  BSCANE2 #(
    .DISABLE_JTAG("FALSE"),
    .JTAG_CHAIN(JTAG_CHAIN)
  ) bscan (
    .CAPTURE(capture),
    .DRCK(drck),
    .RESET(reset),
    .RUNTEST(runtest),
    .SEL(sel),
    .SHIFT(shift),
    .TCK(tck),
    .TDI(tdi),
    .TMS(tms),
    .UPDATE(update),
    .TDO(tdo)
  );
endmodule
