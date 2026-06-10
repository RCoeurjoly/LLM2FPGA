`timescale 1ns/1ps

module task6_ddr3_rowstream_wb_top1_reader #(
  parameter int HIDDEN_SIZE = 64,
  parameter int VOCAB_SIZE = 50257,
  parameter int ROW_BYTES = 68,
  parameter int WB_ADDR_BITS = 25,
  parameter int WB_DATA_BITS = 128,
  parameter int WB_SEL_BITS = WB_DATA_BITS / 8,
  parameter bit REVERSE_WB_BEAT_BYTES = 1'b0,
  parameter int ADDR_WIDTH = (VOCAB_SIZE <= 1) ? 1 : $clog2(VOCAB_SIZE)
)(
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic                            start_i,
  output logic                            busy_o,
  output logic                            done_o,
  output logic                            error_o,

  output logic                            wb_cyc_o,
  output logic                            wb_stb_o,
  output logic                            wb_we_o,
  output logic [WB_ADDR_BITS - 1:0]       wb_addr_o,
  output logic [WB_DATA_BITS - 1:0]       wb_data_o,
  output logic [WB_SEL_BITS - 1:0]        wb_sel_o,
  input  logic                            wb_stall_i,
  input  logic                            wb_ack_i,
  input  logic                            wb_err_i,
  input  logic [WB_DATA_BITS - 1:0]       wb_data_i,

  output logic                            row_valid_o,
  input  logic                            row_ready_i,
  output logic [15:0]                     row_token_id_o,
  output logic [HIDDEN_SIZE * 8 - 1:0]    row_weight_q_i8_o,
  output logic [31:0]                     row_sidecar_word_o,
  output logic                            row_last_o,
  output logic [63:0]                     debug_first_row_sidecar_beat_o,
  output logic                            debug_first_row_sidecar_beat_valid_o
);
  localparam int WB_BYTES = WB_SEL_BITS;
  localparam int WB_BYTE_SHIFT = $clog2(WB_BYTES);
  localparam int ROW_WINDOW_BEATS = ((ROW_BYTES + WB_BYTES - 1) / WB_BYTES) + 1;
  localparam int ROW_WINDOW_BITS = ROW_WINDOW_BEATS * WB_DATA_BITS;
  localparam int BYTE_OFFSET_BITS = $clog2(VOCAB_SIZE * ROW_BYTES + WB_BYTES);

  typedef enum logic [2:0] {
    S_IDLE = 3'd0,
    S_ISSUE = 3'd1,
    S_WAIT_ACK = 3'd2,
    S_EMIT = 3'd3,
    S_ERROR = 3'd4,
    S_FINALIZE = 3'd5
  } state_t;

  state_t state_q;
  logic [ADDR_WIDTH - 1:0] row_index_q;
  logic [$clog2(ROW_WINDOW_BEATS) - 1:0] beat_index_q;
  logic [ROW_WINDOW_BITS - 1:0] row_window_q;
  logic [WB_BYTE_SHIFT - 1:0] row_phase_q;
  logic [BYTE_OFFSET_BITS - 1:0] row_byte_offset;
  logic [BYTE_OFFSET_BITS - 1:0] next_row_byte_offset;
  logic [WB_ADDR_BITS - 1:0] row_base_beat;
  logic [WB_ADDR_BITS - 1:0] next_row_base_beat;
  logic [WB_BYTE_SHIFT - 1:0] next_row_phase;
  logic [WB_ADDR_BITS - 1:0] next_beat_addr;
  logic row_fire;
  logic [WB_DATA_BITS - 1:0] captured_wb_data;
  localparam int FIRST_ROW_SIDECAR_BEAT = HIDDEN_SIZE / WB_BYTES;

  always_comb begin
    captured_wb_data = wb_data_i;
    if (REVERSE_WB_BEAT_BYTES) begin
      for (int lane = 0; lane < WB_SEL_BITS; lane = lane + 1) begin
        captured_wb_data[lane * 8 +: 8] = wb_data_i[(WB_SEL_BITS - 1 - lane) * 8 +: 8];
      end
    end
  end

  assign row_fire = row_valid_o && row_ready_i;
  assign row_byte_offset = BYTE_OFFSET_BITS'(row_index_q) * BYTE_OFFSET_BITS'(ROW_BYTES);
  assign next_row_byte_offset = row_byte_offset + BYTE_OFFSET_BITS'(ROW_BYTES);
  assign row_base_beat = WB_ADDR_BITS'(row_byte_offset[BYTE_OFFSET_BITS - 1:WB_BYTE_SHIFT]);
  assign next_row_base_beat = WB_ADDR_BITS'(next_row_byte_offset[BYTE_OFFSET_BITS - 1:WB_BYTE_SHIFT]);
  assign next_row_phase = next_row_byte_offset[WB_BYTE_SHIFT - 1:0];
  assign next_beat_addr = row_base_beat + WB_ADDR_BITS'(32'(beat_index_q) + 32'd1);
  assign row_token_id_o = 16'(row_index_q);
  assign row_last_o = row_valid_o && row_index_q == ADDR_WIDTH'(VOCAB_SIZE - 1);
  assign wb_we_o = 1'b0;
  assign wb_data_o = '0;
  assign wb_sel_o = {WB_SEL_BITS{1'b1}};

  generate
    if (WB_BYTES == 8) begin : gen_extract_wb8
      always_comb begin
        row_weight_q_i8_o = '0;
        row_sidecar_word_o = 32'd0;
        unique case (row_phase_q)
          3'd0: begin
            row_weight_q_i8_o = row_window_q[0 +: HIDDEN_SIZE * 8];
            row_sidecar_word_o = row_window_q[HIDDEN_SIZE * 8 +: 32];
          end
          3'd4: begin
            row_weight_q_i8_o = row_window_q[32 +: HIDDEN_SIZE * 8];
            row_sidecar_word_o = row_window_q[32 + HIDDEN_SIZE * 8 +: 32];
          end
          default: begin
            row_weight_q_i8_o = '0;
            row_sidecar_word_o = 32'd1;
          end
        endcase
      end
    end else if (WB_BYTES == 16) begin : gen_extract_wb16
      always_comb begin
        row_weight_q_i8_o = '0;
        row_sidecar_word_o = 32'd0;
        unique case (row_phase_q)
          4'd0: begin
            row_weight_q_i8_o = row_window_q[0 +: HIDDEN_SIZE * 8];
            row_sidecar_word_o = row_window_q[HIDDEN_SIZE * 8 +: 32];
          end
          4'd4: begin
            row_weight_q_i8_o = row_window_q[32 +: HIDDEN_SIZE * 8];
            row_sidecar_word_o = row_window_q[32 + HIDDEN_SIZE * 8 +: 32];
          end
          4'd8: begin
            row_weight_q_i8_o = row_window_q[64 +: HIDDEN_SIZE * 8];
            row_sidecar_word_o = row_window_q[64 + HIDDEN_SIZE * 8 +: 32];
          end
          4'd12: begin
            row_weight_q_i8_o = row_window_q[96 +: HIDDEN_SIZE * 8];
            row_sidecar_word_o = row_window_q[96 + HIDDEN_SIZE * 8 +: 32];
          end
          default: begin
            row_weight_q_i8_o = '0;
            row_sidecar_word_o = 32'd1;
          end
        endcase
      end
    end else begin : gen_extract_generic
      logic [31:0] row_sidecar_start_byte;

      assign row_sidecar_start_byte = 32'(row_phase_q) + 32'(HIDDEN_SIZE);
      assign row_weight_q_i8_o = row_window_q[row_phase_q * 8 +: HIDDEN_SIZE * 8];
      assign row_sidecar_word_o = row_window_q[row_sidecar_start_byte * 8 +: 32];
    end
  endgenerate

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      row_index_q <= '0;
      beat_index_q <= '0;
      row_window_q <= '0;
      row_phase_q <= '0;
      debug_first_row_sidecar_beat_o <= 64'd0;
      debug_first_row_sidecar_beat_valid_o <= 1'b0;
      busy_o <= 1'b0;
      done_o <= 1'b0;
      error_o <= 1'b0;
      wb_cyc_o <= 1'b0;
      wb_stb_o <= 1'b0;
      wb_addr_o <= '0;
      row_valid_o <= 1'b0;
    end else begin
      done_o <= 1'b0;

      case (state_q)
      S_IDLE: begin
        wb_cyc_o <= 1'b0;
        wb_stb_o <= 1'b0;
        row_valid_o <= 1'b0;
        busy_o <= 1'b0;
        if (start_i) begin
          busy_o <= 1'b1;
          error_o <= 1'b0;
          row_index_q <= '0;
          beat_index_q <= '0;
          row_window_q <= '0;
          row_phase_q <= '0;
          debug_first_row_sidecar_beat_o <= 64'd0;
          debug_first_row_sidecar_beat_valid_o <= 1'b0;
          wb_addr_o <= '0;
          wb_cyc_o <= 1'b1;
          wb_stb_o <= 1'b1;
          state_q <= S_ISSUE;
        end
      end

      S_ISSUE: begin
        if (wb_err_i) begin
          wb_cyc_o <= 1'b0;
          wb_stb_o <= 1'b0;
          error_o <= 1'b1;
          busy_o <= 1'b0;
          state_q <= S_ERROR;
        end else if (!wb_stall_i) begin
          wb_stb_o <= 1'b0;
          if (wb_ack_i) begin
            wb_cyc_o <= 1'b0;
            row_window_q[beat_index_q * WB_DATA_BITS +: WB_DATA_BITS] <= captured_wb_data;
            if (row_index_q == '0 && 32'(beat_index_q) == 32'(FIRST_ROW_SIDECAR_BEAT)) begin
              debug_first_row_sidecar_beat_o <= captured_wb_data[0 +: 64];
              debug_first_row_sidecar_beat_valid_o <= 1'b1;
            end
            if (beat_index_q == $clog2(ROW_WINDOW_BEATS)'(ROW_WINDOW_BEATS - 1)) begin
              state_q <= S_FINALIZE;
            end else begin
              beat_index_q <= beat_index_q + 1'b1;
              wb_addr_o <= next_beat_addr;
              wb_cyc_o <= 1'b1;
              wb_stb_o <= 1'b1;
              state_q <= S_ISSUE;
            end
          end else begin
            state_q <= S_WAIT_ACK;
          end
        end
      end

      S_WAIT_ACK: begin
        if (wb_err_i) begin
          wb_cyc_o <= 1'b0;
          error_o <= 1'b1;
          busy_o <= 1'b0;
          state_q <= S_ERROR;
        end else if (wb_ack_i) begin
          wb_cyc_o <= 1'b0;
          row_window_q[beat_index_q * WB_DATA_BITS +: WB_DATA_BITS] <= captured_wb_data;
          if (row_index_q == '0 && 32'(beat_index_q) == 32'(FIRST_ROW_SIDECAR_BEAT)) begin
            debug_first_row_sidecar_beat_o <= captured_wb_data[0 +: 64];
            debug_first_row_sidecar_beat_valid_o <= 1'b1;
          end
          if (beat_index_q == $clog2(ROW_WINDOW_BEATS)'(ROW_WINDOW_BEATS - 1)) begin
            state_q <= S_FINALIZE;
          end else begin
            beat_index_q <= beat_index_q + 1'b1;
            wb_addr_o <= next_beat_addr;
            wb_cyc_o <= 1'b1;
            wb_stb_o <= 1'b1;
            state_q <= S_ISSUE;
          end
        end
      end

      S_FINALIZE: begin
        row_valid_o <= 1'b1;
        state_q <= S_EMIT;
      end

      S_EMIT: begin
        if (row_fire) begin
          row_valid_o <= 1'b0;
          if (row_index_q == ADDR_WIDTH'(VOCAB_SIZE - 1)) begin
            busy_o <= 1'b0;
            done_o <= 1'b1;
            state_q <= S_IDLE;
          end else begin
            row_index_q <= row_index_q + 1'b1;
            beat_index_q <= '0;
            row_window_q <= '0;
            row_phase_q <= next_row_phase;
            wb_addr_o <= next_row_base_beat;
            wb_cyc_o <= 1'b1;
            wb_stb_o <= 1'b1;
            state_q <= S_ISSUE;
          end
        end
      end

      S_ERROR: begin
        wb_cyc_o <= 1'b0;
        wb_stb_o <= 1'b0;
        row_valid_o <= 1'b0;
        busy_o <= 1'b0;
        if (start_i) begin
          error_o <= 1'b0;
          row_index_q <= '0;
          beat_index_q <= '0;
          row_window_q <= '0;
          row_phase_q <= '0;
          debug_first_row_sidecar_beat_o <= 64'd0;
          debug_first_row_sidecar_beat_valid_o <= 1'b0;
          busy_o <= 1'b1;
          wb_addr_o <= '0;
          wb_cyc_o <= 1'b1;
          wb_stb_o <= 1'b1;
          state_q <= S_ISSUE;
        end
      end

      default: state_q <= S_IDLE;
      endcase
    end
  end
endmodule
