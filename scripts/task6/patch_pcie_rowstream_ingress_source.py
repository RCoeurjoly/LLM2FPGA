#!/usr/bin/env python3
from pathlib import Path
import sys


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"{label} not found")
    return text.replace(old, new, 1)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_pcie_rowstream_ingress_source.py <pcie_7x_top_aximm.v>")

    path = Path(sys.argv[1])
    pcie_7x_path = path.parent.parent / "pcie_7x.v"

    pcie_7x_text = pcie_7x_path.read_text()
    pcie_7x_text = pcie_7x_text.replace(
        'parameter         PCIE_GT_DEVICE = "GTP",',
        'parameter         PCIE_GT_DEVICE = "GTX",',
        1,
    )
    pcie_7x_text = pcie_7x_text.replace(
        'generate if (PCIE_GT_DEVICE == "GTX") begin : gt_wrapper_gtx',
        'generate if (1) begin : gt_wrapper_gtx',
        1,
    )
    pcie_7x_path.write_text(pcie_7x_text)

    text = path.read_text()
    text = text.replace('parameter GT_DEVICE           = "GTP",', 'parameter GT_DEVICE           = "GTX",', 1)
    text = replace_once(
        text,
        "  .pipe_mmcm_rst_n                            ( 1 ),",
        "  .pipe_mmcm_rst_n                            ( sys_rst_n_c ),",
        "PIPE MMCM reset connection",
    )
    text = replace_once(
        text,
        """  always @(posedge user_clk) begin
    user_reset_q  <= user_reset;
    user_lnk_up_q <= user_lnk_up;
  end
""",
        """  reg [9:0] task6_pcie_bar_ready_cnt = 0;
  wire task6_pcie_bar_base_ready = !user_reset_q && user_lnk_up_q && cfg_command[1];
  wire task6_pcie_bar_ready = task6_pcie_bar_ready_cnt[9];

  always @(posedge user_clk) begin
    user_reset_q  <= user_reset;
    user_lnk_up_q <= user_lnk_up;
    if (!task6_pcie_bar_base_ready) begin
      task6_pcie_bar_ready_cnt <= 0;
    end else if (!task6_pcie_bar_ready) begin
      task6_pcie_bar_ready_cnt <= task6_pcie_bar_ready_cnt + 1'b1;
    end
  end
""",
        "registered user reset/link block",
    )
    text = text.replace(
        "  output      [3:0] led\n);",
        "  output      [3:0] led,\n"
        "  output      task6_user_clk_o,\n"
        "  output      task6_user_reset_o,\n"
        "  output [31:0] task6_s_axi_awaddr_o,\n"
        "  output        task6_s_axi_awvalid_o,\n"
        "  input         task6_s_axi_awready_i,\n"
        "  output [31:0] task6_s_axi_wdata_o,\n"
        "  output [3:0]  task6_s_axi_wstrb_o,\n"
        "  output        task6_s_axi_wvalid_o,\n"
        "  input         task6_s_axi_wready_i,\n"
        "  input  [1:0]  task6_s_axi_bresp_i,\n"
        "  input         task6_s_axi_bvalid_i,\n"
        "  output        task6_s_axi_bready_o,\n"
        "  output [31:0] task6_s_axi_araddr_o,\n"
        "  output        task6_s_axi_arvalid_o,\n"
        "  input         task6_s_axi_arready_i,\n"
        "  input  [31:0] task6_s_axi_rdata_i,\n"
        "  input         task6_s_axi_rvalid_i,\n"
        "  output        task6_s_axi_rready_o,\n"
        "  input  [1:0]  task6_s_axi_rresp_i\n);",
        1,
    )
    text = replace_once(
        text,
        "wire            m_al_rready;\naxis_pcie_to_al_us #(",
        "wire            m_al_rready;\nwire            task6_pcie_bar_rx_tready;\nassign m_axis_rx_tready = task6_pcie_bar_ready && task6_pcie_bar_rx_tready;\naxis_pcie_to_al_us #(",
        "BAR RX ready gate insertion",
    )
    text = replace_once(
        text,
        "\t.rst_n(!user_reset_q),\n\t.cfg_completer_id({ cfg_bus_number, cfg_device_number, cfg_function_number }),",
        "\t.rst_n(task6_pcie_bar_ready),\n\t.cfg_completer_id({ cfg_bus_number, cfg_device_number, cfg_function_number }),",
        "PCIe-to-AL reset gate",
    )
    text = replace_once(
        text,
        "\t.s_axis_rx_tready(m_axis_rx_tready),",
        "\t.s_axis_rx_tready(task6_pcie_bar_rx_tready),",
        "PCIe-to-AL RX ready output",
    )
    text = replace_once(
        text,
        "\t.rst_n(!user_reset_q),\n\t// AXI Lite Interface",
        "\t.rst_n(task6_pcie_bar_ready),\n\t// AXI Lite Interface",
        "AXI-to-AL reset gate",
    )
    old = """// Instantiate axil_minimum
axil_minimum axil_minimum_inst (
\t.clk(user_clk),
\t.rst_n(!user_reset_q),
\t// AXI Lite Interface
\t.s_axi_awaddr(s_axi_awaddr),
\t.s_axi_awvalid(s_axi_awvalid),
\t.s_axi_awready(s_axi_awready),
\t.s_axi_wdata(s_axi_wdata),
\t.s_axi_wstrb(s_axi_wstrb),
\t.s_axi_wvalid(s_axi_wvalid),
\t.s_axi_wready(s_axi_wready),
\t.s_axi_bresp(s_axi_bresp),
\t.s_axi_bvalid(s_axi_bvalid),
\t.s_axi_bready(s_axi_bready),
\t.s_axi_araddr(s_axi_araddr),
\t.s_axi_arvalid(s_axi_arvalid),
\t.s_axi_arready(s_axi_arready),
\t.s_axi_rdata(s_axi_rdata),
\t.s_axi_rvalid(s_axi_rvalid),
\t.s_axi_rready(s_axi_rready),
\t.s_axi_rresp(s_axi_rresp)
);
"""
    new = """assign task6_user_clk_o = user_clk;
assign task6_user_reset_o = !task6_pcie_bar_ready;
assign task6_s_axi_awaddr_o = s_axi_awaddr;
assign task6_s_axi_awvalid_o = s_axi_awvalid;
assign s_axi_awready = task6_s_axi_awready_i;
assign task6_s_axi_wdata_o = s_axi_wdata;
assign task6_s_axi_wstrb_o = s_axi_wstrb;
assign task6_s_axi_wvalid_o = s_axi_wvalid;
assign s_axi_wready = task6_s_axi_wready_i;
assign s_axi_bresp = task6_s_axi_bresp_i;
assign s_axi_bvalid = task6_s_axi_bvalid_i;
assign task6_s_axi_bready_o = s_axi_bready;
assign task6_s_axi_araddr_o = s_axi_araddr;
assign task6_s_axi_arvalid_o = s_axi_arvalid;
assign s_axi_arready = task6_s_axi_arready_i;
assign s_axi_rdata = task6_s_axi_rdata_i;
assign s_axi_rvalid = task6_s_axi_rvalid_i;
assign task6_s_axi_rready_o = s_axi_rready;
assign s_axi_rresp = task6_s_axi_rresp_i;
"""
    if old not in text:
        raise SystemExit("axil_minimum instantiation block not found")
    path.write_text(text.replace(old, new, 1))


if __name__ == "__main__":
    main()
