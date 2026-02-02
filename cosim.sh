#!/bin/bash

set -e

export CIRCT_BUILD=${CIRCT_BUILD:-`pwd`/../circt_build/}
export CIRCT_SRC=${CIRCT_SRC:-`pwd`/../circt/}

export PYTHONPATH=$CIRCT_BUILD/tools/circt/python_packages/pycde:$CIRCT_BUILD/tools/circt/python_packages/circt_core

echo "################################################################################"
echo "### Generating the ESI system with PyCDE."
echo "###    Outputs: SystemVerilog and Cosimulation schema."
echo "################################################################################"
echo

# Wrap the CIRCT HW dialect with the CIRCT ESI dialect and services.
rm -fr PyCDESystem
python dot_prod_system.py 2> dot_prod_system.err > dot_prod_system.log
echo "... done."

echo
echo
echo "################################################################################"
echo "### Compiling the SystemVerilog to simulation with Verilator."
echo "################################################################################"
echo

# Compile the design and cosim DPI library into a simulator with Verilator.
$CIRCT_SRC/ext/bin/verilator \
  --cc --top-module Top -sv --build -CFLAGS "-DTRACE" --exe --assert --trace  -DINIT_RANDOM_PROLOG_='' \
  $CIRCT_SRC/include/circt/Dialect/ESI/cosim/Cosim_DpiPkg.sv \
  $CIRCT_SRC/include/circt/Dialect/ESI/cosim/Cosim_Endpoint.sv \
  $CIRCT_SRC/include/circt/Dialect/ESI/ESIPrimitives.sv \
  $CIRCT_BUILD/lib/libEsiCosimDpiServer.so \
  verilator-driver.cpp \
  PyCDESystem/*.sv
echo
echo "... done."

echo
echo
echo "################################################################################"
echo "### Running the Verilator simulation."
echo "################################################################################"
echo

# Run the simulator in a separate process.
rm -f cosim.cfg
LD_LIBRARY_PATH=$CIRCT_BUILD/lib ./obj_dir/VTop > sim.log &
echo "... started."

echo
echo
echo "################################################################################"
echo "### Connecting to the simulation via ESI cosim and dropping into a Python shell."
echo "################################################################################"
echo

# Run a Python script to connect to the simulator and wait for input.
python -i -m cosim


# Clean up the simulator process.
echo
echo
echo "Killing simulation."
kill -INT $!
echo "... killed."
