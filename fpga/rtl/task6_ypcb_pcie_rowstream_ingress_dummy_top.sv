`timescale 1ns/1ps
`default_nettype none

module task6_ypcb_pcie_rowstream_ingress_dummy_top #(
  parameter int M2_FULL_BLOCK_TOKEN_INDEX = 5,
  parameter bit M2_ENABLE_CONTEXT_INTERNAL_CHECKS = 1'b1,
  parameter bit M2_INPUT_PCIE7X_ROR64_COMPENSATE = 1'b0,
  parameter int M2_ACCEL_KIND = 0,
  parameter bit ENABLE_MLP_ACCEL = 1'b1,
  parameter bit ENABLE_M2_ACCEL = 1'b1
) (
  output wire        pci_exp_txp,
  output wire        pci_exp_txn,
  input  wire        pci_exp_rxp,
  input  wire        pci_exp_rxn,
  input  wire        sys_clk_p,
  input  wire        sys_clk_n,
  input  wire        sys_rst_n,
  input  wire        clk_50,
  output wire  [2:0] led
);
  localparam int COMMAND_WIDTH = 208;

  wire pcie_user_clk;
  wire pcie_user_reset;
  wire pcie_user_rst_n = !pcie_user_reset;
  wire [3:0] pcie_led;

  wire [31:0] s_axi_awaddr;
  wire        s_axi_awvalid;
  wire        s_axi_awready;
  wire [31:0] s_axi_wdata;
  wire [3:0]  s_axi_wstrb;
  wire        s_axi_wvalid;
  wire        s_axi_wready;
  wire [1:0]  s_axi_bresp;
  wire        s_axi_bvalid;
  wire        s_axi_bready;
  wire [31:0] s_axi_araddr;
  wire        s_axi_arvalid;
  wire        s_axi_arready;
  wire [31:0] s_axi_rdata;
  wire        s_axi_rvalid;
  wire        s_axi_rready;
  wire [1:0]  s_axi_rresp;

  wire [COMMAND_WIDTH - 1:0] rowstream_command_payload;
  wire rowstream_command_event;
  wire rowstream_status_clear;
  wire [511:0] rowstream_top1_hidden_vector;
  wire rowstream_top1_start;
  wire rowstream_top1_status_clear;
  wire [31:0] rowstream_mlp_selftest_status;
  wire [31:0] rowstream_mlp_selftest_cycle_count;
  wire [31:0] rowstream_mlp_selftest_fail_detail;
  wire [31:0] rowstream_mlp_selftest_fail_values;
  wire [31:0] rowstream_mlp_selftest_first_add_sample;
  wire [31:0] rowstream_mlp_selftest_first_requant_sample;
  wire [31:0] rowstream_mlp_selftest_requant_debug0;
  wire [31:0] rowstream_mlp_selftest_requant_debug1;
  wire [31:0] rowstream_mlp_selftest_debug_select;
  wire [511:0] rowstream_mlp_accel_activation_vector;
  wire [511:0] rowstream_mlp_accel_residual_vector;
  wire rowstream_mlp_accel_start;
  wire rowstream_mlp_accel_clear;
  wire [31:0] rowstream_mlp_accel_status;
  wire [31:0] rowstream_mlp_accel_cycle_count;
  wire [31:0] rowstream_mlp_accel_output_checksum;
  wire [31:0] rowstream_mlp_accel_output_sample0;
  wire [31:0] rowstream_mlp_accel_output_sample1;
  wire [511:0] rowstream_mlp_accel_output_vector;
  wire [511:0] rowstream_m2_full_block_input_vector;
  wire [511:0] rowstream_m2_full_block_residual_vector;
  wire rowstream_m2_full_block_start;
  wire rowstream_m2_full_block_clear;
  wire [31:0] rowstream_m2_full_block_status;
  wire [31:0] rowstream_m2_full_block_cycle_count;
  wire [31:0] rowstream_m2_full_block_output_checksum;
  wire [31:0] rowstream_m2_full_block_output_sample0;
  wire [31:0] rowstream_m2_full_block_output_sample1;
  wire [31:0] rowstream_m2_full_block_output_count;
  wire [511:0] rowstream_m2_full_block_output_vector;
  wire [127:0] rowstream_m2_full_block_output_hash;
  wire [31:0] rowstream_m2_full_block_debug;
  wire [31:0] rowstream_m2_full_block_debug1;
  wire [31:0] rowstream_m2_full_block_debug2;
  wire [31:0] rowstream_m2_full_block_debug3;
  wire [31:0] rowstream_m2_full_block_provenance;

  reg loader_done_q;
  reg loader_error_q;
  reg loader_last_accepted_q;
  reg loader_last_magic_ok_q;
  reg [7:0] loader_last_opcode_q;
  reg [1:0] loader_last_chunk_q;
  reg [31:0] loader_command_payload_addr_q;
  reg [31:0] loader_wait_cycles_q;
  reg [511:0] loader_read_data_q;
  reg top1_busy_q;
  reg top1_done_q;
  reg top1_error_q;
  reg [31:0] top1_token_q;
  reg [31:0] top1_score_q024_q;
  reg [31:0] top1_rows_scanned_q;
  reg [31:0] top1_cycle_count_q;
  reg [31:0] dummy_cycle_q;

  assign led = pcie_led[2:0];

  assign rowstream_mlp_selftest_status = 32'd0;
  assign rowstream_mlp_selftest_cycle_count = rowstream_mlp_accel_cycle_count;
  assign rowstream_mlp_selftest_fail_detail = 32'd0;
  assign rowstream_mlp_selftest_fail_values = 32'd0;
  assign rowstream_mlp_selftest_first_add_sample = 32'd0;
  assign rowstream_mlp_selftest_first_requant_sample = 32'd0;
  assign rowstream_mlp_selftest_requant_debug0 = 32'd0;
  assign rowstream_mlp_selftest_requant_debug1 = 32'd0;

  pcie_7x_top_aximm #(
    .NO_RESET(0),
    .ENABLE_GEN2(0),
    .GT_DEVICE("GTX"),
    .CFG_DEV_ID(16'h0480)
  ) pcie_7x_top_aximm_i (
    .pci_exp_txp(pci_exp_txp),
    .pci_exp_txn(pci_exp_txn),
    .pci_exp_rxp(pci_exp_rxp),
    .pci_exp_rxn(pci_exp_rxn),
    .sys_clk_p(sys_clk_p),
    .sys_clk_n(sys_clk_n),
    .sys_rst_n(sys_rst_n),
    .led(pcie_led),
    .task6_user_clk_o(pcie_user_clk),
    .task6_user_reset_o(pcie_user_reset),
    .task6_s_axi_awaddr_o(s_axi_awaddr),
    .task6_s_axi_awvalid_o(s_axi_awvalid),
    .task6_s_axi_awready_i(s_axi_awready),
    .task6_s_axi_wdata_o(s_axi_wdata),
    .task6_s_axi_wstrb_o(s_axi_wstrb),
    .task6_s_axi_wvalid_o(s_axi_wvalid),
    .task6_s_axi_wready_i(s_axi_wready),
    .task6_s_axi_bresp_i(s_axi_bresp),
    .task6_s_axi_bvalid_i(s_axi_bvalid),
    .task6_s_axi_bready_o(s_axi_bready),
    .task6_s_axi_araddr_o(s_axi_araddr),
    .task6_s_axi_arvalid_o(s_axi_arvalid),
    .task6_s_axi_arready_i(s_axi_arready),
    .task6_s_axi_rdata_i(s_axi_rdata),
    .task6_s_axi_rvalid_i(s_axi_rvalid),
    .task6_s_axi_rready_o(s_axi_rready),
    .task6_s_axi_rresp_i(s_axi_rresp)
  );

  task6_pcie_axil_rowstream_loader_ingress_cdc #(
    .COMMAND_WIDTH(COMMAND_WIDTH),
    .COMMAND_DATA_LSB(80),
    .M2_INPUT_PCIE7X_ROR64_COMPENSATE(M2_INPUT_PCIE7X_ROR64_COMPENSATE)
  ) pcie_ingress (
    .pcie_clk(pcie_user_clk),
    .pcie_rst_n(pcie_user_rst_n),
    .rowstream_clk(pcie_user_clk),
    .rowstream_rst_n(pcie_user_rst_n),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .s_axi_rresp(s_axi_rresp),
    .rowstream_command_payload_o(rowstream_command_payload),
    .rowstream_command_event_o(rowstream_command_event),
    .rowstream_status_clear_o(rowstream_status_clear),
    .rowstream_calib_complete_i(1'b1),
    .rowstream_boot_done_i(1'b1),
    .rowstream_ddr_debug1_i(32'hd00d_600d),
    .rowstream_loader_done_i(loader_done_q),
    .rowstream_loader_error_i(loader_error_q),
    .rowstream_loader_last_accepted_i(loader_last_accepted_q),
    .rowstream_loader_last_magic_ok_i(loader_last_magic_ok_q),
    .rowstream_loader_last_opcode_i(loader_last_opcode_q),
    .rowstream_loader_last_chunk_i(loader_last_chunk_q),
    .rowstream_loader_command_payload_addr_i(loader_command_payload_addr_q),
    .rowstream_loader_wait_cycles_i(loader_wait_cycles_q),
    .rowstream_loader_read_data_i(loader_read_data_q),
    .rowstream_top1_hidden_vector_o(rowstream_top1_hidden_vector),
    .rowstream_top1_start_o(rowstream_top1_start),
    .rowstream_top1_status_clear_o(rowstream_top1_status_clear),
    .rowstream_top1_busy_i(top1_busy_q),
    .rowstream_top1_done_i(top1_done_q),
    .rowstream_top1_error_i(top1_error_q),
    .rowstream_top1_token_i(top1_token_q),
    .rowstream_top1_score_q024_i(top1_score_q024_q),
    .rowstream_top1_rows_scanned_i(top1_rows_scanned_q),
    .rowstream_top1_cycle_count_i(top1_cycle_count_q),
    .rowstream_top1_debug_status_i(32'h0000_0000),
    .rowstream_top1_debug_reader_addr_i(32'h0000_0000),
    .rowstream_top1_debug_wb_ack_count_i(32'd0),
    .rowstream_top1_debug_wb_err_count_i(32'd0),
    .rowstream_top1_debug_packet_wb_write_ack_count_i(32'd0),
    .rowstream_top1_debug_packet_wb_read_ack_count_i(32'd0),
    .rowstream_mlp_selftest_present_i(1'b1),
    .rowstream_mlp_selftest_status_i(rowstream_mlp_selftest_status),
    .rowstream_mlp_selftest_cycle_count_i(rowstream_mlp_selftest_cycle_count),
    .rowstream_mlp_selftest_fail_detail_i(rowstream_mlp_selftest_fail_detail),
    .rowstream_mlp_selftest_fail_values_i(rowstream_mlp_selftest_fail_values),
    .rowstream_mlp_selftest_first_add_sample_i(rowstream_mlp_selftest_first_add_sample),
    .rowstream_mlp_selftest_first_requant_sample_i(rowstream_mlp_selftest_first_requant_sample),
    .rowstream_mlp_selftest_requant_debug0_i(rowstream_mlp_selftest_requant_debug0),
    .rowstream_mlp_selftest_requant_debug1_i(rowstream_mlp_selftest_requant_debug1),
    .rowstream_mlp_selftest_debug_select_o(rowstream_mlp_selftest_debug_select),
    .rowstream_mlp_accel_activation_vector_o(rowstream_mlp_accel_activation_vector),
    .rowstream_mlp_accel_residual_vector_o(rowstream_mlp_accel_residual_vector),
    .rowstream_mlp_accel_start_o(rowstream_mlp_accel_start),
    .rowstream_mlp_accel_clear_o(rowstream_mlp_accel_clear),
    .rowstream_mlp_accel_status_i(rowstream_mlp_accel_status),
    .rowstream_mlp_accel_cycle_count_i(rowstream_mlp_accel_cycle_count),
    .rowstream_mlp_accel_output_checksum_i(rowstream_mlp_accel_output_checksum),
    .rowstream_mlp_accel_output_sample0_i(rowstream_mlp_accel_output_sample0),
    .rowstream_mlp_accel_output_sample1_i(rowstream_mlp_accel_output_sample1),
    .rowstream_mlp_accel_output_vector_i(rowstream_mlp_accel_output_vector),
    .rowstream_m2_full_block_input_vector_o(rowstream_m2_full_block_input_vector),
    .rowstream_m2_full_block_residual_vector_o(rowstream_m2_full_block_residual_vector),
    .rowstream_m2_full_block_start_o(rowstream_m2_full_block_start),
    .rowstream_m2_full_block_clear_o(rowstream_m2_full_block_clear),
    .rowstream_m2_full_block_status_i(rowstream_m2_full_block_status),
    .rowstream_m2_full_block_cycle_count_i(rowstream_m2_full_block_cycle_count),
    .rowstream_m2_full_block_output_checksum_i(rowstream_m2_full_block_output_checksum),
    .rowstream_m2_full_block_output_sample0_i(rowstream_m2_full_block_output_sample0),
    .rowstream_m2_full_block_output_sample1_i(rowstream_m2_full_block_output_sample1),
    .rowstream_m2_full_block_output_count_i(rowstream_m2_full_block_output_count),
    .rowstream_m2_full_block_debug_i(rowstream_m2_full_block_debug),
    .rowstream_m2_full_block_debug1_i(rowstream_m2_full_block_debug1),
    .rowstream_m2_full_block_debug2_i(rowstream_m2_full_block_debug2),
    .rowstream_m2_full_block_debug3_i(rowstream_m2_full_block_debug3),
    .rowstream_m2_full_block_provenance_i(rowstream_m2_full_block_provenance),
    .rowstream_m2_full_block_output_hash_i(rowstream_m2_full_block_output_hash),
    .rowstream_m2_full_block_output_vector_i(rowstream_m2_full_block_output_vector)
  );

  generate
    if (ENABLE_MLP_ACCEL) begin : gen_mlp_accel
      task6_int8_l2_mlp_chain_residual_add_accel_top mlp_accel (
        .SYS_CLK(pcie_user_clk),
        .SYS_RSTN(pcie_user_rst_n),
        .pcie_accel_activation_i(rowstream_mlp_accel_activation_vector),
        .pcie_accel_residual_i(rowstream_mlp_accel_residual_vector),
        .pcie_accel_start_pulse_i(rowstream_mlp_accel_start),
        .pcie_accel_clear_pulse_i(rowstream_mlp_accel_clear),
        .pcie_accel_status_o(rowstream_mlp_accel_status),
        .pcie_accel_cycle_count_o(rowstream_mlp_accel_cycle_count),
        .pcie_accel_output_checksum_o(rowstream_mlp_accel_output_checksum),
        .pcie_accel_output_sample0_o(rowstream_mlp_accel_output_sample0),
        .pcie_accel_output_sample1_o(rowstream_mlp_accel_output_sample1),
        .pcie_accel_output_vector_o(rowstream_mlp_accel_output_vector)
      );
    end else begin : gen_no_mlp_accel
      assign rowstream_mlp_accel_status = 32'd0;
      assign rowstream_mlp_accel_cycle_count = 32'd0;
      assign rowstream_mlp_accel_output_checksum = 32'd0;
      assign rowstream_mlp_accel_output_sample0 = 32'd0;
      assign rowstream_mlp_accel_output_sample1 = 32'd0;
      assign rowstream_mlp_accel_output_vector = 512'd0;
    end
  endgenerate

  generate
    if (ENABLE_M2_ACCEL && M2_ACCEL_KIND == 3) begin : gen_m2_attention_ln2_accel
      task6_m2_embedding_live_context_attention_ln2_pcie_accel_top #(
        .M2_FULL_BLOCK_TOKEN_INDEX(M2_FULL_BLOCK_TOKEN_INDEX),
        .ENABLE_CONTEXT_INTERNAL_CHECKS(M2_ENABLE_CONTEXT_INTERNAL_CHECKS)
      ) m2_attention_ln2_accel (
        .SYS_CLK(pcie_user_clk),
        .SYS_RSTN(pcie_user_rst_n),
        .pcie_token_ids_i(rowstream_m2_full_block_input_vector),
        .pcie_reserved_i(rowstream_m2_full_block_residual_vector),
        .pcie_start_pulse_i(rowstream_m2_full_block_start),
        .pcie_clear_pulse_i(rowstream_m2_full_block_clear),
        .pcie_status_o(rowstream_m2_full_block_status),
        .pcie_cycle_count_o(rowstream_m2_full_block_cycle_count),
        .pcie_output_checksum_o(rowstream_m2_full_block_output_checksum),
        .pcie_output_sample0_o(rowstream_m2_full_block_output_sample0),
        .pcie_output_sample1_o(rowstream_m2_full_block_output_sample1),
        .pcie_output_count_o(rowstream_m2_full_block_output_count),
        .pcie_output_vector_o(rowstream_m2_full_block_output_vector),
        .pcie_debug_o(rowstream_m2_full_block_debug),
        .pcie_debug1_o(rowstream_m2_full_block_debug1),
        .pcie_debug2_o(rowstream_m2_full_block_debug2),
        .pcie_debug3_o(rowstream_m2_full_block_debug3),
        .pcie_provenance_o(rowstream_m2_full_block_provenance)
      );
      assign rowstream_m2_full_block_output_hash = 128'd0;
    end else if (ENABLE_M2_ACCEL && M2_ACCEL_KIND == 2) begin : gen_m2_attention_slice_accel
      task6_m2_embedding_live_context_attention_slice_pcie_accel_top #(
        .M2_FULL_BLOCK_TOKEN_INDEX(M2_FULL_BLOCK_TOKEN_INDEX),
        .ENABLE_CONTEXT_INTERNAL_CHECKS(M2_ENABLE_CONTEXT_INTERNAL_CHECKS)
      ) m2_attention_slice_accel (
        .SYS_CLK(pcie_user_clk),
        .SYS_RSTN(pcie_user_rst_n),
        .pcie_token_ids_i(rowstream_m2_full_block_input_vector),
        .pcie_reserved_i(rowstream_m2_full_block_residual_vector),
        .pcie_start_pulse_i(rowstream_m2_full_block_start),
        .pcie_clear_pulse_i(rowstream_m2_full_block_clear),
        .pcie_status_o(rowstream_m2_full_block_status),
        .pcie_cycle_count_o(rowstream_m2_full_block_cycle_count),
        .pcie_output_checksum_o(rowstream_m2_full_block_output_checksum),
        .pcie_output_sample0_o(rowstream_m2_full_block_output_sample0),
        .pcie_output_sample1_o(rowstream_m2_full_block_output_sample1),
        .pcie_output_count_o(rowstream_m2_full_block_output_count),
        .pcie_output_vector_o(rowstream_m2_full_block_output_vector),
        .pcie_debug_o(rowstream_m2_full_block_debug),
        .pcie_debug1_o(rowstream_m2_full_block_debug1),
        .pcie_debug2_o(rowstream_m2_full_block_debug2),
        .pcie_debug3_o(rowstream_m2_full_block_debug3),
        .pcie_provenance_o(rowstream_m2_full_block_provenance)
      );
      assign rowstream_m2_full_block_output_hash = 128'd0;
    end else if (ENABLE_M2_ACCEL && M2_ACCEL_KIND == 1) begin : gen_m2_embedding_handoff_accel
      task6_m2_embedding_handoff_pcie_accel_top #(
        .M2_FULL_BLOCK_TOKEN_INDEX(M2_FULL_BLOCK_TOKEN_INDEX)
      ) m2_embedding_handoff_accel (
        .SYS_CLK(pcie_user_clk),
        .SYS_RSTN(pcie_user_rst_n),
        .pcie_token_ids_i(rowstream_m2_full_block_input_vector),
        .pcie_reserved_i(rowstream_m2_full_block_residual_vector),
        .pcie_start_pulse_i(rowstream_m2_full_block_start),
        .pcie_clear_pulse_i(rowstream_m2_full_block_clear),
        .pcie_status_o(rowstream_m2_full_block_status),
        .pcie_cycle_count_o(rowstream_m2_full_block_cycle_count),
        .pcie_output_checksum_o(rowstream_m2_full_block_output_checksum),
        .pcie_output_sample0_o(rowstream_m2_full_block_output_sample0),
        .pcie_output_sample1_o(rowstream_m2_full_block_output_sample1),
        .pcie_output_count_o(rowstream_m2_full_block_output_count),
        .pcie_output_vector_o(rowstream_m2_full_block_output_vector),
        .pcie_output_hash_o(rowstream_m2_full_block_output_hash),
        .pcie_debug_o(rowstream_m2_full_block_debug),
        .pcie_debug1_o(rowstream_m2_full_block_debug1),
        .pcie_debug2_o(rowstream_m2_full_block_debug2),
        .pcie_debug3_o(rowstream_m2_full_block_debug3),
        .pcie_provenance_o(rowstream_m2_full_block_provenance)
      );
    end else if (ENABLE_M2_ACCEL) begin : gen_m2_accel
      task6_m2_embedding_live_context_full_block_pcie_accel_top #(
        .M2_FULL_BLOCK_TOKEN_INDEX(M2_FULL_BLOCK_TOKEN_INDEX),
        .ENABLE_CONTEXT_INTERNAL_CHECKS(M2_ENABLE_CONTEXT_INTERNAL_CHECKS)
      ) m2_full_block_accel (
        .SYS_CLK(pcie_user_clk),
        .SYS_RSTN(pcie_user_rst_n),
        .pcie_token_ids_i(rowstream_m2_full_block_input_vector),
        .pcie_reserved_i(rowstream_m2_full_block_residual_vector),
        .pcie_start_pulse_i(rowstream_m2_full_block_start),
        .pcie_clear_pulse_i(rowstream_m2_full_block_clear),
        .pcie_status_o(rowstream_m2_full_block_status),
        .pcie_cycle_count_o(rowstream_m2_full_block_cycle_count),
        .pcie_output_checksum_o(rowstream_m2_full_block_output_checksum),
        .pcie_output_sample0_o(rowstream_m2_full_block_output_sample0),
        .pcie_output_sample1_o(rowstream_m2_full_block_output_sample1),
        .pcie_output_count_o(rowstream_m2_full_block_output_count),
        .pcie_output_vector_o(rowstream_m2_full_block_output_vector),
        .pcie_debug_o(rowstream_m2_full_block_debug),
        .pcie_debug1_o(rowstream_m2_full_block_debug1),
        .pcie_debug2_o(rowstream_m2_full_block_debug2),
        .pcie_debug3_o(rowstream_m2_full_block_debug3),
        .pcie_provenance_o(rowstream_m2_full_block_provenance)
      );
      assign rowstream_m2_full_block_output_hash = 128'd0;
    end else begin : gen_no_m2_accel
      assign rowstream_m2_full_block_status = 32'd0;
      assign rowstream_m2_full_block_cycle_count = 32'd0;
      assign rowstream_m2_full_block_output_checksum = 32'd0;
      assign rowstream_m2_full_block_output_sample0 = 32'd0;
      assign rowstream_m2_full_block_output_sample1 = 32'd0;
      assign rowstream_m2_full_block_output_count = 32'd0;
      assign rowstream_m2_full_block_output_vector = 512'd0;
      assign rowstream_m2_full_block_output_hash = 128'd0;
      assign rowstream_m2_full_block_debug = 32'd0;
      assign rowstream_m2_full_block_debug1 = 32'd0;
      assign rowstream_m2_full_block_debug2 = 32'd0;
      assign rowstream_m2_full_block_debug3 = 32'd0;
      assign rowstream_m2_full_block_provenance = 32'd0;
    end
  endgenerate

  always @(posedge pcie_user_clk or negedge pcie_user_rst_n) begin
    if (!pcie_user_rst_n) begin
      loader_done_q <= 1'b0;
      loader_error_q <= 1'b0;
      loader_last_accepted_q <= 1'b0;
      loader_last_magic_ok_q <= 1'b0;
      loader_last_opcode_q <= 8'd0;
      loader_last_chunk_q <= 2'd0;
      loader_command_payload_addr_q <= 32'd0;
      loader_wait_cycles_q <= 32'd0;
      loader_read_data_q <= 512'd0;
      top1_busy_q <= 1'b0;
      top1_done_q <= 1'b0;
      top1_error_q <= 1'b0;
      top1_token_q <= 32'd0;
      top1_score_q024_q <= 32'd0;
      top1_rows_scanned_q <= 32'd0;
      top1_cycle_count_q <= 32'd0;
      dummy_cycle_q <= 32'd0;
    end else begin
      dummy_cycle_q <= dummy_cycle_q + 32'd1;
      loader_done_q <= 1'b0;
      loader_last_accepted_q <= 1'b0;
      top1_busy_q <= 1'b0;
      top1_done_q <= 1'b0;
      if (rowstream_status_clear) begin
        loader_error_q <= 1'b0;
        loader_last_magic_ok_q <= 1'b0;
      end
      if (rowstream_command_event) begin
        loader_last_accepted_q <= 1'b1;
        loader_done_q <= 1'b1;
        loader_error_q <= 1'b0;
        loader_last_magic_ok_q <= rowstream_command_payload[0 +: 32] == 32'h33445244;
        loader_last_opcode_q <= rowstream_command_payload[32 +: 8];
        loader_last_chunk_q <= rowstream_command_payload[40 +: 2];
        loader_command_payload_addr_q <= rowstream_command_payload[48 +: 32];
        loader_wait_cycles_q <= dummy_cycle_q;
        loader_read_data_q <= {16{rowstream_command_payload[80 +: 32] ^ rowstream_command_payload[48 +: 32]}};
      end
      if (rowstream_top1_status_clear) begin
        top1_error_q <= 1'b0;
        top1_token_q <= 32'd0;
        top1_score_q024_q <= 32'd0;
        top1_rows_scanned_q <= 32'd0;
        top1_cycle_count_q <= 32'd0;
      end
      if (rowstream_top1_start) begin
        top1_done_q <= 1'b1;
        top1_error_q <= 1'b0;
        top1_token_q <= rowstream_top1_hidden_vector[31:0] ^ 32'h0000_1234;
        top1_score_q024_q <= rowstream_top1_hidden_vector[63:32] ^ 32'h00ab_cdef;
        top1_rows_scanned_q <= 32'd50257;
        top1_cycle_count_q <= dummy_cycle_q;
      end
    end
  end

  wire unused_clk_50 = clk_50;
endmodule

`default_nettype wire
