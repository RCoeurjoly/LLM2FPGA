FROM python:3.9-bullseye

WORKDIR /workspace

RUN apt-get update && \
    apt-get install -y bison flex ninja-build

RUN wget https://github.com/Kitware/CMake/releases/download/v3.23.2/cmake-3.23.2-linux-x86_64.sh; \
    chmod +x cmake-3.23.2-linux-x86_64.sh; \
    ./cmake-3.23.2-linux-x86_64.sh --skip-license --prefix=/usr

RUN pip install \
    https://github.com/llvm/torch-mlir/releases/download/snapshot-20220809.559/torch-1.13.0.dev20220809+cpu-cp39-cp39-linux_x86_64.whl \
    https://github.com/llvm/torch-mlir/releases/download/snapshot-20220809.559/torch_mlir-20220809.559-cp39-cp39-linux_x86_64.whl \
    pybind11

RUN git clone https://github.com/llvm/circt && \
    cd circt && \
    git submodule update --init

RUN cd circt && \
    yes | ./utils/get-capnp.sh && \
    ./utils/get-verilator.sh

RUN cd circt && \
    mkdir build && \
    cmake -B build -G Ninja llvm/llvm \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_PROJECTS=mlir \
      -DLLVM_ENABLE_ASSERTIONS=ON \
      -DLLVM_EXTERNAL_PROJECTS=circt \
      -DLLVM_EXTERNAL_CIRCT_SOURCE_DIR=. \
      -DMLIR_ENABLE_BINDINGS_PYTHON=ON \
      -DCIRCT_BINDINGS_PYTHON_ENABLED=ON \
      -DCIRCT_ENABLE_FRONTENDS=PyCDE

RUN ninja -C circt/build CIRCTMLIRPythonModules CIRCTPythonModules PyCDE EsiCosimDpiServer -j5
