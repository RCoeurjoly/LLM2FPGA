`timescale 1ns/1ps

module task6_m2_embedding_live_context_attention_ln2_pcie_accel_tb;
  `include "tb_data.sv"
  `include "task6_m2_embedding_block_input_tb_data.sv"
  `include "task6_m2_ln_attn_live_kv_all_heads_context_tb_data.sv"

  localparam int TIMEOUT_CYCLES = 500000;
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
  logic [511:0] expected_ln2_vector;
  logic [31:0] expected_block_input_checksum;
  logic [31:0] expected_ln_input_checksum;
  logic [31:0] expected_context_checksum;
  logic [31:0] expected_debug1;
  logic [31:0] expected_debug2;
  logic [31:0] expected_debug3;

  task6_m2_embedding_live_context_attention_ln2_pcie_accel_top #(
    .M2_FULL_BLOCK_TOKEN_INDEX(5)
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

  task automatic pulse_clear;
    begin
      pcie_clear_pulse_i = 1'b1;
      @(posedge SYS_CLK);
      pcie_clear_pulse_i = 1'b0;
      @(posedge SYS_CLK);
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
            "FAIL: task6 M2.5 attention LN2 PCIe wrapper error pass=%0d status=%08x debug=%08x debug1=%08x debug2=%08x",
            pass_index,
            pcie_status_o,
            pcie_debug_o,
            pcie_debug1_o,
            pcie_debug2_o
          );
        end
        if (status_state(pcie_status_o) == M2_DONE && pcie_status_o[3]) begin
          if (pcie_status_o[31:16] !== 16'h4d32) begin
            $fatal(1, "FAIL: status magic expected 4d32 got %04x", pcie_status_o[31:16]);
          end
          if (pcie_provenance_o !== 32'h4d32_4205) begin
            $fatal(1, "FAIL: provenance expected %08x got %08x", 32'h4d32_4205, pcie_provenance_o);
          end
          if (pcie_output_checksum_o !== LN2_EXPECTED_CHECKSUM) begin
            $fatal(1, "FAIL: LN2 checksum expected %08x got %08x", LN2_EXPECTED_CHECKSUM, pcie_output_checksum_o);
          end
          if (pcie_output_sample0_o !== LN2_EXPECTED_SAMPLE0) begin
            $fatal(1, "FAIL: LN2 sample0 expected %08x got %08x", LN2_EXPECTED_SAMPLE0, pcie_output_sample0_o);
          end
          if (pcie_output_sample1_o !== LN2_EXPECTED_SAMPLE1) begin
            $fatal(1, "FAIL: LN2 sample1 expected %08x got %08x", LN2_EXPECTED_SAMPLE1, pcie_output_sample1_o);
          end
          if (pcie_output_count_o !== 32'd64) begin
            $fatal(1, "FAIL: output count expected 64 got %0d", pcie_output_count_o);
          end
          if (pcie_output_vector_o !== expected_ln2_vector) begin
            $fatal(1, "FAIL: LN2 vector mismatch pass=%0d", pass_index);
          end
          if (pcie_debug_o !== expected_ln_input_checksum) begin
            $fatal(1, "FAIL: LN input checksum expected %08x got %08x", expected_ln_input_checksum, pcie_debug_o);
          end
          if (pcie_debug1_o !== expected_debug1) begin
            $fatal(1, "FAIL: debug1 expected %08x got %08x", expected_debug1, pcie_debug1_o);
          end
          if (pcie_debug2_o !== expected_debug2) begin
            $fatal(1, "FAIL: debug2 expected %08x got %08x", expected_debug2, pcie_debug2_o);
          end
          if (pcie_debug3_o !== expected_debug3) begin
            $fatal(1, "FAIL: debug3 expected %08x got %08x", expected_debug3, pcie_debug3_o);
          end
          return;
        end
      end
      $fatal(1, "Timeout waiting for task6 M2.5 attention LN2 PCIe wrapper done");
    end
  endtask

  initial begin
    SYS_CLK = 1'b0;
    SYS_RSTN = 1'b0;
    pcie_token_ids_i = 512'd0;
    pcie_reserved_i = 512'd0;
    pcie_start_pulse_i = 1'b0;
    pcie_clear_pulse_i = 1'b0;
    expected_ln2_vector = 512'd0;
    expected_block_input_checksum = 32'd0;
    expected_ln_input_checksum = 32'd0;
    expected_context_checksum = 32'd0;

    for (int token = 0; token < 6; token = token + 1) begin
      pcie_token_ids_i[token * 16 +: 16] = embed_block_expected_token_ids[token];
    end

    for (int dim = 0; dim < 64; dim = dim + 1) begin
      expected_ln2_vector[dim * 8 +: 8] = ln2_expected_q[dim];
      expected_block_input_checksum =
        expected_block_input_checksum + ({24'd0, embed_block_expected_last_input_q[dim][7:0]} * (dim + 1));
      expected_context_checksum =
        expected_context_checksum + ({24'd0, context_expected_q[dim][7:0]} * (dim + 1));
    end
    for (int token = 0; token < 6; token = token + 1) begin
      for (int dim = 0; dim < 64; dim = dim + 1) begin
        expected_ln_input_checksum =
          expected_ln_input_checksum +
          ({16'd0, embed_block_expected_ln_input_q12_by_token[token][dim][15:0]} * ((token * 64) + dim + 1));
      end
    end

    expected_debug1 = {expected_block_input_checksum[15:0], expected_context_checksum[15:0]};
    expected_debug2 = {
      OUT_PROJ_EXPECTED_CHECKSUM[7:0],
      ATTN_RESIDUAL_EXPECTED_CHECKSUM[7:0],
      LN2_EXPECTED_CHECKSUM[7:0],
      8'h00
    };
    expected_debug3 = {expected_block_input_checksum[15:0], expected_ln_input_checksum[15:0]};

    repeat (4) @(negedge SYS_CLK);
    SYS_RSTN = 1'b1;
    repeat (4) @(posedge SYS_CLK);

    pulse_start();
    wait_done(1);

    pulse_clear();
    if (status_state(pcie_status_o) != M2_IDLE || !pcie_status_o[0]) begin
      $fatal(1, "FAIL: post-clear status expected idle/ready got %08x", pcie_status_o);
    end

    pulse_start();
    wait_done(2);

    $display(
      "PASS: task6 M2.5 embedding live-context attention LN2 PCIe wrapper cycles %0d ln2_checksum %08x ln2_sample0 %08x ln2_sample1 %08x debug %08x debug1 %08x debug2 %08x debug3 %08x provenance %08x",
      pcie_cycle_count_o,
      pcie_output_checksum_o,
      pcie_output_sample0_o,
      pcie_output_sample1_o,
      pcie_debug_o,
      pcie_debug1_o,
      pcie_debug2_o,
      pcie_debug3_o,
      pcie_provenance_o
    );
    $finish;
  end
endmodule
