set_property PACKAGE_PIN AH27 [get_ports clk200_p]
set_property IOSTANDARD LVDS_25 [get_ports clk200_p]
set_property PACKAGE_PIN AH28 [get_ports clk200_n]
set_property IOSTANDARD LVDS_25 [get_ports clk200_n]
create_clock -period 5.000 -name clk200 [get_ports clk200_p]

set_property PACKAGE_PIN R28 [get_ports SYS_RSTN]
set_property IOSTANDARD LVCMOS18 [get_ports SYS_RSTN]
