set_property PACKAGE_PIN AA28 [get_ports SYS_CLK]
set_property IOSTANDARD LVCMOS18 [get_ports SYS_CLK]
create_clock -period 20.000 -name SYS_CLK [get_ports SYS_CLK]

set_property PACKAGE_PIN R28 [get_ports data_i]
set_property IOSTANDARD LVCMOS18 [get_ports data_i]

set_property PACKAGE_PIN AN25 [get_ports data_p]
set_property IOSTANDARD SSTL15 [get_ports data_p]
set_property PACKAGE_PIN AP25 [get_ports data_n]
set_property IOSTANDARD SSTL15 [get_ports data_n]
