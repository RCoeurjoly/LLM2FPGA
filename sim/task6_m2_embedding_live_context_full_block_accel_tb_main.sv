`timescale 1ns/1ps

module task6_m2_embedding_live_context_full_block_accel_tb;
  `include "tb_data.sv"
  `include "task6_m2_ln_attn_live_kv_all_heads_context_tb_data.sv"
  `include "task6_m2_embedding_block_input_tb_data.sv"

  localparam int TIMEOUT_CYCLES = 121000;
  localparam logic [2:0] ST_DONE = 3'd5;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic start_i;
  logic clear_i;
  logic [95:0] token_ids_i;
  logic [31:0] status_o;
  logic [31:0] cycle_count_o;
  logic [31:0] block_input_checksum_o;
  logic [31:0] context_checksum_o;
  logic [31:0] attn_out_checksum_o;
  logic [31:0] attn_residual_checksum_o;
  logic [31:0] ln2_checksum_o;
  logic [31:0] post_gelu_checksum_o;
  logic [31:0] c_proj_checksum_o;
  logic [31:0] final_checksum_o;
  logic [31:0] final_sample0_o;
  logic [31:0] final_sample1_o;
  logic [511:0] final_vector_o;
  logic [31:0] debug_o;
  logic [31:0] debug1_o;
  logic [31:0] debug2_o;
  logic [511:0] expected_final_vector;
  logic [31:0] expected_block_input_checksum;
  logic [31:0] expected_context_checksum;
  integer cycles;

  task6_m2_embedding_live_context_full_block_accel_top dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .start_i(start_i),
    .clear_i(clear_i),
    .token_ids_i(token_ids_i),
    .status_o(status_o),
    .cycle_count_o(cycle_count_o),
    .block_input_checksum_o(block_input_checksum_o),
    .context_checksum_o(context_checksum_o),
    .attn_out_checksum_o(attn_out_checksum_o),
    .attn_residual_checksum_o(attn_residual_checksum_o),
    .ln2_checksum_o(ln2_checksum_o),
    .post_gelu_checksum_o(post_gelu_checksum_o),
    .c_proj_checksum_o(c_proj_checksum_o),
    .final_checksum_o(final_checksum_o),
    .final_sample0_o(final_sample0_o),
    .final_sample1_o(final_sample1_o),
    .final_vector_o(final_vector_o),
    .debug_o(debug_o),
    .debug1_o(debug1_o),
    .debug2_o(debug2_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    start_i = 1'b0;
    clear_i = 1'b0;
    token_ids_i = '0;
    expected_final_vector = 512'd0;
    expected_block_input_checksum = 32'd0;
    expected_context_checksum = 32'd0;
    cycles = 0;

    for (int token = 0; token < EMBED_BLOCK_SEQ; token = token + 1) begin
      token_ids_i[token * 16 +: 16] = embed_block_expected_token_ids[token];
    end
    for (int dim = 0; dim < EMBED_BLOCK_DIM; dim = dim + 1) begin
      expected_block_input_checksum =
        expected_block_input_checksum + ({24'd0, embed_block_expected_last_input_q[dim][7:0]} * (dim + 1));
    end
    for (int dim = 0; dim < CONTEXT_DIM; dim = dim + 1) begin
      expected_context_checksum =
        expected_context_checksum + ({24'd0, context_expected_q[dim][7:0]} * (dim + 1));
    end
    for (int dim = 0; dim < MLP_C_PROJ_OUT_DIM; dim = dim + 1) begin
      expected_final_vector[dim * 8 +: 8] = mlp_final_expected_q[dim];
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);
    start_i = 1'b1;
    @(posedge SYS_CLK);
    start_i = 1'b0;

    while (cycles < TIMEOUT_CYCLES) begin
      @(posedge SYS_CLK);
      cycles = cycles + 1;

      if (status_o[2]) begin
        $fatal(
          1,
          "FAIL: task6 M2 embedding-live-context full-block error status=%08x debug=%08x",
          status_o,
          debug_o
        );
      end

      if (status_o[6:4] == ST_DONE && status_o[3]) begin
        if (block_input_checksum_o !== expected_block_input_checksum) begin
          $fatal(1, "FAIL: block input checksum expected %08x got %08x", expected_block_input_checksum, block_input_checksum_o);
        end
        if (context_checksum_o !== expected_context_checksum) begin
          $fatal(1, "FAIL: context checksum expected %08x got %08x", expected_context_checksum, context_checksum_o);
        end
        if (attn_out_checksum_o !== OUT_PROJ_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: attention checksum expected %08x got %08x", OUT_PROJ_EXPECTED_CHECKSUM, attn_out_checksum_o);
        end
        if (attn_residual_checksum_o !== ATTN_RESIDUAL_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: attention residual checksum expected %08x got %08x", ATTN_RESIDUAL_EXPECTED_CHECKSUM, attn_residual_checksum_o);
        end
        if (ln2_checksum_o !== LN2_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: ln2 checksum expected %08x got %08x", LN2_EXPECTED_CHECKSUM, ln2_checksum_o);
        end
        if (post_gelu_checksum_o !== MLP_POST_GELU_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: post_gelu checksum expected %08x got %08x", MLP_POST_GELU_EXPECTED_CHECKSUM, post_gelu_checksum_o);
        end
        if (c_proj_checksum_o !== MLP_C_PROJ_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: c_proj checksum expected %08x got %08x", MLP_C_PROJ_EXPECTED_CHECKSUM, c_proj_checksum_o);
        end
        if (final_checksum_o !== MLP_FINAL_EXPECTED_CHECKSUM) begin
          $fatal(1, "FAIL: final checksum expected %08x got %08x", MLP_FINAL_EXPECTED_CHECKSUM, final_checksum_o);
        end
        if (final_sample0_o !== MLP_FINAL_EXPECTED_SAMPLE0) begin
          $fatal(1, "FAIL: final sample0 expected %08x got %08x", MLP_FINAL_EXPECTED_SAMPLE0, final_sample0_o);
        end
        if (final_sample1_o !== MLP_FINAL_EXPECTED_SAMPLE1) begin
          $fatal(1, "FAIL: final sample1 expected %08x got %08x", MLP_FINAL_EXPECTED_SAMPLE1, final_sample1_o);
        end
        if (final_vector_o !== expected_final_vector) begin
          $fatal(1, "FAIL: final vector mismatch");
        end
        $display(
          "PASS: task6 M2 embedding-live-context full-block cycles %0d block_input_checksum %08x context_checksum %08x attn_checksum %08x attn_residual_checksum %08x ln2_checksum %08x post_gelu_checksum %08x c_proj_checksum %08x final_checksum %08x final_sample0 %08x final_sample1 %08x",
          cycle_count_o,
          block_input_checksum_o,
          context_checksum_o,
          attn_out_checksum_o,
          attn_residual_checksum_o,
          ln2_checksum_o,
          post_gelu_checksum_o,
          c_proj_checksum_o,
          final_checksum_o,
          final_sample0_o,
          final_sample1_o
        );
        $finish;
      end
    end

    $fatal(1, "Timeout waiting for task6 M2 embedding-live-context full-block done");
  end
endmodule
