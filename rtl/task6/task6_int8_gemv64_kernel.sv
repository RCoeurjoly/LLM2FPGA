`timescale 1ns/1ps

module task6_int8_gemv64_kernel #(
  parameter int IN_DIM = 64,
  parameter int OUT_DIM = 64,
  parameter int ACC_WIDTH = 32,
  parameter int IN_ADDR_WIDTH = (IN_DIM <= 1) ? 1 : $clog2(IN_DIM),
  parameter int WEIGHT_ADDR_WIDTH = (IN_DIM * OUT_DIM <= 1) ? 1 : $clog2(IN_DIM * OUT_DIM),
  parameter int OUT_ADDR_WIDTH = (OUT_DIM <= 1) ? 1 : $clog2(OUT_DIM)
)(
  input  logic clock,
  input  logic reset,
  input  logic start,
  output logic busy,
  output logic done,

  output logic [IN_ADDR_WIDTH - 1:0] activation_addr,
  input  logic signed [7:0] activation_data,

  output logic [WEIGHT_ADDR_WIDTH - 1:0] weight_addr,
  input  logic signed [7:0] weight_data,

  output logic [OUT_ADDR_WIDTH - 1:0] out_addr,
  output logic signed [ACC_WIDTH - 1:0] out_data,
  output logic out_valid,
  input  logic out_ready
);
  localparam int PRODUCT_WIDTH = 16;
  localparam logic [IN_ADDR_WIDTH - 1:0] LAST_IN_INDEX = IN_ADDR_WIDTH'(IN_DIM - 1);
  localparam logic [OUT_ADDR_WIDTH - 1:0] LAST_OUT_INDEX = OUT_ADDR_WIDTH'(OUT_DIM - 1);

  typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_RUN,
    STATE_EMIT
  } state_t;

  state_t state_q;
  logic [IN_ADDR_WIDTH - 1:0] in_index_q;
  logic [OUT_ADDR_WIDTH - 1:0] out_index_q;
  logic [WEIGHT_ADDR_WIDTH - 1:0] weight_index_q;
  logic signed [ACC_WIDTH - 1:0] acc_q;
  logic signed [PRODUCT_WIDTH - 1:0] product_w;
  logic signed [ACC_WIDTH - 1:0] product_ext_w;
  logic signed [ACC_WIDTH - 1:0] acc_next_w;

  assign busy = state_q != STATE_IDLE;
  assign activation_addr = in_index_q;
  assign weight_addr = weight_index_q;

  assign product_w = activation_data * weight_data;
  assign product_ext_w = {{(ACC_WIDTH - PRODUCT_WIDTH){product_w[PRODUCT_WIDTH - 1]}}, product_w};
  assign acc_next_w = acc_q + product_ext_w;

  always_ff @(posedge clock) begin
    if (reset) begin
      state_q <= STATE_IDLE;
      done <= 1'b0;
      in_index_q <= '0;
      out_index_q <= '0;
      weight_index_q <= '0;
      acc_q <= '0;
      out_addr <= '0;
      out_data <= '0;
      out_valid <= 1'b0;
    end else begin
      done <= 1'b0;
      case (state_q)
        STATE_IDLE: begin
          out_valid <= 1'b0;
          if (start) begin
            state_q <= STATE_RUN;
            in_index_q <= '0;
            out_index_q <= '0;
            weight_index_q <= '0;
            acc_q <= '0;
          end
        end

        STATE_RUN: begin
          acc_q <= acc_next_w;
          if (in_index_q == LAST_IN_INDEX) begin
            out_addr <= out_index_q;
            out_data <= acc_next_w;
            out_valid <= 1'b1;
            in_index_q <= '0;
            weight_index_q <= weight_index_q + 1'b1;
            state_q <= STATE_EMIT;
          end else begin
            in_index_q <= in_index_q + 1'b1;
            weight_index_q <= weight_index_q + 1'b1;
          end
        end

        STATE_EMIT: begin
          if (out_valid && out_ready) begin
            out_valid <= 1'b0;
            acc_q <= '0;
            if (out_index_q == LAST_OUT_INDEX) begin
              done <= 1'b1;
              state_q <= STATE_IDLE;
            end else begin
              out_index_q <= out_index_q + 1'b1;
              state_q <= STATE_RUN;
            end
          end
        end

        default: begin
          state_q <= STATE_IDLE;
        end
      endcase
    end
  end
endmodule
