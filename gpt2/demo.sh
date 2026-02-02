#!/usr/bin/env bash
set -euo pipefail

# Tools (adapt paths as needed)
MLIR_OPT=mlir-opt                              # from nixpkgs#llvmPackages_21.mlir
TORCH_MLIR_OPT=/home/roland/mlir_venv/bin/torch-mlir-opt
CIRCT_OPT=/home/roland/circt-nix/result/bin/circt-opt
FIRTOOL=/home/roland/circt-nix/result/bin/firtool
CIRCT_TRANSLATE=/home/roland/circt-nix/result/bin/circt-translate

rm -f *.mlir
rm -f dot.v

echo "### 1) PyTorch → Torch-MLIR (torch dialect)"
python compile-pytorch.py > dot-torch.mlir

echo
echo "### 2) Torch → Linalg-on-Tensors"
$TORCH_MLIR_OPT dot-torch.mlir \
  --torch-reduce-op-variants \
  --torch-function-to-torch-backend-pipeline \
  --torch-backend-to-linalg-on-tensors-backend-pipeline \
  -canonicalize \
  > dot-linalg.mlir

echo "### 3) Linalg → CF (CIRCT-compatible bufferization)"
$MLIR_OPT dot-linalg.mlir \
  --empty-tensor-to-alloc-tensor \
  --one-shot-bufferize="bufferize-function-boundaries" \
  --buffer-results-to-out-params \
  --bufferization-lower-deallocations \
  --convert-bufferization-to-memref \
  --memref-expand \
  --convert-linalg-to-affine-loops \
  --lower-affine \
  --convert-scf-to-cf \
  -canonicalize \
  > dot-cf.mlir

$MLIR_OPT dot-cf.mlir --print-op-stats -o /dev/null \
  > dot-cf.stats || true

echo
echo "### 4) CF → Handshake (with 1D memrefs)"
$CIRCT_OPT dot-cf.mlir \
  -flatten-memref \
  -flatten-memref-calls \
  -canonicalize \
  -handshake-legalize-memrefs \
  --lower-cf-to-handshake \
  -canonicalize \
  > dot-handshake.mlir

echo
echo "### 5a) handshake-lower-extmem-to-hw + materialize forks/sinks"
$CIRCT_OPT dot-handshake.mlir \
  -handshake-lower-extmem-to-hw \
  -handshake-materialize-forks-sinks \
  -canonicalize \
  > dot-hs-ext.mlir

echo
echo "### 5b) lower-handshake-to-hw only"
$CIRCT_OPT dot-hs-ext.mlir \
  -lower-handshake-to-hw \
  -canonicalize \
  > dot-hw0.mlir

echo
echo "### 5c) ESI lowering on HW"
$CIRCT_OPT dot-hw0.mlir \
  -lower-esi-types \
  -lower-esi-ports \
  -lower-esi-to-hw \
  -canonicalize \
  > dot-hw.mlir

echo
echo "### 5.5) Cleanup inner symbols"
$CIRCT_OPT dot-hw.mlir \
  -firrtl-inner-symbol-dce \
  -symbol-dce \
  -canonicalize \
  > dot-hw-clean.mlir


echo
echo "### 6) HW+Seq → SV"
$CIRCT_OPT dot-hw-clean.mlir \
  -lower-seq-hlmem \
  -lower-seq-fifo \
  -lower-seq-shiftreg \
  -lower-seq-to-sv \
  -lower-hw-to-sv \
  -canonicalize \
  -export-verilog \
  -o /dev/null > dot.sv

echo
echo "Generated:"
ls -lh dot.sv
