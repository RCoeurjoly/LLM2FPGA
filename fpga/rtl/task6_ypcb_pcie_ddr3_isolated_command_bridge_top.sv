`timescale 1ns/1ps
`default_nettype none

module task6_ypcb_pcie_ddr3_isolated_command_bridge_top #(
  parameter int DDR_BYTE_LANES = 2
) (
  output wire        pci_exp_txp,
  output wire        pci_exp_txn,
  input  wire        pci_exp_rxp,
  input  wire        pci_exp_rxn,
  input  wire        sys_clk_p,
  input  wire        sys_clk_n,
  input  wire        sys_rst_n,
  input  wire        clk_50,
  output wire  [2:0] led,
  output wire [14:0] ddram_a,
  output wire  [2:0] ddram_ba,
  output wire        ddram_cas_n,
  output wire        ddram_cke,
  output wire        ddram_clk_n,
  output wire        ddram_clk_p,
  output wire        ddram_cs_n,
  inout  wire [DDR_BYTE_LANES * 8 - 1:0] ddram_dq,
  inout  wire [DDR_BYTE_LANES - 1:0] ddram_dqs_n,
  inout  wire [DDR_BYTE_LANES - 1:0] ddram_dqs_p,
  output wire        ddram_odt,
  output wire        ddram_ras_n,
  output wire        ddram_reset_n,
  output wire        ddram_we_n
);
  localparam int COMMAND_WIDTH = 208;

  wire pcie_user_clk;
  wire pcie_user_reset;
  wire [3:0] pcie_led;

  wire ddr_controller_clk;
  wire ddr_controller_rst_n;
  wire ddr_calib_complete;
  wire ddr_boot_done;
  wire [31:0] ddr_debug1;

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

  assign led[0] = pcie_led[0];
  assign led[1] = ddr_controller_rst_n && !ddr_boot_done;
  assign led[2] = ddr_boot_done;

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

  axil_minimum command_bridge (
    .clk(pcie_user_clk),
    .rst_n(!pcie_user_reset),
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
    .s_axi_rresp(s_axi_rresp)
  );

  task6_ypcb_uberddr3_bist_rowstream_loader_top #(
    .BYTE_LANES(DDR_BYTE_LANES),
    .JTAG_CHAIN(3),
    .JTAG_COMMAND_CHAIN(2),
    .DISABLE_JTAG_DEBUG_SHIFT(1),
    .BOOT_ISOLATE_UNTIL_CALIB(1),
    .PLL_CLKOUT0_DIVIDE(3),
    .PLL_CLKOUT1_DIVIDE(3),
    .PLL_CLKOUT2_DIVIDE(12),
    .CONTROLLER_CLK_PERIOD_PS(12_000),
    .DDR3_CLK_PERIOD_PS(3_000),
    .DLL_OFF_PARAM(1'b0),
    .SPEED_BIN_PARAM(1),
    .SDRAM_CAPACITY_PARAM(4),
    .BIST_MODE_PARAM(2),
    .BIST_TEST_DATAMASK(1'b0)
  ) isolated_ddr3 (
    .clk50(clk_50),
    .SYS_RSTN(sys_rst_n),
    .ddram_a(ddram_a),
    .ddram_ba(ddram_ba),
    .ddram_cas_n(ddram_cas_n),
    .ddram_cke(ddram_cke),
    .ddram_clk_n(ddram_clk_n),
    .ddram_clk_p(ddram_clk_p),
    .ddram_cs_n(ddram_cs_n),
    .ddram_dq(ddram_dq),
    .ddram_dqs_n(ddram_dqs_n),
    .ddram_dqs_p(ddram_dqs_p),
    .ddram_odt(ddram_odt),
    .ddram_ras_n(ddram_ras_n),
    .ddram_reset_n(ddram_reset_n),
    .ddram_we_n(ddram_we_n),
    .pcie_command_payload_i({COMMAND_WIDTH{1'b0}}),
    .pcie_command_event_i(1'b0),
    .pcie_status_clear_i(1'b0),
    .pcie_controller_clk_o(ddr_controller_clk),
    .pcie_controller_rst_n_o(ddr_controller_rst_n),
    .pcie_calib_complete_o(ddr_calib_complete),
    .pcie_boot_done_o(ddr_boot_done),
    .pcie_ddr_debug1_o(ddr_debug1),
    .pcie_loader_done_o(),
    .pcie_loader_error_o(),
    .pcie_loader_last_accepted_o(),
    .pcie_loader_last_magic_ok_o(),
    .pcie_loader_last_opcode_o(),
    .pcie_loader_last_chunk_o(),
    .pcie_loader_command_payload_addr_o(),
    .pcie_loader_wait_cycles_o(),
    .pcie_loader_read_data_o(),
    .pcie_top1_hidden_vector_i(512'd0),
    .pcie_top1_start_i(1'b0),
    .pcie_top1_status_clear_i(1'b0),
    .pcie_top1_busy_o(),
    .pcie_top1_done_o(),
    .pcie_top1_error_o(),
    .pcie_top1_token_o(),
    .pcie_top1_score_q024_o(),
    .pcie_top1_rows_scanned_o(),
    .pcie_top1_cycle_count_o(),
    .pcie_top1_debug_status_o(),
    .pcie_top1_debug_reader_addr_o(),
    .pcie_top1_debug_wb_ack_count_o(),
    .pcie_top1_debug_wb_err_count_o(),
    .pcie_top1_debug_packet_wb_write_ack_count_o(),
    .pcie_top1_debug_packet_wb_read_ack_count_o()
  );

  wire unused_ddr_calib_complete = ddr_calib_complete;
  wire [31:0] unused_ddr_debug1 = ddr_debug1;
  wire unused_ddr_controller_clk = ddr_controller_clk;
endmodule

`default_nettype wire
