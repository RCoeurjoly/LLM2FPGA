{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  gitMinimal,
  nix-update-script,
  src ? fetchFromGitHub {
    owner = "llvm";
    repo = "torch-mlir";
    rev = "59c249e5cc2025acca81bdcf1596b8dd36a5c0f9";
    fetchSubmodules = true;
    hash = "sha256-o1HG5JuKRMEnl2PrEu5KQi4iqBe0Doh1SET2W/OjGoI=";
  },
  python,
  pybind11 ? python.pkgs.pybind11,
  nanobind,
  tblgen,
  mlir,
  llvm,
  zlib,
  libxml2,
  ncurses,
}:

let
  mlirDev = if mlir ? dev then mlir.dev else mlir;
  llvmDev = if llvm ? dev then llvm.dev else llvm;
in stdenv.mkDerivation {
  pname = "torch-mlir";
  version = "0-unstable-2026-02-12";
  inherit src;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    gitMinimal
    python
    pybind11
    nanobind
    tblgen
  ];

  buildInputs = [
    zlib
    libxml2
    ncurses
    mlir
    llvm
  ];

  configurePhase = ''
    runHook preConfigure

    export PYTHONPATH="${pybind11}/${python.sitePackages}:${nanobind}/${python.sitePackages}:''${PYTHONPATH:-}"
    extraCmakeFlags=()
    # Local forks are often checked out without submodules. Disable stablehlo
    # in that case so we can still iterate on core torch-mlir code.
    if [ ! -d externals/stablehlo/stablehlo ]; then
      extraCmakeFlags+=(-DTORCH_MLIR_ENABLE_STABLEHLO=OFF)
    fi

    # MLIR's exported config in our split Nix package sets MLIR_TABLEGEN_EXE
    # to a relative `mlir-tblgen`. Re-point it after find_package(MLIR) so
    # generated .inc rules depend on an absolute executable path.
    substituteInPlace CMakeLists.txt \
      --replace-fail "find_package(MLIR REQUIRED CONFIG)" \
      "find_package(MLIR REQUIRED CONFIG)
  set(MLIR_TABLEGEN_EXE ${tblgen}/bin/mlir-tblgen)
  set(MLIR_TABLEGEN_TARGET ${tblgen}/bin/mlir-tblgen)"

    cmake -G Ninja \
      -S . \
      -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DLLVM_ENABLE_ASSERTIONS=ON \
      -DMLIR_ENABLE_BINDINGS_PYTHON=ON \
      -DMLIR_TABLEGEN_EXE=${tblgen}/bin/mlir-tblgen \
      -DLLVM_DIR=${llvmDev}/lib/cmake/llvm \
      -DMLIR_DIR=${mlirDev}/lib/cmake/mlir \
      -Dnanobind_DIR=${nanobind}/${python.sitePackages}/nanobind/cmake \
      -DPython3_EXECUTABLE=${python}/bin/python3 \
      -DPython_EXECUTABLE=${python}/bin/python3 \
      -DPython3_FIND_VIRTUALENV=ONLY \
      -DPython_FIND_VIRTUALENV=ONLY \
      "''${extraCmakeFlags[@]}"

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    cmake --build build --target torch-mlir-opt TorchMLIRPythonModules -- -j''${NIX_BUILD_CORES:-1}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    for component in torch-mlir-headers torch-mlir-opt TorchMLIRPythonModules; do
      cmake --install build --prefix "$out" --component "$component"
    done

    # Keep upstream component layout and expose the Python package under the
    # canonical `${python.sitePackages}` path used by this repo.
    if [ -d "$out/python_packages" ]; then
      mv "$out/python_packages" "$out/python-packages"
    fi
    if [ -d "$out/python-packages" ]; then
      mkdir -p "$out/${python.sitePackages}"
      cp -r "$out/python-packages/." "$out/${python.sitePackages}/"
    fi

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = {
    description = "Torch-MLIR compiler infrastructure and Python bindings";
    homepage = "https://github.com/llvm/torch-mlir";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
}
