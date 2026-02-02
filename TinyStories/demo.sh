#!/usr/bin/env bash
set -euo pipefail

# Tools (adapt paths as needed)
MLIR_OPT=mlir-opt                              # from nixpkgs#llvmPackages_21.mlir
TORCH_MLIR_OPT=/home/roland/mlir_venv/bin/torch-mlir-opt
# CIRCT_OPT=/home/roland/circt-nix/result/bin/circt-opt
CIRCT_OPT=/home/roland/circt/build/bin/circt-opt
FIRTOOL=/home/roland/circt-nix/result/bin/firtool
CIRCT_TRANSLATE=/home/roland/circt-nix/result/bin/circt-translate

rm -f dot.v

#!/usr/bin/env bash
set -euo pipefail

run() {
  local name="$1"; shift
  local out="$1"; shift
  local log="${out}.log"

  echo "=== ${name}"
  if ! "$@" >"$out" 2>"$log"; then
    echo "!!! FAILED: ${name}"
    echo "    command: $*"
    echo "    stdout:  $out"
    echo "    stderr:  $log"
    echo "---- stderr (tail) ----"
    echo "---- stderr (errors) ----"
    grep -nE "error:|remark:|warning:|failed to legalize|unrealized_conversion_cast" "$log" | head -n 80 || true
    echo "---- stderr (tail) ----"
    tail -n 40 "$log" || true
    exit 1
  fi
}

run "1) PyTorch → torch dialect" tinystories_1m_torch.mlir \
  python compile-pytorch.py

run "2) Torch → Linalg-on-Tensors" tinystories_1m_linalg.mlir \
  "$TORCH_MLIR_OPT" tinystories_1m_torch.mlir \
    -verify-each \
    --torch-reduce-op-variants \
    --torch-function-to-torch-backend-pipeline \
    --torch-backend-to-linalg-on-tensors-backend-pipeline \
    -canonicalize

run "3) Linalg → CF" tinystories_1m_cf.mlir \
  "$MLIR_OPT" tinystories_1m_linalg.mlir \
    -verify-each \
    --empty-tensor-to-alloc-tensor \
    --one-shot-bufferize="bufferize-function-boundaries" \
    --buffer-results-to-out-params \
    --bufferization-lower-deallocations \
    --convert-bufferization-to-memref \
    --memref-expand \
    --convert-linalg-to-affine-loops \
    --lower-affine \
    --convert-scf-to-cf \
    -canonicalize

run "3b) normalize-memrefs" tinystories_1m_cf-norm.mlir \
  "$MLIR_OPT" tinystories_1m_cf.mlir \
    -verify-each \
    -normalize-memrefs \
    -canonicalize

run "4a) flatten-memref" tinystories_1m_4a.mlir \
  "$CIRCT_OPT" tinystories_1m_cf-norm.mlir -verify-each -flatten-memref

run "4b) flatten-memref-calls" tinystories_1m_4b.mlir \
  "$CIRCT_OPT" tinystories_1m_4a.mlir -verify-each -flatten-memref-calls

run "4c) canonicalize" tinystories_1m_4c.mlir \
  "$CIRCT_OPT" tinystories_1m_4b.mlir -verify-each -canonicalize

run "4d) handshake-legalize-memrefs" tinystories_1m_4d.mlir \
  "$CIRCT_OPT" tinystories_1m_4c.mlir -verify-each -handshake-legalize-memrefs

run "4e) lower-cf-to-handshake" tinystories_1m_4e.mlir \
  "$CIRCT_OPT" tinystories_1m_4d.mlir -verify-each --lower-cf-to-handshake

run "4f) canonicalize" tinystories_1m_handshake.mlir \
  "$CIRCT_OPT" tinystories_1m_4e.mlir -verify-each -canonicalize

echo
run "5a) handshake-lower-extmem-to-hw + materialize forks/sinks" tinystories_1m_hs-ext.mlir \
  "$CIRCT_OPT" tinystories_1m_handshake.mlir \
    -handshake-lower-extmem-to-hw \
    -handshake-materialize-forks-sinks \
    -canonicalize

echo
run "5b) lower-handshake-to-hw" tinystories_1m_hw0.mlir \
  "$CIRCT_OPT" tinystories_1m_hs-ext.mlir \
    -lower-handshake-to-hw \
    -canonicalize

echo
run "5c) ESI lowering on HW" tinystories_1m_hw.mlir \
  "$CIRCT_OPT" tinystories_1m_hw0.mlir \
    -lower-esi-types \
    -lower-esi-ports \
    -lower-esi-to-hw \
    -canonicalize

echo
run "5.5) Cleanup inner symbols" tinystories_1m_hw-clean.mlir \
  "$CIRCT_OPT" tinystories_1m_hw.mlir \
    -firrtl-inner-symbol-dce \
    -symbol-dce \
    -canonicalize

echo
# For verilog export, keep stderr in a log; write SV to dot.sv directly.
# (circt-opt uses -o for textual outputs; -export-verilog writes to the output stream)
run "6) HW+Seq → SV" tinystories_1m.sv \
  "$CIRCT_OPT" tinystories_1m_hw-clean.mlir \
    -lower-seq-hlmem \
    -lower-seq-fifo \
    -lower-seq-shiftreg \
    -lower-seq-to-sv \
    -lower-hw-to-sv \
    -canonicalize \
    -export-verilog

echo
echo "Generated:"
ls -lh tinystories_1m.sv
