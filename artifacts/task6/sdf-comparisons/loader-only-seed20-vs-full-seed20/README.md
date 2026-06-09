# Task 6 SDF Delay Comparison

- good SDF: `/nix/store/2nffvbhh7p3plhrp1y382rmrlpvs4w4b-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.sdf`
- bad SDF: `/nix/store/j6sha4hcnlrid0sgsmviq3314m4ck68s-task6-ypcb-pcie-uberddr3-rowstream-loader-seed20.sdf`
- common keys: `5457`
- good-only keys: `780`
- bad-only keys: `1882`

## Category Summary

| Category | Good count | Good max ps | Bad count | Bad max ps |
| --- | ---: | ---: | ---: | ---: |
| `bscan` | 4166 | 10652.0 | 4166 | 10800.0 |
| `cdc` | 5 | 1350.0 | 5 | 1320.0 |
| `clocking` | 11708 | 18198.0 | 15899 | 18472.0 |
| `ddr3_phy` | 2325 | 8910.0 | 2326 | 9195.0 |
| `gt` | 3415 | 18198.0 | 4047 | 18472.0 |
| `idelay` | 288 | 7800.0 | 289 | 8340.0 |
| `iserdes` | 416 | 3299.0 | 416 | 4549.0 |
| `oserdes` | 796 | 3299.0 | 796 | 4549.0 |
| `other` | 153625 | 11175.0 | 226540 | 10875.0 |
| `pcie` | 9463 | 18198.0 | 11255 | 18472.0 |
| `reset` | 2090 | 8460.0 | 2127 | 9540.0 |
| `rowstream_top1` | 11737 | 9255.0 | 16763 | 10800.0 |

## Largest Bad-Slower Deltas

- `9585.0` ps: `INTERCONNECT:pcie_ingress.ingress.accepted_count_q[16]$LUT$N/A3`
- `9525.0` ps: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.Y[5]$LUT$N/A4`
- `9400.0` ps: `INTERCONNECT:pcie_ingress.ingress.accepted_count_q[2]$LUT$N/A1`
- `9345.0` ps: `INTERCONNECT:$auto$opt_expr.cc:1948:replace_const_cells$N.B[1]$LUT$N/A3`
- `9108.0` ps: `INTERCONNECT:rowstream_ddr3.loader_fullbeat_expected_base_q[2]$LUT$N/A1`
- `9000.0` ps: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.B[1]$LUT$N/A3`
- `8801.0` ps: `INTERCONNECT:rowstream_ddr3.uberddr3.ddr3_controller_inst.check_test_address_counter[10]$LUT$N/A1`
- `8790.0` ps: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.Y[5]$LUT$N/A3`
- `8730.0` ps: `INTERCONNECT:pcie_ingress.ingress.accepted_count_q[30]$LUT$N/A3`
- `8730.0` ps: `INTERCONNECT:rowstream_ddr3.jtag_command_chunk_data[2]$LUT$N/A3`
- `8700.0` ps: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.X[0]$LUT$N/A3`
- `8685.0` ps: `INTERCONNECT:$abc$$auto$blifparse.cc:535:parse_blif$N.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.lut0.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.genblk1.lut0/A2`
- `8355.0` ps: `INTERCONNECT:rowstream_ddr3.jtag_command_chunk_data[7]$LUT$N/A3`
- `8318.0` ps: `INTERCONNECT:pcie_ingress.rowstream_heartbeat_count_pcie_q[10]$LUT$N/A1`
- `8280.0` ps: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.Y[1]$LUT$N/A3`
- `8183.0` ps: `INTERCONNECT:pcie_ingress.rowstream_clk_counter_q[11]$LUT$N/A1`
- `7895.0` ps: `INTERCONNECT:rowstream_ddr3.uberddr3.idelay_dqs_cntvaluein[4]$LUT$N/A1`
- `7890.0` ps: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.B[0]$LUT$N/A5`
- `7868.0` ps: `INTERCONNECT:pcie_ingress.ingress.top1_start_count_q[8]$LUT$N/A1`
- `7805.0` ps: `INTERCONNECT:rowstream_ddr3.uberddr3.idelay_data_cntvaluein[3]$LUT$N/A1`

## Bad Top Delays

- `18472.0` ps ['pcie', 'gt', 'clocking']: `INTERCONNECT:pcie_7x_top_aximm_i.pcie_7x_i.in_module_mmcm.pipe_clock_i.txoutclk0_i/I0`
- `10875.0` ps ['other']: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.genblk1.slice[0].genblk1.carry4$split$xorcy0/A1`
- `10860.0` ps ['other']: `INTERCONNECT:$abc$$auto$blifparse.cc:535:parse_blif$N/A3`
- `10860.0` ps ['other']: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.genblk1.slice[0].genblk1.carry4$split$xorcy0/A3`
- `10845.0` ps ['other']: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.Y[5]$LUT$N/A1`
- `10845.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A1`
- `10815.0` ps ['other']: `INTERCONNECT:$auto$alumacc.cc:485:replace_alu$N.Y[1]$LUT$N/A1`
- `10815.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A1`
- `10815.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A2`
- `10815.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A2`
- `10815.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A2`
- `10815.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A2`
- `10800.0` ps ['rowstream_top1', 'bscan']: `INTERCONNECT:rowstream_ddr3.jtag_command_chunk_data[4]$LUT$N/A1`
- `10800.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A1`
- `10785.0` ps ['rowstream_top1', 'bscan']: `INTERCONNECT:rowstream_ddr3.jtag_command_chunk_data[6]$LUT$N/A1`
- `10785.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A1`
- `10770.0` ps ['rowstream_top1', 'bscan']: `INTERCONNECT:rowstream_ddr3.jtag_command_chunk_data[6]$LUT$N/A1`
- `10770.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A1`
- `10755.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A2`
- `10755.0` ps ['other']: `INTERCONNECT:$PACKER_GND_NET$LUT$N/A2`
