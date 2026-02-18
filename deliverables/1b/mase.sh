#!/usr/bin/env bash
set -euo pipefail

git clone git@github.com:RCoeurjoly/mase.git
cd mase || exit
git checkout RCoeurjoly/flake

# Dev env (works, not fully polished)
nix develop
if [ -f .venv/bin/activate ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
else
  echo "Missing .venv/bin/activate" >&2
  echo "Create it by running 'nix develop' as documented above." >&2
  exit 1
fi

# Generate RTL via MASE helper
python LLM2FPGA.py

# Check outputs
ls ~/.mase

# Build yosys-slang (per its README), ensure yosys in PATH
cd ~/yosys-slang || exit

# Elaborate with slang (SystemVerilog)
yosys -m build/slang.so -p \
  "read_slang \
     /home/roland/mase/src/mase_components/memory/rtl/fifo.sv \
     /home/roland/mase/src/mase_components/common/rtl/mux.sv \
     /home/roland/.mase/top/hardware/rtl/*.sv \
     /home/roland/mase/src/mase_components/common/rtl/single_element_repeat.sv \
     /home/roland/mase/src/mase_components/common/rtl/unpacked_register_slice.sv \
     /home/roland/mase/src/mase_components/cast/rtl/fixed_rounding.sv \
     /home/roland/mase/src/mase_components/memory/rtl/input_buffer.sv \
     /home/roland/mase/src/mase_components/memory/rtl/unpacked_skid_buffer.sv \
     /home/roland/mase/src/mase_components/cast/rtl/fixed_round.sv \
     /home/roland/mase/src/mase_components/cast/rtl/fixed_signed_cast.sv \
     /home/roland/mase/src/mase_components/cast/rtl/signed_clamp.sv \
     /home/roland/mase/src/mase_components/cast/rtl/floor_round.sv \
     /home/roland/mase/src/mase_components/memory/rtl/blk_mem_gen_0.sv \
     /home/roland/mase/src/mase_components/memory/rtl/simple_dual_port_ram.sv \
     --top top"
