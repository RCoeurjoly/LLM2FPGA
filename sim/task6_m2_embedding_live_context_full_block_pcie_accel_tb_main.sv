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
  logic [31:0] pcie_provenance_o;
  logic [511:0] expected_final_vector;
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
          return;
        end
      end
      $fatal(1, "Timeout waiting for task6 M2 embedding full-block PCIe wrapper done");
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

    for (i = 0; i < MLP_C_PROJ_OUT_DIM; i = i + 1) begin
      expected_final_vector[i * 8 +: 8] = mlp_final_expected_q[i];
    end
    for (i = 0; i < EMBED_BLOCK_SEQ; i = i + 1) begin
      pcie_token_ids_i[i * 16 +: 16] = embed_block_expected_token_ids[i];
    end

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: initial wrapper status expected idle/ready got %08x", pcie_status_o);
    end

    pulse_start();
    wait_done(1);

    pcie_clear_pulse_i = 1'b1;
    @(posedge SYS_CLK);
    pcie_clear_pulse_i = 1'b0;
    @(posedge SYS_CLK);
    if (status_state(pcie_status_o) !== M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: post-clear wrapper status expected idle/ready got %08x", pcie_status_o);
    end

    pulse_start();
    wait_done(2);

    $display(
      "PASS: task6 M2 embedding full-block PCIe wrapper cycles %0d final_checksum %08x final_sample0 %08x final_sample1 %08x provenance %08x debug %08x debug1 %08x debug2 %08x",
      pcie_cycle_count_o,
      pcie_output_checksum_o,
      pcie_output_sample0_o,
      pcie_output_sample1_o,
      pcie_provenance_o,
      pcie_debug_o,
      pcie_debug1_o,
      pcie_debug2_o
    );
    $finish;
  end
endmodule
