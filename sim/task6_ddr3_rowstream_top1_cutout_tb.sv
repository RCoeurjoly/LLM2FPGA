`timescale 1ns/1ps

module task6_ddr3_rowstream_top1_cutout_tb;
  `include "tb_data.sv"

  localparam int TIMEOUT_CYCLES = (VOCAB_SIZE + 16) * SAMPLE_COUNT + 1000;

  logic clock;
  logic reset;
  logic start;
  wire source_busy;
  wire source_done;
  wire row_valid;
  wire row_ready;
  wire [15:0] row_token_id;
  wire [HIDDEN_SIZE * 8 - 1:0] row_weight_q_i8;
  wire [31:0] row_sidecar_word;
  wire row_last;
  logic [HIDDEN_SIZE * 8 - 1:0] hidden_q_i8;
  wire out_valid;
  wire out_error_reserved_bits;
  wire [15:0] out_top_token_id;
  wire signed [45:0] out_top_score_signed_q024;

  integer cycles;
  integer sample_rows;
  integer total_rows;
  integer errors;

  task6_ddr3_rowstream_mem_source #(
    .HIDDEN_SIZE(HIDDEN_SIZE),
    .VOCAB_SIZE(VOCAB_SIZE),
    .PADDED_ROWS(PADDED_ROWS),
    .ROW_BYTES(ROW_BYTES),
    .ROW_MEM_HEX(ROWSTREAM_MEM_FILE)
  ) source (
    .clock(clock),
    .reset(reset),
    .start(start),
    .busy(source_busy),
    .done(source_done),
    .row_valid(row_valid),
    .row_ready(row_ready),
    .row_token_id(row_token_id),
    .row_weight_q_i8(row_weight_q_i8),
    .row_sidecar_word(row_sidecar_word),
    .row_last(row_last)
  );

  task6_ddr3_rowstream_top1_cutout #(
    .HIDDEN_SIZE(HIDDEN_SIZE),
    .ACC_WIDTH(22)
  ) cutout (
    .clock(clock),
    .reset(reset),
    .row_valid(row_valid),
    .row_ready(row_ready),
    .row_token_id(row_token_id),
    .row_weight_q_i8(row_weight_q_i8),
    .row_sidecar_word(row_sidecar_word),
    .row_last(row_last),
    .hidden_q_i8(hidden_q_i8),
    .out_valid(out_valid),
    .out_error_reserved_bits(out_error_reserved_bits),
    .out_top_token_id(out_top_token_id),
    .out_top_score_signed_q024(out_top_score_signed_q024)
  );

  always #5 clock = ~clock;

  task automatic load_hidden(input int sample_index);
    int hidden_index;
    begin
      hidden_q_i8 = '0;
      for (hidden_index = 0; hidden_index < HIDDEN_SIZE; hidden_index = hidden_index + 1) begin
        hidden_q_i8[hidden_index * 8 +: 8] =
          hidden_q_values[sample_index * HIDDEN_SIZE + hidden_index];
      end
    end
  endtask

  task automatic run_sample(input int sample_index);
    begin
      load_hidden(sample_index);
      sample_rows = 0;
      reset = 1'b1;
      start = 1'b0;
      repeat (3) @(negedge clock);
      reset = 1'b0;
      @(negedge clock);
      start = 1'b1;
      @(negedge clock);
      start = 1'b0;

      wait (source_done);
      @(posedge clock);
      #1;

      if (sample_rows != VOCAB_SIZE) begin
        $display(
          "FAIL: sample %0d row count expected %0d got %0d",
          sample_index,
          VOCAB_SIZE,
          sample_rows
        );
        errors = errors + 1;
      end
      if (out_error_reserved_bits) begin
        $display("FAIL: sample %0d saw nonzero reserved sidecar bits", sample_index);
        errors = errors + 1;
      end
      if (out_top_token_id !== expected_top_token[sample_index]) begin
        $display(
          "FAIL: sample %0d top token expected %0d got %0d",
          sample_index,
          expected_top_token[sample_index],
          out_top_token_id
        );
        errors = errors + 1;
      end
      if (out_top_score_signed_q024 !== expected_top_score_q024[sample_index]) begin
        $display(
          "FAIL: sample %0d top score expected %0d got %0d",
          sample_index,
          expected_top_score_q024[sample_index],
          out_top_score_signed_q024
        );
        errors = errors + 1;
      end

      if (errors == 0) begin
        $display(
          "PASS: sample %0d rows %0d top_token %0d top_score %0d",
          sample_index,
          sample_rows,
          out_top_token_id,
          out_top_score_signed_q024
        );
      end
      total_rows = total_rows + sample_rows;
      repeat (2) @(negedge clock);
    end
  endtask

  initial begin : init_control
    integer sample_index;

    clock = 1'b0;
    reset = 1'b1;
    start = 1'b0;
    hidden_q_i8 = '0;
    cycles = 0;
    sample_rows = 0;
    total_rows = 0;
    errors = 0;

    repeat (2) @(negedge clock);
    for (sample_index = 0; sample_index < SAMPLE_COUNT; sample_index = sample_index + 1) begin
      run_sample(sample_index);
    end

    if (errors == 0) begin
      $display(
        "PASS: task6 ddr3 rowstream top1 cutout samples %0d rows_per_sample %0d total_rows %0d cycles %0d",
        SAMPLE_COUNT,
        VOCAB_SIZE,
        total_rows,
        cycles
      );
      $finish;
    end else begin
      $display("FAIL: task6 ddr3 rowstream top1 cutout errors %0d", errors);
      $fatal(1);
    end
  end

  always_ff @(posedge clock) begin
    if (!reset)
      cycles <= cycles + 1;
    if (!reset && row_valid && row_ready)
      sample_rows <= sample_rows + 1;
    if (!reset && cycles > TIMEOUT_CYCLES)
      $fatal(1, "Timeout waiting for task6 DDR3 rowstream cutout completion");
  end
endmodule
