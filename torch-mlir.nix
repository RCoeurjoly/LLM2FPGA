{ pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/346dd96ad74dc4457a9db9de4f4f57dab2e5731d.tar.gz") {}
, python ? pkgs.python311
}:

let
  pythonPackages = python.pkgs;
  wheel = pkgs.fetchurl {
    url = "https://github.com/llvm/torch-mlir-release/releases/download/dev-wheels/torch_mlir-20251205.652-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl";
    sha256 = "6de1cd3bf08e3e109b74f545156baedbd217c95f0f0a7e8ea3484897a7d404be";
  };

in pythonPackages.buildPythonPackage {
  pname = "torch-mlir";
  version = "20251205.652";
  format = "wheel";
  src = wheel;
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib pkgs.ncurses ];
  doCheck = false;
  pythonImportsCheck = [ ];
}
