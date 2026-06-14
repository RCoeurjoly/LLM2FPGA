`timescale 1ns/1ps

module task6_m2_embedding_live_context_full_block_pcie_accel_tb;
  `include "tb_data.sv"
  `include "task6_m2_ln_attn_live_kv_all_heads_context_tb_data.sv"
  `include "task6_m2_embedding_block_input_tb_data.sv"

  localparam int TIMEOUT_CYCLES = 160000;
  localparam logic [2:0] M2_IDLE = 3'd0;
  localparam logic [2:0] M2_DONE = 3'd5;

  logic SYS_CLK;
  logic SYS_RSTN;
  logic [511:0] pcie_token_ids_i;
  logic [511:0] pcie_reserved_i;
  logic pcie_start_pulse_i;
  logic pcie_clear_pulse_i;
  logic [31:0] pcie_status_o;
  logic [31:0] pcie_cycle_count_o;
  logic [31:0] pcie_output_checksum_o;
  logic [31:0] pcie_output_sample0_o;
  logic [31:0] pcie_output_sample1_o;
  logic [31:0] pcie_output_count_o;
  logic [511:0] pcie_output_vector_o;
  logic [31:0] pcie_debug_o;
  logic [31:0] pcie_debug1_o;
  logic [31:0] pcie_debug2_o;
  logic [31:0] pcie_debug3_o;
  logic [31:0] pcie_provenance_o;
  logic [511:0] expected_final_vector;
  logic [31:0] expected_block_input_checksum;
  logic [31:0] expected_ln_input_checksum;
  logic [31:0] expected_context_checksum;
  logic [31:0] expected_debug1;
  logic [31:0] expected_debug2;
  logic [31:0] expected_debug3;
  integer i;

  task6_m2_embedding_live_context_full_block_pcie_accel_top #(
    .M2_FULL_BLOCK_TOKEN_INDEX(M2_FULL_BLOCK_TOKEN_INDEX)
  ) dut (
    .SYS_CLK(SYS_CLK),
    .SYS_RSTN(SYS_RSTN),
    .pcie_token_ids_i(pcie_token_ids_i),
    .pcie_reserved_i(pcie_reserved_i),
    .pcie_start_pulse_i(pcie_start_pulse_i),
    .pcie_clear_pulse_i(pcie_clear_pulse_i),
    .pcie_status_o(pcie_status_o),
    .pcie_cycle_count_o(pcie_cycle_count_o),
    .pcie_output_checksum_o(pcie_output_checksum_o),
    .pcie_output_sample0_o(pcie_output_sample0_o),
    .pcie_output_sample1_o(pcie_output_sample1_o),
    .pcie_output_count_o(pcie_output_count_o),
    .pcie_output_vector_o(pcie_output_vector_o),
    .pcie_debug_o(pcie_debug_o),
    .pcie_debug1_o(pcie_debug1_o),
    .pcie_debug2_o(pcie_debug2_o),
    .pcie_debug3_o(pcie_debug3_o),
    .pcie_provenance_o(pcie_provenance_o)
  );

  always #5 SYS_CLK = ~SYS_CLK;

  function automatic logic [2:0] status_state(input logic [31:0] status);
    status_state = status[6:4];
  endfunction

  task automatic pulse_start;
    begin
      pcie_start_pulse_i = 1'b1;
      @(posedge SYS_CLK);
      pcie_start_pulse_i = 1'b0;
    end
  endtask

  task automatic wait_done(input int pass_index);
    integer cycles;
    begin
      cycles = 0;
      while (cycles < TIMEOUT_CYCLES) begin
        @(posedge SYS_CLK);
        cycles = cycles + 1;
        if (pcie_status_o[2]) begin
          $fatal(
            1,
            "FAIL: task6 M2 embedding full-block PCIe wrapper error pass=%0d status=%08x debug=%08x",
            pass_index,
            pcie_status_o,
            pcie_debug_o
          );
        end
        if (status_state(pcie_status_o) == M2_DONE && pcie_status_o[3]) begin
          if (pcie_status_o[31:16] !== 16'h4d32) begin
            $fatal(1, "FAIL: status magic expected 4d32 got %04x", pcie_status_o[31:16]);
          end
          if (pcie_cycle_count_o == 32'd0) begin
            $fatal(1, "FAIL: done reported with zero core cycles on pass %0d", pass_index);
          end
          if (pcie_provenance_o !== (32'h4d32_3000 | {24'd0, M2_FULL_BLOCK_TOKEN_INDEX[7:0]})) begin
            $fatal(
              1,
              "FAIL: provenance expected %08x got %08x",
              (32'h4d32_3000 | {24'd0, M2_FULL_BLOCK_TOKEN_INDEX[7:0]}),
              pcie_provenance_o
            );
          end
          if (!pcie_status_o[0] || pcie_status_o[1]) begin
            $fatal(1, "FAIL: done status ready/busy inconsistent status=%08x", pcie_status_o);
          end
          if (pcie_output_checksum_o !== MLP_FINAL_EXPECTED_CHECKSUM) begin
            $fatal(
              1,
              "FAIL: final checksum expected %08x got %08x pass=%0d cycles=%0d status=%08x debug=%08x debug1=%08x debug2=%08x sample0=%08x sample1=%08x",
              MLP_FINAL_EXPECTED_CHECKSUM,
              pcie_output_checksum_o,
              pass_index,
              pcie_cycle_count_o,
              pcie_status_o,
              pcie_debug_o,
              pcie_debug1_o,
              pcie_debug2_o,
              pcie_output_sample0_o,
              pcie_output_sample1_o
            );
          end
          if (pcie_output_sample0_o !== MLP_FINAL_EXPECTED_SAMPLE0) begin
            $fatal(1, "FAIL: final sample0 expected %08x got %08x", MLP_FINAL_EXPECTED_SAMPLE0, pcie_output_sample0_o);
          end
          if (pcie_output_sample1_o !== MLP_FINAL_EXPECTED_SAMPLE1) begin
            $fatal(1, "FAIL: final sample1 expected %08x got %08x", MLP_FINAL_EXPECTED_SAMPLE1, pcie_output_sample1_o);
          end
          if (pcie_output_count_o !== 32'd64) begin
            $fatal(1, "FAIL: output count expected 64 got %0d", pcie_output_count_o);
          end
          if (pcie_output_vector_o !== expected_final_vector) begin
            $fatal(1, "FAIL: final vector mismatch");
          end
          if (pcie_debug_o !== expected_ln_input_checksum) begin
            $fatal(
              1,
              "FAIL: DONE debug LN-input checksum expected %08x got %08x pass=%0d",
              expected_ln_input_checksum,
              pcie_debug_o,
              pass_index
            );
          end
          if (pcie_debug1_o !== expected_debug1) begin
            $fatal(
              1,
              "FAIL: done debug1 expected %08x got %08x pass=%0d",
              expected_debug1,
              pcie_debug1_o,
              pass_index
            );
          end
          if (pcie_debug2_o !== expected_debug2) begin
            $fatal(
              1,
              "FAIL: done debug2 expected %08x got %08x pass=%0d",
              expected_debug2,
              pcie_debug2_o,
              pass_index
            );
          end
          if (pcie_debug3_o !== expected_debug3) begin
            $fatal(
              1,
              "FAIL: done debug3 expected %08x got %08x pass=%0d",
              expected_debug3,
              pcie_debug3_o,
              pass_index
            );
          end
          return;
        end
      end
      $fatal(1, "Timeout waiting for task6 M2 embedding full-block PCIe wrapper done");
    end
  endtask

  task automatic pulse_clear;
    begin
      pcie_clear_pulse_i = 1'b1;
      @(posedge SYS_CLK);
      pcie_clear_pulse_i = 1'b0;
      @(posedge SYS_CLK);
    end
  endtask

  task automatic wait_error(input logic [15:0] expected_token_id);
    integer cycles;
    begin
      cycles = 0;
      while (cycles < 32) begin
        @(posedge SYS_CLK);
        cycles = cycles + 1;
        if (pcie_status_o[2]) begin
          if (pcie_debug_o[31:24] !== 8'h01) begin
            $fatal(1, "FAIL: expected embedding error stage got debug=%08x", pcie_debug_o);
          end
          if (pcie_debug_o[15:0] !== expected_token_id) begin
            $fatal(
              1,
              "FAIL: expected token mismatch debug token %04x got %04x",
              expected_token_id,
              pcie_debug_o[15:0]
            );
          end
          return;
        end
      end
      $fatal(1, "Timeout waiting for induced task6 M2 wrapper error");
    end
  endtask

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    pcie_token_ids_i = 512'd0;
    pcie_reserved_i = 512'd0;
    pcie_start_pulse_i = 1'b0;
    pcie_clear_pulse_i = 1'b0;
    expected_final_vector = 512'd0;
    expected_block_input_checksum = 32'd0;
    expected_ln_input_checksum = 32'd0;
    expected_context_checksum = 32'd0;
    expected_debug1 = 32'd0;
    expected_debug2 = 32'd0;
    expected_debug3 = 32'd0;

    for (i = 0; i < MLP_C_PROJ_OUT_DIM; i = i + 1) begin
      expected_final_vector[i * 8 +: 8] = mlp_final_expected_q[i];
    end
    for (i = 0; i < EMBED_BLOCK_SEQ; i = i + 1) begin
      pcie_token_ids_i[i * 16 +: 16] = embed_block_expected_token_ids[i];
    end
    for (i = 0; i < EMBED_BLOCK_DIM; i = i + 1) begin
      expected_block_input_checksum =
        expected_block_input_checksum + ({24'd0, embed_block_expected_last_input_q[i][7:0]} * (i + 1));
    end
    for (int token = 0; token < EMBED_BLOCK_SEQ; token = token + 1) begin
      for (int dim = 0; dim < EMBED_BLOCK_DIM; dim = dim + 1) begin
        expected_ln_input_checksum =
          expected_ln_input_checksum +
          ({16'd0, embed_block_expected_ln_input_q12_by_token[token][dim][15:0]} *
            ((token * EMBED_BLOCK_DIM) + dim + 1));
      end
    end
    for (i = 0; i < CONTEXT_DIM; i = i + 1) begin
      expected_context_checksum =
        expected_context_checksum + ({24'd0, context_expected_q[i][7:0]} * (i + 1));
    end
    expected_debug1 = {expected_block_input_checksum[15:0], expected_context_checksum[15:0]};
    expected_debug2 = {
      OUT_PROJ_EXPECTED_CHECKSUM[7:0],
      ATTN_RESIDUAL_EXPECTED_CHECKSUM[7:0],
      LN2_EXPECTED_CHECKSUM[7:0],
      MLP_C_PROJ_EXPECTED_CHECKSUM[7:0]
    };
    expected_debug3 = {expected_block_input_checksum[15:0], expected_block_input_checksum[15:0]};

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: initial wrapper status expected idle/ready got %08x", pcie_status_o);
    end

    pcie_token_ids_i[0 +: 16] = 16'h3a3c;
    pulse_start();
    wait_error(16'h3a3c);

    pulse_clear();
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: post-error clear wrapper status expected idle/ready got %08x", pcie_status_o);
    end
    pcie_token_ids_i[0 +: 16] = embed_block_expected_token_ids[0];

    pulse_start();
    wait_done(1);

    $display(
      "PASS: task6 M2 embedding full-block PCIe wrapper cycles %0d final_checksum %08x final_sample0 %08x final_sample1 %08x provenance %08x ln_input_checksum %08x debug1 %08x debug2 %08x debug3 %08x",
      pcie_cycle_count_o,
      pcie_output_checksum_o,
      pcie_output_sample0_o,
      pcie_output_sample1_o,
      pcie_provenance_o,
      pcie_debug_o,
      pcie_debug1_o,
      pcie_debug2_o,
      pcie_debug3_o
    );

    pulse_clear();
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: post-clear wrapper status expected idle/ready got %08x", pcie_status_o);
    end

    $finish;
  end
endmodule
