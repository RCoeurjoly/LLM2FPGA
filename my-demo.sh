#!/usr/bin/env bash
set -euo pipefail

# Tools (adapt paths as needed)
MLIR_OPT=mlir-opt                              # from nixpkgs#llvmPackages_21.mlir
TORCH_MLIR_OPT=/home/roland/mlir_venv/bin/torch-mlir-opt
CIRCT_OPT=/home/roland/circt-nix/result/bin/circt-opt
FIRTOOL=/home/roland/circt-nix/result/bin/firtool
CIRCT_TRANSLATE=/home/roland/circt-nix/result/bin/circt-translate

rm -f my*.mlir
rm -f my-dot.v

echo "### 1) PyTorch → Torch-MLIR (torch dialect)"
python my_compile-pytorch.py > my-dot-torch.mlir

echo
echo "### 2) Torch → Linalg-on-Tensors"
$TORCH_MLIR_OPT my-dot-torch.mlir \
  --torch-function-to-torch-backend-pipeline \
  --torch-backend-to-linalg-on-tensors-backend-pipeline \
  -canonicalize \
  > my-dot-linalg.mlir

echo "### 3) Linalg → CF (CIRCT-compatible bufferization)"
$MLIR_OPT my-dot-linalg.mlir \
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
  > my-dot-cf.mlir

$MLIR_OPT my-dot-cf.mlir --print-op-stats -o /dev/null \
  > my-dot-cf.stats || true

echo
echo "### 4) CF → Handshake (with 1D memrefs)"
$CIRCT_OPT my-dot-cf.mlir \
  -flatten-memref \
  -flatten-memref-calls \
  -canonicalize \
  -handshake-legalize-memrefs \
  --lower-cf-to-handshake \
  -canonicalize \
  > my-dot-handshake.mlir

echo
echo "### 5a) handshake-lower-extmem-to-hw + materialize forks/sinks"
$CIRCT_OPT my-dot-handshake.mlir \
  -handshake-lower-extmem-to-hw \
  -handshake-materialize-forks-sinks \
  -canonicalize \
  > my-dot-hs-ext.mlir

echo
echo "### 5b) lower-handshake-to-hw only"
$CIRCT_OPT my-dot-hs-ext.mlir \
  -lower-handshake-to-hw \
  -canonicalize \
  > my-dot-hw0.mlir

echo
echo "### 5c) ESI lowering on HW"
$CIRCT_OPT my-dot-hw0.mlir \
  -lower-esi-types \
  -lower-esi-ports \
  -lower-esi-to-hw \
  -canonicalize \
  > my-dot-hw.mlir

echo
echo "### 5.5) Cleanup inner symbols"
$CIRCT_OPT my-dot-hw.mlir \
  -firrtl-inner-symbol-dce \
  -symbol-dce \
  -canonicalize \
  > my-dot-hw-clean.mlir


echo
echo "### 6) HW+Seq → SV"
$CIRCT_OPT my-dot-hw-clean.mlir \
  -lower-seq-hlmem \
  -lower-seq-fifo \
  -lower-seq-shiftreg \
  -lower-seq-to-sv \
  -lower-hw-to-sv \
  -canonicalize \
  -export-verilog \
  -o /dev/null > my-dot.sv

echo
echo "Generated:"
ls -lh my-dot.sv
