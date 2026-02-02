#!/bin/bash

set -e

export CIRCT_BUILD=${CIRCT_BUILD:-`pwd`/../circt_build/}
export CIRCT_HLS_BUILD=${CIRCT_HLS_BUILD:-`pwd`/../circt_hls_build/}
export MLIR_BUILD=${MLIR_BUILD:-`pwd`/../mlir_build/}
export POLYGEIST_BUILD=${POLYGEIST_BUILD:-`pwd`/../polygeist_build/}

echo "################################################################################"
echo "### Showing PyTorch module."
echo "################################################################################"
echo
cat dot.py
echo

echo
echo "################################################################################"
echo "### Compiling PyTorch module to MLIR Linalg dialect."
echo "################################################################################"
echo
python compile-pytorch.py > dot-linalg.mlir
echo "... done."
echo
cat dot-linalg.mlir

echo
echo "################################################################################"
echo "### Compiling MLIR Linalg dialect to MLIR Affine dialect."
echo "################################################################################"
echo
$MLIR_BUILD/bin/mlir-opt dot-linalg.mlir \
  -one-shot-bufferize='allow-return-allocs bufferize-function-boundaries' \
  -convert-linalg-to-affine-loops |
$POLYGEIST_BUILD/bin/polygeist-opt \
  -detect-reduction |
$MLIR_BUILD/bin/mlir-opt \
  -affine-scalrep |
$CIRCT_HLS_BUILD/bin/hls-opt \
    -affine-scalrep > dot-affine.mlir
echo "... done."
echo
cat dot-affine.mlir

echo
echo "################################################################################"
echo "### Compiling MLIR Affine dialect to MLIR ControlFlow dialect."
echo "################################################################################"
echo
$MLIR_BUILD/bin/mlir-opt dot-affine.mlir \
  -lower-affine \
  -convert-scf-to-cf > dot-cf.mlir
echo "... done."
echo
cat dot-cf.mlir

echo
echo "################################################################################"
echo "### Compiling MLIR ControlFlow dialect to CIRCT Handshake dialect."
echo "################################################################################"
echo
$CIRCT_BUILD/bin/circt-opt dot-cf.mlir \
  -lower-std-to-handshake \
  -canonicalize > dot-handshake.mlir
echo "... done."
echo
cat dot-handshake.mlir

echo
echo "################################################################################"
echo "### Compiling CIRCT Handshake dialect to CIRCT Hardware dialect."
echo "###     Outputs: Low-level modules, combinational logic, and registers."
echo "################################################################################"
echo
$CIRCT_BUILD/bin/circt-opt dot-handshake.mlir \
  -handshake-materialize-forks-sinks \
  -canonicalize \
  -handshake-insert-buffers=strategy=all \
  -lower-handshake-to-firrtl |
$CIRCT_BUILD/bin/firtool \
  -format=mlir \
  -ir-hw > dot-hw.mlir
echo "... done."
echo
echo

# Wrap the design with ESI services, then compile and run co-simulation with Verilator and Python.
./cosim.sh
