`timescale 1ns/1ps

module task6_int8_v4k_l2_residual_add_output_head_selftest_top #(
  parameter int DEBUG_LEDS = 0
)(
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);
  `include "tb_data.sv"

  localparam logic [31:0] TIMEOUT_CYCLES = 32'd50000000;
  localparam logic [7:0] BOOT_RESET_CYCLES = 8'd16;
  localparam logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] LAST_C_PROJ_OUT_INDEX =
    C_PROJ_OUT_ADDR_WIDTH'(C_PROJ_OUT_DIM - 1);
  localparam logic [2:0] FAIL_REASON_TIMEOUT = 3'd1;
  localparam logic [2:0] FAIL_REASON_RESIDUAL_MISMATCH = 3'd2;
  localparam logic [2:0] FAIL_REASON_TOP_INDEX = 3'd3;
  localparam logic [2:0] FAIL_REASON_TOP_ACC = 3'd4;
  localparam logic [2:0] FAIL_REASON_DEFAULT = 3'd7;

  typedef enum logic [4:0] {
    SELFTEST_BOOT,
    SELFTEST_LOAD_C_FC_ACTIVATION,
    SELFTEST_LOAD_C_FC_WEIGHT,
    SELFTEST_LOAD_C_FC_REQUANT,
    SELFTEST_LOAD_C_PROJ_WEIGHT,
    SELFTEST_LOAD_C_PROJ_REQUANT,
    SELFTEST_LOAD_RESIDUAL,
    SELFTEST_LOAD_VOCAB_WEIGHT_SETUP,
    SELFTEST_LOAD_VOCAB_WEIGHT_WRITE,
    SELFTEST_START_RESIDUAL,
    SELFTEST_RUN_RESIDUAL,
    SELFTEST_LOAD_HEAD_ACTIVATION_SETUP,
    SELFTEST_LOAD_HEAD_ACTIVATION_WRITE,
    SELFTEST_START_OUTPUT_HEAD,
    SELFTEST_RUN_OUTPUT_HEAD,
    SELFTEST_PASS,
    SELFTEST_FAIL
  } selftest_state_t;

  selftest_state_t state_q;
  logic [7:0] boot_count_q;
  logic [31:0] load_index_q;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] activation_index_q;
  logic [31:0] cycle_count_q;
  logic [28:0] blink_count_q;
  logic [7:0] config_reset_count_q = 8'd0;
  logic config_reset_done;
  logic selftest_reset;
  logic [2:0] fail_reason_q;
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] fail_index_q;
  logic signed [7:0] fail_expected_residual_q;
  logic signed [7:0] fail_observed_residual_q;
  logic [VOCAB_ADDR_WIDTH - 1:0] fail_observed_top_index_q;
  logic signed [VOCAB_ACC_WIDTH - 1:0] fail_observed_top_acc_q;

  logic residual_reset;
  logic residual_start;
  logic residual_busy;
  logic residual_done;

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
  logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] residual_output_read_addr;
  logic signed [7:0] residual_output_read_data;

  (* rom_style = "block", ram_style = "block" *)
  logic [VOCAB_LANES * 8 - 1:0] vocab_packed_weight_rom
    [0:VOCAB_PACKED_WEIGHT_WORDS - 1];
  logic [VOCAB_LANES * 8 - 1:0] vocab_packed_weight_rom_data_q;

  logic output_head_reset;
  logic output_head_start;
  logic output_head_busy;
  logic output_head_done;
  logic vocab_weight_load_valid;
  logic [VOCAB_PACKED_WEIGHT_ADDR_WIDTH - 1:0] vocab_weight_load_addr;
  logic [VOCAB_LANES * 8 - 1:0] vocab_weight_load_data;
  logic vocab_activation_load_valid;
  logic [VOCAB_ACTIVATION_ADDR_WIDTH - 1:0] vocab_activation_load_addr;
  logic signed [7:0] vocab_activation_load_data;
  logic [VOCAB_ADDR_WIDTH - 1:0] top_index;
  logic signed [VOCAB_ACC_WIDTH - 1:0] top_acc;

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN)
      config_reset_count_q <= 8'd0;
    else if (!config_reset_done)
      config_reset_count_q <= config_reset_count_q + 8'd1;
  end

  assign config_reset_done = config_reset_count_q[7];
  assign selftest_reset = !SYS_RSTN || !config_reset_done;
  assign residual_start = (state_q == SELFTEST_START_RESIDUAL);
  assign output_head_start = (state_q == SELFTEST_START_OUTPUT_HEAD);
  assign residual_output_read_addr = activation_index_q;

  initial begin
    $readmemh("vocab_packed_weights.mem", vocab_packed_weight_rom);
  end

  always_ff @(posedge SYS_CLK) begin
    vocab_packed_weight_rom_data_q <=
      vocab_packed_weight_rom[VOCAB_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q)];
  end

  always_comb begin
    residual_reset = selftest_reset;
    unique case (state_q)
      SELFTEST_BOOT,
      SELFTEST_LOAD_C_FC_ACTIVATION,
      SELFTEST_LOAD_C_FC_WEIGHT,
      SELFTEST_LOAD_C_FC_REQUANT,
      SELFTEST_LOAD_C_PROJ_WEIGHT,
      SELFTEST_LOAD_C_PROJ_REQUANT,
      SELFTEST_LOAD_RESIDUAL,
      SELFTEST_LOAD_VOCAB_WEIGHT_SETUP,
      SELFTEST_LOAD_VOCAB_WEIGHT_WRITE: residual_reset = 1'b1;
      default: residual_reset = selftest_reset;
    endcase
  end

  always_comb begin
    output_head_reset = selftest_reset;
    unique case (state_q)
      SELFTEST_BOOT,
      SELFTEST_LOAD_C_FC_ACTIVATION,
      SELFTEST_LOAD_C_FC_WEIGHT,
      SELFTEST_LOAD_C_FC_REQUANT,
      SELFTEST_LOAD_C_PROJ_WEIGHT,
      SELFTEST_LOAD_C_PROJ_REQUANT,
      SELFTEST_LOAD_RESIDUAL,
      SELFTEST_LOAD_VOCAB_WEIGHT_SETUP,
      SELFTEST_LOAD_VOCAB_WEIGHT_WRITE,
      SELFTEST_START_RESIDUAL,
      SELFTEST_RUN_RESIDUAL,
      SELFTEST_LOAD_HEAD_ACTIVATION_SETUP,
      SELFTEST_LOAD_HEAD_ACTIVATION_WRITE: output_head_reset = 1'b1;
      default: output_head_reset = selftest_reset;
    endcase
  end

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
    vocab_weight_load_valid = 1'b0;
    vocab_weight_load_addr = '0;
    vocab_weight_load_data = '0;
    vocab_activation_load_valid = 1'b0;
    vocab_activation_load_addr = '0;
    vocab_activation_load_data = '0;

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

      SELFTEST_LOAD_VOCAB_WEIGHT_WRITE: begin
        vocab_weight_load_valid = 1'b1;
        vocab_weight_load_addr =
          VOCAB_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q);
        vocab_weight_load_data = vocab_packed_weight_rom_data_q;
      end

      SELFTEST_LOAD_HEAD_ACTIVATION_WRITE: begin
        vocab_activation_load_valid = 1'b1;
        vocab_activation_load_addr = VOCAB_ACTIVATION_ADDR_WIDTH'(activation_index_q);
        vocab_activation_load_data = residual_output_read_data;
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= SELFTEST_BOOT;
      boot_count_q <= 8'd0;
      load_index_q <= 32'd0;
      activation_index_q <= '0;
      cycle_count_q <= 32'd0;
      blink_count_q <= 29'd0;
      fail_reason_q <= 3'd0;
      fail_index_q <= '0;
      fail_expected_residual_q <= '0;
      fail_observed_residual_q <= '0;
      fail_observed_top_index_q <= '0;
      fail_observed_top_acc_q <= '0;
    end else if (!config_reset_done) begin
      state_q <= SELFTEST_BOOT;
      boot_count_q <= 8'd0;
      load_index_q <= 32'd0;
      activation_index_q <= '0;
      cycle_count_q <= 32'd0;
      blink_count_q <= 29'd0;
      fail_reason_q <= 3'd0;
      fail_index_q <= '0;
      fail_expected_residual_q <= '0;
      fail_observed_residual_q <= '0;
      fail_observed_top_index_q <= '0;
      fail_observed_top_acc_q <= '0;
    end else begin
      blink_count_q <= blink_count_q + 29'd1;

      if ((state_q == SELFTEST_RUN_RESIDUAL ||
           state_q == SELFTEST_RUN_OUTPUT_HEAD) &&
          cycle_count_q >= TIMEOUT_CYCLES) begin
        fail_reason_q <= FAIL_REASON_TIMEOUT;
        fail_index_q <= activation_index_q;
        fail_expected_residual_q <= expected_residual_add_output_q_values[activation_index_q];
        fail_observed_residual_q <= residual_output_read_data;
        fail_observed_top_index_q <= top_index;
        fail_observed_top_acc_q <= top_acc;
        state_q <= SELFTEST_FAIL;
      end else begin
        unique case (state_q)
          SELFTEST_BOOT: begin
            load_index_q <= 32'd0;
            activation_index_q <= '0;
            cycle_count_q <= 32'd0;
            if (boot_count_q <= BOOT_RESET_CYCLES)
              boot_count_q <= boot_count_q + 8'd1;
            else
              state_q <= SELFTEST_LOAD_C_FC_ACTIVATION;
          end

          SELFTEST_LOAD_C_FC_ACTIVATION: begin
            if (load_index_q == 32'(C_FC_IN_DIM - 1)) begin
              load_index_q <= 32'd0;
              state_q <= SELFTEST_LOAD_C_FC_WEIGHT;
            end else begin
              load_index_q <= load_index_q + 32'd1;
            end
          end

          SELFTEST_LOAD_C_FC_WEIGHT: begin
            if (load_index_q == 32'(C_FC_PACKED_WEIGHT_WORDS - 1)) begin
              load_index_q <= 32'd0;
              state_q <= SELFTEST_LOAD_C_FC_REQUANT;
            end else begin
              load_index_q <= load_index_q + 32'd1;
            end
          end

          SELFTEST_LOAD_C_FC_REQUANT: begin
            if (load_index_q == 32'(HIDDEN_DIM - 1)) begin
              load_index_q <= 32'd0;
              state_q <= SELFTEST_LOAD_C_PROJ_WEIGHT;
            end else begin
              load_index_q <= load_index_q + 32'd1;
            end
          end

          SELFTEST_LOAD_C_PROJ_WEIGHT: begin
            if (load_index_q == 32'(C_PROJ_PACKED_WEIGHT_WORDS - 1)) begin
              load_index_q <= 32'd0;
              state_q <= SELFTEST_LOAD_C_PROJ_REQUANT;
            end else begin
              load_index_q <= load_index_q + 32'd1;
            end
          end

          SELFTEST_LOAD_C_PROJ_REQUANT: begin
            if (load_index_q == 32'(C_PROJ_OUT_DIM - 1)) begin
              load_index_q <= 32'd0;
              state_q <= SELFTEST_LOAD_RESIDUAL;
            end else begin
              load_index_q <= load_index_q + 32'd1;
            end
          end

          SELFTEST_LOAD_RESIDUAL: begin
            if (load_index_q == 32'(C_PROJ_OUT_DIM - 1)) begin
              load_index_q <= 32'd0;
              state_q <= SELFTEST_LOAD_VOCAB_WEIGHT_SETUP;
            end else begin
              load_index_q <= load_index_q + 32'd1;
            end
          end

          SELFTEST_LOAD_VOCAB_WEIGHT_SETUP: begin
            state_q <= SELFTEST_LOAD_VOCAB_WEIGHT_WRITE;
          end

          SELFTEST_LOAD_VOCAB_WEIGHT_WRITE: begin
            if (load_index_q == 32'(VOCAB_PACKED_WEIGHT_WORDS - 1)) begin
              load_index_q <= 32'd0;
              cycle_count_q <= 32'd0;
              state_q <= SELFTEST_START_RESIDUAL;
            end else begin
              load_index_q <= load_index_q + 32'd1;
              state_q <= SELFTEST_LOAD_VOCAB_WEIGHT_SETUP;
            end
          end

          SELFTEST_START_RESIDUAL: begin
            cycle_count_q <= 32'd0;
            state_q <= SELFTEST_RUN_RESIDUAL;
          end

          SELFTEST_RUN_RESIDUAL: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (residual_done) begin
              activation_index_q <= '0;
              cycle_count_q <= 32'd0;
              state_q <= SELFTEST_LOAD_HEAD_ACTIVATION_SETUP;
            end
          end

          SELFTEST_LOAD_HEAD_ACTIVATION_SETUP: begin
            state_q <= SELFTEST_LOAD_HEAD_ACTIVATION_WRITE;
          end

          SELFTEST_LOAD_HEAD_ACTIVATION_WRITE: begin
            if (residual_output_read_data !=
                expected_residual_add_output_q_values[activation_index_q]) begin
              fail_reason_q <= FAIL_REASON_RESIDUAL_MISMATCH;
              fail_index_q <= activation_index_q;
              fail_expected_residual_q <=
                expected_residual_add_output_q_values[activation_index_q];
              fail_observed_residual_q <= residual_output_read_data;
              fail_observed_top_index_q <= top_index;
              fail_observed_top_acc_q <= top_acc;
              state_q <= SELFTEST_FAIL;
            end else if (activation_index_q == LAST_C_PROJ_OUT_INDEX) begin
              cycle_count_q <= 32'd0;
              state_q <= SELFTEST_START_OUTPUT_HEAD;
            end else begin
              activation_index_q <= activation_index_q + 1'b1;
              state_q <= SELFTEST_LOAD_HEAD_ACTIVATION_SETUP;
            end
          end

          SELFTEST_START_OUTPUT_HEAD: begin
            cycle_count_q <= 32'd0;
            state_q <= SELFTEST_RUN_OUTPUT_HEAD;
          end

          SELFTEST_RUN_OUTPUT_HEAD: begin
            cycle_count_q <= cycle_count_q + 32'd1;
            if (output_head_done) begin
              fail_observed_top_index_q <= top_index;
              fail_observed_top_acc_q <= top_acc;
              if (top_index != EXPECTED_TOP_INDEX) begin
                fail_reason_q <= FAIL_REASON_TOP_INDEX;
                state_q <= SELFTEST_FAIL;
              end else if (top_acc != EXPECTED_TOP_ACC) begin
                fail_reason_q <= FAIL_REASON_TOP_ACC;
                state_q <= SELFTEST_FAIL;
              end else begin
                state_q <= SELFTEST_PASS;
              end
            end
          end

          SELFTEST_PASS,
          SELFTEST_FAIL: begin
            state_q <= state_q;
          end

          default: begin
            fail_reason_q <= FAIL_REASON_DEFAULT;
            fail_index_q <= activation_index_q;
            fail_expected_residual_q <=
              expected_residual_add_output_q_values[activation_index_q];
            fail_observed_residual_q <= residual_output_read_data;
            fail_observed_top_index_q <= top_index;
            fail_observed_top_acc_q <= top_acc;
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

    if (DEBUG_LEDS != 0 && state_q == SELFTEST_FAIL) begin
      unique case (blink_count_q[25:24])
        2'd0: led_3bits_tri_o = {1'b1, fail_reason_q[1:0]};
        2'd1: led_3bits_tri_o = fail_index_q[2:0];
        2'd2: led_3bits_tri_o = fail_observed_top_index_q[2:0];
        default: led_3bits_tri_o = fail_observed_top_acc_q[2:0];
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
    .C_PROJ_RESIDUAL_ADD_REQUANT_MULT(C_PROJ_RESIDUAL_ADD_REQUANT_MULT)
  ) residual_dut (
    .clock(SYS_CLK),
    .reset(residual_reset),
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
    .start(residual_start),
    .busy(residual_busy),
    .done(residual_done),
    .output_read_addr(residual_output_read_addr),
    .output_read_data(residual_output_read_data),
    .debug_add_valid(),
    .debug_add_addr(),
    .debug_add_residual_q(),
    .debug_add_c_proj_q(),
    .debug_add_output_q(),
    .debug_c_proj_requant_valid(),
    .debug_c_proj_requant_addr(),
    .debug_c_proj_requant_acc_q(),
    .debug_c_proj_requant_scale_mul_q(),
    .debug_c_proj_requant_bias_q(),
    .debug_c_proj_requant_product_q(),
    .debug_c_proj_requant_scaled_q(),
    .debug_c_proj_requant_biased_q(),
    .debug_c_proj_requant_output_q(),
    .debug_c_proj_gemv_lane0_samples(),
    .debug_c_proj_gemv_lane0_sample_count(),
    .debug_c_proj_gemv_lane0_final_acc(),
    .debug_c_proj_transfer_post_gelu_samples(),
    .debug_c_fc_post_gelu_samples(),
    .debug_c_fc_post_gelu_sample_count(),
    .debug_c_fc_gemv_samples(),
    .debug_c_fc_gemv_sample_count(),
    .debug_c_fc_gemv_final_acc()
  );

  task6_int8_vocab_output_head_top1_kernel #(
    .IN_DIM(VOCAB_IN_DIM),
    .VOCAB_SIZE(VOCAB_SIZE),
    .TILE_OUT_DIM(VOCAB_TILE_OUT_DIM),
    .LANES(VOCAB_LANES),
    .ACC_WIDTH(VOCAB_ACC_WIDTH),
    .PACKED_WEIGHT_WORDS(VOCAB_PACKED_WEIGHT_WORDS),
    .PHASE_BANKED_WEIGHT_MEMORY(1)
  ) output_head_dut (
    .clock(SYS_CLK),
    .reset(output_head_reset),
    .weight_load_valid(vocab_weight_load_valid),
    .weight_load_addr(vocab_weight_load_addr),
    .weight_load_data(vocab_weight_load_data),
    .activation_load_valid(vocab_activation_load_valid),
    .activation_load_addr(vocab_activation_load_addr),
    .activation_load_data(vocab_activation_load_data),
    .start(output_head_start),
    .busy(output_head_busy),
    .done(output_head_done),
    .top_index(top_index),
    .top_acc(top_acc)
  );
endmodule
