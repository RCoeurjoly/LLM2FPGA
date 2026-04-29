`timescale 1ns/1ps

module task6_int8_l2_mlp_chain_residual_add_selftest_top(
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);
  `include "tb_data.sv"

  localparam logic [31:0] TIMEOUT_CYCLES = 32'd50000000;
  localparam logic [7:0] BOOT_RESET_CYCLES = 8'd16;
  localparam logic [C_PROJ_OUT_ADDR_WIDTH - 1:0] LAST_C_PROJ_OUT_INDEX =
    C_PROJ_OUT_ADDR_WIDTH'(C_PROJ_OUT_DIM - 1);

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
  logic [25:0] blink_count_q;
  logic [7:0] config_reset_count_q = 8'd0;
  logic config_reset_done;
  logic selftest_reset;

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
      blink_count_q <= 26'd0;
    end else if (!config_reset_done) begin
      state_q <= SELFTEST_BOOT;
      boot_count_q <= 8'd0;
      load_index_q <= 13'd0;
      check_index_q <= '0;
      cycle_count_q <= 32'd0;
      blink_count_q <= 26'd0;
    end else begin
      blink_count_q <= blink_count_q + 26'd1;

      if (boot_count_q <= BOOT_RESET_CYCLES)
        boot_count_q <= boot_count_q + 8'd1;

      if ((state_q == SELFTEST_RUN ||
           state_q == SELFTEST_READ_SETUP ||
           state_q == SELFTEST_READ_CHECK) &&
          cycle_count_q >= TIMEOUT_CYCLES) begin
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
            state_q <= SELFTEST_FAIL;
          end
        endcase
      end
    end
  end

  assign led_3bits_tri_o[0] = blink_count_q[25];
  assign led_3bits_tri_o[1] = (state_q == SELFTEST_PASS);
  assign led_3bits_tri_o[2] = (state_q == SELFTEST_FAIL);

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
    .output_read_data(output_read_data)
  );
endmodule
