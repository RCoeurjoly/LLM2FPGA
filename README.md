# Install Torch and Torch-MLIR.

```sh
python -m venv .venv

source .venv/bin/activate

pip install https://github.com/llvm/torch-mlir/releases/download/snapshot-20220816.566/torch-1.13.0.dev20220816+cpu-cp38-cp38-linux_x86_64.whl \
    https://github.com/llvm/torch-mlir/releases/download/snapshot-20220816.566/torch_mlir-20220816.566-cp38-cp38-linux_x86_64.whl \
    pybind11

```

# Install MLIR, CIRCT, CIRCT-HLS, and Polygeist.

Follow the instructions on their respective websites.

# Set relevant environment variables to point to the build directories.

```sh

export MLIR_BUILD=...
export CIRCT_SRC=...
export CIRCT_BUILD=...
export CIRCT_HLS_BUILD=...
export POLYGEIST_BUILD=
```

# Run the demo script.

```sh
./demo.sh
```
