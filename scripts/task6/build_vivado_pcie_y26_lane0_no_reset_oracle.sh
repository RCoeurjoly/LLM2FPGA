#!/usr/bin/env bash
set -euo pipefail

out_dir=${1:-artifacts/task6/vivado-pcie-y26-lane0-no-reset-oracle}
vivado_bin=${VIVADO_BIN:-/home/roland/Vivado/2025.2.1/Vivado/bin/vivado}

mkdir -p "$out_dir"
"$vivado_bin" \
  -mode batch \
  -source scripts/task6/build_vivado_pcie_y26_lane0_no_reset_oracle.tcl \
  -journal "$out_dir/vivado.jou" \
  -log "$out_dir/vivado.log"
