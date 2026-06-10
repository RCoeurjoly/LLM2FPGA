`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_accel_top (
  input logic SYS_CLK,
  input logic SYS_RSTN,
  input logic [511:0] pcie_accel_activation_i,
  input logic [511:0] pcie_accel_residual_i,
  input logic pcie_accel_start_pulse_i,
  input logic pcie_accel_clear_pulse_i,
  output logic [31:0] pcie_accel_status_o,
  output logic [31:0] pcie_accel_cycle_count_o,
  output logic [31:0] pcie_accel_output_checksum_o,
  output logic [31:0] pcie_accel_output_sample0_o,
  output logic [31:0] pcie_accel_output_sample1_o,
  output logic [511:0] pcie_accel_output_vector_o
);
  `include "tb_data.sv"

  typedef enum logic [3:0] {
    BOOT_LOAD_C_FC_WEIGHT,
    BOOT_LOAD_C_FC_REQUANT,
    BOOT_LOAD_C_PROJ_WEIGHT,
    BOOT_LOAD_C_PROJ_REQUANT,
    ACCEL_IDLE,
    ACCEL_LOAD_ACTIVATION,
    ACCEL_LOAD_RESIDUAL,
    ACCEL_START,
    ACCEL_RUN,
    ACCEL_READ_SETUP,
    ACCEL_READ_ACCUM,
    ACCEL_DONE,
    ACCEL_ERROR
  } accel_state_t;

  localparam logic [12:0] LAST_C_FC_WEIGHT_INDEX =
    13'(C_FC_PACKED_WEIGHT_WORDS - 1);
  localparam logic [12:0] LAST_C_FC_REQUANT_INDEX =
    13'(HIDDEN_DIM - 1);
  localparam logic [12:0] LAST_C_PROJ_WEIGHT_INDEX =
    13'(C_PROJ_PACKED_WEIGHT_WORDS - 1);
  localparam logic [12:0] LAST_C_PROJ_REQUANT_INDEX =
    13'(C_PROJ_OUT_DIM - 1);
  localparam logic [5:0] LAST_OUTPUT_INDEX = 6'(C_PROJ_OUT_DIM - 1);

  accel_state_t state_q;
  logic [12:0] load_index_q;
  logic [5:0] accel_index_q;
  logic [31:0] cycle_count_q;
  logic [31:0] start_count_q;
  logic ready_q;
  logic output_valid_q;
  logic error_q;
  logic start;
  logic busy;
  logic done;
  logic dut_reset;

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

  assign start = state_q == ACCEL_START;
  assign dut_reset =
    !SYS_RSTN ||
    state_q == BOOT_LOAD_C_FC_WEIGHT ||
    state_q == BOOT_LOAD_C_FC_REQUANT ||
    state_q == BOOT_LOAD_C_PROJ_WEIGHT ||
    state_q == BOOT_LOAD_C_PROJ_REQUANT ||
    state_q == ACCEL_LOAD_ACTIVATION ||
    state_q == ACCEL_LOAD_RESIDUAL;

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
    output_read_addr = C_PROJ_OUT_ADDR_WIDTH'(accel_index_q);

    unique case (state_q)
      BOOT_LOAD_C_FC_WEIGHT: begin
        c_fc_weight_load_valid = 1'b1;
        c_fc_weight_load_addr = C_FC_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q);
        c_fc_weight_load_data =
          c_fc_packed_weight_values[
            load_index_q[C_FC_PACKED_WEIGHT_ADDR_WIDTH - 1:0]
          ];
      end

      BOOT_LOAD_C_FC_REQUANT: begin
        c_fc_requant_load_valid = 1'b1;
        c_fc_requant_load_addr = HIDDEN_ADDR_WIDTH'(load_index_q);
        c_fc_requant_scale_mul_load_data =
          c_fc_requant_scale_mul_values[load_index_q[HIDDEN_ADDR_WIDTH - 1:0]];
        c_fc_requant_bias_q_load_data =
          c_fc_requant_bias_q_values[load_index_q[HIDDEN_ADDR_WIDTH - 1:0]];
      end

      BOOT_LOAD_C_PROJ_WEIGHT: begin
        c_proj_weight_load_valid = 1'b1;
        c_proj_weight_load_addr = C_PROJ_PACKED_WEIGHT_ADDR_WIDTH'(load_index_q);
        c_proj_weight_load_data =
          c_proj_packed_weight_values[
            load_index_q[C_PROJ_PACKED_WEIGHT_ADDR_WIDTH - 1:0]
          ];
      end

      BOOT_LOAD_C_PROJ_REQUANT: begin
        c_proj_requant_load_valid = 1'b1;
        c_proj_requant_load_addr = C_PROJ_OUT_ADDR_WIDTH'(load_index_q);
        c_proj_requant_scale_mul_load_data =
          c_proj_requant_scale_mul_values[
            load_index_q[C_PROJ_OUT_ADDR_WIDTH - 1:0]
          ];
        c_proj_requant_bias_q_load_data =
          c_proj_requant_bias_q_values[
            load_index_q[C_PROJ_OUT_ADDR_WIDTH - 1:0]
          ];
      end

      ACCEL_LOAD_ACTIVATION: begin
        c_fc_activation_load_valid = 1'b1;
        c_fc_activation_load_addr = C_FC_ACTIVATION_ADDR_WIDTH'(accel_index_q);
        c_fc_activation_load_data =
          pcie_accel_activation_i[accel_index_q * 8 +: 8];
      end

      ACCEL_LOAD_RESIDUAL: begin
        residual_load_valid = 1'b1;
        residual_load_addr = C_PROJ_OUT_ADDR_WIDTH'(accel_index_q);
        residual_load_data = pcie_accel_residual_i[accel_index_q * 8 +: 8];
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      state_q <= BOOT_LOAD_C_FC_WEIGHT;
      load_index_q <= 13'd0;
      accel_index_q <= 6'd0;
      cycle_count_q <= 32'd0;
      start_count_q <= 32'd0;
      ready_q <= 1'b0;
      output_valid_q <= 1'b0;
      error_q <= 1'b0;
      pcie_accel_output_checksum_o <= 32'd0;
      pcie_accel_output_sample0_o <= 32'd0;
      pcie_accel_output_sample1_o <= 32'd0;
      pcie_accel_output_vector_o <= 512'd0;
    end else begin
      if (pcie_accel_clear_pulse_i) begin
        output_valid_q <= 1'b0;
        error_q <= 1'b0;
        cycle_count_q <= 32'd0;
        pcie_accel_output_checksum_o <= 32'd0;
        pcie_accel_output_sample0_o <= 32'd0;
        pcie_accel_output_sample1_o <= 32'd0;
        pcie_accel_output_vector_o <= 512'd0;
      end

      unique case (state_q)
        BOOT_LOAD_C_FC_WEIGHT: begin
          if (load_index_q == LAST_C_FC_WEIGHT_INDEX) begin
            load_index_q <= 13'd0;
            state_q <= BOOT_LOAD_C_FC_REQUANT;
          end else begin
            load_index_q <= load_index_q + 13'd1;
          end
        end

        BOOT_LOAD_C_FC_REQUANT: begin
          if (load_index_q == LAST_C_FC_REQUANT_INDEX) begin
            load_index_q <= 13'd0;
            state_q <= BOOT_LOAD_C_PROJ_WEIGHT;
          end else begin
            load_index_q <= load_index_q + 13'd1;
          end
        end

        BOOT_LOAD_C_PROJ_WEIGHT: begin
          if (load_index_q == LAST_C_PROJ_WEIGHT_INDEX) begin
            load_index_q <= 13'd0;
            state_q <= BOOT_LOAD_C_PROJ_REQUANT;
          end else begin
            load_index_q <= load_index_q + 13'd1;
          end
        end

        BOOT_LOAD_C_PROJ_REQUANT: begin
          if (load_index_q == LAST_C_PROJ_REQUANT_INDEX) begin
            load_index_q <= 13'd0;
            ready_q <= 1'b1;
            state_q <= ACCEL_IDLE;
          end else begin
            load_index_q <= load_index_q + 13'd1;
          end
        end

        ACCEL_IDLE: begin
          if (pcie_accel_start_pulse_i) begin
            start_count_q <= start_count_q + 32'd1;
            cycle_count_q <= 32'd0;
            output_valid_q <= 1'b0;
            error_q <= 1'b0;
            accel_index_q <= 6'd0;
            pcie_accel_output_checksum_o <= 32'd0;
            pcie_accel_output_sample0_o <= 32'd0;
            pcie_accel_output_sample1_o <= 32'd0;
            pcie_accel_output_vector_o <= 512'd0;
            state_q <= ACCEL_LOAD_ACTIVATION;
          end
        end

        ACCEL_LOAD_ACTIVATION: begin
          if (accel_index_q == LAST_OUTPUT_INDEX) begin
            accel_index_q <= 6'd0;
            state_q <= ACCEL_LOAD_RESIDUAL;
          end else begin
            accel_index_q <= accel_index_q + 6'd1;
          end
        end

        ACCEL_LOAD_RESIDUAL: begin
          if (accel_index_q == LAST_OUTPUT_INDEX) begin
            accel_index_q <= 6'd0;
            state_q <= ACCEL_START;
          end else begin
            accel_index_q <= accel_index_q + 6'd1;
          end
        end

        ACCEL_START: begin
          cycle_count_q <= 32'd0;
          state_q <= ACCEL_RUN;
        end

        ACCEL_RUN: begin
          cycle_count_q <= cycle_count_q + 32'd1;
          if (done) begin
            accel_index_q <= 6'd0;
            state_q <= ACCEL_READ_SETUP;
          end
        end

        ACCEL_READ_SETUP: begin
          state_q <= ACCEL_READ_ACCUM;
        end

        ACCEL_READ_ACCUM: begin
          pcie_accel_output_vector_o[accel_index_q * 8 +: 8] <=
            output_read_data;
          pcie_accel_output_checksum_o <=
            {pcie_accel_output_checksum_o[30:0],
             pcie_accel_output_checksum_o[31]} ^
            {{24{output_read_data[7]}}, output_read_data};
          if (accel_index_q[1:0] == 2'd0)
            pcie_accel_output_sample0_o[accel_index_q[4:2] * 8 +: 8] <=
              output_read_data;
          if (accel_index_q[1:0] == 2'd1)
            pcie_accel_output_sample1_o[accel_index_q[4:2] * 8 +: 8] <=
              output_read_data;

          if (accel_index_q == LAST_OUTPUT_INDEX) begin
            output_valid_q <= 1'b1;
            state_q <= ACCEL_DONE;
          end else begin
            accel_index_q <= accel_index_q + 6'd1;
            state_q <= ACCEL_READ_SETUP;
          end
        end

        ACCEL_DONE: begin
          if (pcie_accel_start_pulse_i) begin
            output_valid_q <= 1'b0;
            accel_index_q <= 6'd0;
            pcie_accel_output_checksum_o <= 32'd0;
            pcie_accel_output_sample0_o <= 32'd0;
            pcie_accel_output_sample1_o <= 32'd0;
            pcie_accel_output_vector_o <= 512'd0;
            state_q <= ACCEL_LOAD_ACTIVATION;
          end
        end

        ACCEL_ERROR: begin
          if (pcie_accel_clear_pulse_i)
            state_q <= ACCEL_IDLE;
        end

        default: begin
          error_q <= 1'b1;
          state_q <= ACCEL_ERROR;
        end
      endcase
    end
  end

  always_comb begin
    pcie_accel_status_o = {
      16'h4d4c,
      6'd0,
      state_q,
      output_valid_q,
      error_q,
      busy,
      ready_q
    };
    pcie_accel_cycle_count_o = cycle_count_q;
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
    .GELU_APPROX_MODE(GELU_APPROX_MODE),
    .GELU_PWL_X0(GELU_PWL_X0),
    .GELU_PWL_X1(GELU_PWL_X1),
    .GELU_PWL_X2(GELU_PWL_X2),
    .GELU_PWL_X3(GELU_PWL_X3),
    .GELU_PWL_X4(GELU_PWL_X4),
    .GELU_PWL_X5(GELU_PWL_X5),
    .GELU_PWL_X6(GELU_PWL_X6),
    .GELU_PWL_X7(GELU_PWL_X7),
    .GELU_PWL_X8(GELU_PWL_X8),
    .GELU_PWL_X9(GELU_PWL_X9),
    .GELU_PWL_X10(GELU_PWL_X10),
    .GELU_PWL_X11(GELU_PWL_X11),
    .GELU_PWL_X12(GELU_PWL_X12),
    .GELU_PWL_X13(GELU_PWL_X13),
    .GELU_PWL_X14(GELU_PWL_X14),
    .GELU_PWL_X15(GELU_PWL_X15),
    .GELU_PWL_Y0(GELU_PWL_Y0),
    .GELU_PWL_Y1(GELU_PWL_Y1),
    .GELU_PWL_Y2(GELU_PWL_Y2),
    .GELU_PWL_Y3(GELU_PWL_Y3),
    .GELU_PWL_Y4(GELU_PWL_Y4),
    .GELU_PWL_Y5(GELU_PWL_Y5),
    .GELU_PWL_Y6(GELU_PWL_Y6),
    .GELU_PWL_Y7(GELU_PWL_Y7),
    .GELU_PWL_Y8(GELU_PWL_Y8),
    .GELU_PWL_Y9(GELU_PWL_Y9),
    .GELU_PWL_Y10(GELU_PWL_Y10),
    .GELU_PWL_Y11(GELU_PWL_Y11),
    .GELU_PWL_Y12(GELU_PWL_Y12),
    .GELU_PWL_Y13(GELU_PWL_Y13),
    .GELU_PWL_Y14(GELU_PWL_Y14),
    .GELU_PWL_Y15(GELU_PWL_Y15),
    .OUTPUT_REQUANT_SHIFT(OUTPUT_REQUANT_SHIFT),
    .OUTPUT_REQUANT_MULT(OUTPUT_REQUANT_MULT),
    .C_PROJ_OUTPUT_REQUANT_SHIFT(C_PROJ_OUTPUT_REQUANT_SHIFT),
    .RESIDUAL_ADD_REQUANT_SHIFT(RESIDUAL_ADD_REQUANT_SHIFT),
    .RESIDUAL_REQUANT_MULT(RESIDUAL_REQUANT_MULT),
    .C_PROJ_RESIDUAL_ADD_REQUANT_MULT(C_PROJ_RESIDUAL_ADD_REQUANT_MULT)
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
endmodule
