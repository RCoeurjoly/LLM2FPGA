
# YPCB PCIe Gen1 oracle: external PERST# on board-file Y26 and Vivado systest lane-0 placement.

set_property PACKAGE_PIN J8 [get_ports {sys_clk_p}]
set_property PACKAGE_PIN J7 [get_ports {sys_clk_n}]

set_property PACKAGE_PIN H6 [get_ports {pci_exp_rxp}]
set_property PACKAGE_PIN H5 [get_ports {pci_exp_rxn}]
set_property PACKAGE_PIN F2 [get_ports {pci_exp_txp}]
set_property PACKAGE_PIN F1 [get_ports {pci_exp_txn}]

set_property PACKAGE_PIN Y26 [get_ports {sys_rst_n}]
set_property PULLUP true [get_ports {sys_rst_n}]
set_property IOSTANDARD LVCMOS18 [get_ports {sys_rst_n}]

set_property PACKAGE_PIN AA28 [get_ports {clk_50}]
set_property IOSTANDARD LVCMOS18 [get_ports {clk_50}]

set_property PACKAGE_PIN N30 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[0]}]
set_property PACKAGE_PIN M30 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[1]}]
set_property PACKAGE_PIN P30 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[2]}]

set_property LOC GTXE2_CHANNEL_X0Y23 [get_cells {pcie_7x_top_aximm_i/pcie_7x_i/gt_wrapper_gtx/pipe_wrapper_i/gtxe2_channel_i}]
set_property LOC PCIE_X0Y0 [get_cells {pcie_7x_top_aximm_i/pcie_7x_i/pcie_block_inst/pcie_2_1_block}]

create_clock -name pcie_100mhz_refin -period 10 [get_nets pcie_7x_top_aximm_i/sys_clk]
create_clock -name pcie_125mhz_d_rxusr_oob_p -period 8 [get_nets pcie_7x_top_aximm_i/pcie_7x_i/in_module_mmcm.pipe_clock_i/clk_125mhz]
create_clock -name pcie_62d5mhz_user1_user2 -period 16 [get_nets pcie_7x_top_aximm_i/pcie_7x_i/in_module_mmcm.pipe_clock_i/userclk1]

