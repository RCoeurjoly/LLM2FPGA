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
  logic [31:0] expected_context_fixture_signature;
  logic [31:0] expected_context_error_debug;
  logic [31:0] expected_context_error_debug1;
  logic [31:0] expected_context_error_debug2;
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

  function automatic signed [63:0] round_shift_signed64_tb(
    input signed [63:0] value,
    input int shift
  );
    logic signed [63:0] abs_value;
    begin
      if (shift == 0) begin
        round_shift_signed64_tb = value;
      end else if (value >= 0) begin
        round_shift_signed64_tb = (value + (64'sd1 <<< (shift - 1))) >>> shift;
      end else begin
        abs_value = -value;
        round_shift_signed64_tb =
          -((abs_value + (64'sd1 <<< (shift - 1))) >>> shift);
      end
    end
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

  task automatic induce_context_ln2_error;
    integer cycles;
    begin
      cycles = 0;
      while (cycles < TIMEOUT_CYCLES) begin
        @(negedge SYS_CLK);
        cycles = cycles + 1;
        if (dut.core_i.block_i.context_i.state_q == 5'd13 &&
            dut.core_i.block_i.context_i.token_index_q == '0 &&
            dut.core_i.block_i.context_i.ln_index_q == 6'd2) begin
          force dut.core_i.block_i.context_i.ln_piped_output_w = 8'sd0;
          return;
        end
        if (pcie_status_o[2]) begin
          $fatal(1, "FAIL: context entered error before induced LN index 2 mismatch debug=%08x", pcie_debug_o);
        end
      end
      $fatal(1, "Timeout waiting to induce context LN index 2 mismatch");
    end
  endtask

  task automatic wait_context_error(
    input logic [31:0] expected_debug,
    input logic [31:0] expected_debug1_value,
    input logic [31:0] expected_debug2_value
  );
    integer cycles;
    logic [31:0] fallback_debug1;
    logic [31:0] fallback_debug2;
    begin
      fallback_debug1 = {
        embed_block_expected_ln_input_q12_by_token[0][0][15:0],
        embed_block_expected_ln_input_q12_by_token[0][1][15:0]
      };
      fallback_debug2 = {
        embed_block_expected_ln_input_q12_by_token[0][2][15:0],
        embed_block_expected_ln_input_q12_by_token[0][3][15:0]
      };
      cycles = 0;
      while (cycles < TIMEOUT_CYCLES) begin
        @(posedge SYS_CLK);
        cycles = cycles + 1;
        if (pcie_status_o[2]) begin
          if (pcie_debug_o[31:28] !== 4'hc) begin
            $fatal(1, "FAIL: expected context error got debug=%08x", pcie_debug_o);
          end
          if (pcie_debug_o !== expected_debug) begin
            $fatal(
              1,
              "FAIL: context error debug expected %08x got %08x",
              expected_debug,
              pcie_debug_o
            );
          end
          if (pcie_debug1_o === fallback_debug1 || pcie_debug2_o === fallback_debug2) begin
            $fatal(
              1,
              "FAIL: context error debug1/debug2 used fallback LN input words debug1=%08x debug2=%08x",
              pcie_debug1_o,
              pcie_debug2_o
            );
          end
          if (pcie_debug1_o !== expected_debug1_value) begin
            $fatal(
              1,
              "FAIL: context error debug1 expected %08x got %08x",
              expected_debug1_value,
              pcie_debug1_o
            );
          end
          if (pcie_debug2_o !== expected_debug2_value) begin
            $fatal(
              1,
              "FAIL: context error debug2 expected %08x got %08x",
              expected_debug2_value,
              pcie_debug2_o
            );
          end
          return;
        end
      end
      $fatal(1, "Timeout waiting for induced context error");
    end
  endtask

  task automatic wait_context_ln_checkpoint(
    input int target_token,
    input int target_ln_index
  );
    integer cycles;
    logic signed [31:0] mean_acc_q12;
    logic signed [31:0] mean_q12;
    logic signed [31:0] centered_q12;
    logic signed [31:0] norm_q12;
    logic signed [31:0] affine_q12;
    logic signed [63:0] mean_shifted;
    logic signed [63:0] norm_shifted;
    logic signed [63:0] affine_shifted;
    logic [31:0] expected_debug1_value;
    logic [31:0] expected_debug2_value;
    begin
      mean_acc_q12 = 32'sd0;
      for (int dim = 0; dim < LN_DIM; dim = dim + 1) begin
        mean_acc_q12 =
          mean_acc_q12 +
          $signed({{16{ln_input_q12_by_token[target_token][dim][15]}}, ln_input_q12_by_token[target_token][dim]});
      end
      mean_shifted = round_shift_signed64_tb({{32{mean_acc_q12[31]}}, mean_acc_q12}, 6);
      mean_q12 = $signed(mean_shifted[31:0]);
      centered_q12 =
        $signed({{16{ln_input_q12_by_token[target_token][target_ln_index][15]}}, ln_input_q12_by_token[target_token][target_ln_index]}) -
        mean_q12;
      norm_shifted = round_shift_signed64_tb(
        $signed(centered_q12) * $signed(ln_inv_std_q16_by_token[target_token]),
        16
      );
      norm_q12 = $signed(norm_shifted[31:0]);
      affine_shifted = round_shift_signed64_tb(
        $signed(norm_q12) * $signed(ln_gamma_q16[target_ln_index]),
        16
      );
      affine_q12 =
        $signed(affine_shifted[31:0]) +
        $signed({{16{ln_beta_q12[target_ln_index][15]}}, ln_beta_q12[target_ln_index]});
      expected_debug1_value = {mean_q12[15:0], centered_q12[15:0]};
      expected_debug2_value = {norm_q12[15:0], affine_q12[15:0]};

      cycles = 0;
      while (cycles < TIMEOUT_CYCLES) begin
        @(posedge SYS_CLK);
        cycles = cycles + 1;
        if (pcie_status_o[2]) begin
          $fatal(
            1,
            "FAIL: context entered error before natural token %0d LN index %0d checkpoint debug=%08x debug1=%08x debug2=%08x",
            target_token,
            target_ln_index,
            pcie_debug_o,
            pcie_debug1_o,
            pcie_debug2_o
          );
        end
        if (dut.core_i.block_i.context_i.state_q == 5'd13 &&
            dut.core_i.block_i.context_i.token_index_q == target_token &&
            dut.core_i.block_i.context_i.ln_index_q == target_ln_index) begin
          if (dut.core_i.block_i.context_i.debug1_o !== expected_debug1_value) begin
            $fatal(
              1,
              "FAIL: natural context token %0d LN index %0d debug1 expected %08x got %08x",
              target_token,
              target_ln_index,
              expected_debug1_value,
              dut.core_i.block_i.context_i.debug1_o
            );
          end
          if (dut.core_i.block_i.context_i.debug2_o !== expected_debug2_value) begin
            $fatal(
              1,
              "FAIL: natural context token %0d LN index %0d debug2 expected %08x got %08x",
              target_token,
              target_ln_index,
              expected_debug2_value,
              dut.core_i.block_i.context_i.debug2_o
            );
          end
          if (dut.core_i.block_i.context_i.ln_piped_output_w !== ln_expected_q_by_token[target_token][target_ln_index]) begin
            $fatal(
              1,
              "FAIL: natural context token %0d LN index %0d output expected %02x got %02x debug1=%08x debug2=%08x",
              target_token,
              target_ln_index,
              ln_expected_q_by_token[target_token][target_ln_index],
              dut.core_i.block_i.context_i.ln_piped_output_w,
              dut.core_i.block_i.context_i.debug1_o,
              dut.core_i.block_i.context_i.debug2_o
            );
          end
          if (target_token == 5 && target_ln_index == 1) begin
            $display(
              "INFO: natural context token5 LN1 debug1 %08x debug2 %08x output %02x expected %02x",
              dut.core_i.block_i.context_i.debug1_o,
              dut.core_i.block_i.context_i.debug2_o,
              dut.core_i.block_i.context_i.ln_piped_output_w,
              ln_expected_q_by_token[target_token][target_ln_index]
            );
          end
          return;
        end
      end
      $fatal(1, "Timeout waiting for natural context token %0d LN index %0d checkpoint", target_token, target_ln_index);
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
    expected_context_fixture_signature = 32'd0;
    expected_context_error_debug = 32'd0;
    expected_context_error_debug1 = 32'd0;
    expected_context_error_debug2 = 32'd0;

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
    expected_context_fixture_signature = {
      8'hc5,
      ln_expected_q_by_token[5][1],
      ln_input_q12_by_token[5][1][7:0],
      ln_inv_std_q16_by_token[5][7:0]
    };

    begin
      logic signed [31:0] mean_acc_q12;
      logic signed [31:0] mean_q12;
      logic signed [31:0] centered_q12;
      logic signed [31:0] norm_q12;
      logic signed [31:0] affine_q12;
      logic signed [63:0] mean_shifted;
      logic signed [63:0] norm_shifted;
      logic signed [63:0] affine_shifted;

      mean_acc_q12 = 32'sd0;
      for (int dim = 0; dim < LN_DIM; dim = dim + 1) begin
        mean_acc_q12 =
          mean_acc_q12 +
          $signed({{16{ln_input_q12_by_token[0][dim][15]}}, ln_input_q12_by_token[0][dim]});
      end
      mean_shifted = round_shift_signed64_tb({{32{mean_acc_q12[31]}}, mean_acc_q12}, 6);
      mean_q12 = $signed(mean_shifted[31:0]);
      centered_q12 =
        $signed({{16{ln_input_q12_by_token[0][2][15]}}, ln_input_q12_by_token[0][2]}) -
        mean_q12;
      norm_shifted = round_shift_signed64_tb(
        $signed(centered_q12) * $signed(ln_inv_std_q16_by_token[0]),
        16
      );
      norm_q12 = $signed(norm_shifted[31:0]);
      affine_shifted = round_shift_signed64_tb(
        $signed(norm_q12) * $signed(ln_gamma_q16[2]),
        16
      );
      affine_q12 =
        $signed(affine_shifted[31:0]) +
        $signed({{16{ln_beta_q12[2][15]}}, ln_beta_q12[2]});
      expected_context_error_debug = {
        4'hc,
        4'h1,
        6'd2,
        ln_expected_q_by_token[0][2],
        2'd0,
        8'sd0
      };
      expected_context_error_debug1 = {mean_q12[15:0], centered_q12[15:0]};
      expected_context_error_debug2 = {norm_q12[15:0], affine_q12[15:0]};
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: initial wrapper status expected idle/ready got %08x", pcie_status_o);
    end
    if (pcie_debug3_o !== expected_context_fixture_signature) begin
      $fatal(
        1,
        "FAIL: idle context fixture signature expected %08x got %08x",
        expected_context_fixture_signature,
        pcie_debug3_o
      );
    end
    $display("INFO: idle context fixture signature %08x", pcie_debug3_o);

    pcie_token_ids_i[0 +: 16] = 16'h3a3c;
    pulse_start();
    wait_error(16'h3a3c);

    pulse_clear();
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: post-error clear wrapper status expected idle/ready got %08x", pcie_status_o);
    end
    if (pcie_debug3_o !== expected_context_fixture_signature) begin
      $fatal(
        1,
        "FAIL: post-error idle context fixture signature expected %08x got %08x",
        expected_context_fixture_signature,
        pcie_debug3_o
      );
    end
    pcie_token_ids_i[0 +: 16] = embed_block_expected_token_ids[0];

    pulse_start();
    induce_context_ln2_error();
    wait_context_error(
      expected_context_error_debug,
      expected_context_error_debug1,
      expected_context_error_debug2
    );
    release dut.core_i.block_i.context_i.ln_piped_output_w;

    pulse_clear();
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: post-context-error clear wrapper status expected idle/ready got %08x", pcie_status_o);
    end
    if (pcie_debug3_o !== expected_context_fixture_signature) begin
      $fatal(
        1,
        "FAIL: post-context-error idle context fixture signature expected %08x got %08x",
        expected_context_fixture_signature,
        pcie_debug3_o
      );
    end

    pulse_start();
    wait_context_ln_checkpoint(0, 2);
    wait_context_ln_checkpoint(5, 1);
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
