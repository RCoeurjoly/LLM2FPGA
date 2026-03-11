{ lib, stdenv, fetchFromGitHub, cmake, ninja, pkg-config, gitMinimal
, callPackage, llvmPackages_git, python311, nix-update-script, torchMlirSrc ?
  fetchFromGitHub {
    owner = "llvm";
    repo = "torch-mlir";
    rev = "59c249e5cc2025acca81bdcf1596b8dd36a5c0f9";
    fetchSubmodules = true;
    hash = "sha256-o1HG5JuKRMEnl2PrEu5KQi4iqBe0Doh1SET2W/OjGoI=";
  }, python ? python311, nanobindBootstrap ?
  callPackage ./nix/nanobind-bootstrap.nix { inherit python; }
, torchMlirLlvmPackages ? (llvmPackages_git.override {
  llvmVersions = {
    "22.0.0-git" = {
      gitRelease = {
        rev = "3ca2a5fc0b84762f0e7d8a0e613fd69f7e344219";
        rev-version = "23.0.0-unstable-2026-01-20";
        sha256 = "sha256-jjdb2PtKnjYo9RIGJ82YtKmZinqEOlmm7R64SeJqTac=";
      };
    };
  };
}).overrideScope (final: prev: {
  libllvm = (prev.libllvm.override { buildLlvmPackages = final; }).overrideAttrs
    (old: {
      postConfigure = "";
      doCheck = false;
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        (lib.cmakeBool "LLVM_BUILD_TESTS" false)
        (lib.cmakeBool "LLVM_INCLUDE_TESTS" false)
      ];
    });
}), zlib, libxml2, ncurses, }:

let
  inherit (python.pkgs) pybind11;
  inherit (torchMlirLlvmPackages) tblgen llvm;
  mlir = (torchMlirLlvmPackages.mlir.override {
    devExtraCmakeFlags = [ (lib.cmakeBool "MLIR_ENABLE_BINDINGS_PYTHON" true) ];
  }).overrideAttrs (old: {
    doCheck = false;
    nativeBuildInputs = old.nativeBuildInputs ++ [ python ];
    preConfigure = (old.preConfigure or "") + ''
      export PYTHONPATH="${pybind11}/${python.sitePackages}:${nanobindBootstrap}/${python.sitePackages}:''${PYTHONPATH:-}"
    '';
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      (lib.cmakeBool "LLVM_BUILD_TESTS" false)
      (lib.cmakeFeature "Python3_EXECUTABLE" "${python}/bin/python3")
      (lib.cmakeFeature "Python_EXECUTABLE" "${python}/bin/python3")
      (lib.cmakeFeature "pybind11_DIR"
        "${pybind11}/${python.sitePackages}/pybind11/share/cmake/pybind11")
      (lib.cmakeFeature "nanobind_DIR"
        "${nanobindBootstrap}/${python.sitePackages}/nanobind/cmake")
    ];
  });
  mlirDev = mlir.dev or mlir;
  llvmDev = llvm.dev or llvm;
in stdenv.mkDerivation {
  pname = "torch-mlir";
  version = "0-unstable-2026-02-12";
  src = torchMlirSrc;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    gitMinimal
    python
    pybind11
    nanobindBootstrap
    tblgen
  ];

  buildInputs = [ zlib libxml2 ncurses mlir llvm ];

  configurePhase = ''
      runHook preConfigure

      export PYTHONPATH="${pybind11}/${python.sitePackages}:${nanobindBootstrap}/${python.sitePackages}:''${PYTHONPATH:-}"
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
        -Dnanobind_DIR=${nanobindBootstrap}/${python.sitePackages}/nanobind/cmake \
        -DPython3_EXECUTABLE=${python}/bin/python3 \
        -DPython_EXECUTABLE=${python}/bin/python3 \
        -DPython3_FIND_VIRTUALENV=ONLY \
        -DPython_FIND_VIRTUALENV=ONLY \
        -DTORCH_MLIR_ENABLE_STABLEHLO=OFF

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

    mkdir -p "$out/${python.sitePackages}"
    cp -r "$out/python_packages/torch_mlir/torch_mlir" \
      "$out/${python.sitePackages}/torch_mlir"

    runHook postInstall
  '';

  passthru.updateScript =
    nix-update-script { extraArgs = [ "--version=branch" ]; };

  meta = {
    description = "Torch-MLIR compiler infrastructure and Python bindings";
    homepage = "https://github.com/llvm/torch-mlir";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
}
