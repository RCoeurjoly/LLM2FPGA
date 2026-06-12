`timescale 1ns/1ps
`default_nettype none

module task6_ypcb_pcie_uberddr3_rowstream_loader_only_top1_top #(
  parameter int DDR_BYTE_LANES = 1
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
  task6_ypcb_pcie_uberddr3_rowstream_loader_top #(
    .DDR_BYTE_LANES(DDR_BYTE_LANES),
    .ENABLE_PCIE_TOP1(1'b1),
    // M1 needs both the internal MLP/residual selftest and the live
    // host-supplied accelerator aperture for board acceptance.
    .ENABLE_PCIE_MLP_SELFTEST(1'b1),
    .ENABLE_PCIE_MLP_ACCEL(1'b1),
    .ENABLE_PCIE_M2_FULL_BLOCK_ACCEL(1'b0)
  ) impl (
    .pci_exp_txp(pci_exp_txp),
    .pci_exp_txn(pci_exp_txn),
    .pci_exp_rxp(pci_exp_rxp),
    .pci_exp_rxn(pci_exp_rxn),
    .sys_clk_p(sys_clk_p),
    .sys_clk_n(sys_clk_n),
    .sys_rst_n(sys_rst_n),
    .clk_50(clk_50),
    .led(led),
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
    .ddram_we_n(ddram_we_n)
  );
endmodule

`default_nettype wire
