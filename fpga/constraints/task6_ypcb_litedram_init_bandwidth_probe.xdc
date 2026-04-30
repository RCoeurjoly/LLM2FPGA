set_property LOC AH27 [get_ports clk200_p]
set_property IOSTANDARD LVDS [get_ports clk200_p]
set_property LOC AH28 [get_ports clk200_n]
set_property IOSTANDARD LVDS [get_ports clk200_n]
create_clock -period 5.000 -name clk200_p [get_ports clk200_p]

set_property LOC R28 [get_ports SYS_RSTN]
set_property IOSTANDARD LVCMOS18 [get_ports SYS_RSTN]
