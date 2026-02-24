{ pkgs ? import (fetchTarball
  "https://github.com/NixOS/nixpkgs/archive/346dd96ad74dc4457a9db9de4f4f57dab2e5731d.tar.gz")
  { }, python ? pkgs.python311, }:

let
  pythonPackages = python.pkgs;
  wheel = pkgs.fetchurl {
    url =
      "https://github.com/llvm/torch-mlir-release/releases/download/dev-wheels/torch_mlir-20251226.673-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl";
    sha256 = "75ec9b97b53f8608a3f9a277a179b5c7061cb88ca1c4d422a9e93c97a4bd92c2";
  };

in pythonPackages.buildPythonPackage {
  pname = "torch-mlir";
  version = "20251226.673";
  format = "wheel";
  src = wheel;
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib pkgs.ncurses ];
  doCheck = false;
  pythonImportsCheck = [ ];
}
