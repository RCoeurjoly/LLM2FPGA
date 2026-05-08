`timescale 1ns/1ps

module task6_int8_v4k_l2_residual_add_output_head_selftest_top #(
  parameter int DEBUG_LEDS = 0,
  parameter int ENABLE_JTAG_DEBUG = 0,
  parameter int PHASE_BANKED_VOCAB_LOADER_ROM = 1
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
  localparam int VOCAB_PHASES = VOCAB_SIZE / VOCAB_TILE_OUT_DIM;
  localparam int VOCAB_TILE_PACKED_WEIGHT_WORDS =
    VOCAB_PACKED_WEIGHT_WORDS / VOCAB_PHASES;
  localparam int VOCAB_TILE_PACKED_WEIGHT_ADDR_WIDTH =
    (VOCAB_TILE_PACKED_WEIGHT_WORDS <= 1) ? 1 :
      $clog2(VOCAB_TILE_PACKED_WEIGHT_WORDS);
  localparam int VOCAB_PHASE_WIDTH =
    (VOCAB_PHASES <= 1) ? 1 : $clog2(VOCAB_PHASES);
  localparam logic [2:0] FAIL_REASON_TIMEOUT = 3'd1;
  localparam logic [2:0] FAIL_REASON_RESIDUAL_MISMATCH = 3'd2;
  localparam logic [2:0] FAIL_REASON_TOP_INDEX = 3'd3;
  localparam logic [2:0] FAIL_REASON_TOP_ACC = 3'd4;
  localparam logic [2:0] FAIL_REASON_EMBEDDING_MISMATCH = 3'd5;
  localparam logic [2:0] FAIL_REASON_DEFAULT = 3'd7;
  localparam int JTAG_DEBUG_WIDTH = 768;
  localparam logic [31:0] JTAG_DEBUG_MAGIC = 32'h54364a44;
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd13;

  function automatic signed [7:0] clamp_signed_i8(input signed [8:0] value);
    if (value > 9'sd127)
      clamp_signed_i8 = 8'sd127;
    else if (value < -9'sd127)
      clamp_signed_i8 = -8'sd127;
    else
      clamp_signed_i8 = value[7:0];
  endfunction

  typedef enum logic [4:0] {
    SELFTEST_BOOT,
    SELFTEST_CHECK_EMBED_TOKEN_SETUP,
    SELFTEST_CHECK_EMBED_TOKEN_ACCUM,
    SELFTEST_CHECK_EMBED_DONE,
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
  logic [31:0] vocab_load_checksum_q;
  logic [31:0] vocab_first_word_q;
  logic [31:0] vocab_last_word_q;
  logic [31:0] head_activation_checksum_q;
  logic [31:0] embedding_token_checksum_q;
  logic [31:0] embedding_position_checksum_q;
  logic [31:0] embedding_combined_checksum_q;
  logic [7:0] jtag_debug_status;
  logic [JTAG_DEBUG_WIDTH - 1:0] jtag_debug_payload;

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

  logic [VOCAB_LANES * 8 - 1:0] vocab_packed_weight_rom_data_q;
  logic [VOCAB_PACKED_WEIGHT_ADDR_WIDTH - 1:0] vocab_loader_read_addr;
  logic signed [7:0] embedding_token_value_w;
  logic signed [7:0] embedding_position_value_w;
  logic signed [8:0] embedding_sum_w;
  logic signed [7:0] embedding_combined_value_w;

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
  assign embedding_token_value_w =
    token_embedding_q_values[load_index_q[EMBED_WORD_ADDR_WIDTH - 1:0]];
  assign embedding_position_value_w =
    position_embedding_q_values[load_index_q[EMBED_WORD_ADDR_WIDTH - 1:0]];
  assign embedding_sum_w =
    {embedding_token_value_w[7], embedding_token_value_w} +
    {embedding_position_value_w[7], embedding_position_value_w};
  assign embedding_combined_value_w = clamp_signed_i8(embedding_sum_w);
  assign jtag_debug_status = {
    4'd0,
    output_head_done,
    residual_done,
    state_q == SELFTEST_FAIL,
    state_q == SELFTEST_PASS
  };

  always_comb begin
    jtag_debug_payload = '0;
    jtag_debug_payload[0 +: 32] = JTAG_DEBUG_MAGIC;
    jtag_debug_payload[32 +: 8] = JTAG_DEBUG_VERSION;
    jtag_debug_payload[40 +: 8] = {3'd0, state_q};
    jtag_debug_payload[48 +: 8] = jtag_debug_status;
    jtag_debug_payload[56 +: 32] = cycle_count_q;
    jtag_debug_payload[88 +: 8] = {5'd0, fail_reason_q};
    jtag_debug_payload[96 +: 8] =
      {{(8 - C_PROJ_OUT_ADDR_WIDTH){1'b0}}, fail_index_q};
    jtag_debug_payload[104 +: 8] = fail_expected_residual_q;
    jtag_debug_payload[112 +: 8] = fail_observed_residual_q;
    jtag_debug_payload[120 +: 16] =
      {{(16 - VOCAB_ADDR_WIDTH){1'b0}}, fail_observed_top_index_q};
    jtag_debug_payload[136 +: 16] =
      {{(16 - VOCAB_ADDR_WIDTH){1'b0}}, EXPECTED_TOP_INDEX};
    jtag_debug_payload[152 +: 32] = fail_observed_top_acc_q[31:0];
    jtag_debug_payload[184 +: 32] = EXPECTED_TOP_ACC[31:0];
    jtag_debug_payload[216 +: 16] =
      {{(16 - VOCAB_ADDR_WIDTH){1'b0}}, top_index};
    jtag_debug_payload[232 +: 24] = top_acc[23:0];
    jtag_debug_payload[256 +: 32] = vocab_load_checksum_q;
    jtag_debug_payload[288 +: 32] = EXPECTED_VOCAB_WEIGHT_CHECKSUM;
    jtag_debug_payload[320 +: 32] = vocab_first_word_q;
    jtag_debug_payload[352 +: 32] = EXPECTED_VOCAB_FIRST_WORD;
    jtag_debug_payload[384 +: 32] = vocab_last_word_q;
    jtag_debug_payload[416 +: 32] = EXPECTED_VOCAB_LAST_WORD;
    jtag_debug_payload[448 +: 32] = head_activation_checksum_q;
    jtag_debug_payload[480 +: 32] = EXPECTED_HEAD_ACTIVATION_BYTE_CHECKSUM;
    jtag_debug_payload[512 +: 32] = embedding_token_checksum_q;
    jtag_debug_payload[544 +: 32] = EXPECTED_EMBED_TOKEN_CHECKSUM;
    jtag_debug_payload[576 +: 32] = embedding_position_checksum_q;
    jtag_debug_payload[608 +: 32] = EXPECTED_EMBED_POSITION_CHECKSUM;
    jtag_debug_payload[640 +: 32] = embedding_combined_checksum_q;
    jtag_debug_payload[672 +: 32] = EXPECTED_EMBED_COMBINED_CHECKSUM;
    jtag_debug_payload[704 +: 16] = 16'(EMBED_TOKEN_ID);
    jtag_debug_payload[720 +: 16] = 16'(EMBED_POSITION_ID);
  end

  always_comb begin
    vocab_loader_read_addr = VOCAB_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q);
    if (state_q == SELFTEST_CHECK_EMBED_TOKEN_SETUP) begin
      vocab_loader_read_addr =
        EMBED_TOKEN_BASE_WORD_ADDR + VOCAB_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q);
    end
  end

  generate
    if (PHASE_BANKED_VOCAB_LOADER_ROM != 0) begin : gen_phase_banked_vocab_loader_rom
      logic [VOCAB_PHASE_WIDTH - 1:0] vocab_loader_phase;
      logic [VOCAB_TILE_PACKED_WEIGHT_ADDR_WIDTH - 1:0] vocab_loader_tile_addr;
      logic [VOCAB_LANES * 8 - 1:0] vocab_packed_weight_phase_data
        [0:VOCAB_PHASES - 1];

      assign vocab_loader_phase =
        VOCAB_PHASE_WIDTH'(vocab_loader_read_addr / VOCAB_TILE_PACKED_WEIGHT_WORDS);
      assign vocab_loader_tile_addr =
        VOCAB_TILE_PACKED_WEIGHT_ADDR_WIDTH'(
          vocab_loader_read_addr % VOCAB_TILE_PACKED_WEIGHT_WORDS
        );

      for (
        genvar weight_phase = 0;
        weight_phase < VOCAB_PHASES;
        weight_phase = weight_phase + 1
      ) begin : gen_vocab_loader_phase_rom
        (* rom_style = "block", ram_style = "block" *)
        logic [VOCAB_LANES * 8 - 1:0] vocab_packed_weight_phase_rom
          [0:VOCAB_TILE_PACKED_WEIGHT_WORDS - 1];

`include "vocab_loader_phase_readmemh_cases.sv"

        always_ff @(posedge SYS_CLK) begin
          vocab_packed_weight_phase_data[weight_phase] <=
            vocab_packed_weight_phase_rom[vocab_loader_tile_addr];
        end
      end

      always_comb begin
        vocab_packed_weight_rom_data_q =
          vocab_packed_weight_phase_data[vocab_loader_phase];
      end
    end else begin : gen_block_vocab_loader_rom
      (* rom_style = "block", ram_style = "block" *)
      logic [VOCAB_LANES * 8 - 1:0] vocab_packed_weight_rom
        [0:VOCAB_PACKED_WEIGHT_WORDS - 1];

      initial begin
        $readmemh("vocab_packed_weights.mem", vocab_packed_weight_rom);
      end

      always_ff @(posedge SYS_CLK) begin
        vocab_packed_weight_rom_data_q <=
          vocab_packed_weight_rom[vocab_loader_read_addr];
      end
    end
  endgenerate

  always_comb begin
    residual_reset = selftest_reset;
    unique case (state_q)
      SELFTEST_BOOT,
      SELFTEST_CHECK_EMBED_TOKEN_SETUP,
      SELFTEST_CHECK_EMBED_TOKEN_ACCUM,
      SELFTEST_CHECK_EMBED_DONE,
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
      SELFTEST_CHECK_EMBED_TOKEN_SETUP,
      SELFTEST_CHECK_EMBED_TOKEN_ACCUM,
      SELFTEST_CHECK_EMBED_DONE,
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
      vocab_load_checksum_q <= '0;
      vocab_first_word_q <= '0;
      vocab_last_word_q <= '0;
      head_activation_checksum_q <= '0;
      embedding_token_checksum_q <= '0;
      embedding_position_checksum_q <= '0;
      embedding_combined_checksum_q <= '0;
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
      vocab_load_checksum_q <= '0;
      vocab_first_word_q <= '0;
      vocab_last_word_q <= '0;
      head_activation_checksum_q <= '0;
      embedding_token_checksum_q <= '0;
      embedding_position_checksum_q <= '0;
      embedding_combined_checksum_q <= '0;
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
              state_q <= SELFTEST_CHECK_EMBED_TOKEN_SETUP;
          end

          SELFTEST_CHECK_EMBED_TOKEN_SETUP: begin
            if (load_index_q == 32'd0) begin
              embedding_token_checksum_q <= '0;
              embedding_position_checksum_q <= '0;
              embedding_combined_checksum_q <= '0;
            end
            state_q <= SELFTEST_CHECK_EMBED_TOKEN_ACCUM;
          end

          SELFTEST_CHECK_EMBED_TOKEN_ACCUM: begin
            embedding_token_checksum_q <=
              embedding_token_checksum_q + {24'd0, embedding_token_value_w};
            embedding_position_checksum_q <=
              embedding_position_checksum_q + {24'd0, embedding_position_value_w};
            embedding_combined_checksum_q <=
              embedding_combined_checksum_q + {24'd0, embedding_combined_value_w};
            if (load_index_q == 32'(EMBED_WORDS - 1)) begin
              state_q <= SELFTEST_CHECK_EMBED_DONE;
            end else begin
              load_index_q <= load_index_q + 32'd1;
              state_q <= SELFTEST_CHECK_EMBED_TOKEN_SETUP;
            end
          end

          SELFTEST_CHECK_EMBED_DONE: begin
            if (embedding_token_checksum_q != EXPECTED_EMBED_TOKEN_CHECKSUM ||
                embedding_position_checksum_q != EXPECTED_EMBED_POSITION_CHECKSUM ||
                embedding_combined_checksum_q != EXPECTED_EMBED_COMBINED_CHECKSUM) begin
              fail_reason_q <= FAIL_REASON_EMBEDDING_MISMATCH;
              fail_index_q <= C_PROJ_OUT_ADDR_WIDTH'(load_index_q);
              state_q <= SELFTEST_FAIL;
            end else begin
              load_index_q <= 32'd0;
              state_q <= SELFTEST_LOAD_C_FC_ACTIVATION;
            end
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
            if (load_index_q == 32'd0) begin
              vocab_load_checksum_q <= '0;
              vocab_first_word_q <= '0;
              vocab_last_word_q <= '0;
            end
            state_q <= SELFTEST_LOAD_VOCAB_WEIGHT_WRITE;
          end

          SELFTEST_LOAD_VOCAB_WEIGHT_WRITE: begin
            vocab_load_checksum_q <=
              vocab_load_checksum_q + vocab_packed_weight_rom_data_q;
            if (load_index_q == 32'd0)
              vocab_first_word_q <= vocab_packed_weight_rom_data_q;
            if (load_index_q == 32'(VOCAB_PACKED_WEIGHT_WORDS - 1))
              vocab_last_word_q <= vocab_packed_weight_rom_data_q;
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
            if (activation_index_q == '0)
              head_activation_checksum_q <= '0;
            state_q <= SELFTEST_LOAD_HEAD_ACTIVATION_WRITE;
          end

          SELFTEST_LOAD_HEAD_ACTIVATION_WRITE: begin
            head_activation_checksum_q <=
              head_activation_checksum_q + {24'd0, residual_output_read_data};
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

  generate
    if (VOCAB_WEIGHT_MODE == 2) begin : gen_ternary_base3_output_head
      task6_ternary_base3_vocab_output_head_top1_kernel #(
        .IN_DIM(VOCAB_IN_DIM),
        .VOCAB_SIZE(VOCAB_SIZE),
        .VALID_VOCAB_SIZE(VOCAB_VALID_SIZE),
        .TILE_OUT_DIM(VOCAB_TILE_OUT_DIM),
        .ACC_WIDTH(VOCAB_ACC_WIDTH),
        .PACKED_WEIGHT_WORDS(VOCAB_PACKED_WEIGHT_WORDS)
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
    end else if (VOCAB_WEIGHT_MODE == 1) begin : gen_ternary_output_head
      task6_ternary_vocab_output_head_top1_kernel #(
        .IN_DIM(VOCAB_IN_DIM),
        .VOCAB_SIZE(VOCAB_SIZE),
        .VALID_VOCAB_SIZE(VOCAB_VALID_SIZE),
        .TILE_OUT_DIM(VOCAB_TILE_OUT_DIM),
        .ACC_WIDTH(VOCAB_ACC_WIDTH),
        .PACKED_WEIGHT_WORDS(VOCAB_PACKED_WEIGHT_WORDS)
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
    end else begin : gen_int8_output_head
      task6_int8_vocab_output_head_top1_kernel #(
        .IN_DIM(VOCAB_IN_DIM),
        .VOCAB_SIZE(VOCAB_SIZE),
        .VALID_VOCAB_SIZE(VOCAB_VALID_SIZE),
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
    end
  endgenerate

  generate
    if (ENABLE_JTAG_DEBUG != 0) begin : gen_jtag_debug
      task6_v4k_jtag_debug_shift #(
        .WIDTH(JTAG_DEBUG_WIDTH),
        .JTAG_CHAIN(1)
      ) jtag_debug_shift (
        .payload_i(jtag_debug_payload)
      );
    end
  endgenerate
endmodule

module task6_v4k_jtag_debug_shift #(
  parameter int WIDTH = 256,
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
