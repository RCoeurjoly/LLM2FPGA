{
  description = "LLM2FPGA";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-llvm21.url = "github:NixOS/nixpkgs/346dd96ad74dc4457a9db9de4f4f57dab2e5731d";
    flake-utils.url = "github:numtide/flake-utils";
    # Clone with submodules
    yosys.url = "git+https://github.com/YosysHQ/yosys?submodules=1";
    circt-nix.url = "github:dtzSiFive/circt-nix";
    llvm-project-src = {
      url = "github:llvm/llvm-project/b32e067e97003db47aed52edc9ef8c3c30899b91";
      flake = false;
    };
    circt-src = {
      url = "github:llvm/circt/24ad90a7550031f941ed6905e28d59ef37916583";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-llvm21, flake-utils, yosys, circt-nix
    , llvm-project-src, circt-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgsLlvm21 = import nixpkgs-llvm21 { inherit system; };
        circtPkgs = circt-nix.packages.${system};
        circt = circtPkgs.circt;
        yosysPkg = yosys.packages.${system}.default;
        llvmPackages = pkgsLlvm21.llvmPackages_21;
        mlir = llvmPackages.mlir;
        python = pkgs.python311;
        pythonWithTorch = python.withPackages (ps: [ ps.torch ps.packaging ]);
        # Torch-MLIR is not available in nixpkgs, pending this PR: https://github.com/NixOS/nixpkgs/pull/490242
        # For the moment, we consume the wheel
        torchMlir = pkgs.callPackage ./torch-mlir.nix {
          inherit pkgs;
          python = python;
        };

        matmulTorch = pkgs.runCommand "matmul-torch.mlir" {
          buildInputs = [ pythonWithTorch torchMlir ];
        } ''
          export TORCH_MLIR_OPT=${torchMlir}/${python.sitePackages}/torch_mlir/_mlir_libs/torch-mlir-opt
          export PYTHONPATH=${torchMlir}/${python.sitePackages}:$PYTHONPATH
          python ${./compile-pytorch.py} > $out
        '';

        matmulLinalg = pkgs.runCommand "matmul-linalg.mlir" {
          buildInputs = [ torchMlir ];
        } ''
          ${torchMlir}/${python.sitePackages}/torch_mlir/_mlir_libs/torch-mlir-opt ${matmulTorch} \
            --torch-function-to-torch-backend-pipeline \
            --torch-backend-to-linalg-on-tensors-backend-pipeline \
            -canonicalize > $out
        '';

        matmulCf = pkgs.runCommand "matmul-cf.mlir" {
          buildInputs = [ mlir ];
        } ''
          ${mlir}/bin/mlir-opt ${matmulLinalg} \
            --empty-tensor-to-alloc-tensor \
            --one-shot-bufferize="bufferize-function-boundaries" \
            --buffer-results-to-out-params \
            --bufferization-lower-deallocations \
            --convert-bufferization-to-memref \
            --memref-expand \
            --convert-linalg-to-affine-loops \
            --lower-affine \
            --convert-scf-to-cf \
            -canonicalize > $out
        '';

        matmulCfStats = pkgs.runCommand "matmul-cf.stats" {
          buildInputs = [ mlir ];
        } ''
          ${mlir}/bin/mlir-opt ${matmulCf} --print-op-stats -o /dev/null > $out || true
        '';

        matmulHandshake = pkgs.runCommand "matmul-handshake.mlir" {
          buildInputs = [ circt ];
        } ''
          ${circt}/bin/circt-opt ${matmulCf} \
            -flatten-memref \
            -flatten-memref-calls \
            -canonicalize \
            -handshake-legalize-memrefs \
            --lower-cf-to-handshake \
            -handshake-insert-buffers \
            -canonicalize > $out
        '';

        matmulHsExt = pkgs.runCommand "matmul-hs-ext.mlir" {
          buildInputs = [ circt ];
        } ''
          ${circt}/bin/circt-opt ${matmulHandshake} \
            -handshake-lower-extmem-to-hw \
            -handshake-materialize-forks-sinks \
            -canonicalize > $out
        '';

        matmulHw0 = pkgs.runCommand "matmul-hw0.mlir" {
          buildInputs = [ circt ];
        } ''
          ${circt}/bin/circt-opt ${matmulHsExt} \
            -lower-handshake-to-hw \
            -canonicalize > $out
        '';

        matmulHw = pkgs.runCommand "matmul-hw.mlir" {
          buildInputs = [ circt ];
        } ''
          ${circt}/bin/circt-opt ${matmulHw0} \
            -lower-esi-types \
            -lower-esi-ports \
            -lower-esi-to-hw \
            -canonicalize > $out
        '';

        matmulHwClean = pkgs.runCommand "matmul-hw-clean.mlir" {
          buildInputs = [ circt ];
        } ''
          ${circt}/bin/circt-opt ${matmulHw} \
            -firrtl-inner-symbol-dce \
            -symbol-dce \
            -canonicalize > $out
        '';

        matmulSv = pkgs.runCommand "matmul.sv" {
          buildInputs = [ circt ];
        } ''
          ${circt}/bin/circt-opt ${matmulHwClean} \
            -lower-seq-hlmem \
            -lower-seq-fifo \
            -lower-seq-shiftreg \
            -lower-seq-to-sv \
            -lower-hw-to-sv \
            -canonicalize \
            -export-verilog \
            -o /dev/null > $out
        '';

      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            mlir
            circt
            yosysPkg
            torchMlir
            llvmPackages.clang
            llvmPackages.llvm
            pythonWithTorch
            pkgs.cmake
            pkgs.ninja
            pkgs.git
          ];
        };

        packages = {
          default = matmulSv;
          torch-mlir = torchMlir;
          matmul-torch = matmulTorch;
          matmul-linalg = matmulLinalg;
          matmul-cf = matmulCf;
          matmul-cf-stats = matmulCfStats;
          matmul-handshake = matmulHandshake;
          matmul-hs-ext = matmulHsExt;
          matmul-hw0 = matmulHw0;
          matmul-hw = matmulHw;
          matmul-hw-clean = matmulHwClean;
          matmul-sv = matmulSv;
        };
      });
}
