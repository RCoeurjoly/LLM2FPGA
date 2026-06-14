`timescale 1ns/1ps

module task6_m2_ln_attn_live_kv_all_heads_context_accel_tb;
  `include "task6_m2_ln_attn_live_kv_all_heads_context_tb_data.sv"

  localparam int TIMEOUT_CYCLES = 450000;
  localparam logic [2:0] S_DONE = 3'd6;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic start_i;
  logic clear_i;
  logic use_external_ln_input_i;
  logic [CACHE_SEQ*LN_DIM*16-1:0] external_ln_input_q12_by_token_i;
  logic [31:0] status_o;
  logic [31:0] cycle_count_o;
  logic [31:0] output_checksum_o;
  logic [31:0] output_sample0_o;
  logic [31:0] output_sample1_o;
  logic [511:0] output_vector_o;
  logic [31:0] debug_o;
  logic [31:0] debug1_o;
  logic [31:0] debug2_o;
  logic [511:0] expected_output_vector;
  logic [31:0] expected_checksum;
  logic [31:0] expected_sample0;
  logic [31:0] expected_sample1;
  integer cycles;

  task6_m2_ln_attn_live_kv_all_heads_context_accel_top #(
    .ENABLE_INTERNAL_CHECKS(1'b1)
  ) dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(start_i),
    .clear_i(clear_i),
    .use_external_ln_input_i(use_external_ln_input_i),
    .external_ln_input_q12_by_token_i(external_ln_input_q12_by_token_i),
    .status_o(status_o),
    .cycle_count_o(cycle_count_o),
    .output_checksum_o(output_checksum_o),
    .output_sample0_o(output_sample0_o),
    .output_sample1_o(output_sample1_o),
    .output_vector_o(output_vector_o),
    .debug_o(debug_o),
    .debug1_o(debug1_o),
    .debug2_o(debug2_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  task automatic pulse_start;
    begin
      start_i = 1'b1;
      @(posedge SYS_CLK);
      start_i = 1'b0;
    end
  endtask

  task automatic wait_done(input int pass_index);
    integer pass_cycles;
    begin
      pass_cycles = 0;
      while (pass_cycles < TIMEOUT_CYCLES) begin
        @(posedge SYS_CLK);
        pass_cycles = pass_cycles + 1;

        if (status_o[2]) begin
          $fatal(
            1,
            "FAIL: task6 M2 live-kv all-head context accel entered error pass=%0d status=%08x debug=%08x debug1=%08x debug2=%08x",
            pass_index,
            status_o,
            debug_o,
            debug1_o,
            debug2_o
          );
        end

        if (status_o[6:4] == S_DONE && status_o[3]) begin
          if (output_checksum_o !== expected_checksum) begin
            $fatal(
              1,
              "FAIL: checksum expected %08x got %08x pass=%0d",
              expected_checksum,
              output_checksum_o,
              pass_index
            );
          end
          if (output_sample0_o !== expected_sample0) begin
            $fatal(
              1,
              "FAIL: sample0 expected %08x got %08x pass=%0d",
              expected_sample0,
              output_sample0_o,
              pass_index
            );
          end
          if (output_sample1_o !== expected_sample1) begin
            $fatal(
              1,
              "FAIL: sample1 expected %08x got %08x pass=%0d",
              expected_sample1,
              output_sample1_o,
              pass_index
            );
          end
          if (output_vector_o !== expected_output_vector) begin
            $fatal(1, "FAIL: output vector mismatch pass=%0d", pass_index);
          end
          return;
        end
      end

      $fatal(
        1,
        "Timeout waiting for task6 M2 ln attn live-kv all-head context accel done pass=%0d",
        pass_index
      );
    end
  endtask

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    start_i = 1'b0;
    clear_i = 1'b0;
    use_external_ln_input_i = 1'b1;
    external_ln_input_q12_by_token_i = '0;
    expected_output_vector = 512'd0;
    expected_checksum = 32'd0;
    expected_sample0 = 32'd0;
    expected_sample1 = 32'd0;
    cycles = 0;

    for (int token = 0; token < CACHE_SEQ; token = token + 1) begin
      for (int dim = 0; dim < LN_DIM; dim = dim + 1) begin
        external_ln_input_q12_by_token_i[(token * LN_DIM + dim) * 16 +: 16] =
          ln_input_q12_by_token[token][dim];
      end
    end

    for (int dim = 0; dim < CONTEXT_DIM; dim = dim + 1) begin
      expected_output_vector[dim * 8 +: 8] = context_expected_q[dim];
      expected_checksum =
        expected_checksum + ({24'd0, context_expected_q[dim][7:0]} * (dim + 1));
      if (dim < 4) begin
        expected_sample0 =
          expected_sample0 | ({24'd0, context_expected_q[dim][7:0]} << (8 * dim[1:0]));
      end else if (dim < 8) begin
        expected_sample1 =
          expected_sample1 | ({24'd0, context_expected_q[dim][7:0]} << (8 * dim[1:0]));
      end
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);

    pulse_start();
    wait_done(1);

    clear_i = 1'b1;
    @(posedge SYS_CLK);
    clear_i = 1'b0;
    @(posedge SYS_CLK);
    if (status_o[6:4] != 3'd0 || !status_o[0]) begin
      $fatal(1, "FAIL: post-clear context status expected idle/ready got %08x", status_o);
    end

    pulse_start();
    wait_done(2);

    $display(
      "PASS: task6 M2 ln attn live-kv all-head context accel cycles %0d checksum %08x sample0 %08x sample1 %08x",
      cycle_count_o,
      output_checksum_o,
      output_sample0_o,
      output_sample1_o
    );
    $finish;
  end
endmodule
