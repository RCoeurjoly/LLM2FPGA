`timescale 1ns/1ps
`default_nettype none

module task6_ddr3_rowstream_wb_top1_reader_tb;
  localparam int HIDDEN_SIZE = 64;
  localparam int VOCAB_SIZE = 8;
  localparam int ROW_BYTES = 68;
  localparam int WB_ADDR_BITS = 8;
  `ifndef TASK6_TOP1_READER_WB_DATA_BITS
  `define TASK6_TOP1_READER_WB_DATA_BITS 128
`endif
  localparam int WB_DATA_BITS = `TASK6_TOP1_READER_WB_DATA_BITS;
  localparam int WB_SEL_BITS = WB_DATA_BITS / 8;
  `ifndef TASK6_TOP1_READER_REVERSE_WB_BEAT_BYTES
  `define TASK6_TOP1_READER_REVERSE_WB_BEAT_BYTES 0
`endif
  localparam bit REVERSE_WB_BEAT_BYTES = `TASK6_TOP1_READER_REVERSE_WB_BEAT_BYTES;
  localparam int TOTAL_BYTES = VOCAB_SIZE * ROW_BYTES;
  localparam int TOTAL_BEATS = (TOTAL_BYTES + WB_SEL_BITS - 1) / WB_SEL_BITS + 1;

  logic clk;
  logic rst_n;
  logic start;
  wire busy;
  wire done;
  wire error;
  wire wb_cyc;
  wire wb_stb;
  wire wb_we;
  wire [WB_ADDR_BITS - 1:0] wb_addr;
  wire [WB_DATA_BITS - 1:0] wb_data_o;
  wire [WB_SEL_BITS - 1:0] wb_sel;
  logic wb_stall;
  logic wb_ack;
  logic wb_err;
  logic [WB_DATA_BITS - 1:0] wb_data_i;
  wire row_valid;
  logic row_ready;
  wire [15:0] row_token_id;
  wire [HIDDEN_SIZE * 8 - 1:0] row_weight_q_i8;
  wire [31:0] row_sidecar_word;
  wire row_last;

  logic [7:0] image [0:TOTAL_BEATS * WB_SEL_BITS - 1];
  logic [WB_DATA_BITS - 1:0] beat_mem [0:TOTAL_BEATS - 1];
  int errors;
  int rows_seen;

  task6_ddr3_rowstream_wb_top1_reader #(
    .HIDDEN_SIZE(HIDDEN_SIZE),
    .VOCAB_SIZE(VOCAB_SIZE),
    .ROW_BYTES(ROW_BYTES),
    .WB_ADDR_BITS(WB_ADDR_BITS),
    .WB_DATA_BITS(WB_DATA_BITS),
    .WB_SEL_BITS(WB_SEL_BITS),
    .REVERSE_WB_BEAT_BYTES(REVERSE_WB_BEAT_BYTES)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .start_i(start),
    .busy_o(busy),
    .done_o(done),
    .error_o(error),
    .wb_cyc_o(wb_cyc),
    .wb_stb_o(wb_stb),
    .wb_we_o(wb_we),
    .wb_addr_o(wb_addr),
    .wb_data_o(wb_data_o),
    .wb_sel_o(wb_sel),
    .wb_stall_i(wb_stall),
    .wb_ack_i(wb_ack),
    .wb_err_i(wb_err),
    .wb_data_i(wb_data_i),
    .row_valid_o(row_valid),
    .row_ready_i(row_ready),
    .row_token_id_o(row_token_id),
    .row_weight_q_i8_o(row_weight_q_i8),
    .row_sidecar_word_o(row_sidecar_word),
    .row_last_o(row_last)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_ack <= 1'b0;
      wb_err <= 1'b0;
      wb_data_i <= '0;
    end else begin
      wb_ack <= wb_cyc && wb_stb && !wb_stall;
      wb_err <= 1'b0;
      if (wb_cyc && wb_stb && !wb_stall)
        wb_data_i <= beat_mem[$clog2(TOTAL_BEATS)'(wb_addr)];
    end
  end

  task automatic check(input bit condition, input string message);
    if (!condition) begin
      $display("FAIL: %s", message);
      errors++;
    end
  endtask

  task automatic check_row(input int row);
    int base;
    logic [31:0] expected_sidecar;
    begin
      base = row * ROW_BYTES;
      check(row_token_id == row[15:0], "row token id must match row index");
      for (int i = 0; i < HIDDEN_SIZE; i++)
        check(row_weight_q_i8[i * 8 +: 8] == image[base + i], "row weight byte must match packed image");
      expected_sidecar = {
        image[base + 67],
        image[base + 66],
        image[base + 65],
        image[base + 64]
      };
      check(row_sidecar_word == expected_sidecar, "row sidecar word must match packed image");
      check(row_last == (row == VOCAB_SIZE - 1), "row_last must mark only the final vocab row");
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;
    wb_stall = 1'b0;
    row_ready = 1'b1;
    errors = 0;
    rows_seen = 0;

    for (int i = 0; i < TOTAL_BEATS * WB_SEL_BITS; i++)
      image[i] = 8'h00;

    for (int row = 0; row < VOCAB_SIZE; row++) begin
      int base = row * ROW_BYTES;
      for (int i = 0; i < HIDDEN_SIZE; i++)
        image[base + i] = 8'(row * 17 + i);
      image[base + 64] = 8'(row);
      image[base + 65] = 8'(row + 32'h40);
      image[base + 66] = 8'(row + 32'h80);
      image[base + 67] = 8'h00;
    end

    for (int beat = 0; beat < TOTAL_BEATS; beat++) begin
      beat_mem[beat] = '0;
      for (int lane = 0; lane < WB_SEL_BITS; lane++) begin
        if (REVERSE_WB_BEAT_BYTES)
          beat_mem[beat][(WB_SEL_BITS - 1 - lane) * 8 +: 8] = image[beat * WB_SEL_BITS + lane];
        else
          beat_mem[beat][lane * 8 +: 8] = image[beat * WB_SEL_BITS + lane];
      end
    end

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    repeat (1000) begin
      @(negedge clk);
      if (row_valid && row_ready) begin
        check_row(rows_seen);
        rows_seen++;
      end
      if (done)
        break;
    end

    check(done, "reader must complete");
    check(!error, "reader must not report an error");
    check(rows_seen == VOCAB_SIZE, "reader must emit all vocab rows");
    check(!busy, "reader must drop busy after completion");

    if (errors == 0) begin
      $display("PASS: task6 DDR3 rowstream WB top1 reader rows %0d", rows_seen);
      $finish;
    end else begin
      $display("FAIL: task6 DDR3 rowstream WB top1 reader errors %0d", errors);
      $fatal(1);
    end
  end
endmodule

`default_nettype wire
