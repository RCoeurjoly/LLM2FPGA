set src_root /home/roland/pcie_7x
set out_dir [file normalize artifacts/task6/vivado-pcie-smoke]
file mkdir $out_dir

read_verilog -sv \
  $src_root/src/xilinx_pcie_mmcm.v \
  $src_root/src/axil_to_al.v \
  $src_root/src/axis_pcie_to_al_us.v \
  $src_root/src/pcie_7x.v \
  $src_root/src/pcie_axi_rx.v \
  $src_root/src/pcie_axi_tx.v \
  $src_root/src/pcie_block.v \
  $src_root/src/pcie_brams.v \
  $src_root/src/pcie_tx_thrtl_ctl.v \
  $src_root/src/pipe_wrapper_gtx.v \
  $src_root/src/aximm-minimal/pcie_7x_top_aximm_ypcb_480t.v \
  $src_root/src/aximm-minimal/pcie_7x_top_aximm.v \
  $src_root/src/aximm-minimal/axil_minimum.v

read_xdc $src_root/pcie_7x_ypcb_k480t.xdc
synth_design -top pcie_7x_top_aximm_ypcb_480t -part xc7k480tffg1156-2
write_checkpoint -force $out_dir/post_synth.dcp
opt_design
place_design
write_checkpoint -force $out_dir/post_place.dcp
route_design
write_checkpoint -force $out_dir/post_route.dcp
report_timing_summary -file $out_dir/timing_summary.rpt
report_utilization -file $out_dir/utilization.rpt
write_bitstream -force $out_dir/ypcb_pcie_smoke_vivado.bit
