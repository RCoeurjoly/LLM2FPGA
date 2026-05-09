{
  description = "LLM2FPGA";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-llvm21.url =
      "github:NixOS/nixpkgs/346dd96ad74dc4457a9db9de4f4f57dab2e5731d";
    flake-utils.url = "github:numtide/flake-utils";
    # Clone with submodules
    yosys.url = "git+https://github.com/YosysHQ/yosys?submodules=1";
    yosys-slang = {
      url = "git+https://github.com/povik/yosys-slang?submodules=1";
      flake = false;
    };
    circt-nix = {
      url = "git+https://github.com/dtzSiFive/circt-nix?ref=main";
    };
    nix-eda.url = "github:fossi-foundation/nix-eda";
    openXC7.url = "github:RCoeurjoly/toolchain-nix";
    nextpnrXilinxFork = {
      url =
        "git+https://github.com/RCoeurjoly/nextpnr-xilinx?ref=stable-backports&submodules=1";
      flake = false;
    };
    ypcbHack = {
      url = "github:RCoeurjoly/ypcb_00338_1p1_hack";
      flake = false;
    };
    litex = {
      url = "github:enjoy-digital/litex";
      flake = false;
    };
    litedram = {
      url = "github:enjoy-digital/litedram";
      flake = false;
    };
    litepcie = {
      url = "github:enjoy-digital/litepcie";
      flake = false;
    };
    litexBoards = {
      url = "github:litex-hub/litex-boards";
      flake = false;
    };
    litexBoardsValidatedYpcb = {
      url =
        "github:litex-hub/litex-boards/6d58ae6b31d80b255de12c2d3f5bfefda4c38b90";
      flake = false;
    };
    pythondataCpuVexriscv = {
      url = "github:litex-hub/pythondata-cpu-vexriscv";
      flake = false;
    };
    pythondataSoftwarePicolibc = {
      url =
        "git+https://github.com/litex-hub/pythondata-software-picolibc?submodules=1";
      flake = false;
    };
    pythondataSoftwareCompilerRt = {
      url =
        "git+https://github.com/litex-hub/pythondata-software-compiler_rt?submodules=1";
      flake = false;
    };
    uberDdr3 = {
      url = "github:AngeloJacobo/UberDDR3";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, nixpkgs-llvm21, flake-utils, yosys, circt-nix
    , nix-eda, openXC7, nextpnrXilinxFork, ypcbHack, litex, litedram
    , litepcie, litexBoards, litexBoardsValidatedYpcb, pythondataCpuVexriscv
    , pythondataSoftwarePicolibc, pythondataSoftwareCompilerRt, uberDdr3
    , ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgsLlvm21 = import nixpkgs-llvm21 {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [ "torch" ];
        };
        circtPkgs = circt-nix.packages.${system};
        circt = (circtPkgs.circt.override { enableSlang = false; }).overrideAttrs
          (old: {
            patches = (old.patches or [ ]) ++ [
              ./patches/circt-upstream-task3-recovery/0001-flatten-memref-shape-ops-after-memref-flattening.patch
              ./patches/circt-upstream-task3-recovery/0002-handle-cfg-threaded-memrefs-in-handshake-lowering.patch
              ./patches/circt-upstream-task3-recovery/0005-handle-dense-resource-globals-in-flattenmemrefs.patch
              ./patches/circt-upstream-task3-recovery/0011-rebased-handshaketohw-stack.patch
              ./patches/circt-upstream-task3-recovery/0012-update-buffer-lowering-test-for-constant-order.patch
            ];
          });
        yosysPkg = nix-eda.packages.${system}.yosysFull.overrideAttrs (_: {
          src = yosys.outPath;
          version = "unstable-${builtins.substring 0 8 yosys.sourceInfo.rev}";
        });
        yosysPkgWithPythonEnv = if yosysPkg ? python3-env then
          yosysPkg
        else
          (yosysPkg // { python3-env = pkgs.python311; });
        yosysSlang = pkgs.clangStdenv.mkDerivation {
          pname = "yosys-slang";
          version = "flake-input";
          src = inputs."yosys-slang";
          dylibs = [ "slang" ];
          cmakeFlags = [
            "-DYOSYS_CONFIG=${yosysPkgWithPythonEnv}/bin/yosys-config"
            "-DFMT_INSTALL:BOOL=OFF"
          ];
          nativeBuildInputs = [ pkgs.cmake pkgs.jq ];
          buildInputs = [
            yosysPkgWithPythonEnv
            yosysPkgWithPythonEnv.python3-env
            pkgs.fmt
          ];
          patchPhase = ''
            runHook prePatch
            sed -i \
              -e '/git_rev_parse(YOSYS_SLANG_REVISION/c\set(YOSYS_SLANG_REVISION flake-input)' \
              -e '/git_rev_parse(SLANG_REVISION/c\set(SLANG_REVISION flake-input-submodule)' \
              src/CMakeLists.txt
            runHook postPatch
          '';
          doCheck = true;
          cmakeBuildType = "Debug";
          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/yosys/plugins
            cp ../build/slang.so $out/share/yosys/plugins/
            runHook postInstall
          '';
          meta = {
            description = "SystemVerilog frontend for Yosys";
            license = [ pkgs.lib.licenses.mit ];
            homepage = "https://github.com/povik/yosys-slang";
            platforms = pkgs.lib.platforms.all;
          };
        };
        task6UberDdr3SourceSummary =
          pkgs.runCommand "task6-uberddr3-source-summary" { } ''
            set -euo pipefail
            mkdir -p "$out"
            {
              echo "# UberDDR3 Source Summary"
              echo
              echo "Source: ${uberDdr3}"
              echo
              echo "## Top-level files"
              find ${uberDdr3} -maxdepth 2 -type f \
                | sort \
                | sed "s#${uberDdr3}/##"
              echo
              echo "## RTL modules"
              find ${uberDdr3}/rtl -maxdepth 2 -type f \
                | sort \
                | sed "s#${uberDdr3}/##"
              echo
              echo "## Formal files"
              find ${uberDdr3}/formal -maxdepth 3 -type f \
                | sort \
                | sed "s#${uberDdr3}/##"
            } > "$out/summary.md"
            ln -s ${uberDdr3} "$out/source"
          '';
        task6UberDdr3ControllerYosysJson =
          pkgs.runCommand "task6-uberddr3-controller-yosys.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv \
              ${uberDdr3}/rtl/ddr3_controller.v \
              ${uberDdr3}/rtl/ecc/ecc_dec.sv \
              ${uberDdr3}/rtl/ecc/ecc_enc.sv
            hierarchy -top ddr3_controller -check
            proc
            opt
            memory
            opt
            write_json "$out"
            EOF
            yosys -s run.ys
          '';
        task6YpcbUberDdr3BistYosysJson =
          pkgs.runCommand "task6-ypcb-uberddr3-bist-yosys.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            read_verilog -sv \
              ${uberDdr3}/rtl/ddr3_top.v \
              ${uberDdr3}/rtl/ddr3_controller.v \
              ${uberDdr3}/rtl/ddr3_phy.v \
              ${uberDdr3}/rtl/ecc/ecc_dec.sv \
              ${uberDdr3}/rtl/ecc/ecc_enc.sv \
              ${./fpga/rtl/task6_ypcb_uberddr3_bist_top.sv}
            hierarchy -top task6_ypcb_uberddr3_bist_top -check
            synth_xilinx -family xc7 -top task6_ypcb_uberddr3_bist_top -noiopad
            stat -top task6_ypcb_uberddr3_bist_top
            write_json "$out"
            EOF
            yosys -s run.ys
          '';
        llvmPackages = pkgsLlvm21.llvmPackages_21;
        # Keep LLVM for torch-mlir separate and pinned to torch-mlir's
        # submodule revision so source edits in torch-mlir do not rebuild LLVM.
        torchMlirLlvmPackages = (pkgsLlvm21.llvmPackages_git.override {
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
          # This commit reports LLVM 23 in source headers, while the package set
          # key stays on llvmPackages_git. Skip nixpkgs' strict version triplet
          # guard for this custom pin.
          libllvm = (prev.libllvm.override {
            # Ensure llvm builds against the matching tblgen from this pinned
            # package set, not the default llvmPackages_git bootstrap set.
            buildLlvmPackages = final;
          }).overrideAttrs (old: {
            postConfigure = "";
            doCheck = false;
            cmakeFlags = (old.cmakeFlags or [ ]) ++ [
              (pkgsLlvm21.lib.cmakeBool "LLVM_BUILD_TESTS" false)
              (pkgsLlvm21.lib.cmakeBool "LLVM_INCLUDE_TESTS" false)
            ];
          });
        });
        inherit (llvmPackages) mlir;
        python = pkgsLlvm21.python311;
        litexPkg = pkgs.python311Packages.buildPythonPackage {
          pname = "litex";
          version = "flake-input";
          src = litex;
          format = "setuptools";
          propagatedBuildInputs = with pkgs.python311Packages; [
            migen
            packaging
            pyserial
            pyyaml
            requests
          ];
          postPatch = ''
            substituteInPlace litex/build/xilinx/yosys_nextpnr.py \
              --replace-fail 'self._synth_opts = "-flatten -abc9 -arch xc7 "' 'self._synth_opts = "-flatten -abc9 -arch xc7 -nolutram "'
            substituteInPlace litex/build/xilinx/yosys_nextpnr.py \
              --replace-fail '        # pre packer options' '        prjxray_part = self.device.replace("-", "", 1) if self.device.startswith("xc7") else self.device

        # pre packer options' \
              --replace-fail '            part    = self.device,' '            part    = prjxray_part,' \
              --replace-fail '            part   = self.device,' '            part   = prjxray_part,'
          '';
          postFixup = ''
            chmod -R u+w "$out/${pkgs.python311.sitePackages}/litex/soc/software"
          '';
          doCheck = false;
        };
        litedramPkg = pkgs.python311Packages.buildPythonPackage {
          pname = "litedram";
          version = "flake-input";
          src = litedram;
          format = "setuptools";
          propagatedBuildInputs = (with pkgs.python311Packages; [
            migen
            pyyaml
          ]) ++ [ litexPkg ];
          doCheck = false;
        };
        pythondataCpuVexriscvPkg =
          pkgs.python311Packages.buildPythonPackage {
            pname = "pythondata-cpu-vexriscv";
            version = "flake-input";
            src = pythondataCpuVexriscv;
            format = "setuptools";
            doCheck = false;
          };
        pythondataSoftwarePicolibcPkg =
          pkgs.python311Packages.buildPythonPackage {
            pname = "pythondata-software-picolibc";
            version = "flake-input";
            src = pythondataSoftwarePicolibc;
            format = "setuptools";
            doCheck = false;
          };
        pythondataSoftwareCompilerRtPkg =
          pkgs.python311Packages.buildPythonPackage {
            pname = "pythondata-software-compiler-rt";
            version = "flake-input";
            src = pythondataSoftwareCompilerRt;
            format = "setuptools";
            doCheck = false;
          };
        litepciePkg = pkgs.python311Packages.buildPythonPackage {
          pname = "litepcie";
          version = "flake-input";
          src = litepcie;
          format = "setuptools";
          propagatedBuildInputs = (with pkgs.python311Packages; [
            migen
            pyyaml
          ]) ++ [ litexPkg ];
          doCheck = false;
        };
        mkLitexBoardsPkg = src:
          pkgs.python311Packages.buildPythonPackage {
            pname = "litex-boards";
            version = "flake-input";
            inherit src;
            format = "setuptools";
            propagatedBuildInputs = [
              litexPkg
              litedramPkg
              litepciePkg
            ];
            doCheck = false;
          };
        litexBoardsPkg = mkLitexBoardsPkg litexBoards;
        litexBoardsValidatedYpcbPkg =
          mkLitexBoardsPkg litexBoardsValidatedYpcb;
        mkLitexBoardsYpcbToolchainPatchedSource = source:
          pkgs.runCommand "litex-boards-ypcb-toolchain-patched-source" { } ''
            cp -r ${source} "$out"
            chmod -R u+w "$out"
            target="$out/litex_boards/targets/ypcb_00338_1p1.py"
            substituteInPlace "$target" \
              --replace-fail "with_pcie       = False," "with_pcie       = False,
        toolchain       = \"vivado\"," \
              --replace-fail "platform = ypcb_00338_1p1.Platform()" "platform = ypcb_00338_1p1.Platform(toolchain=toolchain)" \
              --replace-fail "with_pcie      = args.with_pcie," "with_pcie      = args.with_pcie,
        toolchain      = args.toolchain,"
          '';
        litexBoardsYpcbToolchainPatchedSource =
          mkLitexBoardsYpcbToolchainPatchedSource litexBoards;
        litexBoardsValidatedYpcbToolchainPatchedSource =
          mkLitexBoardsYpcbToolchainPatchedSource litexBoardsValidatedYpcb;
        litexBoardsYpcbJtagOnlyPatchedSource =
          pkgs.runCommand "litex-boards-ypcb-jtag-only-patched-source" { } ''
            cp -r ${litexBoardsYpcbToolchainPatchedSource} "$out"
            chmod -R u+w "$out"
            target="$out/litex_boards/targets/ypcb_00338_1p1.py"
            substituteInPlace "$target" \
              --replace-fail "        self.idelayctrl = S7IDELAYCTRL(self.cd_idelay)" "        # Removed for the non-DDR JTAG-UART proof: openXC7 rejects
        # an IDELAYCTRL with no associated I/ODELAYs.
        # self.idelayctrl = S7IDELAYCTRL(self.cd_idelay)"
          '';
        liteDramPython = pkgs.python311.withPackages (ps: [
          ps.migen
          ps.packaging
          ps.pyyaml
          litexPkg
          litedramPkg
          pythondataCpuVexriscvPkg
          pythondataSoftwarePicolibcPkg
          pythondataSoftwareCompilerRtPkg
        ]);
        litexBoardsPython = pkgs.python311.withPackages (ps: [
          ps.migen
          ps.packaging
          ps.pyserial
          ps.pyyaml
          ps.requests
          litexPkg
          litedramPkg
          litepciePkg
          litexBoardsPkg
          pythondataCpuVexriscvPkg
          pythondataSoftwarePicolibcPkg
          pythondataSoftwareCompilerRtPkg
        ]);
        litexBoardsValidatedYpcbPython = pkgs.python311.withPackages (ps: [
          ps.migen
          ps.packaging
          ps.pyserial
          ps.pyyaml
          ps.requests
          litexPkg
          litedramPkg
          litepciePkg
          litexBoardsValidatedYpcbPkg
          pythondataCpuVexriscvPkg
          pythondataSoftwarePicolibcPkg
          pythondataSoftwareCompilerRtPkg
        ]);
        litexWritableCp = pkgs.writeShellScriptBin "cp" ''
          set +e
          ${pkgs.coreutils}/bin/cp "$@"
          status=$?
          set -e
          if [ "$status" -eq 0 ] && [ "$#" -ge 1 ]; then
            dest=
            for arg in "$@"; do
              dest="$arg"
            done
            chmod -R u+w "$dest" 2>/dev/null || true
          fi
          exit "$status"
        '';
        mkLitexBoardsYpcbRunner = { name, pythonEnv, source }:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [
              litexWritableCp
              pythonEnv
              pkgs.gcc
              pkgs.gnumake
              pkgs.meson
              pkgs.ninja
              pkgs.yosys
              openXC7Nextpnr
              openXC7Fasm
              openXC7Prjxray
              prjxrayPythonDeps
            ];
            text = ''
              export CHIPDB=${litexOpenXC7ChipdbCompat}
              export PRJXRAY_DB_DIR=${fpgaPrjxrayDb}
              export PYTHONPATH="${prjxrayPythonPath}''${PYTHONPATH:+:$PYTHONPATH}"
              exec python ${source}/litex_boards/targets/ypcb_00338_1p1.py --uart-name=jtag_uart "$@"
            '';
          };
        task6LitexBoardsYpcbMasterRunner = mkLitexBoardsYpcbRunner {
          name = "task6-litex-boards-ypcb-master";
          pythonEnv = litexBoardsPython;
          source = litexBoardsYpcbToolchainPatchedSource;
        };
        task6LitexBoardsYpcbValidatedRunner = mkLitexBoardsYpcbRunner {
          name = "task6-litex-boards-ypcb-validated";
          pythonEnv = litexBoardsValidatedYpcbPython;
          source = litexBoardsValidatedYpcbToolchainPatchedSource;
        };
        task6LitexBoardsYpcbJtagOnlyRunner = mkLitexBoardsYpcbRunner {
          name = "task6-litex-boards-ypcb-jtag-only";
          pythonEnv = litexBoardsPython;
          source = litexBoardsYpcbJtagOnlyPatchedSource;
        };
        task6LitexBoardsYpcbMasterHelp =
          pkgs.runCommand "task6-litex-boards-ypcb-master-help" { } ''
            mkdir -p "$out"
            ${task6LitexBoardsYpcbMasterRunner}/bin/task6-litex-boards-ypcb-master \
              --help > "$out/help.txt"
          '';
        task6LitexBoardsYpcbValidatedHelp =
          pkgs.runCommand "task6-litex-boards-ypcb-validated-help" { } ''
            mkdir -p "$out"
            ${task6LitexBoardsYpcbValidatedRunner}/bin/task6-litex-boards-ypcb-validated \
              --help > "$out/help.txt"
          '';
        torchao = python.pkgs.buildPythonPackage rec {
          pname = "torchao";
          version = "0.15.0";
          format = "wheel";
          src = pkgs.fetchurl {
            url =
              "https://files.pythonhosted.org/packages/f6/3b/6b9d5618720f63dbc2e2509cd6b57aae9c0d61b738d1d2172f4d5d9efaab/torchao-0.15.0-py3-none-any.whl";
            hash = "sha256-PzgSZ2BI74oqDp1JLRLYlxunp+uxb1SqVvaQQU4TDSw=";
          };
          propagatedBuildInputs = [ python.pkgs.torch ];
          dontBuild = true;
          doCheck = false;
          pythonImportsCheck = [ "torchao" ];
        };
        pythonWithTorch = python.withPackages (ps: [ ps.torch ps.packaging ]);
        pythonWithTorchAO =
          python.withPackages (ps: [ ps.torch ps.packaging torchao ]);
        pythonWithTinyStories =
          python.withPackages (ps: [ ps.torch ps.packaging ps.transformers ]);
        torchCpu = python.pkgs.torch-bin.overridePythonAttrs (_old: {
          version = "2.9.1+cpu";
          src = pkgs.fetchurl {
            name = "torch-2.9.1+cpu-cp311-cp311-manylinux_2_28_x86_64.whl";
            url =
              "https://download.pytorch.org/whl/cpu/torch-2.9.1%2Bcpu-cp311-cp311-manylinux_2_28_x86_64.whl";
            hash = "sha256-PeKtubREPckhDvHxsW2jZHrOU1UxZtY2C7vX7dbxbk0=";
          };
          buildInputs = [ ];
          dependencies = with python.pkgs; [
            filelock
            fsspec
            jinja2
            networkx
            numpy
            pyyaml
            requests
            setuptools
            sympy
            typing-extensions
          ];
          extraRunpaths = [ ];
        });
        safetensorsWithTorchBin = python.pkgs.safetensors.override {
          torch = torchCpu;
        };
        transformersWithTorchBin = python.pkgs.transformers.override {
          safetensors = safetensorsWithTorchBin;
          torch = torchCpu;
        };
        pythonWithTinyStoriesBin = python.withPackages
          (ps: [ torchCpu ps.packaging transformersWithTorchBin ]);
        pythonWithTinyStoriesTorchAO = python.withPackages
          (ps: [ ps.torch ps.packaging ps.transformers torchao ]);
        nanobindBootstrap =
          pkgsLlvm21.callPackage ./nix/nanobind-bootstrap.nix {
            inherit python;
          };
        mlirForTorchMlir = (torchMlirLlvmPackages.mlir.override {
          devExtraCmakeFlags =
            [ (pkgsLlvm21.lib.cmakeBool "MLIR_ENABLE_BINDINGS_PYTHON" true) ];
        }).overrideAttrs (old: {
          doCheck = false;
          nativeBuildInputs = old.nativeBuildInputs ++ [ python ];
          preConfigure = (old.preConfigure or "") + ''
            export PYTHONPATH="${python.pkgs.pybind11}/${python.sitePackages}:${nanobindBootstrap}/${python.sitePackages}:''${PYTHONPATH:-}"
          '';
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            (pkgsLlvm21.lib.cmakeBool "LLVM_BUILD_TESTS" false)
            (pkgsLlvm21.lib.cmakeFeature "Python3_EXECUTABLE"
              "${python}/bin/python3")
            (pkgsLlvm21.lib.cmakeFeature "Python_EXECUTABLE"
              "${python}/bin/python3")
            (pkgsLlvm21.lib.cmakeFeature "pybind11_DIR"
              "${python.pkgs.pybind11}/${python.sitePackages}/pybind11/share/cmake/pybind11")
            (pkgsLlvm21.lib.cmakeFeature "nanobind_DIR"
              "${nanobindBootstrap}/${python.sitePackages}/nanobind/cmake")
          ];
        });
        openXC7Packages = openXC7.packages.${system};
        openXC7Fasm = openXC7Packages.fasm;
        openXC7Nextpnr = openXC7Packages.nextpnr-xilinx.overrideAttrs
          (old: {
            src = nextpnrXilinxFork;
            patches = (old.patches or [ ]) ++ [
              ./patches/nextpnr-xilinx/0001-xc7-allow-odelay-to-hr-output-buffers.patch
            ];
          });
        openXC7Chipdb = openXC7Packages.nextpnr-xilinx-chipdb.kintex7.override {
          chipdbFootprints = [ "xc7k480tffg1156" ];
          "nextpnr-xilinx" = openXC7Nextpnr;
        };
        litexOpenXC7ChipdbCompat = pkgs.runCommand "litex-openxc7-chipdb-compat" { } ''
          mkdir -p "$out"
          ln -s ${openXC7Chipdb}/xc7k480tffg1156.bin "$out/xc7k480t-ffg1156.bin"
          ln -s ${openXC7Chipdb}/xc7k480tffg1156.bin "$out/xc7k480tffg1156.bin"
        '';
        openXC7Prjxray = openXC7Packages.prjxray;
        prjxrayPythonDeps = pkgs.python312.withPackages (ps: [
          ps.pyyaml
          ps.simplejson
          ps.intervaltree
          ps.pyjson5
          ps.progressbar2
        ]);
        fpgaPartFamily = "kintex7";
        fpgaPartName = "xc7k480tffg1156-1";
        fpgaPrjxrayDb = "${openXC7Nextpnr}/share/nextpnr/external/prjxray-db";
        fpgaPrjxrayFamilyDb = "${fpgaPrjxrayDb}/${fpgaPartFamily}";
        fpgaPartFile = "${fpgaPrjxrayFamilyDb}/${fpgaPartName}/part.yaml";
        fpgaChipdb = "${openXC7Chipdb}/xc7k480tffg1156.bin";
        prjxrayPythonPath =
          "${openXC7Fasm}/lib/python3.12/site-packages:${prjxrayPythonDeps}/${pkgs.python312.sitePackages}:${openXC7Prjxray}/usr/share/python3";
        torchMlirPatched = pkgsLlvm21.callPackage ./torch-mlir.nix {
          inherit python;
          nanobind = nanobindBootstrap;
          inherit (torchMlirLlvmPackages) tblgen;
          mlir = mlirForTorchMlir;
          inherit (torchMlirLlvmPackages) llvm;
          applyTask3RfpPatches = true;
        };
        torchMlirUnpatched = pkgsLlvm21.callPackage ./torch-mlir.nix {
          inherit python;
          nanobind = nanobindBootstrap;
          inherit (torchMlirLlvmPackages) tblgen;
          mlir = mlirForTorchMlir;
          inherit (torchMlirLlvmPackages) llvm;
          applyTask3RfpPatches = false;
        };
        torchMlir = torchMlirUnpatched;
        pipelineScripts = ./scripts/pipeline;
        fpPrimsSv = ./rtl/fp/circt_fp_primitives.sv;
        tinyStories1m = let
          modelId = "roneneldan/TinyStories-1M";
          revision = "77f1b168e219585646439073245fe87e56b3023e";
          fetch = file: hash:
            pkgs.fetchurl {
              url =
                "https://huggingface.co/${modelId}/resolve/${revision}/${file}";
              inherit hash;
            };
          snapshot = pkgs.linkFarm "tinystories-1m-hf-snapshot" [
            {
              name = "config.json";
              path = fetch "config.json"
                "sha256-/3TDDV67WrHaDy6kea33GXxQS0K1UiqFjDNKuR7UlYw=";
            }
            {
              name = "pytorch_model.bin";
              path = fetch "pytorch_model.bin"
                "sha256-B/lgnqiCuBY/87I9QOK4LLcV1AljG+sVyEsWTzh32uc=";
            }
          ];
        in {
          inherit modelId revision snapshot;
          sourceDir = ./TinyStories;
          adapterPy = ./TinyStories/model_adapter.py;
        };
        representativeCoreSweepSpecs =
          import ./nix/representative-core-sweep.nix;
        pipelineLib = import ./nix/pipeline.nix {
          inherit pkgs mlir circt yosysPkg yosysSlang torchMlir python;
          inherit pipelineScripts;
        };
        modelRegistry = import ./nix/models.nix {
          inherit (pipelineLib) registerModel registerLsqModel
            registerQuantizedModel;
          inherit pythonWithTorch pythonWithTinyStories
            pythonWithTinyStoriesTorchAO torchMlir python;
          inherit tinyStories1m;
          inherit fpPrimsSv;
          compilePyTorch = ./scripts/compile-pytorch.py;
          matmulPy = ./src/matmul.py;
          matmulAdapterPy = ./src/matmul_adapter.py;
          matmulSrcDir = ./src;
          gemv64Py = ./src/gemv64.py;
          gemv64AdapterPy = ./src/gemv64_adapter.py;
          gemv64Int16Py = ./src/gemv64_int16.py;
          gemv64Int16AdapterPy = ./src/gemv64_int16_adapter.py;
          task6RectGemvPy = ./src/task6_rect_gemv.py;
          task6RectGemvAdapterPy = ./src/task6_rect_gemv_adapter.py;
          task6RectGemvPt2eStaticQuantAdapterPy =
            ./src/task6_rect_gemv_pt2e_static_quant_adapter.py;
          tinyStoriesRepresentativeCoreAdapterPy =
            ./TinyStories/model_adapter_representative_core.py;
          tinyStoriesRepresentativeCorePt2eStaticQuantAdapterPy =
            ./TinyStories/model_adapter_representative_core_pt2e_static_quant.py;
          tinyStoriesTorchaoAdapterPy = ./TinyStories/model_adapter_torchao.py;
          tinyStoriesPt2eStaticQuantAdapterPy =
            ./TinyStories/model_adapter_pt2e_static_quant.py;
          simDir = ./sim;
          inherit representativeCoreSweepSpecs;
        };
        modelPipelines = pipelineLib.modelPipelinesFromRegistry modelRegistry;
        pipelineStagePackages =
          pipelineLib.pipelineStagePackagesFromRegistry modelRegistry;
        pipelineMetadataPackages =
          pipelineLib.metadataPackagesFromRegistry modelRegistry;
        modelRegistryJson = pipelineLib.registryIndexPackage modelRegistry;
        task6Ui64Fifo2SiteMap = import ./nix/task6-ui64-fifo2-site-map.nix;

        matmulPipeline = modelPipelines.matmul;
        matmulTorch = matmulPipeline.torch;
        matmulLinalg = matmulPipeline.linalg;
        matmulCf = matmulPipeline.cf;
        matmulCfStats = matmulPipeline."cf-stats";
        matmulHandshake = matmulPipeline.handshake;
        matmulHsExt = matmulPipeline."hs-ext";
        matmulHw0 = matmulPipeline.hw0;
        matmulHw = matmulPipeline.hw;
        matmulHwClean = matmulPipeline."hw-clean";
        matmulSv = matmulPipeline.sv;
        matmulIl = matmulPipeline.il;
        matmulYosysStat = matmulPipeline."yosys-stat";
        task6L0Gemv64Pipeline = modelPipelines."task6-l0-gemv64";
        task6L0Gemv64YosysStat = task6L0Gemv64Pipeline."yosys-stat";
        task6L0Gemv64Sv = task6L0Gemv64Pipeline.sv;
        task6L0Gemv64Json = mkSynthJson {
          name = "task6-l0-gemv64";
          svFilelist = "${task6L0Gemv64Sv}/sources.f";
          topName = "main";
          topSv = "${task6L0Gemv64Sv}/sv/main.sv";
        };
        task6L0Gemv64Abc9Json = mkSynthJson {
          name = "task6-l0-gemv64-abc9";
          svFilelist = "${task6L0Gemv64Sv}/sources.f";
          topName = "main";
          topSv = "${task6L0Gemv64Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L0Gemv64Utilization = mkMappedJsonUtilizationReport {
          name = "task6-l0-gemv64";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L0Gemv64Json;
        };
        task6L0Gemv64Abc9Utilization = mkMappedJsonUtilizationReport {
          name = "task6-l0-gemv64-abc9";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L0Gemv64Abc9Json;
        };
        task6L0Gemv64Int16Pipeline = modelPipelines."task6-l0-gemv64-int16";
        task6L0Gemv64Int16Sv = task6L0Gemv64Int16Pipeline.sv;
        task6L0Gemv64Int16Json = mkSynthJson {
          name = "task6-l0-gemv64-int16";
          svFilelist = "${task6L0Gemv64Int16Sv}/sources.f";
          topName = "main";
          topSv = "${task6L0Gemv64Int16Sv}/sv/main.sv";
        };
        task6L0Gemv64Int16Utilization = mkMappedJsonUtilizationReport {
          name = "task6-l0-gemv64-int16";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L0Gemv64Int16Json;
        };
        task6L1CProjRedirectPipeline = modelPipelines."task6-l1-c-proj-redirect";
        task6L1CProjRedirectSv = task6L1CProjRedirectPipeline.sv;
        task6L1CProjRedirectJson = mkSynthJson {
          name = "task6-l1-c-proj-redirect";
          svFilelist = "${task6L1CProjRedirectSv}/sources.f";
          topName = "main";
          topSv = "${task6L1CProjRedirectSv}/sv/main.sv";
        };
        task6L1CProjRedirectAbc9Json = mkSynthJson {
          name = "task6-l1-c-proj-redirect-abc9";
          svFilelist = "${task6L1CProjRedirectSv}/sources.f";
          topName = "main";
          topSv = "${task6L1CProjRedirectSv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CProjRedirectUtilization = mkMappedJsonUtilizationReport {
          name = "task6-l1-c-proj-redirect";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L1CProjRedirectJson;
        };
        task6L1CProjRedirectAbc9Utilization = mkMappedJsonUtilizationReport {
          name = "task6-l1-c-proj-redirect-abc9";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L1CProjRedirectAbc9Json;
        };
        task6L1CFcRedirectPipeline = modelPipelines."task6-l1-c-fc-redirect";
        task6L1CFcRedirectYosysStat = task6L1CFcRedirectPipeline."yosys-stat";
        task6L1CFcRedirectSv = task6L1CFcRedirectPipeline.sv;
        task6L1CFcRedirectIl = task6L1CFcRedirectPipeline.il;
        task6L1CFcRedirectLsqPipeline =
          modelPipelines."task6-l1-c-fc-redirect-lsq";
        task6L1CFcRedirectLsqSv = task6L1CFcRedirectLsqPipeline.sv;
        task6L1CFcRedirectLsqIndexRing3Ui64SiteIds = [
          160
          161
          162
          165
          173
          177
          178
          179
          180
          181
          182
          185
          186
          187
          188
          189
          190
          191
          213
          214
          215
          217
          218
          219
        ];
        task6L1CFcRedirectLsqPostBranchUi64SiteIds = [ 264 265 266 269 ];
        task6L1CFcRedirectLsqPostBranchOutBufUi64SiteIds = [ 279 ];
        task6L1CFcRedirectLsqIndexRing3Fifo2Sv = mkTask6Ui64Fifo2SitePatchSv {
          name = "task6-l1-c-fc-redirect-lsq-index-ring3-fifo2-sv";
          baseSv = task6L1CFcRedirectLsqSv;
          siteIds = task6L1CFcRedirectLsqIndexRing3Ui64SiteIds;
        };
        task6L1CFcRedirectLsqIndexRing3PostBranchFifo2Sv =
          mkTask6Ui64Fifo2SitePatchSv {
            name = "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-fifo2-sv";
            baseSv = task6L1CFcRedirectLsqIndexRing3Fifo2Sv;
            siteIds = task6L1CFcRedirectLsqPostBranchUi64SiteIds;
            ensureHelper = false;
          };
        task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Sv =
          mkTask6Ui64Fifo2SitePatchSv {
            name =
              "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sv";
            baseSv = task6L1CFcRedirectLsqIndexRing3PostBranchFifo2Sv;
            siteIds = task6L1CFcRedirectLsqPostBranchOutBufUi64SiteIds;
            ensureHelper = false;
          };
        task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2YosysStat =
          mkSvYosysStat {
            name =
              "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2";
            sv = task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Sv;
          };
        task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Abc9Json =
          mkSynthJson {
            name =
              "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9";
            svFilelist =
              "${task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Sv}/sources.f";
            topName = "main";
            topSv =
              "${task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Sv}/sv/main.sv";
            useAbc9 = true;
          };
        task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name =
              "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson =
              task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Abc9Json;
          };
        task6L1CFcRedirectUi64BufferLiteSv = pkgs.runCommand
          "task6-l1-c-fc-redirect-ui64-buffer-lite-sv" { } ''
            cp -r ${task6L1CFcRedirectSv} "$out"
            chmod -R u+w "$out"
            cp ${
              ./rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq.sv
            } "$out/sv/handshake_buffer_in_ui64_out_ui64_2slots_seq.sv"
            sed \
              "s#${task6L1CFcRedirectSv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectSv}/sources.f > "$out/sources.f"
            sed \
              "s#${task6L1CFcRedirectSv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectSv}/sv/filelist.f > "$out/sv/filelist.f"
          '';
        task6L1CFcRedirectUi64BufferFifo2Sv = mkTask6Ui64Fifo2WholeClassSv {
          name = "task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv";
          baseSv = task6L1CFcRedirectSv;
        };
        task6L1CFcRedirectBuffer165Fifo2Sv = mkTask6Ui64Fifo2SitePatchSv {
          name = "task6-l1-c-fc-redirect-buffer165-fifo2-sv";
          baseSv = task6L1CFcRedirectSv;
          siteIds = task6Ui64Fifo2SiteMap.l1.buffer165;
        };
        task6L1CFcRedirectIndexSpineFifo2Sv = mkTask6Ui64Fifo2SitePatchSv {
          name = "task6-l1-c-fc-redirect-index-spine-fifo2-sv";
          baseSv = task6L1CFcRedirectSv;
          siteIds = task6Ui64Fifo2SiteMap.l1.indexSpine;
        };
        task6L1CFcRedirectIndexFanoutFifo2Sv = mkTask6Ui64Fifo2SitePatchSv {
          name = "task6-l1-c-fc-redirect-index-fanout-fifo2-sv";
          baseSv = task6L1CFcRedirectSv;
          siteIds = task6Ui64Fifo2SiteMap.l1.indexFanout;
        };
        task6L1CFcRedirectIndexRing2Fifo2Sv = mkTask6Ui64Fifo2SitePatchSv {
          name = "task6-l1-c-fc-redirect-index-ring2-fifo2-sv";
          baseSv = task6L1CFcRedirectSv;
          siteIds = task6Ui64Fifo2SiteMap.l1.indexRing2;
        };
        task6L1CFcRedirectIndexRing3Fifo2Sv = mkTask6Ui64Fifo2SitePatchSv {
          name = "task6-l1-c-fc-redirect-index-ring3-fifo2-sv";
          baseSv = task6L1CFcRedirectSv;
          siteIds = task6Ui64Fifo2SiteMap.l1.indexRing3;
        };
        task6L1CFcRedirectIndexRing3CtrlMergeFifo2Sv = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv" { } ''
            cp -r ${task6L1CFcRedirectIndexRing3Fifo2Sv} "$out"
            chmod -R u+w "$out"
            cp ${
              ./rtl/task6/task6_ctrl_fifo2_buffer.sv
            } "$out/sv/task6_ctrl_fifo2_buffer.sv"
            for id in 194 220 229 237; do
              sed -i \
                "s/^  handshake_buffer_in_none_out_none_2slots_seq_1ins_1outs_ctrl handshake_buffer''${id} (/  task6_ctrl_fifo2_buffer handshake_buffer''${id} (/" \
                "$out/sv/main.sv"
            done
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sources.f > "$out/sources.f"
            printf '%s\n' "$out/sv/task6_ctrl_fifo2_buffer.sv" >> "$out/sources.f"
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/filelist.f > "$out/sv/filelist.f"
            printf '%s\n' "$out/sv/task6_ctrl_fifo2_buffer.sv" >> "$out/sv/filelist.f"
          '';
        task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Sv = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv" { } ''
            cp -r ${task6L1CFcRedirectIndexRing3Fifo2Sv} "$out"
            chmod -R u+w "$out"
            cp ${
              ./rtl/task6/task6_ui1_fifo2_buffer.sv
            } "$out/sv/task6_ui1_fifo2_buffer.sv"
            sed -i \
              "s/^  handshake_buffer_in_ui1_out_ui1_2slots_seq handshake_buffer263 (/  task6_ui1_fifo2_buffer handshake_buffer263 (/" \
              "$out/sv/main.sv"
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sources.f > "$out/sources.f"
            printf '%s\n' "$out/sv/task6_ui1_fifo2_buffer.sv" >> "$out/sources.f"
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/filelist.f > "$out/sv/filelist.f"
            printf '%s\n' "$out/sv/task6_ui1_fifo2_buffer.sv" >> "$out/sv/filelist.f"
          '';
        task6L1CFcRedirectIndexRing3Fork49StatevecSv = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv" { } ''
            cp -r ${task6L1CFcRedirectIndexRing3Fifo2Sv} "$out"
            chmod -R u+w "$out"
            cp ${
              ./rtl/task6/task6_ui1_fork5.sv
            } "$out/sv/task6_ui1_fork5.sv"
            sed -i \
              "s/^  handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1 handshake_fork49 (/  task6_ui1_fork5 handshake_fork49 (/" \
              "$out/sv/main.sv"
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sources.f > "$out/sources.f"
            printf '%s\n' "$out/sv/task6_ui1_fork5.sv" >> "$out/sources.f"
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/filelist.f > "$out/sv/filelist.f"
            printf '%s\n' "$out/sv/task6_ui1_fork5.sv" >> "$out/sv/filelist.f"
          '';
        task6L1CFcRedirectIndexRing3SelectClusterFifo2Sv = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv" { } ''
            cp -r ${task6L1CFcRedirectIndexRing3Fifo2Sv} "$out"
            chmod -R u+w "$out"
            cp ${
              ./rtl/task6/task6_ui1_init0_fifo2_fork4.sv
            } "$out/sv/task6_ui1_init0_fifo2_fork4.sv"
            awk '
              BEGIN {
                skipping = 0;
                replaced = 0;
              }
              /^  handshake_buffer_in_ui1_out_ui1_1slots_seq_init_0 handshake_buffer255 \(/ {
                skipping = 1;
                print "  task6_ui1_init0_fifo2_fork4 task6_ui1_selectcluster255_46 (";
                print "    .in0        (_handshake_fork49_out4),";
                print "    .in0_valid  (_handshake_fork49_out4_valid),";
                print "    .clock      (clock),";
                print "    .reset      (reset),";
                print "    .out0_ready (_handshake_mux41_select_ready),";
                print "    .out1_ready (_handshake_mux40_select_ready),";
                print "    .out2_ready (_handshake_mux39_select_ready),";
                print "    .out3_ready (_handshake_mux38_select_ready),";
                print "    .in0_ready  (_handshake_buffer255_in0_ready),";
                print "    .out0       (_handshake_fork46_out0),";
                print "    .out0_valid (_handshake_fork46_out0_valid),";
                print "    .out1       (_handshake_fork46_out1),";
                print "    .out1_valid (_handshake_fork46_out1_valid),";
                print "    .out2       (_handshake_fork46_out2),";
                print "    .out2_valid (_handshake_fork46_out2_valid),";
                print "    .out3       (_handshake_fork46_out3),";
                print "    .out3_valid (_handshake_fork46_out3_valid)";
                print "  );\t// Task 6 local selector cluster helper";
                next;
              }
              skipping && /^  handshake_mux_in_ui1_none_none_out_none_3ins_1outs_ctrl handshake_mux38 \(/ {
                skipping = 0;
                replaced = 1;
              }
              !skipping {
                print;
              }
              END {
                if (!replaced) {
                  exit 1;
                }
              }
            ' "$out/sv/main.sv" > "$out/sv/main.sv.tmp"
            mv "$out/sv/main.sv.tmp" "$out/sv/main.sv"
            grep -q "task6_ui1_init0_fifo2_fork4 task6_ui1_selectcluster255_46" \
              "$out/sv/main.sv"
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sources.f > "$out/sources.f"
            printf '%s\n' "$out/sv/task6_ui1_init0_fifo2_fork4.sv" >> "$out/sources.f"
            sed \
              "s#${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/#$out/sv/#g" \
              ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/filelist.f > "$out/sv/filelist.f"
            printf '%s\n' "$out/sv/task6_ui1_init0_fifo2_fork4.sv" >> "$out/sv/filelist.f"
          '';
        task6L1CFcRedirectIndexRing3PostBranchFifo2Sv =
          mkTask6Ui64Fifo2SitePatchSv {
            name = "task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv";
            baseSv = task6L1CFcRedirectIndexRing3Fifo2Sv;
            siteIds = task6Ui64Fifo2SiteMap.l1.postBranchOnly;
            ensureHelper = false;
          };
        task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Sv =
          mkTask6Ui64Fifo2SitePatchSv {
            name =
              "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv";
            baseSv = task6L1CFcRedirectIndexRing3PostBranchFifo2Sv;
            siteIds = task6Ui64Fifo2SiteMap.l1.postBranchOutBufOnly;
            ensureHelper = false;
          };
        task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2YosysStat =
          mkSvYosysStat {
            name = "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2";
            sv = task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Sv;
          };
        task6L1CFcRedirectJson = mkSynthJson {
          name = "task6-l1-c-fc-redirect";
          svFilelist = "${task6L1CFcRedirectSv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectSv}/sv/main.sv";
        };
        task6L1CFcRedirectAbc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-abc9";
          svFilelist = "${task6L1CFcRedirectSv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectSv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectUtilization = mkMappedJsonUtilizationReport {
          name = "task6-l1-c-fc-redirect";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L1CFcRedirectJson;
        };
        task6L1CFcRedirectAbc9Utilization = mkMappedJsonUtilizationReport {
          name = "task6-l1-c-fc-redirect-abc9";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L1CFcRedirectAbc9Json;
        };
        task6L1CFcRedirectUi64BufferLiteJson = mkSynthJson {
          name = "task6-l1-c-fc-redirect-ui64-buffer-lite";
          svFilelist = "${task6L1CFcRedirectUi64BufferLiteSv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectUi64BufferLiteSv}/sv/main.sv";
        };
        task6L1CFcRedirectUi64BufferLiteUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-ui64-buffer-lite";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectUi64BufferLiteJson;
          };
        task6L1CFcRedirectUi64BufferFifo2Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-ui64-buffer-fifo2";
          svFilelist = "${task6L1CFcRedirectUi64BufferFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectUi64BufferFifo2Sv}/sv/main.sv";
        };
        task6L1CFcRedirectUi64BufferFifo2Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-ui64-buffer-fifo2";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectUi64BufferFifo2Json;
          };
        task6L1CFcRedirectBuffer165Fifo2Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-buffer165-fifo2";
          svFilelist = "${task6L1CFcRedirectBuffer165Fifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectBuffer165Fifo2Sv}/sv/main.sv";
        };
        task6L1CFcRedirectBuffer165Fifo2Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-buffer165-fifo2";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectBuffer165Fifo2Json;
          };
        task6L1CFcRedirectIndexSpineFifo2Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-spine-fifo2";
          svFilelist = "${task6L1CFcRedirectIndexSpineFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexSpineFifo2Sv}/sv/main.sv";
        };
        task6L1CFcRedirectIndexSpineFifo2Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-spine-fifo2";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexSpineFifo2Json;
          };
        task6L1CFcRedirectIndexSpineFifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-spine-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexSpineFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexSpineFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexSpineFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-spine-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexSpineFifo2Abc9Json;
          };
        task6L1CFcRedirectIndexFanoutFifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-fanout-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexFanoutFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexFanoutFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexFanoutFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-fanout-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexFanoutFifo2Abc9Json;
          };
        task6L1CFcRedirectIndexRing2Fifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring2-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing2Fifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing2Fifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing2Fifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring2-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing2Fifo2Abc9Json;
          };
        task6L1CFcRedirectIndexRing3Fifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing3Fifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3Fifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing3Fifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring3-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing3Fifo2Abc9Json;
          };
        task6L1CFcRedirectIndexRing3CtrlMergeFifo2Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2";
          svFilelist = "${task6L1CFcRedirectIndexRing3CtrlMergeFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3CtrlMergeFifo2Sv}/sv/main.sv";
        };
        task6L1CFcRedirectIndexRing3CtrlMergeFifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing3CtrlMergeFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3CtrlMergeFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing3CtrlMergeFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing3CtrlMergeFifo2Abc9Json;
          };
        task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Abc9Json;
          };
        task6L1CFcRedirectIndexRing3Fork49StatevecAbc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing3Fork49StatevecSv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3Fork49StatevecSv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing3Fork49StatevecAbc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing3Fork49StatevecAbc9Json;
          };
        task6L1CFcRedirectIndexRing3SelectClusterFifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing3SelectClusterFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3SelectClusterFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing3SelectClusterFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing3SelectClusterFifo2Abc9Json;
          };
        task6L1CFcRedirectIndexRing3PostBranchFifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing3PostBranchFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3PostBranchFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing3PostBranchFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing3PostBranchFifo2Abc9Json;
          };
        task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Abc9Json = mkSynthJson {
          name = "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9";
          svFilelist = "${task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Abc9Json;
          };
        task6L1CFcRedirectStagedAbc9 = mkSynthJsonStages {
          name = "task6-l1-c-fc-redirect-staged-abc9";
          modelIl = task6L1CFcRedirectIl;
          topName = "main";
          quiet = true;
          useAbc9 = true;
        };
        task6L1CFcRedirectStagedAbc9Utilization = mkMappedJsonUtilizationReport {
          name = "task6-l1-c-fc-redirect-staged-abc9";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L1CFcRedirectStagedAbc9.json;
        };
        task6L2CFcRedirectPipeline = modelPipelines."task6-l2-c-fc-redirect";
        task6L2CFcRedirectSv = task6L2CFcRedirectPipeline.sv;
        task6L2CFcRedirectPostBranchFifo2Sv = mkTask6Ui64Fifo2SitePatchSv {
          name = "task6-l2-c-fc-redirect-postbranch-fifo2-sv";
          baseSv = task6L2CFcRedirectSv;
          siteIds = task6Ui64Fifo2SiteMap.l2.monolithicPostBranch;
        };
        task6L2CFcRedirectDownstreamOutBufFifo2Sv =
          mkTask6Ui64Fifo2SitePatchSv {
            name = "task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv";
            baseSv = task6L2CFcRedirectSv;
            siteIds = task6Ui64Fifo2SiteMap.l2.monolithicDownstreamOutBuf;
          };
        task6L2CFcRedirectJson = mkSynthJson {
          name = "task6-l2-c-fc-redirect";
          svFilelist = "${task6L2CFcRedirectSv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectSv}/sv/main.sv";
        };
        task6L2CFcRedirectUtilization = mkMappedJsonUtilizationReport {
          name = "task6-l2-c-fc-redirect";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = task6L2CFcRedirectJson;
        };
        task6L2CFcRedirectPostBranchFifo2Abc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-postbranch-fifo2-abc9";
          svFilelist = "${task6L2CFcRedirectPostBranchFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectPostBranchFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectPostBranchFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-postbranch-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L2CFcRedirectPostBranchFifo2Abc9Json;
          };
        task6L2CFcRedirectDownstreamOutBufFifo2Abc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9";
          svFilelist = "${task6L2CFcRedirectDownstreamOutBufFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectDownstreamOutBufFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectDownstreamOutBufFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L2CFcRedirectDownstreamOutBufFifo2Abc9Json;
          };
        task6L2CFcRedirectTile64Pipeline =
          modelPipelines."task6-l2-c-fc-redirect-tile64";
        task6L2CFcRedirectTile64YosysStat =
          task6L2CFcRedirectTile64Pipeline."yosys-stat";
        task6L2CFcRedirectTile64Sv = task6L2CFcRedirectTile64Pipeline.sv;
        task6L2CFcRedirectTile64Abc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-tile64-abc9";
          svFilelist = "${task6L2CFcRedirectTile64Sv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectTile64Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectTile64Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-tile64-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L2CFcRedirectTile64Abc9Json;
          };
        task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv =
          mkTask6Ui64Fifo2SitePatchSv {
            name = "task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-sv";
            baseSv = task6L2CFcRedirectTile64Sv;
            siteIds = task6Ui64Fifo2SiteMap.l2.tile64PostBranchOutBuf;
          };
        task6L2CFcRedirectTile64PostBranchOutBufFifo2Abc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9";
          svFilelist = "${task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectTile64PostBranchOutBufFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson =
              task6L2CFcRedirectTile64PostBranchOutBufFifo2Abc9Json;
          };
        task6L2CFcRedirectTile64StorepathForkCtrlSv = mkTask6PatchedSv {
          name = "task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv";
          baseSv = task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv;
          copiedSv = [
            {
              src = ./rtl/task6/task6_ctrl_fifo2_buffer.sv;
              dest = "task6_ctrl_fifo2_buffer.sv";
              appendToFilelists = true;
            }
            {
              src = ./rtl/task6/task6_ui64_fork2.sv;
              dest = "task6_ui64_fork2.sv";
              appendToFilelists = true;
            }
            {
              src = ./rtl/task6/task6_ui64_fork3.sv;
              dest = "task6_ui64_fork3.sv";
              appendToFilelists = true;
            }
            {
              src = ./rtl/task6/task6_ctrl_fork3.sv;
              dest = "task6_ctrl_fork3.sv";
              appendToFilelists = true;
            }
          ];
          rewriteMain =
            let
              ctrlBufferRewrites = pkgs.lib.concatMapStringsSep "\n" (id: ''
                sed -i \
                  "s/^  handshake_buffer_in_none_out_none_2slots_seq_1ins_1outs_ctrl handshake_buffer${toString id} (/  task6_ctrl_fifo2_buffer handshake_buffer${toString id} (/" \
                  "$out/sv/main.sv"
              '') task6Ui64Fifo2SiteMap.l2.tile64StorePathCtrlBuffers;
            in ''
              ${ctrlBufferRewrites}
              sed -i \
                's/^  handshake_fork_in_ui64_out_ui64_ui64 handshake_fork50 (/  task6_ui64_fork2 handshake_fork50 (/' \
                "$out/sv/main.sv"
              sed -i \
                's/^  handshake_fork_in_ui64_out_ui64_ui64_ui64 handshake_fork51 (/  task6_ui64_fork3 handshake_fork51 (/' \
                "$out/sv/main.sv"
              sed -i \
                's/^  handshake_fork_in_none_out_none_none_none_1ins_3outs_ctrl handshake_fork52 (/  task6_ctrl_fork3 handshake_fork52 (/' \
                "$out/sv/main.sv"
            '';
        };
        task6L2CFcRedirectTile64StorepathForkCtrlAbc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-tile64-storepath-forkctrl-abc9";
          svFilelist = "${task6L2CFcRedirectTile64StorepathForkCtrlSv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectTile64StorepathForkCtrlSv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectTile64StorepathForkCtrlAbc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-tile64-storepath-forkctrl-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson =
              task6L2CFcRedirectTile64StorepathForkCtrlAbc9Json;
          };
        task6L2CFcRedirectTile64StorepathForksSv = mkTask6PatchedSv {
          name = "task6-l2-c-fc-redirect-tile64-storepath-forks-sv";
          baseSv = task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv;
          copiedSv = [
            {
              src = ./rtl/task6/task6_ui64_fork2.sv;
              dest = "task6_ui64_fork2.sv";
              appendToFilelists = true;
            }
            {
              src = ./rtl/task6/task6_ui64_fork3.sv;
              dest = "task6_ui64_fork3.sv";
              appendToFilelists = true;
            }
            {
              src = ./rtl/task6/task6_ctrl_fork3.sv;
              dest = "task6_ctrl_fork3.sv";
              appendToFilelists = true;
            }
          ];
          rewriteMain = ''
            sed -i \
              's/^  handshake_fork_in_ui64_out_ui64_ui64 handshake_fork50 (/  task6_ui64_fork2 handshake_fork50 (/' \
              "$out/sv/main.sv"
            sed -i \
              's/^  handshake_fork_in_ui64_out_ui64_ui64_ui64 handshake_fork51 (/  task6_ui64_fork3 handshake_fork51 (/' \
              "$out/sv/main.sv"
            sed -i \
              's/^  handshake_fork_in_none_out_none_none_none_1ins_3outs_ctrl handshake_fork52 (/  task6_ctrl_fork3 handshake_fork52 (/' \
              "$out/sv/main.sv"
          '';
        };
        task6L2CFcRedirectTile64StorepathForksAbc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-tile64-storepath-forks-abc9";
          svFilelist = "${task6L2CFcRedirectTile64StorepathForksSv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectTile64StorepathForksSv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectTile64StorepathForksAbc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-tile64-storepath-forks-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L2CFcRedirectTile64StorepathForksAbc9Json;
          };
        task6L2CFcRedirectTile4x64Sv = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile4x64-sv" { } ''
            cp -r ${task6L2CFcRedirectTile64Sv} "$out"
            chmod -R u+w "$out"
            mv "$out/sv/main.sv" "$out/sv/task6_l2_c_fc_tile64_kernel.sv"
            sed -i \
              '0,/^module main(/s//module task6_l2_c_fc_tile64_kernel(/' \
              "$out/sv/task6_l2_c_fc_tile64_kernel.sv"
            cp ${
              ./rtl/task6/task6_l2_c_fc_tile4x64_main.sv
            } "$out/sv/main.sv"
            sed \
              -e "s#${task6L2CFcRedirectTile64Sv}/sv/main.sv#$out/sv/task6_l2_c_fc_tile64_kernel.sv#g" \
              -e "s#${task6L2CFcRedirectTile64Sv}/sv/#$out/sv/#g" \
              ${task6L2CFcRedirectTile64Sv}/sources.f > "$out/sources.f"
            printf '%s\n' "$out/sv/main.sv" >> "$out/sources.f"
            sed \
              -e "s#^main\\.sv#task6_l2_c_fc_tile64_kernel.sv#g" \
              ${task6L2CFcRedirectTile64Sv}/sv/filelist.f > "$out/sv/filelist.f"
            printf '%s\n' "main.sv" >> "$out/sv/filelist.f"
          '';
        task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Sv = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv" { } ''
            cp -r ${task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv} "$out"
            chmod -R u+w "$out"
            mv "$out/sv/main.sv" "$out/sv/task6_l2_c_fc_tile64_kernel.sv"
            sed -i \
              '0,/^module main(/s//module task6_l2_c_fc_tile64_kernel(/' \
              "$out/sv/task6_l2_c_fc_tile64_kernel.sv"
            cp ${
              ./rtl/task6/task6_l2_c_fc_tile4x64_main.sv
            } "$out/sv/main.sv"
            sed \
              -e "s#${task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv}/sv/main.sv#$out/sv/task6_l2_c_fc_tile64_kernel.sv#g" \
              -e "s#${task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv}/sv/#$out/sv/#g" \
              ${task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv}/sources.f > "$out/sources.f"
            printf '%s\n' "$out/sv/main.sv" >> "$out/sources.f"
            sed \
              -e "s#^main\\.sv#task6_l2_c_fc_tile64_kernel.sv#g" \
              ${task6L2CFcRedirectTile64PostBranchOutBufFifo2Sv}/sv/filelist.f > "$out/sv/filelist.f"
            printf '%s\n' "main.sv" >> "$out/sv/filelist.f"
          '';
        task6L2CFcRedirectTile4x64PostBranchOutBufFifo2YosysStat =
          mkSvYosysStat {
            name = "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2";
            sv = task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Sv;
          };
        task6L2CFcRedirectTile4x64Abc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-tile4x64-abc9";
          svFilelist = "${task6L2CFcRedirectTile4x64Sv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectTile4x64Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Abc9Json = mkSynthJson {
          name = "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9";
          svFilelist = "${task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Sv}/sources.f";
          topName = "main";
          topSv = "${task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Sv}/sv/main.sv";
          useAbc9 = true;
        };
        task6L2CFcRedirectTile4x64Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-tile4x64-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = task6L2CFcRedirectTile4x64Abc9Json;
          };
        task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Abc9Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson =
              task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Abc9Json;
          };
        tinyStories1mPipeline = modelPipelines."tiny-stories-1m";
        tinyStories1mIl = tinyStories1mPipeline.il;
        tinyStories1mBaselineFloatPipeline =
          modelPipelines."tiny-stories-1m-baseline-float";
        tinyStories1mBaselineFloatIl = tinyStories1mBaselineFloatPipeline.il;
        representativeCoreDefaultKey =
          (builtins.head representativeCoreSweepSpecs).key;
        tinyStories1mRepresentativeCorePipeline =
          builtins.getAttr representativeCoreDefaultKey modelPipelines;
        tinyStories1mRepresentativeCoreIl =
          tinyStories1mRepresentativeCorePipeline.il;
        tinyStoriesCapacities = {
          slices = 74650;
          clb_luts = 298600;
          clb_ffs = 597200;
          dsp = 1920;
          bram36 = 955;
          bram_kb = 34380;
        };

        boardXdc = "${ypcbHack}/constraints/ypcb003381p1.xdc";

        mkYosysRtlil = { name, quiet ? false, memoryLimitKb ? null, script }:
          pkgs.runCommand "${name}.il" { } ''
            cat > run.ys <<EOF
            ${script}
            EOF
            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}
            ${yosysPkg}/bin/yosys ${
              pkgs.lib.optionalString quiet "-q"
            } -m ${yosysSlang}/share/yosys/plugins/slang.so -s run.ys

            if [ ! -e "$out" ]; then
              echo "mkYosysRtlil expected output path was not created: $out" >&2
              echo "--- run.ys ---" >&2
              cat run.ys >&2
              exit 1
            fi
          '';

        mkYosysJson = { name, modelIl, topName, topSv }:
          pkgs.runCommand "${name}.json" { } ''
            ${yosysPkg}/bin/yosys -m ${yosysSlang}/share/yosys/plugins/slang.so -p "
              read_rtlil ${modelIl}
              read_slang ${topSv}
              hierarchy -top ${topName} -check
              write_json $out
            "
          '';

        mkSynthStageIl = { name, stageId, stageLabel, inputIl, topName
          , topSv ? null, quiet ? false, memoryLimitKb ? null, preCommands ? [ ]
          , commands }:
          pkgs.runCommand "${name}-${stageId}.il" { } ''
            cat > run.ys <<EOF
            ${builtins.concatStringsSep "\n" ([ "read_rtlil ${inputIl}" ]
              ++ pkgs.lib.optional (topSv != null) "read_slang ${topSv}"
              ++ [ "hierarchy -top ${topName} -check" ] ++ preCommands
              ++ commands ++ [ "write_rtlil $out" ])}
            EOF

            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}

            echo "[mkSynthJson:${name}] ${stageLabel}" >&2
            ${yosysPkg}/bin/yosys ${pkgs.lib.optionalString quiet "-q"} ${
              pkgs.lib.optionalString (topSv != null)
              "-m ${yosysSlang}/share/yosys/plugins/slang.so"
            } -s run.ys

            if [ ! -e "$out" ]; then
              echo "mkSynthJson ${stageId} expected output path was not created: $out" >&2
              echo "--- run.ys ---" >&2
              cat run.ys >&2
              exit 1
            fi
          '';

        mkSynthStageMemoryMapIl = { name, stageId, stageLabel, inputIl, topName
          , quiet ? false, memoryLimitKb ? null }:
          pkgs.runCommand "${name}-${stageId}.il" { } ''
            ${pkgs.gawk}/bin/awk '
              /^module / { mod = $2 }
              /^[[:space:]]*cell \$mem/ { mods[mod] = 1 }
              END {
                for (mod in mods)
                  print mod
              }
            ' ${inputIl} | sort > stage-modules.txt

            cat > run.ys <<EOF
            read_rtlil ${inputIl}
            hierarchy -top ${topName} -check
            EOF

            while IFS= read -r moduleName; do
              printf '%s\n' \
                "cd $moduleName" \
                'memory_map' \
                'cd ..' \
                >> run.ys
            done < stage-modules.txt

            printf '%s\n' "write_rtlil $out" >> run.ys

            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}

            echo "[mkSynthJson:${name}] ${stageLabel}" >&2
            ${yosysPkg}/bin/yosys ${
              pkgs.lib.optionalString quiet "-q"
            } -s run.ys

            if [ ! -e "$out" ]; then
              echo "mkSynthJson ${stageId} expected output path was not created: $out" >&2
              echo "--- run.ys ---" >&2
              cat run.ys >&2
              exit 1
            fi
          '';

        mkSynthStageTargetedTechmapIl = { name, stageId, stageLabel, inputIl
          , topName, quiet ? false, memoryLimitKb ? null, cellRegex, techmapArgs
          , batchSize ? null, restartPerBatch ? false }:
          pkgs.runCommand "${name}-${stageId}.il" { } ''
            awk '
              /^module / { mod = $2 }
              /^[[:space:]]*cell / {
                cell_name = $2
                if (cell_name ~ ${builtins.toJSON cellRegex})
                  mods[mod] = 1
              }
              END {
                for (mod in mods)
                  print mod
              }
            ' ${inputIl} | sort > stage-modules.txt

            moduleCount=$(wc -l < stage-modules.txt)
            ${pkgs.lib.optionalString (batchSize != null) ''
              batchSize=${toString batchSize}
              if [ "$moduleCount" -eq 0 ]; then
                batchCount=0
              else
                batchCount=$(( (moduleCount + batchSize - 1) / batchSize ))
              fi
            ''}

            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}

            echo "[mkSynthJson:${name}] ${stageLabel} (selected modules: $moduleCount${
              pkgs.lib.optionalString (batchSize != null)
              ", batch size: ${toString batchSize}, batches: \$batchCount${
                pkgs.lib.optionalString restartPerBatch ", mode: restart"
              }"
            })" >&2

            ${pkgs.lib.optionalString (batchSize == null) ''
              cat > run.ys <<EOF
              read_rtlil ${inputIl}
              hierarchy -top ${topName} -check
              select -none
              EOF

              while IFS= read -r moduleName; do
                printf '%s\n' \
                  "select -add $moduleName" \
                  >> run.ys
              done < stage-modules.txt

              cat >> run.ys <<EOF
              techmap ${techmapArgs}
              select -clear
              write_rtlil $out
              EOF

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s run.ys
            ''}

            ${pkgs.lib.optionalString (batchSize != null && !restartPerBatch) ''
              cat > run.ys <<EOF
              read_rtlil ${inputIl}
              hierarchy -top ${topName} -check
              select -none
              EOF

              batchModules=0
              while IFS= read -r moduleName; do
                if [ "$batchModules" -gt 0 ] && [ $((batchModules % batchSize)) -eq 0 ]; then
                  cat >> run.ys <<EOF
            techmap ${techmapArgs}
            select -clear
            select -none
            EOF
                fi
                printf '%s\n' \
                  "select -add $moduleName" \
                  >> run.ys
                batchModules=$((batchModules + 1))
              done < stage-modules.txt

              if [ "$moduleCount" -gt 0 ]; then
                cat >> run.ys <<EOF
            techmap ${techmapArgs}
            select -clear
            EOF
              fi

              cat >> run.ys <<EOF
            write_rtlil $out
            EOF

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s run.ys
            ''}

            ${pkgs.lib.optionalString (batchSize != null && restartPerBatch) ''
              cp ${inputIl} work.il

              if [ "$moduleCount" -gt 0 ]; then
                batchIndex=0
                while [ "$batchIndex" -lt "$batchCount" ]; do
                  startLine=$((batchIndex * batchSize + 1))
                  endLine=$((startLine + batchSize - 1))
                  sed -n "''${startLine},''${endLine}p" stage-modules.txt > batch-modules.txt

                  echo "[mkSynthJson:${name}] ${stageLabel} batch $((batchIndex + 1))/$batchCount" >&2

                  printf '%s\n' \
                    'read_rtlil work.il' \
                    'hierarchy -top ${topName} -check' \
                    'select -none' \
                    > run.ys

                  while IFS= read -r moduleName; do
                    printf '%s\n' \
                      "select -add $moduleName" \
                      >> run.ys
                  done < batch-modules.txt

                  printf '%s\n' \
                    'techmap ${techmapArgs}' \
                    'select -clear' \
                    'write_rtlil next.il' \
                    >> run.ys

                  ${yosysPkg}/bin/yosys ${
                    pkgs.lib.optionalString quiet "-q"
                  } -s run.ys

                  mv next.il work.il
                  batchIndex=$((batchIndex + 1))
                done
              fi

              cp work.il $out
            ''}

            if [ ! -e "$out" ]; then
              echo "mkSynthJson ${stageId} expected output path was not created: $out" >&2
              echo "--- run.ys ---" >&2
              cat run.ys >&2
              exit 1
            fi
          '';
        mkSynthStageJson = { name, stageId, stageLabel, inputIl, quiet ? false
          , memoryLimitKb ? null }:
          pkgs.runCommand "${name}.json" { } ''
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/filter_rtlil_modules.py
            } \
              --input ${inputIl} \
              --output stage8-stripped.il \
              --drop-escaped-uppercase-modules

            cat > run.ys <<EOF
            read_rtlil stage8-stripped.il
            proc
            write_json $out
            EOF

            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}

            echo "[mkSynthJson:${name}] ${stageLabel}" >&2
            ${yosysPkg}/bin/yosys ${
              pkgs.lib.optionalString quiet "-q"
            } -s run.ys

            if [ ! -e "$out" ]; then
              echo "mkSynthJson ${stageId} expected output path was not created: $out" >&2
              echo "--- run.ys ---" >&2
              cat run.ys >&2
              exit 1
            fi
          '';

        mkSynthStage9Debug = { name, inputIl, failingLine ? 66916687
          , contextLines ? 40 }:
          pkgs.runCommand "${name}-stage9-debug" { } ''
            mkdir -p "$out"

            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/filter_rtlil_modules.py
            } \
              --input ${inputIl} \
              --output stage8-stripped.il \
              --drop-escaped-uppercase-modules

            line=${toString failingLine}
            context=${toString contextLines}
            line_count=$(wc -l < stage8-stripped.il)
            focus_line=$line
            if [ "$focus_line" -gt "$line_count" ]; then
              focus_line=$line_count
            fi
            start=$((line - context))
            end=$((line + context))
            if [ "$line" -gt "$line_count" ]; then
              start=$((line_count - context))
              end=$line_count
            fi
            if [ "$start" -lt 1 ]; then
              start=1
            fi

            {
              echo "name: ${name}"
              echo "input_il: ${inputIl}"
              echo "filtered_line_count: $line_count"
              echo "failing_line: $line"
              echo "context_focus_line: $focus_line"
              echo "context_start: $start"
              echo "context_end: $end"
            } > "$out/summary.txt"

            sed -n "''${start},''${end}p" stage8-stripped.il \
              > "$out/failing-line-context.il"
            sed -n "''${start},''${end}p" stage8-stripped.il \
              | nl -ba -v "$start" \
              > "$out/failing-line-context-numbered.il"
            tail -n "$context" stage8-stripped.il > "$out/eof-context.il"

            cat > "$out/run.ys" <<EOF
            read_rtlil stage8-stripped.il
            proc
            write_json stage9-debug.json
            EOF

            set +e
            ${yosysPkg}/bin/yosys -s "$out/run.ys" \
              > "$out/stage9-debug.log" 2>&1
            status=$?
            set -e

            echo "yosys_exit_status: $status" >> "$out/summary.txt"
            if [ -e stage9-debug.json ]; then
              cp stage9-debug.json "$out/stage9-debug.json"
            fi
          '';

        mkSynthJsonStages = { name, modelIl, topName, topSv ? null
          , quiet ? false, memoryLimitKb ? null, splitFineStage ? false
          , useAbc9 ? false }: rec {
            stage1 = mkSynthStageIl {
              inherit name topName topSv quiet memoryLimitKb;
              stageId = "stage1";
              stageLabel = "stage1 synth_xilinx begin:prepare";
              inputIl = modelIl;
              preCommands = [ "proc" ];
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run begin:prepare"
              ];
            };

            stage2 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage2";
              stageLabel = "stage2 synth_xilinx coarse:map_memory";
              inputIl = stage1;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run coarse:map_memory"
              ];
            };

            stage3 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage3";
              stageLabel = "stage3 opt -fast -full";
              inputIl = stage2;
              commands = [ "opt -fast -full" ];
            };

            stage4 = mkSynthStageMemoryMapIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage4";
              stageLabel = "stage4 targeted memory_map";
              inputIl = stage3;
            };

            stage5a = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage5a";
              stageLabel = "stage5a fine opt -full";
              inputIl = stage4;
              commands = [ "opt -full" ];
            };

            stage5b = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage5b";
              stageLabel = "stage5b xilinx_srl -variable -minlen 3";
              inputIl = stage5a;
              commands = [ "xilinx_srl -variable -minlen 3" ];
            };

            stage5c = mkSynthStageTargetedTechmapIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage5c";
              stageLabel = "stage5c targeted techmap arith_map";
              inputIl = stage5b;
              cellRegex = "^\\$(alu|lcu)$";
              techmapArgs =
                "-map +/techmap.v -D LUT_SIZE=6 -map +/xilinx/arith_map.v";
            };

            stage5d = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage5d";
              stageLabel = "stage5d opt -fast";
              inputIl = stage5c;
              commands = [ "opt -fast" ];
            };

            stage5Monolithic = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage5";
              stageLabel = "stage5 synth_xilinx fine:fine";
              inputIl = stage4;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run fine:fine"
              ];
            };
            stage5 = stage5Monolithic;

            stage6a = mkSynthStageTargetedTechmapIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage6a";
              stageLabel = "stage6a targeted techmap cells_map";
              inputIl = if splitFineStage then stage5d else stage5Monolithic;
              cellRegex = "^\\$";
              techmapArgs = "-map +/techmap.v -map +/xilinx/cells_map.v";
              batchSize = 2;
              restartPerBatch = true;
            };

            stage6b = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage6b";
              stageLabel = "stage6b clean";
              inputIl = stage6a;
              commands = [ "clean" ];
            };

            stage6Monolithic = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage6";
              stageLabel = "stage6 synth_xilinx map_cells:map_cells";
              inputIl = if splitFineStage then stage5d else stage5Monolithic;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run map_cells:map_cells"
              ];
            };
            stage6 = stage6Monolithic;

            stage7 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage7";
              stageLabel = if useAbc9 then
                "stage7 synth_xilinx -abc9 map_ffs:map_ffs"
              else
                "stage7 synth_xilinx map_ffs:map_ffs";
              inputIl = if splitFineStage then stage6b else stage6Monolithic;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad ${
                  pkgs.lib.optionalString useAbc9 "-abc9 "
                }-run map_ffs:map_ffs"
              ];
            };

            stage8a = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8a";
              stageLabel = "stage8a opt_expr -mux_undef -noclkinv";
              inputIl = stage7;
              commands = [ "opt_expr -mux_undef -noclkinv" ];
            };

            stage8b = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8b";
              stageLabel = "stage8b abc -luts 2:2,3,6:5,10,20";
              inputIl = stage8a;
              commands = [ "abc -luts 2:2,3,6:5,10,20" ];
            };

            stage8c = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8c";
              stageLabel = "stage8c clean";
              inputIl = stage8b;
              commands = [ "clean" ];
            };

            stage8d = mkSynthStageTargetedTechmapIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8d";
              stageLabel = "stage8d targeted techmap ff_map";
              inputIl = stage8c;
              cellRegex = "^\\$_(DFF|DFFE|DFFSRE|SDFF|SDFFE|DLATCH)_";
              techmapArgs = "-map +/xilinx/ff_map.v";
            };

            stage8e = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8e";
              stageLabel = "stage8e xilinx_srl -fixed -minlen 3";
              inputIl = stage8d;
              commands = [ "xilinx_srl -fixed -minlen 3" ];
            };

            stage8f = mkSynthStageTargetedTechmapIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8f";
              stageLabel = "stage8f targeted techmap lut_map";
              inputIl = stage8e;
              cellRegex = "^\\$(lut|__XILINX_SHIFTX)$";
              techmapArgs =
                "-map +/xilinx/lut_map.v -map +/xilinx/cells_map.v -D LUT_WIDTH=6";
            };

            stage8g = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8g";
              stageLabel = "stage8g xilinx_dffopt";
              inputIl = stage8f;
              commands = [ "xilinx_dffopt" ];
            };

            stage8h = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8h";
              stageLabel = "stage8h opt_lut_ins -tech xilinx";
              inputIl = stage8g;
              commands = [ "opt_lut_ins -tech xilinx" ];
            };

            stage8Monolithic = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8";
              stageLabel = if useAbc9 then
                "stage8 final synth/write -abc9"
              else
                "stage8 final synth/write";
              inputIl = stage7;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad ${
                  pkgs.lib.optionalString useAbc9 "-abc9 "
                }-run map_luts:check"
              ];
            };

            stage8Abc9 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8";
              stageLabel = "stage8 synth_xilinx -abc9 map_luts:check";
              inputIl = stage7;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -abc9 -run map_luts:check"
              ];
            };

            stage8 = if splitFineStage then
              (if useAbc9 then stage8Abc9 else stage8h)
            else
              stage8Monolithic;
            stage9 = mkSynthStageJson {
              inherit name quiet memoryLimitKb;
              stageId = "stage9";
              stageLabel = "stage9 write_json";
              inputIl = stage8;
            };

            json = stage9;
          };

        appendYosysCommands = commands: ''
          cat >> run.ys <<EOF
          ${pkgs.lib.concatStringsSep "\n" commands}
          EOF
        '';

        appendReadSlangFromFilelist = { svFilelist, topSv }: ''
          {
            printf 'read_slang --threads 1 --no-proc'
            while IFS= read -r line; do
              if [ -z "''${line//[[:space:]]/}" ]; then
                continue
              fi
              if [ "''${line#\#}" != "$line" ]; then
                continue
              fi
              printf ' %q' "$line"
            done < ${svFilelist}
            printf ' %q' ${topSv}
            printf '\n'
          } >> run.ys
        '';

        mkTask6PatchedSv =
          { name, baseSv, copiedSv ? [ ], rewriteMain ? "" }:
          let
            copyCommands = pkgs.lib.concatMapStringsSep "\n" (entry: ''
              cp ${entry.src} "$out/sv/${entry.dest}"
            '') copiedSv;
            appendSourcesCommands =
              pkgs.lib.concatMapStringsSep "\n" (entry:
                pkgs.lib.optionalString (entry.appendToFilelists or false) ''
                  printf '%s\n' "$out/sv/${entry.dest}" >> "$out/sources.f"
                '') copiedSv;
            appendFilelistCommands =
              pkgs.lib.concatMapStringsSep "\n" (entry:
                pkgs.lib.optionalString (entry.appendToFilelists or false) ''
                  printf '%s\n' "$out/sv/${entry.dest}" >> "$out/sv/filelist.f"
                '') copiedSv;
          in pkgs.runCommand name { } ''
            cp -r ${baseSv} "$out"
            chmod -R u+w "$out"
            ${copyCommands}
            ${rewriteMain}
            sed \
              "s#${baseSv}/sv/#$out/sv/#g" \
              ${baseSv}/sources.f > "$out/sources.f"
            ${appendSourcesCommands}
            sed \
              "s#${baseSv}/sv/#$out/sv/#g" \
              ${baseSv}/sv/filelist.f > "$out/sv/filelist.f"
            ${appendFilelistCommands}
          '';

        mkTask6Ui64Fifo2SitePatchSv =
          { name, baseSv, siteIds, ensureHelper ? true }:
          mkTask6PatchedSv {
            inherit name baseSv;
            copiedSv = pkgs.lib.optionals ensureHelper [{
              src = ./rtl/task6/task6_ui64_fifo2_buffer.sv;
              dest = "task6_ui64_fifo2_buffer.sv";
              appendToFilelists = true;
            }];
            rewriteMain = pkgs.lib.concatMapStringsSep "\n" (id: ''
              sed -i \
                "s/^  handshake_buffer_in_ui64_out_ui64_2slots_seq handshake_buffer${toString id} (/  task6_ui64_fifo2_buffer handshake_buffer${toString id} (/" \
                "$out/sv/main.sv"
              grep -q \
                "^  task6_ui64_fifo2_buffer handshake_buffer${toString id} (" \
                "$out/sv/main.sv"
            '') siteIds;
          };

        mkTask6Ui64Fifo2WholeClassSv = { name, baseSv }:
          mkTask6PatchedSv {
            inherit name baseSv;
            copiedSv = [
              {
                src = ./rtl/task6/task6_ui64_fifo2_buffer.sv;
                dest = "task6_ui64_fifo2_buffer.sv";
                appendToFilelists = true;
              }
              {
                src = ./rtl/task6/handshake_buffer_in_ui64_out_ui64_2slots_seq_fifo2.sv;
                dest = "handshake_buffer_in_ui64_out_ui64_2slots_seq.sv";
              }
            ];
          };

        mkSynthJson =
          { name, modelIl ? null, svFilelist ? null, topName, topSv
          , useAbc9 ? false }:
          let
            useModelIl = modelIl != null;
            useSvFilelist = svFilelist != null;
            inputScript = if useModelIl then
              appendYosysCommands
              ([ "read_rtlil ${modelIl}" ] ++ [ "read_slang ${topSv}" ])
            else
              appendReadSlangFromFilelist {
                inherit svFilelist;
                inherit topSv;
              };
          in assert pkgs.lib.assertMsg (useModelIl != useSvFilelist)
            "mkSynthJson requires exactly one of `modelIl` or `svFilelist`";
          pkgs.runCommand "${name}.json" { } ''
            ${inputScript}
            ${appendYosysCommands [
              "hierarchy -top ${topName} -check"
              "proc"
              "synth_xilinx -family xc7 -top ${topName} -noiopad ${pkgs.lib.optionalString useAbc9 "-abc9 "} -json $out"
            ]}

            echo "[mkSynthJson:${name}] stage8 final synth/write${pkgs.lib.optionalString useAbc9 " -abc9"}" >&2
            ${yosysPkg}/bin/yosys -m ${yosysSlang}/share/yosys/plugins/slang.so -s run.ys

            if [ ! -e "$out" ]; then
              echo "mkSynthJson expected output path was not created: $out" >&2
              echo "--- run.ys ---" >&2
              cat run.ys >&2
              exit 1
            fi
          '';

        mkRtlilStageStatReport = { name, stageId, inputIl, topName }:
          pkgs.runCommand "${name}-${stageId}-stats" {
            nativeBuildInputs = [ pkgs.python311 yosysPkg ];
          } ''
            cat > run.ys <<EOF
            read_rtlil ${inputIl}
            hierarchy -top ${topName} -check
            tee -o raw-stat.json stat -json
            EOF

            ${yosysPkg}/bin/yosys -q -s run.ys >/dev/null

            mkdir -p "$out"
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/write_rtlil_stage_stat_report.py
            } \
              --input-il ${inputIl} \
              --raw-yosys-json raw-stat.json \
              --summary-json "$out/summary.json" \
              --summary-txt "$out/summary.txt" \
              --stat-json "$out/stat.json" \
              --top ${topName} \
              --stage-id ${stageId}
          '';

        mkRtlilStageStats = { name, stages, topName, splitFineStage ? false
          , useAbc9 ? false }:
          let
            stageOrder =
              if splitFineStage then
                if useAbc9 then
                  [
                    "stage1"
                    "stage2"
                    "stage3"
                    "stage4"
                    "stage5a"
                    "stage5b"
                    "stage5c"
                    "stage5d"
                    "stage6a"
                    "stage6b"
                    "stage7"
                    "stage8"
                  ]
                else
                  [
                    "stage1"
                    "stage2"
                    "stage3"
                    "stage4"
                    "stage5a"
                    "stage5b"
                    "stage5c"
                    "stage5d"
                    "stage6a"
                    "stage6b"
                    "stage7"
                    "stage8a"
                    "stage8b"
                    "stage8c"
                    "stage8d"
                    "stage8e"
                    "stage8f"
                    "stage8g"
                    "stage8h"
                  ]
              else
                [
                  "stage1"
                  "stage2"
                  "stage3"
                  "stage4"
                  "stage5"
                  "stage6"
                  "stage7"
                  "stage8"
                ];
            reports = builtins.listToAttrs (map (stageId: {
              name = stageId;
              value = mkRtlilStageStatReport {
                inherit name stageId topName;
                inputIl = builtins.getAttr stageId stages;
              };
            }) stageOrder);
            index = pkgs.writeText "${name}-stage-stats-index.json"
              (builtins.toJSON {
                inherit name stageOrder;
                top = topName;
              });
            bundle = pkgs.runCommand "${name}-stage-stats" { } ''
              mkdir -p "$out"
              cp ${index} "$out/index.json"
              ${builtins.concatStringsSep "\n" (map (stageId: ''
                mkdir -p "$out/${stageId}"
                cp ${builtins.getAttr stageId reports}/summary.json "$out/${stageId}/summary.json"
                cp ${builtins.getAttr stageId reports}/summary.txt "$out/${stageId}/summary.txt"
                cp ${builtins.getAttr stageId reports}/stat.json "$out/${stageId}/stat.json"
              '') stageOrder)}
            '';
          in {
            inherit stageOrder reports bundle;
          };

        mkStageStatComparison = { name, baselineDir, candidateDir
          , baselineLabel, candidateLabel, stageMapJson ? null }:
          pkgs.runCommand "${name}-stage-stats-compare" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
            mkdir -p "$out"
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/compare_stage_stats.py
            } \
              --baseline-dir ${baselineDir} \
              --candidate-dir ${candidateDir} \
              --baseline-label ${
                pkgs.lib.escapeShellArg baselineLabel
              } \
              --candidate-label ${
                pkgs.lib.escapeShellArg candidateLabel
              } ${
                pkgs.lib.optionalString (stageMapJson != null)
                "--stage-map-json ${stageMapJson}"
              } \
              --summary-json "$out/summary.json" \
              --summary-txt "$out/summary.txt"
          '';

        mkUtilizationComparison = { name, baselineDir, candidateDir
          , baselineLabel, candidateLabel }:
          pkgs.runCommand "${name}-utilization-compare" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
            mkdir -p "$out"
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/compare_utilization_reports.py
            } \
              --baseline-dir ${baselineDir} \
              --candidate-dir ${candidateDir} \
              --baseline-label ${
                pkgs.lib.escapeShellArg baselineLabel
              } \
              --candidate-label ${
                pkgs.lib.escapeShellArg candidateLabel
              } \
              --summary-json "$out/summary.json" \
              --summary-txt "$out/summary.txt"
          '';

        mkComparisonBundle = { name, baselineLabel, candidateLabel
          , stageStatsCompare, utilizationCompare }:
          let
            index = pkgs.writeText "${name}-index.json" (builtins.toJSON {
              inherit baselineLabel candidateLabel;
              views = {
                stageStats = "stage-stats/summary.json";
                utilization = "utilization/summary.json";
              };
            });
          in pkgs.runCommand "${name}-compare-bundle" { } ''
            mkdir -p "$out/stage-stats" "$out/utilization"
            cp ${index} "$out/index.json"
            cp ${stageStatsCompare}/summary.json "$out/stage-stats/summary.json"
            cp ${stageStatsCompare}/summary.txt "$out/stage-stats/summary.txt"
            cp ${utilizationCompare}/summary.json "$out/utilization/summary.json"
            cp ${utilizationCompare}/summary.txt "$out/utilization/summary.txt"
            {
              echo "baseline: ${baselineLabel}"
              echo "candidate: ${candidateLabel}"
              echo
              echo "[stage-stats]"
              cat ${stageStatsCompare}/summary.txt
              echo
              echo "[utilization]"
              cat ${utilizationCompare}/summary.txt
            } > "$out/summary.txt"
          '';

        mkRepresentativeCoreSweepSummary = { name, manifestJson }:
          pkgs.runCommand "${name}-summary" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
            mkdir -p "$out"
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/summarize_representative_core_sweep.py
            } \
              --manifest-json ${manifestJson} \
              --summary-json "$out/summary.json" \
              --summary-txt "$out/summary.txt"
          '';

        mkMlirOpStatsComparison = { name, baselineInput, baselineStats
          , candidateInput, candidateStats, baselineLabel, candidateLabel }:
          pkgs.runCommand "${name}-op-coverage" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
            mkdir -p "$out"
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/compare_mlir_op_stats.py
            } \
              --baseline-input ${baselineInput} \
              --candidate-input ${candidateInput} \
              --baseline-stats ${baselineStats} \
              --candidate-stats ${candidateStats} \
              --baseline-label ${
                pkgs.lib.escapeShellArg baselineLabel
              } \
              --candidate-label ${
                pkgs.lib.escapeShellArg candidateLabel
              } \
              --summary-json "$out/summary.json" \
              --summary-txt "$out/summary.txt"
          '';

        mkMlirOpCoverageBundle = { name, baselineLabel, candidateLabel
          , torchCoverage, cfCoverage }:
          let
            index = pkgs.writeText "${name}-index.json" (builtins.toJSON {
              inherit baselineLabel candidateLabel;
              views = {
                torch = "torch/summary.json";
                cf = "cf/summary.json";
              };
            });
          in pkgs.runCommand "${name}-op-coverage-bundle" { } ''
            mkdir -p "$out/torch" "$out/cf"
            cp ${index} "$out/index.json"
            cp ${torchCoverage}/summary.json "$out/torch/summary.json"
            cp ${torchCoverage}/summary.txt "$out/torch/summary.txt"
            cp ${cfCoverage}/summary.json "$out/cf/summary.json"
            cp ${cfCoverage}/summary.txt "$out/cf/summary.txt"
            {
              echo "baseline: ${baselineLabel}"
              echo "candidate: ${candidateLabel}"
              echo
              echo "[torch]"
              cat ${torchCoverage}/summary.txt
              echo
              echo "[cf]"
              cat ${cfCoverage}/summary.txt
            } > "$out/summary.txt"
          '';

        mkMappedJsonUtilizationReport =
          { name, capacities, topName, designJson }:
          pkgs.runCommand "${name}-utilization" { } ''
            mkdir -p "$out"
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/write_utilization_report.py
            } \
              --design-json ${designJson} \
              --top ${topName} \
              --summary-json "$out/summary.json" \
              --summary-txt "$out/summary.txt" \
              --stat-json "$out/stat.json" \
              --capacity-slices ${toString capacities.slices} \
              --capacity-clb-luts ${toString capacities.clb_luts} \
              --capacity-clb-ffs ${toString capacities.clb_ffs} \
              --capacity-dsp ${toString capacities.dsp} \
              --capacity-bram36 ${toString capacities.bram36} \
              --capacity-bram-kb ${toString capacities.bram_kb}
          '';

        mkSvYosysStat = { name, sv, slangPerFileExternModules ? false }:
          pkgs.runCommand "${name}-yosys.stat" {
            buildInputs = [ yosysPkg python ];
          } ''
            ${pkgs.lib.optionalString slangPerFileExternModules ''
              export YOSYS_SLANG_PER_FILE_EXTERNS=1
            ''}
            ${pkgs.bash}/bin/bash ${pipelineScripts}/sv_to_yosys_stat.sh \
              ${yosysPkg}/bin/yosys \
              ${yosysSlang}/share/yosys/plugins/slang.so \
              ${sv}/sources.f "$out"
          '';

        mkExternalizedMemoryPlan =
          { name, modelIl, minModuleBits ? (128 * 1024), maxModules ? null }:
          pkgs.runCommand "${name}-external-memory-plan" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/externalize_large_memories.py
            } \
              --input ${modelIl} \
              --output-script externalize.ys \
              --output-report report.json \
              --min-module-bits ${toString minModuleBits} ${
                pkgs.lib.optionalString (maxModules != null)
                "--max-modules ${toString maxModules}"
              }
            mkdir -p "$out"
            cp externalize.ys "$out/externalize.ys"
            cp report.json "$out/report.json"
          '';

        mkTinyStoriesSelftestBundle = { name, topName, mainSv, modelIl
          , capacities, externalMemoryMinModuleBits ? (128 * 1024)
          , externalMemoryMaxModules ? null, useAbc9 ? false }:
          let
            top = pkgs.runCommand "${name}-top.sv" { } ''
              ${python}/bin/python ${
                ./scripts/pipeline/gen_tiny_stories_selftest_top.py
              } \
                --main-sv ${mainSv} \
                --out "$out"
            '';
            modelOptIl = mkYosysRtlil {
              name = "${name}-model-opt";
              script = ''
                read_rtlil ${modelIl}
                hierarchy -top main -check
                proc
                opt_expr
                opt_clean
                clean
                write_rtlil $out
              '';
            };
            externalMemoryPlan = mkExternalizedMemoryPlan {
              inherit name;
              modelIl = modelOptIl;
              minModuleBits = externalMemoryMinModuleBits;
              maxModules = externalMemoryMaxModules;
            };
            modelShellIl = mkYosysRtlil {
              name = "${name}-model-shell";
              script = ''
                read_rtlil ${modelOptIl}
                script ${externalMemoryPlan}/externalize.ys
                hierarchy -top main -check
                write_rtlil $out
              '';
            };
            stages = mkSynthJsonStages {
              inherit name topName;
              modelIl = modelShellIl;
              topSv = top;
              quiet = true;
              splitFineStage = externalMemoryMaxModules != null;
              inherit useAbc9;
            };
            inherit (stages) json;
            yosysJson = mkYosysJson {
              name = "${name}-yosys";
              inherit topName;
              modelIl = modelShellIl;
              topSv = top;
            };
            utilizationReport = mkMappedJsonUtilizationReport {
              inherit name capacities topName;
              designJson = json;
            };
            rtlilStageStats = mkRtlilStageStats {
              inherit name stages topName;
              splitFineStage = externalMemoryMaxModules != null;
              inherit useAbc9;
            };
            stage9Debug = mkSynthStage9Debug {
              inherit name;
              inputIl = stages.stage8;
            };
          in {
            inherit top modelOptIl modelShellIl externalMemoryPlan stages json
              yosysJson utilizationReport rtlilStageStats stage9Debug;
          };

        representativeCoreAllMemoryVsTop4MemoryStageMap = pkgs.writeText
          "tiny-stories-1m-representative-core-all-memory-vs-top4-memory-stage-map.json"
          (builtins.toJSON [
            {
              id = "stage1";
              baseline = "stage1";
              candidate = "stage1";
              label = "begin:prepare";
            }
            {
              id = "stage2";
              baseline = "stage2";
              candidate = "stage2";
              label = "coarse:map_memory";
            }
            {
              id = "stage3";
              baseline = "stage3";
              candidate = "stage3";
              label = "post-memory-map opt";
            }
            {
              id = "stage4";
              baseline = "stage4";
              candidate = "stage4";
              label = "targeted memory_map";
            }
            {
              id = "stage5";
              baseline = "stage5";
              candidate = "stage5d";
              label = "fine:fine frontier";
            }
            {
              id = "stage6";
              baseline = "stage6";
              candidate = "stage6b";
              label = "map_cells frontier";
            }
            {
              id = "stage7";
              baseline = "stage7";
              candidate = "stage7";
              label = "map_ffs frontier";
            }
            {
              id = "stage8";
              baseline = "stage8";
              candidate = "stage8h";
              label = "map_luts:check frontier";
            }
          ]);

        mkRepresentativeCoreAllMemoryVsTop4MemoryArtifacts = { key, allMemory
          , top4Memory }:
          let
            comparisonName = "${key}-all-memory-vs-top4-memory";
            baselineLabel = "${key}-selftest-all-memory";
            candidateLabel = "${key}-selftest-top4-memory";
            stageStatsCompare = mkStageStatComparison {
              name = comparisonName;
              baselineDir = allMemory.rtlilStageStats.bundle;
              candidateDir = top4Memory.rtlilStageStats.bundle;
              inherit baselineLabel candidateLabel;
              stageMapJson = representativeCoreAllMemoryVsTop4MemoryStageMap;
            };
            utilizationCompare = mkUtilizationComparison {
              name = comparisonName;
              baselineDir = allMemory.utilizationReport;
              candidateDir = top4Memory.utilizationReport;
              inherit baselineLabel candidateLabel;
            };
            compare = mkComparisonBundle {
              name = comparisonName;
              inherit baselineLabel candidateLabel stageStatsCompare
                utilizationCompare;
            };
          in {
            inherit stageStatsCompare utilizationCompare compare;
          };

        mkRepresentativeCoreSweepVariantArtifacts = spec:
          let
            key = spec.key;
            pipeline = builtins.getAttr key modelPipelines;
            modelIl = pipeline.il;
            allMemory = mkTinyStoriesSelftestBundle {
              name = "${key}-selftest-all-memory";
              topName = "tiny_stories_selftest_top";
              mainSv = "${pipeline.sv}/sv/main.sv";
              inherit modelIl;
              capacities = tinyStoriesCapacities;
              externalMemoryMinModuleBits = 1;
            };
            top4Memory = mkTinyStoriesSelftestBundle {
              name = "${key}-selftest-top4-memory";
              topName = "tiny_stories_selftest_top";
              mainSv = "${pipeline.sv}/sv/main.sv";
              inherit modelIl;
              capacities = tinyStoriesCapacities;
              externalMemoryMinModuleBits = 1;
              externalMemoryMaxModules = 4;
            };
            allVsTop4 = mkRepresentativeCoreAllMemoryVsTop4MemoryArtifacts {
              inherit key allMemory top4Memory;
            };
          in {
            inherit spec pipeline modelIl allMemory top4Memory allVsTop4;
          };

        representativeCoreSweepArtifacts = builtins.listToAttrs
          (map (spec: {
            name = spec.key;
            value = mkRepresentativeCoreSweepVariantArtifacts spec;
          }) representativeCoreSweepSpecs);

        representativeCoreSweepManifest = pkgs.writeText
          "tiny-stories-1m-representative-core-sweep-manifest.json"
          (builtins.toJSON (map (spec: {
            inherit (spec) key label;
            config = {
              vocab_size = spec.vocabSize;
              num_layers = spec.numLayers;
              max_position_embeddings = spec.maxPositionEmbeddings;
              window_size = spec.windowSize;
              hidden_size = spec.hiddenSize;
              num_heads = spec.numHeads;
            };
            packages = {
              compare = "${spec.key}-all-memory-vs-top4-memory-compare";
              all_memory_utilization =
                "${spec.key}-selftest-all-memory-utilization";
              top4_memory_utilization =
                "${spec.key}-selftest-top4-memory-utilization";
            };
          }) representativeCoreSweepSpecs));

        representativeCoreSweepSummaryManifest = pkgs.writeText
          "tiny-stories-1m-representative-core-sweep-summary-manifest.json"
          (builtins.toJSON (map (spec:
            let artifacts = builtins.getAttr spec.key representativeCoreSweepArtifacts;
            in {
              inherit (spec) key label;
              config = {
                vocab_size = spec.vocabSize;
                num_layers = spec.numLayers;
                max_position_embeddings = spec.maxPositionEmbeddings;
                window_size = spec.windowSize;
                hidden_size = spec.hiddenSize;
                num_heads = spec.numHeads;
              };
              compare_dir = "${artifacts.allVsTop4.compare}";
            }) representativeCoreSweepSpecs));

        representativeCoreSweepSummary = mkRepresentativeCoreSweepSummary {
          name = "tiny-stories-1m-representative-core-sweep-all-memory-vs-top4-memory";
          manifestJson = representativeCoreSweepSummaryManifest;
        };
        representativeCoreAdditionalSweepArtifacts = pkgs.lib.filterAttrs
          (key: _: key != representativeCoreDefaultKey)
          representativeCoreSweepArtifacts;
        representativeCoreSweepPackages = pkgs.lib.concatMapAttrs
          (key: artifacts: {
            "${key}-selftest-all-memory-top" = artifacts.allMemory.top;
            "${key}-selftest-all-memory-model-opt-il" =
              artifacts.allMemory.modelOptIl;
            "${key}-selftest-all-memory-model-shell-il" =
              artifacts.allMemory.modelShellIl;
            "${key}-selftest-all-memory-external-memory-plan" =
              artifacts.allMemory.externalMemoryPlan;
            "${key}-selftest-all-memory-json" = artifacts.allMemory.json;
            "${key}-selftest-all-memory-yosys-json" =
              artifacts.allMemory.yosysJson;
            "${key}-selftest-all-memory-utilization" =
              artifacts.allMemory.utilizationReport;
            "${key}-selftest-all-memory-stage-stats" =
              artifacts.allMemory.rtlilStageStats.bundle;
            "${key}-selftest-top4-memory-top" = artifacts.top4Memory.top;
            "${key}-selftest-top4-memory-model-opt-il" =
              artifacts.top4Memory.modelOptIl;
            "${key}-selftest-top4-memory-model-shell-il" =
              artifacts.top4Memory.modelShellIl;
            "${key}-selftest-top4-memory-external-memory-plan" =
              artifacts.top4Memory.externalMemoryPlan;
            "${key}-selftest-top4-memory-json" = artifacts.top4Memory.json;
            "${key}-selftest-top4-memory-yosys-json" =
              artifacts.top4Memory.yosysJson;
            "${key}-selftest-top4-memory-utilization" =
              artifacts.top4Memory.utilizationReport;
            "${key}-selftest-top4-memory-stage-stats" =
              artifacts.top4Memory.rtlilStageStats.bundle;
            "${key}-selftest-top4-memory-stage6a-stats" =
              artifacts.top4Memory.rtlilStageStats.reports.stage6a;
            "${key}-all-memory-vs-top4-memory-stage-stats" =
              artifacts.allVsTop4.stageStatsCompare;
            "${key}-all-memory-vs-top4-memory-utilization" =
              artifacts.allVsTop4.utilizationCompare;
            "${key}-all-memory-vs-top4-memory-compare" =
              artifacts.allVsTop4.compare;
          }) representativeCoreAdditionalSweepArtifacts;

        mkXdc = { name, includeBoardXdc ? true, extraConstraints ? [ ] }:
          let
            constraintFiles = (if includeBoardXdc then [ boardXdc ] else [ ])
              ++ extraConstraints;
          in pkgs.runCommand "${name}.xdc" { inherit constraintFiles; } ''
            cat $constraintFiles > "$out"
          '';

        mkFasm = { name, xdc, json, freqMHz ? null, seed ? null }:
          let
            outputArgs =
              if freqMHz == null then "--fasm \"$out\""
              else "--freq ${toString freqMHz} --fasm \"$out\"";
            seedArg =
              pkgs.lib.optionalString (seed != null) "--seed ${toString seed} ";
          in
          pkgs.runCommand "${name}.fasm" { } ''
            if [ ! -f "${fpgaChipdb}" ]; then
              echo "chipdb file missing: ${fpgaChipdb}" >&2
              exit 1
            fi

            ${openXC7Nextpnr}/bin/nextpnr-xilinx \
              --chipdb "${fpgaChipdb}" \
              --xdc ${xdc} \
              --json ${json} \
              ${seedArg}${outputArgs}
          '';

        mkBitstream = { name, fasm, framesBase }:
          pkgs.runCommand "${name}.bit" {
            nativeBuildInputs =
              [ openXC7Fasm openXC7Prjxray prjxrayPythonDeps ];
          } ''
            set -euo pipefail
            export PYTHONPATH="${prjxrayPythonPath}''${PYTHONPATH:+:$PYTHONPATH}"
            export PRJXRAY_PYTHON_DIR="${openXC7Prjxray}/usr/share/python3"
            export PRJXRAY_DB_DIR="${fpgaPrjxrayFamilyDb}"
            tmpdir="$(mktemp -d)"
            frames="$tmpdir/${framesBase}.frm"
            fasm2frames \
              --db-root "${fpgaPrjxrayFamilyDb}" \
              --part ${fpgaPartName} \
              ${fasm} "$frames"
            xc7frames2bit \
              --part_file "${fpgaPartFile}" \
              --frm_file "$frames" \
              --output_file "$out"
          '';

        matmulSelftestTop = ./fpga/rtl/matmul_selftest_top.sv;
        matmulSelftestJson = mkSynthJson {
          name = "matmul-selftest";
          svFilelist = "${matmulSv}/sources.f";
          topName = "matmul_selftest_top";
          topSv = matmulSelftestTop;
        };
        matmulSelftestXdc = mkXdc {
          name = "matmul-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };
        matmulSelftestFasm = mkFasm {
          name = "matmul-selftest";
          xdc = matmulSelftestXdc;
          json = matmulSelftestJson;
        };
        matmulSelftestBitstream = mkBitstream {
          name = "matmul-selftest";
          fasm = matmulSelftestFasm;
          framesBase = "matmul-selftest";
        };

        task6LedMapJson =
          pkgs.runCommand "task6-led-map.json" { buildInputs = [ pkgs.yosys ]; } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./fpga/rtl/task6_led_map_top.sv}
            hierarchy -top task6_led_map_top -check
            proc
            synth_xilinx -family xc7 -top task6_led_map_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6LedMapXdc = mkXdc {
          name = "task6-led-map";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6LedMapFasm = mkFasm {
          name = "task6-led-map";
          xdc = task6LedMapXdc;
          json = task6LedMapJson;
        };

        task6LedMapBitstream = mkBitstream {
          name = "task6-led-map";
          fasm = task6LedMapFasm;
          framesBase = "task6-led-map";
        };

        task6TernipSrc = pkgs.fetchFromGitHub {
          owner = "sifferman";
          repo = "ternip";
          rev = "7573c17dbed8f01e7d9e07e59a863376426a5489";
          hash = "sha256-ERtufGKw75r22GcBKNpPcpXRU+qW+S2L25jRwwwWWpE=";
        };

        task6TernipBasejumpStlSrc = pkgs.fetchFromGitHub {
          owner = "bespoke-silicon-group";
          repo = "basejump_stl";
          rev = "a43571d2eaaae2dda7c10490e8350dfdac7da878";
          hash = "sha256-7/u2qBhd4qNwQI/KUe+Ka+i6cz2/ZJkphBXjRKduf+4=";
        };

        task6TernipReducedConfig = pkgs.writeText "ternip-reduced-ypcb.svh" ''
          localparam int D = 64;
          localparam int TmatmulParallelism = 8;
          localparam int VectorParallelism = 4;
          localparam int LutParallelism = 1;

          localparam int FixedPointPrecision = 8;
          localparam int FixedPointExponent = -3;

          parameter mul_impl_e MultiplicationImplementation = MUL_BSG;
          parameter div_impl_e DivisionImplementation = DIV_BSG;

          localparam bit UseHardSigmoid = 1;

          localparam int BatchSize = 1;

          localparam int NumVectorRegisters = 8;
          localparam int ImmediateWidth = 16;
          localparam int DdrAddressWidth = 64;
          localparam int InstructionWidth = 128;

          localparam int DdrDataWidth = 128;
          localparam int InstrFetchWidth = 128;
          localparam int CoreInterconnectNumStages = 4;

          localparam real DramMaxBytesPerSecond = 10.0**12;
          localparam real ClockPeriod = 10.0 * 10.0**-9;
        '';

        task6TernipUpstreamRepro =
          pkgs.runCommand "task6-ternip-upstream-repro" { } ''
            set -euo pipefail
            mkdir -p "$out"
            ln -s ${task6TernipSrc} "$out/ternip-src"
            ln -s ${task6TernipBasejumpStlSrc} "$out/basejump-stl-src"
            cp ${task6TernipSrc}/README.md "$out/ternip-README.md"
            cp ${task6TernipSrc}/LICENSE "$out/ternip-LICENSE"
            cat > "$out/summary.json" <<'EOF'
            {
              "artifact_name": "task6-ternip-upstream-repro",
              "status": "SOURCE_PINNED",
              "ternip": {
                "repository": "https://github.com/sifferman/ternip",
                "commit": "7573c17dbed8f01e7d9e07e59a863376426a5489",
                "license": "BSD-3-Clause",
                "nix_hash": "sha256-ERtufGKw75r22GcBKNpPcpXRU+qW+S2L25jRwwwWWpE="
              },
              "basejump_stl": {
                "repository": "https://github.com/bespoke-silicon-group/basejump_stl",
                "commit": "a43571d2eaaae2dda7c10490e8350dfdac7da878",
                "nix_hash": "sha256-7/u2qBhd4qNwQI/KUe+Ka+i6cz2/ZJkphBXjRKduf+4="
              },
              "decision": {
                "next_gate": "Build .#task6-ternip-reduced-elab-json before creating a YPCB wrapper or bitstream.",
                "board_default": "Board A",
                "board_b_status": "Blocked until non-DDR LED-map reports INIT=1 and DONE=1."
              }
            }
            EOF
            cat > "$out/summary.md" <<'EOF'
            # Task 6 Ternip upstream reproduction gate

            Status: SOURCE_PINNED

            Ternip is pinned to `sifferman/ternip` commit
            `7573c17dbed8f01e7d9e07e59a863376426a5489`.

            BaseJump STL is pinned to `bespoke-silicon-group/basejump_stl`
            commit `a43571d2eaaae2dda7c10490e8350dfdac7da878`.

            Ternip is BSD-3-Clause. This gate records source provenance only;
            the next gate is reduced open-source elaboration.
            EOF
          '';

        task6TernipReducedElabJson =
          pkgs.runCommand "task6-ternip-reduced-elab.json" {
            buildInputs = [ yosysPkg ];
          } ''
            set -euo pipefail
            cp -r ${task6TernipSrc} ternip
            chmod -R u+w ternip
            mkdir -p ternip/config
            cp ${task6TernipReducedConfig} ternip/config/reduced_ypcb.svh
            substituteInPlace ternip/rtl/ternip_pkg.sv \
              --replace '`include `CONFIG_FILENAME' '`include "config/reduced_ypcb.svh"'
            find ${task6TernipBasejumpStlSrc}/bsg_dataflow \
              ${task6TernipBasejumpStlSrc}/bsg_misc \
              -name '*.sv' | sort > basejump-files.txt
            cat > ternip-files.txt <<'EOF'
            ternip/rtl/ternip_pkg.sv
            ternip/rtl/ternip_vector_registers.sv
            ternip/rtl/common/ternip_gearbox_fifo.sv
            ternip/rtl/common/ternip_multioperand_accumulator.sv
            ternip/rtl/common/ternip_pipelined_interconnect.sv
            ternip/rtl/common/ternip_pipelined_mem.sv
            ternip/rtl/math/ternip_add.sv
            ternip/rtl/math/ternip_sub.sv
            ternip/rtl/math/ternip_mul.sv
            ternip/rtl/math/ternip_div.sv
            ternip/rtl/math/ternip_sqrt_int.sv
            ternip/rtl/math/ternip_sqrt.sv
            ternip/rtl/math/ternip_starmul.sv
            ternip/rtl/math/ternip_fixed_point_convert.sv
            ternip/rtl/math/ternip_round_robin_operation.sv
            ternip/rtl/math/ternip_csig.sv
            ternip/rtl/math/ternip_csig_parallelized.sv
            ternip/rtl/math/ternip_sig.sv
            ternip/rtl/math/ternip_sig_parallelized.sv
            ternip/rtl/math/ternip_silu.sv
            ternip/rtl/math/ternip_silu_parallelized.sv
            ternip/rtl/fus/ternip_loadstore.sv
            ternip/rtl/fus/ternip_rms.sv
            ternip/rtl/fus/ternip_rowwise_operation.sv
            ternip/rtl/fus/ternip_tmatmul.sv
            ternip/rtl/axi/s_axi_ternip_const_rd.v
            ternip/rtl/axi/s_axi_ternip_rst.v
            ternip/rtl/axi/s_axi_ternip_wait_for_interrupt.v
            ternip/rtl/axi/s_axi_ternip_write_byte.v
            ternip/rtl/ternip/ternip_core.sv
            EOF
            tr '\n' ' ' < basejump-files.txt > all-files.txt
            printf ' ' >> all-files.txt
            tr '\n' ' ' < ternip-files.txt >> all-files.txt
            cat > run.ys <<EOF
            plugin -i ${yosysSlang}/share/yosys/plugins/slang.so
            read_slang --threads 1 --no-proc --top ternip_core -Iternip -Iternip/rtl $(cat all-files.txt)
            hierarchy -top ternip_core -check
            write_json "$out"
            EOF
            ${yosysPkg}/bin/yosys -s run.ys
          '';

        task6TernipReducedVerilatorLintReport =
          pkgs.runCommand "task6-ternip-reduced-verilator-lint-report" {
            buildInputs = [ pkgs.verilator ];
          } ''
            set -euo pipefail
            cp -r ${task6TernipSrc} ternip
            chmod -R u+w ternip
            mkdir -p ternip/config "$out"
            cp ${task6TernipReducedConfig} ternip/config/reduced_ypcb.svh
            substituteInPlace ternip/rtl/ternip_pkg.sv \
              --replace '`include `CONFIG_FILENAME' '`include "config/reduced_ypcb.svh"'
            find ${task6TernipBasejumpStlSrc}/bsg_dataflow \
              ${task6TernipBasejumpStlSrc}/bsg_misc \
              -name '*.sv' | sort > basejump-files.txt
            cat > ternip-files.txt <<'EOF'
            ternip/rtl/ternip_pkg.sv
            ternip/rtl/ternip_vector_registers.sv
            ternip/rtl/common/ternip_gearbox_fifo.sv
            ternip/rtl/common/ternip_multioperand_accumulator.sv
            ternip/rtl/common/ternip_pipelined_interconnect.sv
            ternip/rtl/common/ternip_pipelined_mem.sv
            ternip/rtl/math/ternip_add.sv
            ternip/rtl/math/ternip_sub.sv
            ternip/rtl/math/ternip_mul.sv
            ternip/rtl/math/ternip_div.sv
            ternip/rtl/math/ternip_sqrt_int.sv
            ternip/rtl/math/ternip_sqrt.sv
            ternip/rtl/math/ternip_starmul.sv
            ternip/rtl/math/ternip_fixed_point_convert.sv
            ternip/rtl/math/ternip_round_robin_operation.sv
            ternip/rtl/math/ternip_csig.sv
            ternip/rtl/math/ternip_csig_parallelized.sv
            ternip/rtl/math/ternip_sig.sv
            ternip/rtl/math/ternip_sig_parallelized.sv
            ternip/rtl/math/ternip_silu.sv
            ternip/rtl/math/ternip_silu_parallelized.sv
            ternip/rtl/fus/ternip_loadstore.sv
            ternip/rtl/fus/ternip_rms.sv
            ternip/rtl/fus/ternip_rowwise_operation.sv
            ternip/rtl/fus/ternip_tmatmul.sv
            ternip/rtl/axi/s_axi_ternip_const_rd.v
            ternip/rtl/axi/s_axi_ternip_rst.v
            ternip/rtl/axi/s_axi_ternip_wait_for_interrupt.v
            ternip/rtl/axi/s_axi_ternip_write_byte.v
            ternip/rtl/ternip/ternip_core.sv
            EOF
            tr '\n' ' ' < basejump-files.txt > all-files.txt
            printf ' ' >> all-files.txt
            tr '\n' ' ' < ternip-files.txt >> all-files.txt
            set +e
            verilator --lint-only --sv --top-module ternip_core \
              -Iternip -Iternip/rtl \
              -Wno-fatal -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY \
              $(cat all-files.txt) > "$out/lint.log" 2>&1
            rc=$?
            set -e
            status=PASS
            if [ "$rc" -ne 0 ]; then
              status=FAIL
            fi
            cat > "$out/summary.json" <<EOF
            {
              "artifact_name": "task6-ternip-reduced-verilator-lint-report",
              "status": "$status",
              "verilator_exit_code": $rc,
              "reduced_config": {
                "D": 64,
                "TmatmulParallelism": 8,
                "VectorParallelism": 4,
                "BatchSize": 1,
                "FixedPointPrecision": 8
              },
              "next_gate": "If PASS, repair the Yosys/yosys-slang synthesis gate; if FAIL, fix the first RTL lint blocker."
            }
            EOF
          '';

        tinyStories1mSelftestAllMemory = mkTinyStoriesSelftestBundle {
          name = "tiny-stories-1m-selftest-all-memory";
          topName = "tiny_stories_selftest_top";
          mainSv = "${tinyStories1mPipeline.sv}/sv/main.sv";
          modelIl = tinyStories1mIl;
          capacities = tinyStoriesCapacities;
          externalMemoryMinModuleBits = 1;
        };
        tinyStories1mBaselineFloatSelftestAllMemory =
          mkTinyStoriesSelftestBundle {
            name = "tiny-stories-1m-baseline-float-selftest-all-memory";
            topName = "tiny_stories_selftest_top";
            mainSv = "${tinyStories1mBaselineFloatPipeline.sv}/sv/main.sv";
            modelIl = tinyStories1mBaselineFloatIl;
            capacities = tinyStoriesCapacities;
            externalMemoryMinModuleBits = 1;
          };
        tinyStories1mBaselineFloatSelftestTop4Memory =
          mkTinyStoriesSelftestBundle {
            name = "tiny-stories-1m-baseline-float-selftest-top4-memory";
            topName = "tiny_stories_selftest_top";
            mainSv = "${tinyStories1mBaselineFloatPipeline.sv}/sv/main.sv";
            modelIl = tinyStories1mBaselineFloatIl;
            capacities = tinyStoriesCapacities;
            externalMemoryMinModuleBits = 1;
            externalMemoryMaxModules = 4;
          };
        tinyStories1mBaselineFloatSelftestTop32Memory =
          mkTinyStoriesSelftestBundle {
            name = "tiny-stories-1m-baseline-float-selftest-top32-memory";
            topName = "tiny_stories_selftest_top";
            mainSv = "${tinyStories1mBaselineFloatPipeline.sv}/sv/main.sv";
            modelIl = tinyStories1mBaselineFloatIl;
            capacities = tinyStoriesCapacities;
            externalMemoryMinModuleBits = 1;
            externalMemoryMaxModules = 32;
          };
        tinyStories1mBaselineFloatSelftestTop34Memory =
          mkTinyStoriesSelftestBundle {
            name = "tiny-stories-1m-baseline-float-selftest-top34-memory";
            topName = "tiny_stories_selftest_top";
            mainSv = "${tinyStories1mBaselineFloatPipeline.sv}/sv/main.sv";
            modelIl = tinyStories1mBaselineFloatIl;
            capacities = tinyStoriesCapacities;
            externalMemoryMinModuleBits = 1;
            externalMemoryMaxModules = 34;
          };
        tinyStories1mRepresentativeCoreArtifacts =
          builtins.getAttr representativeCoreDefaultKey
          representativeCoreSweepArtifacts;
        tinyStories1mRepresentativeCoreSelftestAllMemory =
          tinyStories1mRepresentativeCoreArtifacts.allMemory;
        tinyStories1mRepresentativeCoreSelftestTop4Memory =
          tinyStories1mRepresentativeCoreArtifacts.top4Memory;
        tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9 =
          mkTinyStoriesSelftestBundle {
            name =
              "tiny-stories-1m-representative-core-selftest-top4-memory-abc9";
            topName = "tiny_stories_selftest_top";
            mainSv = "${tinyStories1mRepresentativeCorePipeline.sv}/sv/main.sv";
            modelIl = tinyStories1mRepresentativeCoreIl;
            capacities = tinyStoriesCapacities;
            externalMemoryMinModuleBits = 1;
            externalMemoryMaxModules = 4;
            useAbc9 = true;
          };
        tinyStories1mRepresentativeCoreVsBaselineFloatTop4MemoryStageStats =
          mkStageStatComparison {
            name =
              "tiny-stories-1m-representative-core-vs-baseline-float-top4-memory";
            baselineDir =
              tinyStories1mBaselineFloatSelftestTop4Memory.rtlilStageStats.bundle;
            candidateDir =
              tinyStories1mRepresentativeCoreSelftestTop4Memory.rtlilStageStats.bundle;
            baselineLabel = "tiny-stories-1m-baseline-float-selftest-top4-memory";
            candidateLabel =
              "tiny-stories-1m-representative-core-selftest-top4-memory";
          };
        tinyStories1mRepresentativeCoreAllMemoryVsTop4MemoryStageStats =
          tinyStories1mRepresentativeCoreArtifacts.allVsTop4.stageStatsCompare;
        tinyStories1mRepresentativeCoreAllMemoryVsTop4MemoryUtilization =
          tinyStories1mRepresentativeCoreArtifacts.allVsTop4.utilizationCompare;
        tinyStories1mRepresentativeCoreAllMemoryVsTop4MemoryComparison =
          tinyStories1mRepresentativeCoreArtifacts.allVsTop4.compare;
        tinyStories1mBaselineFloatVsRepresentativeCoreTorchOpCoverage =
          mkMlirOpStatsComparison {
            name =
              "tiny-stories-1m-baseline-float-vs-representative-core-torch";
            baselineInput = tinyStories1mBaselineFloatPipeline.torch;
            baselineStats = tinyStories1mBaselineFloatPipeline."torch-stats";
            candidateInput = tinyStories1mRepresentativeCorePipeline.torch;
            candidateStats =
              tinyStories1mRepresentativeCorePipeline."torch-stats";
            baselineLabel = "tiny-stories-1m-baseline-float-torch";
            candidateLabel = "tiny-stories-1m-representative-core-torch";
          };
        tinyStories1mBaselineFloatVsRepresentativeCoreCfOpCoverage =
          mkMlirOpStatsComparison {
            name = "tiny-stories-1m-baseline-float-vs-representative-core-cf";
            baselineInput = tinyStories1mBaselineFloatPipeline.cf;
            baselineStats = tinyStories1mBaselineFloatPipeline."cf-stats";
            candidateInput = tinyStories1mRepresentativeCorePipeline.cf;
            candidateStats = tinyStories1mRepresentativeCorePipeline."cf-stats";
            baselineLabel = "tiny-stories-1m-baseline-float-cf";
            candidateLabel = "tiny-stories-1m-representative-core-cf";
          };
        tinyStories1mBaselineFloatVsRepresentativeCoreMlirOpCoverage =
          mkMlirOpCoverageBundle {
            name = "tiny-stories-1m-baseline-float-vs-representative-core";
            baselineLabel = "tiny-stories-1m-baseline-float";
            candidateLabel = "tiny-stories-1m-representative-core";
            torchCoverage =
              tinyStories1mBaselineFloatVsRepresentativeCoreTorchOpCoverage;
            cfCoverage = tinyStories1mBaselineFloatVsRepresentativeCoreCfOpCoverage;
          };

        tbDataSv = pkgs.runCommand "tb-data-sv" { } ''
          mkdir -p "$out"
          MATMUL_PY=${./src/matmul.py} \
          ${pythonWithTorch}/bin/python ${
            ./sim
          }/gen_tb_data.py > "$out/tb_data.sv"
        '';

        task6L0Gemv64TbDataSv = pkgs.runCommand "task6-l0-gemv64-tb-data-sv" { } ''
          mkdir -p "$out"
          export GEMV64_PY=${./src/gemv64.py}
          export PYTHONPATH="${./src}:${./sim}:''${PYTHONPATH:-}"
          ${pythonWithTorch}/bin/python ${
            ./sim
          }/gen_task6_l0_gemv64_tb_data.py > "$out/tb_data.sv"
        '';

        task6L1CFcRedirectTbDataSv = pkgs.runCommand "task6-l1-c-fc-redirect-tb-data-sv" { } ''
          mkdir -p "$out"
          ${pythonWithTorch}/bin/python ${
            ./sim
          }/gen_task6_contract_gemv_tb_data.py \
            --contract-manifest ${
              ./artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_fc-contract
            }/manifest.json \
            --weight-pack-manifest ${
              ./artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_fc
            }/manifest.json > "$out/tb_data.sv"
        '';

        task6L1CProjRedirectTbDataSv = pkgs.runCommand "task6-l1-c-proj-redirect-tb-data-sv" { } ''
          mkdir -p "$out"
          ${pythonWithTorch}/bin/python ${
            ./sim
          }/gen_task6_contract_gemv_tb_data.py \
            --contract-manifest ${
              ./artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract
            }/manifest.json \
            --weight-pack-manifest ${
              ./artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj
            }/manifest.json > "$out/tb_data.sv"
        '';

        task6L2CFcRedirectTbDataSv = pkgs.runCommand "task6-l2-c-fc-redirect-tb-data-sv" { } ''
          mkdir -p "$out"
          ${pythonWithTorch}/bin/python ${
            ./sim
          }/gen_task6_contract_gemv_tb_data.py \
            --contract-manifest ${
              ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
            }/manifest.json \
            --weight-pack-manifest ${
              ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
            }/manifest.json > "$out/tb_data.sv"
        '';

        task6Int8L2CFcContractLocalIoTbDataSv =
          pkgs.runCommand "task6-int8-l2-c-fc-contract-local-io-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_c_fc_contract_tb_data.py \
              --contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --out-sv "$out/tb_data.sv" \
              --out-json "$out/summary.json"
          '';

        task6Int8L2CFcScaleBiasOutputBoundary =
          pkgs.runCommand "task6-int8-l2-c-fc-scale-bias-output-boundary" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/score_int8_output_boundary.py \
              --contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --contract-replay-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json
              } \
              --out-json "$out/summary.json"
          '';

        task6Int8L2CFcDownstreamInt8Boundary =
          pkgs.runCommand "task6-int8-l2-c-fc-downstream-int8-boundary" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/score_int8_downstream_boundary.py \
              --contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --contract-replay-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-local-io-contract-replay.json
              } \
              --out-json "$out/summary.json"
          '';

        task6Int8L2CProjFromPostGeluBoundary =
          pkgs.runCommand "task6-int8-l2-c-proj-from-post-gelu-boundary" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/score_int8_c_proj_from_post_gelu.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --out-json "$out/summary.json"
          '';

        task6Int8L2CProjOutputBoundary =
          pkgs.runCommand "task6-int8-l2-c-proj-output-boundary" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/score_int8_c_proj_output_boundary.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --mlp-chain-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof.json
              } \
              --c-proj-candidate-json ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json
              } \
              --out-json "$out/summary.json"
          '';

        task6Int8L2CProjFromPostGeluTbDataSv =
          pkgs.runCommand "task6-int8-l2-c-proj-from-post-gelu-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_c_proj_from_post_gelu_tb_data.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --out-sv "$out/tb_data.sv" \
              --out-json "$out/summary.json"
          '';

        task6Int8L2MlpChainPostGeluCProjTbDataSv =
          pkgs.runCommand "task6-int8-l2-mlp-chain-post-gelu-c-proj-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_mlp_chain_post_gelu_c_proj_tb_data.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --out-sv "$out/tb_data.sv" \
              --out-json "$out/summary.json"
          '';

        task6Int8L2MlpChainCProjRequantTbDataSv =
          pkgs.runCommand "task6-int8-l2-mlp-chain-c-proj-requant-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_mlp_chain_c_proj_requant_tb_data.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-output-boundary.json
              } \
              --out-sv "$out/tb_data.sv" \
              --out-json "$out/summary.json"
          '';

        task6Int8L2MlpChainResidualAddTbDataSv =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_mlp_chain_residual_add_tb_data.py \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --out-sv "$out/tb_data.sv" \
              --out-json "$out/summary.json"
          '';

        task6Int8L2MlpChainResidualAddSelftestTop =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-top.sv" { } ''
            sed 's|"tb_data.sv"|"${task6Int8L2MlpChainResidualAddTbDataSv}/tb_data.sv"|g' \
              ${./fpga/rtl/task6_int8_l2_mlp_chain_residual_add_selftest_top.sv} \
              > "$out"
          '';

        task6Int8V4kL2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-int8-v4k-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 4096 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v4k-h64-l1 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6Int8V4kL2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-int8-v4k-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6Int8V4kL2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6Int8V4kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6Int8V4kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6Int8V10kL2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-int8-v10k-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --artifact-name h2-v10k-int8-l2-residual-add-output-head-selftest \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 10000 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v10k-h64-l1 \
              --tile-out-dim 80 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6Int8V10kL2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-int8-v10k-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6Int8V10kL2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6Int8V10kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6Int8V10kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --artifact-name h2-v10k-ternary-base3-20-l2-residual-add-output-head-selftest \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 10000 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v10k-h64-l1 \
              --tile-out-dim 80 \
              --weight-quantization ternary-base3-20 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6OutputHeadV10kQuantizationSweep =
          pkgs.runCommand "task6-output-head-v10k-quantization-sweep" { } ''
            mkdir -p "$out"
            TASK6_REPO_ROOT=${./.} ${pythonWithTinyStoriesBin}/bin/python ${
              ./scripts/task6/score_output_head_quantization.py
            } \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 10000 \
              --physical-vocab-size 10000 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v10k-h64-l1 \
              --out-json "$out/output-head-v10k-sweep.json" \
              --out-md "$out/output-head-v10k-sweep.md"
          '';

        task6OutputHeadV10kMultisampleQuantizationSweep =
          pkgs.runCommand "task6-output-head-v10k-multisample-quantization-sweep" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./scripts/task6/score_output_head_multisample_quantization.py
            } \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --vocab-size 10000 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v10k-h64-l1 \
              --sample-count 8 \
              --out-json "$out/output-head-v10k-multisample-sweep.json" \
              --out-md "$out/output-head-v10k-multisample-sweep.md"
          '';

        task6OutputHeadFullPretrainedMultisampleQuantizationSweep =
          pkgs.runCommand "task6-output-head-full-pretrained-multisample-quantization-sweep" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./scripts/task6/score_output_head_multisample_quantization.py
            } \
              --load-pretrained \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --vocab-size 50257 \
              --model-label tiny-stories-1m-pretrained-full \
              --sample-count 8 \
              --out-json "$out/output-head-full-pretrained-multisample-sweep.json" \
              --out-md "$out/output-head-full-pretrained-multisample-sweep.md"
          '';

        task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6Int8V6kL2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-int8-v6k-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --artifact-name e1-v6k-int8-l2-residual-add-output-head-selftest \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 6144 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v6k-h64-l1 \
              --tile-out-dim 64 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6Int8V6kL2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-int8-v6k-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6Int8V6kL2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6Int8V6kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6Int8V6kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6Int8V8kL2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-int8-v8k-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --artifact-name e1-v8k-int8-l2-residual-add-output-head-selftest \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 8192 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v8k-h64-l1 \
              --tile-out-dim 64 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6Int8V8kL2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-int8-v8k-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6Int8V8kL2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6Int8V8kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6Int8V8kL2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6Int8V9984L2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-int8-v9984-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --artifact-name e1-v9984-int8-l2-residual-add-output-head-selftest \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 9984 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v9984-h64-l1 \
              --tile-out-dim 64 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6Int8V9984L2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-int8-v9984-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6Int8V9984L2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6Int8V9984L2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6Int8V9984L2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6TernaryV9984L2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-ternary-v9984-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --artifact-name e1-v9984-ternary2-l2-residual-add-output-head-selftest \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 9984 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v9984-h64-l1 \
              --tile-out-dim 64 \
              --weight-quantization ternary2 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6TernaryV9984L2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-ternary-v9984-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6TernaryV9984L2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6TernaryV9984L2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6TernaryV9984L2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTbDataSv =
          pkgs.runCommand "task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./sim
            }/gen_task6_int8_v4k_l2_residual_add_output_head_selftest_tb_data.py \
              --artifact-name e1-v10k-padded-tile64-int8-l2-residual-add-output-head-selftest \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v4k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v4k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --residual-add-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-v4k-int8-l2-mlp-chain-residual-add-rtl-proof.json
              } \
              --vocab-size 10000 \
              --physical-vocab-size 10048 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --model-label tiny-stories-v10k-padded10048-h64-l1 \
              --tile-out-dim 64 \
              --out-sv "$out/tb_data.sv" \
              --out-vocab-mem "$out/vocab_packed_weights.mem" \
              --out-json "$out/summary.json"
          '';

        task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTop =
          pkgs.runCommand "task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-top.sv" { } ''
            sed \
              -e 's|"tb_data.sv"|"${task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTbDataSv}/tb_data.sv"|g' \
              -e 's|"vocab_packed_weights.mem"|"${task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTbDataSv}/vocab_packed_weights.mem"|g' \
              -e 's|"vocab_loader_phase_readmemh_cases.sv"|"${task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTbDataSv}/vocab_loader_phase_readmemh_cases.sv"|g' \
              ${./fpga/rtl/task6_int8_v4k_l2_residual_add_output_head_selftest_top.sv} \
              > "$out"
          '';

        task6FullVocabRowwiseTopkReplay =
          pkgs.runCommand "h2-full-vocab-rowwise-topk-replay.json" { } ''
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./scripts/task6
            }/check_full_vocab_rowwise_topk_contract.py \
              --model-path ${tinyStories1m.snapshot} \
              --adapter-path ${./TinyStories/model_adapter.py} \
              --date 2026-04-30 \
              --out "$out"
          '';

        task6Ddr3RowStreamInterfaceContract =
          pkgs.runCommand "h2-ddr3-row-stream-interface-contract.json" { } ''
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/write_ddr3_row_stream_interface_contract.py \
              --replay-json ${
                ./artifacts/task6/parallel-hypotheses/h2-full-vocab-rowwise-topk-replay.json
              } \
              --replay-artifact-label artifacts/task6/parallel-hypotheses/h2-full-vocab-rowwise-topk-replay.json \
              --date 2026-04-30 \
              --out "$out"
          '';

        task6Ddr3RowStreamPackReplay =
          pkgs.runCommand "h2-ddr3-row-stream-pack-replay" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./scripts/task6
            }/pack_ddr3_row_stream_image.py \
              --model-path ${tinyStories1m.snapshot} \
              --model-artifact-label tiny-stories-1m-snapshot \
              --adapter-path ${./TinyStories/model_adapter.py} \
              --adapter-artifact-label TinyStories/model_adapter.py \
              --contract-json ${
                ./artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-interface-contract.json
              } \
              --replay-json ${
                ./artifacts/task6/parallel-hypotheses/h2-full-vocab-rowwise-topk-replay.json
              } \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6Ddr3RowStreamCutoutTbData =
          pkgs.runCommand "task6-ddr3-row-stream-cutout-tb-data" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./scripts/task6
            }/gen_ddr3_rowstream_cutout_tb_data.py \
              --model-path ${tinyStories1m.snapshot} \
              --model-artifact-label tiny-stories-1m-snapshot \
              --adapter-path ${./TinyStories/model_adapter.py} \
              --adapter-artifact-label TinyStories/model_adapter.py \
              --contract-json ${
                ./artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-interface-contract.json
              } \
              --contract-artifact-label artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-interface-contract.json \
              --replay-json ${
                ./artifacts/task6/parallel-hypotheses/h2-full-vocab-rowwise-topk-replay.json
              } \
              --replay-artifact-label artifacts/task6/parallel-hypotheses/h2-full-vocab-rowwise-topk-replay.json \
              --rowstream-bin ${
                ./artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-pack-replay/rowstream.bin
              } \
              --rowstream-artifact-label artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-pack-replay/rowstream.bin \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6Ddr3BoardSupportInventory =
          pkgs.runCommand "h2-ddr3-board-support-inventory.json" { } ''
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/summarize_ypcb_ddr3_board_support.py \
              --mig-prj ${ypcbHack}/ypcb003381p1/1.0/mig_0.prj \
              --mig-prj-artifact-label ypcbHack/ypcb003381p1/1.0/mig_0.prj \
              --memory-ch0-ucf ${ypcbHack}/constraints/MEMORY_CH0.ucf \
              --memory-ch0-ucf-artifact-label ypcbHack/constraints/MEMORY_CH0.ucf \
              --board-xml ${ypcbHack}/ypcb003381p1/1.0/board.xml \
              --board-xml-artifact-label ypcbHack/ypcb003381p1/1.0/board.xml \
              --date 2026-04-30 \
              --out "$out"
          '';

        task6YpcbDdr3LaneReport =
          pkgs.runCommand "h2-ypcb-ddr3-lane-report" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/write_ypcb_ddr3_lane_report.py \
              --memory-ch0-ucf ${ypcbHack}/constraints/MEMORY_CH0.ucf \
              --memory-ch0-ucf-artifact-label ypcbHack/constraints/MEMORY_CH0.ucf \
              --package-pins-csv ${
                openXC7Nextpnr
              }/share/nextpnr/external/prjxray-db/${fpgaPartFamily}/${fpgaPartName}/package_pins.csv \
              --package-pins-csv-artifact-label openXC7/prjxray-db/${fpgaPartFamily}/${fpgaPartName}/package_pins.csv \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6LiteDramOpenControllerProbe =
          pkgs.runCommand "h2-litedram-open-controller-probe.json" { } ''
            ${liteDramPython}/bin/python ${
              ./scripts/task6
            }/check_litedram_open_controller_path.py \
              --memory-ch0-ucf ${ypcbHack}/constraints/MEMORY_CH0.ucf \
              --memory-ch0-ucf-artifact-label ypcbHack/constraints/MEMORY_CH0.ucf \
              --part0-pins-xml ${ypcbHack}/ypcb003381p1/1.0/part0_pins.xml \
              --part0-pins-xml-artifact-label ypcbHack/ypcb003381p1/1.0/part0_pins.xml \
              --board-xml ${ypcbHack}/ypcb003381p1/1.0/board.xml \
              --board-xml-artifact-label ypcbHack/ypcb003381p1/1.0/board.xml \
              --memory-part MT41K256M8DA-125 \
              --date 2026-04-30 \
              --out "$out"
          '';

        task6YpcbLiteDramConfig =
          pkgs.runCommand "h2-ypcb-litedram-config" { } ''
            mkdir -p "$out"
            ${liteDramPython}/bin/python ${
              ./scripts/task6
            }/write_ypcb_litedram_config.py \
              --memory-ch0-ucf ${ypcbHack}/constraints/MEMORY_CH0.ucf \
              --memory-ch0-ucf-artifact-label ypcbHack/constraints/MEMORY_CH0.ucf \
              --part0-pins-xml ${ypcbHack}/ypcb003381p1/1.0/part0_pins.xml \
              --part0-pins-xml-artifact-label ypcbHack/ypcb003381p1/1.0/part0_pins.xml \
              --board-xml ${ypcbHack}/ypcb003381p1/1.0/board.xml \
              --board-xml-artifact-label ypcbHack/ypcb003381p1/1.0/board.xml \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6YpcbLiteDramNoOdelayConfig =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-config" { } ''
            mkdir -p "$out"
            ${liteDramPython}/bin/python ${
              ./scripts/task6
            }/write_ypcb_litedram_config.py \
              --memory-ch0-ucf ${ypcbHack}/constraints/MEMORY_CH0.ucf \
              --memory-ch0-ucf-artifact-label ypcbHack/constraints/MEMORY_CH0.ucf \
              --part0-pins-xml ${ypcbHack}/ypcb003381p1/1.0/part0_pins.xml \
              --part0-pins-xml-artifact-label ypcbHack/ypcb003381p1/1.0/part0_pins.xml \
              --board-xml ${ypcbHack}/ypcb003381p1/1.0/board.xml \
              --board-xml-artifact-label ypcbHack/ypcb003381p1/1.0/board.xml \
              --sdram-phy A7DDRPHY \
              --sys-clk-freq 50e6 \
              --artifact-name h2-ypcb-litedram-no-odelay-config \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6YpcbLiteDramNoOdelayLowrateConfig =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-lowrate-config" { } ''
            mkdir -p "$out"
            ${liteDramPython}/bin/python ${
              ./scripts/task6
            }/write_ypcb_litedram_config.py \
              --memory-ch0-ucf ${ypcbHack}/constraints/MEMORY_CH0.ucf \
              --memory-ch0-ucf-artifact-label ypcbHack/constraints/MEMORY_CH0.ucf \
              --part0-pins-xml ${ypcbHack}/ypcb003381p1/1.0/part0_pins.xml \
              --part0-pins-xml-artifact-label ypcbHack/ypcb003381p1/1.0/part0_pins.xml \
              --board-xml ${ypcbHack}/ypcb003381p1/1.0/board.xml \
              --board-xml-artifact-label ypcbHack/ypcb003381p1/1.0/board.xml \
              --sdram-phy A7DDRPHY \
              --sys-clk-freq 25e6 \
              --artifact-name h2-ypcb-litedram-no-odelay-lowrate-config \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6YpcbLiteDramRtlElaboration =
          pkgs.runCommand "h2-ypcb-litedram-rtl-elaboration" { } ''
            mkdir -p "$out"
              export CHIPDB=${litexOpenXC7ChipdbCompat}
            export PRJXRAY_DB_DIR=${fpgaPrjxrayDb}
            ${liteDramPython}/bin/python ${
              ./scripts/task6
            }/generate_ypcb_litedram_core.py \
              --config-yml ${
                task6YpcbLiteDramConfig
              }/ypcb_litedram_64bit_payload.yml \
              --config-summary-json ${task6YpcbLiteDramConfig}/summary.json \
              --name ypcb_litedram_core \
              --device ${fpgaPartName} \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6YpcbLiteDramNoOdelayRtlElaboration =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-rtl-elaboration" { } ''
            mkdir -p "$out"
            export CHIPDB=${openXC7Chipdb}
            export PRJXRAY_DB_DIR=${fpgaPrjxrayDb}
            ${liteDramPython}/bin/python ${
              ./scripts/task6
            }/generate_ypcb_litedram_core.py \
              --config-yml ${
                task6YpcbLiteDramNoOdelayConfig
              }/ypcb_litedram_64bit_payload.yml \
              --config-summary-json ${task6YpcbLiteDramNoOdelayConfig}/summary.json \
              --name ypcb_litedram_core \
              --device ${fpgaPartName} \
              --artifact-name h2-ypcb-litedram-no-odelay-rtl-elaboration \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6YpcbLiteDramNoOdelayLowrateRtlElaboration =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-lowrate-rtl-elaboration" { } ''
            mkdir -p "$out"
            export CHIPDB=${openXC7Chipdb}
            export PRJXRAY_DB_DIR=${fpgaPrjxrayDb}
            ${liteDramPython}/bin/python ${
              ./scripts/task6
            }/generate_ypcb_litedram_core.py \
              --config-yml ${
                task6YpcbLiteDramNoOdelayLowrateConfig
              }/ypcb_litedram_64bit_payload.yml \
              --config-summary-json ${
                task6YpcbLiteDramNoOdelayLowrateConfig
              }/summary.json \
              --name ypcb_litedram_core \
              --device ${fpgaPartName} \
              --artifact-name h2-ypcb-litedram-no-odelay-lowrate-rtl-elaboration \
              --date 2026-04-30 \
              --out-dir "$out"
          '';

        task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-lowrate-dfi-debug-rtl-elaboration" { } ''
            set -euo pipefail
            cp -R ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/. "$out"
            chmod -R u+w "$out"
            ${pkgs.python3}/bin/python3 ${
              ./scripts/task6
            }/patch_litedram_dfi_debug_ports.py \
              "$out/build/gateware/ypcb_litedram_core.v"
            {
              echo "source: task6YpcbLiteDramNoOdelayLowrateRtlElaboration"
              echo "override: add A7 PHY DFI wrdata debug output ports"
              echo "controller path: LiteDRAM/LiteX only"
              echo "Vivado MIG lane: rejected"
            } > "$out/dfi_debug_ports.txt"
          '';

        task6YpcbLiteDramNoOdelayLowrateDqs0RtlElaboration =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-lowrate-dqs0-rtl-elaboration" { } ''
            set -euo pipefail
            cp -R ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/. "$out"
            chmod -R u+w "$out"
            rtl="$out/build/gateware/ypcb_litedram_core.v"
            substituteInPlace "$rtl" \
              --replace-fail ".CLKOUT3_PHASE  (7'd90)," \
                             ".CLKOUT3_PHASE  (1'd0),"
            {
              echo "source: task6YpcbLiteDramNoOdelayLowrateRtlElaboration"
              echo "override: sys4x_dqs CLKOUT3_PHASE 90 -> 0 degrees"
              echo "controller path: LiteDRAM/LiteX only"
              echo "Vivado MIG lane: rejected"
            } > "$out/dqs_phase_override.txt"
          '';

        task6YpcbLiteDramNoOdelayRtlCheck =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-rtl-check" { } ''
            set -euo pipefail
            mkdir -p "$out"
            rtl=${task6YpcbLiteDramNoOdelayRtlElaboration}/build/gateware/ypcb_litedram_core.v

            if ${pkgs.gnugrep}/bin/grep -R "ODELAYE2" "$rtl" > "$out/odelaye2.txt"; then
              echo "ERROR: no-ODELAY LiteDRAM RTL still contains ODELAYE2" >&2
              exit 1
            fi

            ${pkgs.gnugrep}/bin/grep -R "IDELAYE2" "$rtl" > "$out/idelaye2.txt"
            ${pkgs.gnugrep}/bin/grep -R "sys4x_dqs" "$rtl" > "$out/sys4x_dqs.txt"
            {
              echo "PASS: no ODELAYE2 instances found"
              echo "IDELAYE2 mentions: $(wc -l < "$out/idelaye2.txt")"
              echo "sys4x_dqs mentions: $(wc -l < "$out/sys4x_dqs.txt")"
            } > "$out/summary.txt"
          '';

        task6YpcbLiteDramNoOdelayLowrateRtlCheck =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-lowrate-rtl-check" { } ''
            set -euo pipefail
            mkdir -p "$out"
            rtl=${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v

            if ${pkgs.gnugrep}/bin/grep -R "ODELAYE2" "$rtl" > "$out/odelaye2.txt"; then
              echo "ERROR: low-rate no-ODELAY LiteDRAM RTL still contains ODELAYE2" >&2
              exit 1
            fi

            ${pkgs.gnugrep}/bin/grep -R "IDELAYE2" "$rtl" > "$out/idelaye2.txt"
            ${pkgs.gnugrep}/bin/grep -R "sys4x_dqs" "$rtl" > "$out/sys4x_dqs.txt"
            {
              echo "PASS: low-rate no-ODELAY RTL has no ODELAYE2 instances"
              echo "IDELAYE2 mentions: $(wc -l < "$out/idelaye2.txt")"
              echo "sys4x_dqs mentions: $(wc -l < "$out/sys4x_dqs.txt")"
            } > "$out/summary.txt"
          '';

        task6YpcbLiteDramNoOdelayLowrateDqs0RtlCheck =
          pkgs.runCommand "h2-ypcb-litedram-no-odelay-lowrate-dqs0-rtl-check" { } ''
            set -euo pipefail
            mkdir -p "$out"
            rtl=${task6YpcbLiteDramNoOdelayLowrateDqs0RtlElaboration}/build/gateware/ypcb_litedram_core.v

            if ${pkgs.gnugrep}/bin/grep -R "ODELAYE2" "$rtl" > "$out/odelaye2.txt"; then
              echo "ERROR: low-rate dqs0 no-ODELAY LiteDRAM RTL still contains ODELAYE2" >&2
              exit 1
            fi

            ${pkgs.gnugrep}/bin/grep -R "IDELAYE2" "$rtl" > "$out/idelaye2.txt"
            ${pkgs.gnugrep}/bin/grep -R "sys4x_dqs" "$rtl" > "$out/sys4x_dqs.txt"
            ${pkgs.gnugrep}/bin/grep -R "CLKOUT3_PHASE  (1'd0)" "$rtl" > "$out/dqs0_phase.txt"
            {
              echo "PASS: low-rate dqs0 no-ODELAY RTL has no ODELAYE2 instances"
              echo "IDELAYE2 mentions: $(wc -l < "$out/idelaye2.txt")"
              echo "sys4x_dqs mentions: $(wc -l < "$out/sys4x_dqs.txt")"
              echo "CLKOUT3_PHASE 0 degree override: $(wc -l < "$out/dqs0_phase.txt")"
            } > "$out/summary.txt"
          '';

        task6YpcbLiteDramOpenSynthJson =
          pkgs.runCommand "h2-ypcb-litedram-open-synth-json" { } ''
            mkdir -p "$out"
            cat > "$out/run.ys" <<EOF
            verilog_defaults -push
            verilog_defaults -add -defer
            read_verilog ${task6YpcbLiteDramRtlElaboration}/build/gateware/ypcb_litedram_core.v
            verilog_defaults -pop
            attrmap -tocase keep -imap keep="true" keep=1 -imap keep="false" keep=0 -remove keep=0
            synth_xilinx -flatten -abc9 -arch xc7 -top ypcb_litedram_core
            stat -top ypcb_litedram_core
            write_json $out/ypcb_litedram_core.json
            EOF
            ${pkgs.yosys}/bin/yosys -l "$out/yosys.rpt" -s "$out/run.ys"
          '';

        task6YpcbLiteDramOpenSynthUtilization =
          mkMappedJsonUtilizationReport {
            name = "h2-ypcb-litedram-open-synth";
            capacities = tinyStoriesCapacities;
            topName = "ypcb_litedram_core";
            designJson =
              "${task6YpcbLiteDramOpenSynthJson}/ypcb_litedram_core.json";
          };

        task6YpcbLiteDramInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramInitBandwidthProbeIopadJson =
          pkgs.runCommand "task6-ypcb-litedram-init-bandwidth-probe-iopad.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson = task6YpcbLiteDramInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDqs0RtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_DISABLE_WRITE_COMMAND 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_PHASE_MATRIX_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_SOURCE_COMMAND_MATRIX_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_SOURCE_ORDER_MATRIX_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_BYTE_PHASE_ASSOC_MATRIX_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_INIT_STATUS_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-chain0-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_INIT_STATUS_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            chparam -set JTAG_CHAIN 0 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_HALF_ORDER_MATRIX_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_DISPLACEMENT_PROBE_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_CSR_ECHO_PROBE_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_WBITSLIP_SWEEP_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_RBITSLIP_SWEEP_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_MAP_PROBE_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ACTIVE_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_BIST_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ADDRWALK_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE 1 task6_ypcb_litedram_init_bandwidth_probe_top
            chparam -set READ_COUNT_LOG2 4 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN 1 task6_ypcb_litedram_init_bandwidth_probe_top
            chparam -set READ_COUNT_LOG2 6 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_EXPECTED_READ 1 task6_ypcb_litedram_init_bandwidth_probe_top
            chparam -set READ_COUNT_LOG2 6 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_PACKING_CLASSIFIER 1 task6_ypcb_litedram_init_bandwidth_probe_top
            chparam -set READ_COUNT_LOG2 6 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_ADDRESS_CLASSIFIER 1 task6_ypcb_litedram_init_bandwidth_probe_top
            chparam -set READ_COUNT_LOG2 4 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_CMDADDR_TRACE 1 task6_ypcb_litedram_init_bandwidth_probe_top
            chparam -set READ_COUNT_LOG2 4 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeByCommandIndex =
          let
            baseName =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe";
            commandIndexRange = builtins.genList (index: index) 16;
            buildForIndex = { index }: let
              indexStr = toString index;
              artifactName =
                "${baseName}-native-cmdaddr-first-command-index-${indexStr}";
              json =
                pkgs.runCommand "${artifactName}.json" {
                  buildInputs = [ pkgs.yosys ];
                } ''
                  set -euo pipefail
                  cat > run.ys <<EOF
                  read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
                  read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
                  read_verilog -lib +/xilinx/cells_sim.v
                  read_verilog -lib +/xilinx/cells_xtra.v
                  chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_CMDADDR_TRACE 1 task6_ypcb_litedram_init_bandwidth_probe_top
                  chparam -set NATIVE_CMDADDR_FIRST_COMMAND_INDEX ${indexStr} task6_ypcb_litedram_init_bandwidth_probe_top
                  chparam -set READ_COUNT_LOG2 4 task6_ypcb_litedram_init_bandwidth_probe_top
                  hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
                  proc
                  synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
                  write_json "$out"
                  EOF
                  ${pkgs.yosys}/bin/yosys -s run.ys
                '';
              fasm = mkFasm {
                name = artifactName;
                xdc =
                  task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeXdc;
                json = json;
                seed = 13;
                freqMHz = 25;
              };
              bitstream = mkBitstream {
                name = artifactName;
                fasm = fasm;
                framesBase = artifactName;
              };
            in {
              json = json;
              fasm = fasm;
              bitstream = bitstream;
            };

            indexedArtifacts = builtins.listToAttrs (map
              (index: {
                name = toString index;
                value = buildForIndex { index = index; };
              })
              commandIndexRange);
          in {
            json = builtins.listToAttrs (map
              (index: {
                name =
                  "${baseName}-native-cmdaddr-first-command-index-${toString index}-json";
                value = indexedArtifacts.${toString index}.json;
              })
              commandIndexRange);

            fasm = builtins.listToAttrs (map
              (index: {
                name =
                  "${baseName}-native-cmdaddr-first-command-index-${toString index}-fasm";
                value = indexedArtifacts.${toString index}.fasm;
              })
              commandIndexRange);

            bitstream = builtins.listToAttrs (map
              (index: {
                name =
                  "${baseName}-native-cmdaddr-first-command-index-${toString index}-bitstream";
                value = indexedArtifacts.${toString index}.bitstream;
              })
              commandIndexRange);
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrSingleReadInitBandwidthProbeByStartIndex =
          let
            baseName =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-single-read-init-bandwidth-probe";
            startIndexRange = builtins.genList (index: index) 16;
            buildForIndex = { index }: let
              indexStr = toString index;
              artifactName =
                "${baseName}-start-index-${indexStr}";
              json =
                pkgs.runCommand "${artifactName}.json" {
                  buildInputs = [ pkgs.yosys ];
                } ''
                  set -euo pipefail
                  cat > run.ys <<EOF
                  read_verilog ${task6YpcbLiteDramNoOdelayLowrateDfiDebugRtlElaboration}/build/gateware/ypcb_litedram_core.v
                  read_verilog -sv -DTASK6_LITEDRAM_DEBUG_PORTS ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
                  read_verilog -lib +/xilinx/cells_sim.v
                  read_verilog -lib +/xilinx/cells_xtra.v
                  chparam -set DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_CMDADDR_TRACE 1 task6_ypcb_litedram_init_bandwidth_probe_top
                  chparam -set NATIVE_CMDADDR_FIRST_COMMAND_INDEX 0 task6_ypcb_litedram_init_bandwidth_probe_top
                  chparam -set NATIVE_ADDRESS_CLASSIFIER_START_INDEX ${indexStr} task6_ypcb_litedram_init_bandwidth_probe_top
                  chparam -set READ_COUNT_LOG2 0 task6_ypcb_litedram_init_bandwidth_probe_top
                  hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
                  proc
                  synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
                  write_json "$out"
                  EOF
                  ${pkgs.yosys}/bin/yosys -s run.ys
                '';
              fasm = mkFasm {
                name = artifactName;
                xdc =
                  task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeXdc;
                json = json;
                seed = 13;
                freqMHz = 25;
              };
              bitstream = mkBitstream {
                name = artifactName;
                fasm = fasm;
                framesBase = artifactName;
              };
            in {
              json = json;
              fasm = fasm;
              bitstream = bitstream;
            };

            indexedArtifacts = builtins.listToAttrs (map
              (index: {
                name = toString index;
                value = buildForIndex { index = index; };
              })
              startIndexRange);
          in {
            json = builtins.listToAttrs (map
              (index: {
                name =
                  "${baseName}-start-index-${toString index}-json";
                value = indexedArtifacts.${toString index}.json;
              })
              startIndexRange);

            fasm = builtins.listToAttrs (map
              (index: {
                name =
                  "${baseName}-start-index-${toString index}-fasm";
                value = indexedArtifacts.${toString index}.fasm;
              })
              startIndexRange);

            bitstream = builtins.listToAttrs (map
              (index: {
                name =
                  "${baseName}-start-index-${toString index}-bitstream";
                value = indexedArtifacts.${toString index}.bitstream;
              })
              startIndexRange);
          };

        task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeJson =
          pkgs.runCommand "task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog ${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.v
            read_verilog -sv ${./fpga/rtl/task6_ypcb_litedram_init_bandwidth_probe_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY 1 task6_ypcb_litedram_init_bandwidth_probe_top
            hierarchy -top task6_ypcb_litedram_init_bandwidth_probe_top -check
            proc
            synth_xilinx -family xc7 -top task6_ypcb_litedram_init_bandwidth_probe_top -noiopad
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6YpcbLiteDramNoOdelayInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson = task6YpcbLiteDramNoOdelayInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeJson;
          };

        task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe";
            capacities = tinyStoriesCapacities;
            topName = "task6_ypcb_litedram_init_bandwidth_probe_top";
            designJson =
              task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeJson;
          };

        task6YpcbLiteDramInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateDqs0RtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbUberDdr3BistXdc =
          pkgs.runCommand "task6-ypcb-uberddr3-bist.xdc" {
            nativeBuildInputs = [ pkgs.python3 ];
          } ''
            set -euo pipefail
            python3 - <<'PY' > "$out"
            import re
            from pathlib import Path

            platform = Path("${litexBoards}/litex_boards/platforms/ypcb_00338_1p1.py").read_text()
            channel0 = platform.split("# DDR3 SDRAM", 1)[1].split("# DDR3 SDRAM", 1)[0]

            def pins_for(name):
                match = re.search(
                    r'Subsignal\("' + re.escape(name) + r'".*?Pins\((.*?)\)',
                    channel0,
                    re.S,
                )
                if not match:
                    raise SystemExit(f"missing LiteX YPCB ddram0.{name} pins")
                return " ".join(re.findall(r'"([^"]+)"', match.group(1))).split()

            def scalar(name, port, iostandard="SSTL15", slew=True):
                pin = pins_for(name)[0]
                print(f"# LiteX-Boards ddram:0.{name}")
                print(f"set_property LOC {pin} [get_ports {{{port}}}]")
                if slew:
                    print(f"set_property SLEW FAST [get_ports {{{port}}}]")
                print(f"set_property IOSTANDARD {iostandard} [get_ports {{{port}}}]")
                print()

            def vector(name, port, width, iostandard="SSTL15", in_term=False):
                pins = pins_for(name)
                if len(pins) < width:
                    raise SystemExit(f"ddram0.{name} has {len(pins)} pins, need {width}")
                for index, pin in enumerate(pins[:width]):
                    print(f"# LiteX-Boards ddram:0.{name}[{index}]")
                    print(f"set_property LOC {pin} [get_ports {{{port}[{index}]}}]")
                    print(f"set_property SLEW FAST [get_ports {{{port}[{index}]}}]")
                    print(f"set_property IOSTANDARD {iostandard} [get_ports {{{port}[{index}]}}]")
                    if in_term:
                        print(f"set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {{{port}[{index}]}}]")
                    print()

            print("# Generated from litex-hub/litex-boards ypcb_00338_1p1.py.")
            print("# Channel 0, 64-bit data lane only; YPCB LiteX platform exposes no DM pins.")
            print("set_property LOC AH27 [get_ports {clk200_p}]")
            print("set_property IOSTANDARD LVDS_25 [get_ports {clk200_p}]")
            print("set_property LOC AH28 [get_ports {clk200_n}]")
            print("set_property IOSTANDARD LVDS_25 [get_ports {clk200_n}]")
            print("create_clock -name clk200_p -period 5.000 [get_ports clk200_p]")
            print()
            print("set_property LOC R28 [get_ports {SYS_RSTN}]")
            print("set_property IOSTANDARD LVCMOS18 [get_ports {SYS_RSTN}]")
            print()

            vector("a", "ddram_a", 15)
            vector("ba", "ddram_ba", 3)
            scalar("ras_n", "ddram_ras_n")
            scalar("cas_n", "ddram_cas_n")
            scalar("we_n", "ddram_we_n")
            scalar("cs_n", "ddram_cs_n")
            scalar("cke", "ddram_cke")
            scalar("odt", "ddram_odt")
            scalar("reset_n", "ddram_reset_n")
            vector("dq", "ddram_dq", 64, in_term=True)
            vector("dqs_p", "ddram_dqs_p", 8, iostandard="DIFF_SSTL15", in_term=True)
            vector("dqs_n", "ddram_dqs_n", 8, iostandard="DIFF_SSTL15", in_term=True)
            scalar("clk_p", "ddram_clk_p", iostandard="DIFF_SSTL15")
            scalar("clk_n", "ddram_clk_n", iostandard="DIFF_SSTL15")

            print("")
            print("# INTERNAL_VREF 0.750 on DDR3 banks 11..18 is present in the")
            print("# LiteX/Vivado-style constraints, but nextpnr-xilinx's XDC")
            print("# frontend only accepts get_ports targets here.")
            PY
          '';

        task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeXdc = mkXdc {
          name = "task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe";
          includeBoardXdc = false;
          extraConstraints = [
            "${task6YpcbLiteDramNoOdelayLowrateRtlElaboration}/build/gateware/ypcb_litedram_core.xdc"
            ./fpga/constraints/task6_ypcb_litedram_init_bandwidth_probe.xdc
          ];
        };

        task6YpcbLiteDramInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-init-bandwidth-probe";
          xdc = task6YpcbLiteDramInitBandwidthProbeXdc;
          json = task6YpcbLiteDramInitBandwidthProbeJson;
          seed = 1;
          freqMHz = 50;
        };

        task6YpcbLiteDramInitBandwidthProbeBitstream = mkBitstream {
          name = "task6-ypcb-litedram-init-bandwidth-probe";
          fasm = task6YpcbLiteDramInitBandwidthProbeFasm;
          framesBase = "task6-ypcb-litedram-init-bandwidth-probe";
        };

        task6YpcbLiteDramNoOdelayInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-init-bandwidth-probe";
          xdc = task6YpcbLiteDramNoOdelayInitBandwidthProbeXdc;
          json = task6YpcbLiteDramNoOdelayInitBandwidthProbeJson;
          seed = 2;
          freqMHz = 50;
        };

        task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe";
          xdc = task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeXdc;
          json = task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeJson;
          seed = 3;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe";
          xdc = task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeXdc;
          json = task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeJson;
          seed = 4;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeJson;
          seed = 5;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeJson;
          seed = 6;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeJson;
          seed = 7;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeJson;
          seed = 7;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-chain0-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeJson;
          seed = 8;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeJson;
          seed = 9;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeJson;
          seed = 9;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeJson;
          seed = 9;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeJson;
          seed = 9;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeJson;
          seed = 9;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeJson;
          seed = 10;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeJson;
          seed = 12;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeJson;
          seed = 13;
          freqMHz = 25;
        };

        task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeFasm = mkFasm {
          name = "task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe";
          xdc =
            task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeXdc;
          json =
            task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeJson;
          seed = 11;
          freqMHz = 25;
        };

        task6YpcbUberDdr3BistFasm = mkFasm {
          name = "task6-ypcb-uberddr3-bist";
          xdc = task6YpcbUberDdr3BistXdc;
          json = task6YpcbUberDdr3BistYosysJson;
          seed = 14;
          freqMHz = 25;
        };

        task6YpcbUberDdr3BistBitstream = mkBitstream {
          name = "task6-ypcb-uberddr3-bist";
          fasm = task6YpcbUberDdr3BistFasm;
          framesBase = "task6-ypcb-uberddr3-bist";
        };

        task6YpcbLiteDramNoOdelayInitBandwidthProbeBitstream =
          mkBitstream {
            name = "task6-ypcb-litedram-no-odelay-init-bandwidth-probe";
            fasm = task6YpcbLiteDramNoOdelayInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeBitstream =
          mkBitstream {
            name = "task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe";
            fasm = task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-chain0-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-init-status-only-chain0-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe";
          };

        task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeBitstream =
          mkBitstream {
            name =
              "task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe";
            fasm =
              task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeFasm;
            framesBase =
              "task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe";
          };

        task6YpcbLiteDramInitBandwidthProbeIopadFasm = mkFasm {
          name = "task6-ypcb-litedram-init-bandwidth-probe-iopad";
          xdc = task6YpcbLiteDramInitBandwidthProbeXdc;
          json = task6YpcbLiteDramInitBandwidthProbeIopadJson;
          seed = 1;
          freqMHz = 50;
        };

        task6YpcbLiteDramInitBandwidthProbeIopadBitstream = mkBitstream {
          name = "task6-ypcb-litedram-init-bandwidth-probe-iopad";
          fasm = task6YpcbLiteDramInitBandwidthProbeIopadFasm;
          framesBase = "task6-ypcb-litedram-init-bandwidth-probe-iopad";
        };

        mkTask6OdelayCutoutJson = { name, topName }:
          pkgs.runCommand "${name}.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./fpga/rtl/task6_odelay_obuf_cutout_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            hierarchy -top ${topName} -check
            proc
            synth_xilinx -family xc7 -top ${topName}
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6OdelayObufCutoutJson = mkTask6OdelayCutoutJson {
          name = "task6-odelay-obuf-cutout";
          topName = "task6_odelay_obuf_cutout_top";
        };

        task6OdelayObufdsCutoutJson = mkTask6OdelayCutoutJson {
          name = "task6-odelay-obufds-cutout";
          topName = "task6_odelay_obufds_cutout_top";
        };

        mkTask6NoOdelayCutoutJson = { name, topName }:
          pkgs.runCommand "${name}.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./fpga/rtl/task6_no_odelay_obuf_cutout_top.sv}
            read_verilog -lib +/xilinx/cells_sim.v
            read_verilog -lib +/xilinx/cells_xtra.v
            hierarchy -top ${topName} -check
            proc
            synth_xilinx -family xc7 -top ${topName}
            write_json "$out"
            EOF
            ${pkgs.yosys}/bin/yosys -s run.ys
          '';

        task6NoOdelayObufCutoutJson = mkTask6NoOdelayCutoutJson {
          name = "task6-no-odelay-obuf-cutout";
          topName = "task6_no_odelay_obuf_cutout_top";
        };

        task6NoOdelayObufdsCutoutJson = mkTask6NoOdelayCutoutJson {
          name = "task6-no-odelay-obufds-cutout";
          topName = "task6_no_odelay_obufds_cutout_top";
        };

        task6OdelayObufCutoutXdc = mkXdc {
          name = "task6-odelay-obuf-cutout";
          includeBoardXdc = false;
          extraConstraints = [
            ./fpga/constraints/task6_odelay_obuf_cutout.xdc
          ];
        };

        task6OdelayObufdsCutoutXdc = mkXdc {
          name = "task6-odelay-obufds-cutout";
          includeBoardXdc = false;
          extraConstraints = [
            ./fpga/constraints/task6_odelay_obufds_cutout.xdc
          ];
        };

        task6NoOdelayObufCutoutXdc = mkXdc {
          name = "task6-no-odelay-obuf-cutout";
          includeBoardXdc = false;
          extraConstraints = [
            ./fpga/constraints/task6_odelay_obuf_cutout.xdc
          ];
        };

        task6NoOdelayObufdsCutoutXdc = mkXdc {
          name = "task6-no-odelay-obufds-cutout";
          includeBoardXdc = false;
          extraConstraints = [
            ./fpga/constraints/task6_odelay_obufds_cutout.xdc
          ];
        };

        task6OdelayObufCutoutFasm = mkFasm {
          name = "task6-odelay-obuf-cutout";
          xdc = task6OdelayObufCutoutXdc;
          json = task6OdelayObufCutoutJson;
          seed = 1;
          freqMHz = 50;
        };

        task6OdelayObufdsCutoutFasm = mkFasm {
          name = "task6-odelay-obufds-cutout";
          xdc = task6OdelayObufdsCutoutXdc;
          json = task6OdelayObufdsCutoutJson;
          seed = 1;
          freqMHz = 50;
        };

        task6NoOdelayObufCutoutFasm = mkFasm {
          name = "task6-no-odelay-obuf-cutout";
          xdc = task6NoOdelayObufCutoutXdc;
          json = task6NoOdelayObufCutoutJson;
          seed = 1;
          freqMHz = 50;
        };

        task6NoOdelayObufdsCutoutFasm = mkFasm {
          name = "task6-no-odelay-obufds-cutout";
          xdc = task6NoOdelayObufdsCutoutXdc;
          json = task6NoOdelayObufdsCutoutJson;
          seed = 1;
          freqMHz = 50;
        };

        task6Int8L2CFcPostGeluRequantTbDataSv =
          pkgs.runCommand "task6-int8-l2-c-fc-post-gelu-requant-tb-data-sv" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_c_fc_post_gelu_requant_tb_data.py \
              --contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --downstream-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json
              } \
              --out-sv "$out/tb_data.sv" \
              --out-json "$out/summary.json"
          '';

        simMain = pkgs.runCommand "sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -I${tbDataSv} \
            -top tb -Mdir "$out/obj_dir" -o sim_main \
            -f ${matmulSv}/sources.f ${./sim/tb_main.sv}
        '';

        task6L0Gemv64SimMain = pkgs.runCommand "task6-l0-gemv64-sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -I${task6L0Gemv64TbDataSv} \
            -top task6_l0_gemv64_tb -Mdir "$out/obj_dir" -o sim_main \
            -f ${task6L0Gemv64Sv}/sources.f ${./sim/task6_l0_gemv64_tb_main.sv}
        '';

        task6Int8Gemv64SimMain = pkgs.runCommand "task6-int8-gemv64-sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -top task6_int8_gemv64_tb -Mdir "$out/obj_dir" -o sim_main \
            ${./rtl/task6/task6_int8_gemv64_kernel.sv} ${./sim/task6_int8_gemv64_tb_main.sv}
        '';

        task6Int8Gemv64Lanes4SimMain = pkgs.runCommand "task6-int8-gemv64-lanes4-sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -top task6_int8_gemv64_lanes4_tb -Mdir "$out/obj_dir" -o sim_main \
            ${./rtl/task6/task6_int8_gemv64_lanes4_kernel.sv} ${./sim/task6_int8_gemv64_lanes4_tb_main.sv}
        '';

        task6Int8Gemv64Lanes4PackedSimMain =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -top task6_int8_gemv64_lanes4_packed_tb -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_kernel.sv} \
              ${./sim/task6_int8_gemv64_lanes4_packed_tb_main.sv}
          '';

        task6Int8Gemv64Lanes4PackedSyncMemSimMain =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed-sync-mem-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -top task6_int8_gemv64_lanes4_packed_sync_mem_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_mem_kernel.sv} \
              ${./sim/task6_int8_gemv64_lanes4_packed_sync_mem_tb_main.sv}
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemSimMain =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -top task6_int8_gemv64x256_lanes4_packed_sync_mem_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_tb_main.sv}
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoSimMain =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -top task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./sim/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_tb_main.sv}
          '';

        task6Int8L2CFcContractLocalIoSimMain =
          pkgs.runCommand "task6-int8-l2-c-fc-contract-local-io-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8L2CFcContractLocalIoTbDataSv} \
              -top task6_int8_l2_c_fc_contract_local_io_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./sim/task6_int8_l2_c_fc_contract_local_io_tb_main.sv}
          '';

        task6Int8L2CFcPostGeluRequantSimMain =
          pkgs.runCommand "task6-int8-l2-c-fc-post-gelu-requant-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8L2CFcPostGeluRequantTbDataSv} \
              -top task6_int8_l2_c_fc_post_gelu_requant_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./sim/task6_int8_l2_c_fc_post_gelu_requant_tb_main.sv}
          '';

        task6Int8L2CProjFromPostGeluSimMain =
          pkgs.runCommand "task6-int8-l2-c-proj-from-post-gelu-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8L2CProjFromPostGeluTbDataSv} \
              -top task6_int8_l2_c_proj_from_post_gelu_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./sim/task6_int8_l2_c_proj_from_post_gelu_tb_main.sv}
          '';

        task6Int8L2MlpChainPostGeluCProjSimMain =
          pkgs.runCommand "task6-int8-l2-mlp-chain-post-gelu-c-proj-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8L2MlpChainPostGeluCProjTbDataSv} \
              -top task6_int8_l2_mlp_chain_post_gelu_c_proj_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./sim/task6_int8_l2_mlp_chain_post_gelu_c_proj_tb_main.sv}
          '';

        task6Int8L2MlpChainCProjRequantSimMain =
          pkgs.runCommand "task6-int8-l2-mlp-chain-c-proj-requant-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8L2MlpChainCProjRequantTbDataSv} \
              -top task6_int8_l2_mlp_chain_c_proj_requant_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv} \
              ${./sim/task6_int8_l2_mlp_chain_c_proj_requant_tb_main.sv}
          '';

        task6Int8L2MlpChainResidualAddSimMain =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8L2MlpChainResidualAddTbDataSv} \
              -top task6_int8_l2_mlp_chain_residual_add_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv} \
              ${./sim/task6_int8_l2_mlp_chain_residual_add_tb_main.sv}
          '';

        task6Int8L2MlpChainResidualAddSelftestSimMain =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8L2MlpChainResidualAddTbDataSv} \
              -top task6_int8_l2_mlp_chain_residual_add_selftest_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv} \
              ${./fpga/rtl/task6_int8_l2_mlp_chain_residual_add_selftest_top.sv} \
              ${./sim/task6_int8_l2_mlp_chain_residual_add_selftest_tb_main.sv}
          '';

        task6Int8V4kL2ResidualAddOutputHeadSelftestSimMain =
          pkgs.runCommand "task6-int8-v4k-l2-residual-add-output-head-selftest-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8V4kL2ResidualAddOutputHeadSelftestTbDataSv} \
              -top task6_int8_v4k_l2_residual_add_output_head_selftest_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv} \
              ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv} \
              ${task6Int8V4kL2ResidualAddOutputHeadSelftestTop} \
              ${./sim/task6_int8_v4k_l2_residual_add_output_head_selftest_tb_main.sv}
          '';

        task6Int8V10kL2ResidualAddOutputHeadSelftestSimMain =
          pkgs.runCommand "task6-int8-v10k-l2-residual-add-output-head-selftest-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Int8V10kL2ResidualAddOutputHeadSelftestTbDataSv} \
              -top task6_int8_v4k_l2_residual_add_output_head_selftest_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv} \
              ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv} \
              ${task6Int8V10kL2ResidualAddOutputHeadSelftestTop} \
              ${./sim/task6_int8_v4k_l2_residual_add_output_head_selftest_tb_main.sv}
          '';

        task6TernaryV9984L2ResidualAddOutputHeadSelftestSimMain =
          pkgs.runCommand "task6-ternary-v9984-l2-residual-add-output-head-selftest-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6TernaryV9984L2ResidualAddOutputHeadSelftestTbDataSv} \
              -top task6_int8_v4k_l2_residual_add_output_head_selftest_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_ternary_vocab_output_head_top1_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv} \
              ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv} \
              ${task6TernaryV9984L2ResidualAddOutputHeadSelftestTop} \
              ${./sim/task6_int8_v4k_l2_residual_add_output_head_selftest_tb_main.sv}
          '';

        task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestSimMain =
          pkgs.runCommand "task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTbDataSv} \
              -top task6_int8_v4k_l2_residual_add_output_head_selftest_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv} \
              ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv} \
              ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv} \
              ${./rtl/task6/task6_ternary_base3_vocab_output_head_top1_kernel.sv} \
              ${./rtl/task6/task6_ternary_vocab_output_head_top1_kernel.sv} \
              ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv} \
              ${task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTop} \
              ${./sim/task6_int8_v4k_l2_residual_add_output_head_selftest_tb_main.sv}
          '';

        task6Ddr3RowStreamCutoutSimMain =
          pkgs.runCommand "task6-ddr3-row-stream-cutout-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6Ddr3RowStreamCutoutTbData} \
              -top task6_ddr3_rowstream_top1_cutout_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./rtl/task6/task6_q024_topk_score_compare.sv} \
              ${./rtl/task6/task6_ddr3_rowstream_mem_source.sv} \
              ${./rtl/task6/task6_ddr3_rowstream_top1_cutout.sv} \
              ${./sim/task6_ddr3_rowstream_top1_cutout_tb.sv}
          '';

        task6CProjRequantArithSelftestSimMain =
          pkgs.runCommand "task6-c-proj-requant-arith-selftest-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -top task6_c_proj_requant_arith_selftest_tb \
              -Mdir "$out/obj_dir" -o sim_main \
              ${./fpga/rtl/task6_c_proj_requant_arith_selftest_top.sv} \
              ${./sim/task6_c_proj_requant_arith_selftest_tb_main.sv}
          '';

        task6Int8Gemv64YosysStat = pkgs.runCommand "task6-int8-gemv64-yosys-stat.json" {
          buildInputs = [ pkgs.yosys ];
        } ''
          set -euo pipefail
          cat > run.ys <<EOF
          read_verilog -sv ${./rtl/task6/task6_int8_gemv64_kernel.sv}
          hierarchy -top task6_int8_gemv64_kernel -check
          proc
          synth_xilinx -family xc7 -top task6_int8_gemv64_kernel -noiopad
          tee -o stat.json stat -json
          EOF
          yosys -s run.ys
          cp stat.json "$out"
        '';

        task6Int8Gemv64Lanes4YosysStat = pkgs.runCommand "task6-int8-gemv64-lanes4-yosys-stat.json" {
          buildInputs = [ pkgs.yosys ];
        } ''
          set -euo pipefail
          cat > run.ys <<EOF
          read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_kernel.sv}
          hierarchy -top task6_int8_gemv64_lanes4_kernel -check
          proc
          synth_xilinx -family xc7 -top task6_int8_gemv64_lanes4_kernel -noiopad
          tee -o stat.json stat -json
          EOF
          yosys -s run.ys
          cp stat.json "$out"
        '';

        task6Int8Gemv64Lanes4PackedYosysStat =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_kernel.sv}
            hierarchy -top task6_int8_gemv64_lanes4_packed_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64_lanes4_packed_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8Gemv64Lanes4PackedSyncMemYosysStat =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_mem_kernel.sv}
            hierarchy -top task6_int8_gemv64_lanes4_packed_sync_mem_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64_lanes4_packed_sync_mem_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemYosysStat =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            hierarchy -top task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoYosysStat =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            hierarchy -top task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8L2CFcPostGeluRequantYosysStat =
          pkgs.runCommand "task6-int8-l2-c-fc-post-gelu-requant-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            hierarchy -top task6_int8_l2_c_fc_post_gelu_requant_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_c_fc_post_gelu_requant_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8L2CProjFromPostGeluYosysStat =
          pkgs.runCommand "task6-int8-l2-c-proj-from-post-gelu-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            hierarchy -top task6_int8_l2_c_proj_from_post_gelu_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_c_proj_from_post_gelu_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8L2MlpChainPostGeluCProjYosysStat =
          pkgs.runCommand "task6-int8-l2-mlp-chain-post-gelu-c-proj-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            hierarchy -top task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8L2MlpChainCProjRequantYosysStat =
          pkgs.runCommand "task6-int8-l2-mlp-chain-c-proj-requant-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            hierarchy -top task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8L2MlpChainResidualAddYosysStat =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8VocabOutputHeadTop1YosysStat =
          pkgs.runCommand "task6-int8-vocab-output-head-top1-yosys-stat.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            hierarchy -top task6_int8_vocab_output_head_top1_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_vocab_output_head_top1_kernel -noiopad
            tee -o stat.json stat -json
            EOF
            yosys -s run.ys
            cp stat.json "$out"
          '';

        task6Int8Gemv64Json = pkgs.runCommand "task6-int8-gemv64.json" {
          buildInputs = [ pkgs.yosys ];
        } ''
          set -euo pipefail
          cat > run.ys <<EOF
          read_verilog -sv ${./rtl/task6/task6_int8_gemv64_kernel.sv}
          hierarchy -top task6_int8_gemv64_kernel -check
          proc
          synth_xilinx -family xc7 -top task6_int8_gemv64_kernel -noiopad
          write_json "$out"
          EOF
          yosys -s run.ys
        '';

        task6Int8Gemv64Lanes4Json = pkgs.runCommand "task6-int8-gemv64-lanes4.json" {
          buildInputs = [ pkgs.yosys ];
        } ''
          set -euo pipefail
          cat > run.ys <<EOF
          read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_kernel.sv}
          hierarchy -top task6_int8_gemv64_lanes4_kernel -check
          proc
          synth_xilinx -family xc7 -top task6_int8_gemv64_lanes4_kernel -noiopad
          write_json "$out"
          EOF
          yosys -s run.ys
        '';

        task6Int8Gemv64Lanes4PackedJson =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_kernel.sv}
            hierarchy -top task6_int8_gemv64_lanes4_packed_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64_lanes4_packed_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8Gemv64Lanes4PackedSyncMemJson =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed-sync-mem.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_mem_kernel.sv}
            hierarchy -top task6_int8_gemv64_lanes4_packed_sync_mem_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64_lanes4_packed_sync_mem_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemJson =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            hierarchy -top task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoJson =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            hierarchy -top task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2CFcPostGeluRequantJson =
          pkgs.runCommand "task6-int8-l2-c-fc-post-gelu-requant.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            hierarchy -top task6_int8_l2_c_fc_post_gelu_requant_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_c_fc_post_gelu_requant_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2CProjFromPostGeluJson =
          pkgs.runCommand "task6-int8-l2-c-proj-from-post-gelu.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            hierarchy -top task6_int8_l2_c_proj_from_post_gelu_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_c_proj_from_post_gelu_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainPostGeluCProjJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-post-gelu-c-proj.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            hierarchy -top task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainCProjRequantJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-c-proj-requant.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            hierarchy -top task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8VocabOutputHeadTop1Json =
          pkgs.runCommand "task6-int8-vocab-output-head-top1.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            hierarchy -top task6_int8_vocab_output_head_top1_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_vocab_output_head_top1_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8Vocab10kOutputHeadTop1Json =
          pkgs.runCommand "task6-int8-vocab10k-output-head-top1.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            chparam -set VOCAB_SIZE 10000 task6_int8_vocab_output_head_top1_kernel
            chparam -set TILE_OUT_DIM 80 task6_int8_vocab_output_head_top1_kernel
            hierarchy -top task6_int8_vocab_output_head_top1_kernel -check
            proc
            synth_xilinx -family xc7 -top task6_int8_vocab_output_head_top1_kernel -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddSelftestJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${task6Int8L2MlpChainResidualAddSelftestTop}
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V4kL2ResidualAddOutputHeadSelftestJson =
          pkgs.runCommand "task6-int8-v4k-l2-residual-add-output-head-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V4kL2ResidualAddOutputHeadSelftestTop}
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V10kL2ResidualAddOutputHeadSelftestJson =
          pkgs.runCommand "task6-int8-v10k-l2-residual-add-output-head-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V10kL2ResidualAddOutputHeadSelftestTop}
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V6kL2ResidualAddOutputHeadSelftestJson =
          pkgs.runCommand "task6-int8-v6k-l2-residual-add-output-head-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V6kL2ResidualAddOutputHeadSelftestTop}
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V8kL2ResidualAddOutputHeadSelftestJson =
          pkgs.runCommand "task6-int8-v8k-l2-residual-add-output-head-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V8kL2ResidualAddOutputHeadSelftestTop}
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V9984L2ResidualAddOutputHeadSelftestJson =
          pkgs.runCommand "task6-int8-v9984-l2-residual-add-output-head-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V9984L2ResidualAddOutputHeadSelftestTop}
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebugJson =
          pkgs.runCommand "task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V9984L2ResidualAddOutputHeadSelftestTop}
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set ENABLE_JTAG_DEBUG 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            chparam -set PHASE_BANKED_VOCAB_LOADER_ROM 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebugJson =
          pkgs.runCommand "task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_ternary_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6TernaryV9984L2ResidualAddOutputHeadSelftestTop}
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set ENABLE_JTAG_DEBUG 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            chparam -set PHASE_BANKED_VOCAB_LOADER_ROM 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestJtagDebugJson =
          pkgs.runCommand "task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-jtag-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_ternary_base3_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_ternary_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTop}
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set ENABLE_JTAG_DEBUG 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            chparam -set PHASE_BANKED_VOCAB_LOADER_ROM 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestJson =
          pkgs.runCommand "task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTop}
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugJson =
          pkgs.runCommand "task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V4kL2ResidualAddOutputHeadSelftestTop}
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set ENABLE_JTAG_DEBUG 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            chparam -set PHASE_BANKED_VOCAB_LOADER_ROM 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugJson =
          pkgs.runCommand "task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_vocab_output_head_top1_kernel.sv}
            read_verilog -sv ${task6Int8V10kL2ResidualAddOutputHeadSelftestTop}
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set ENABLE_JTAG_DEBUG 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            chparam -set PHASE_BANKED_VOCAB_LOADER_ROM 1 task6_int8_v4k_l2_residual_add_output_head_selftest_top
            hierarchy -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_v4k_l2_residual_add_output_head_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddSelftestDebugJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${task6Int8L2MlpChainResidualAddSelftestTop}
            chparam -set DEBUG_LEDS 1 task6_int8_l2_mlp_chain_residual_add_selftest_top
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddSelftestValueDebugJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-value-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${task6Int8L2MlpChainResidualAddSelftestTop}
            chparam -set DEBUG_LEDS 2 task6_int8_l2_mlp_chain_residual_add_selftest_top
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddSelftestCProjDebugJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${task6Int8L2MlpChainResidualAddSelftestTop}
            chparam -set DEBUG_LEDS 3 task6_int8_l2_mlp_chain_residual_add_selftest_top
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${task6Int8L2MlpChainResidualAddSelftestTop}
            chparam -set DEBUG_LEDS 4 task6_int8_l2_mlp_chain_residual_add_selftest_top
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddSelftestJtagDebugJson =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64_lanes4_packed_sync_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_fc_post_gelu_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_c_proj_from_post_gelu_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel.sv}
            read_verilog -sv ${./rtl/task6/task6_int8_l2_mlp_chain_residual_add_kernel.sv}
            read_verilog -sv ${task6Int8L2MlpChainResidualAddSelftestTop}
            read_verilog -lib +/xilinx/cells_xtra.v
            chparam -set ENABLE_JTAG_DEBUG 1 task6_int8_l2_mlp_chain_residual_add_selftest_top
            hierarchy -top task6_int8_l2_mlp_chain_residual_add_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_int8_l2_mlp_chain_residual_add_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6CProjRequantArithSelftestJson =
          pkgs.runCommand "task6-c-proj-requant-arith-selftest.json" {
            buildInputs = [ pkgs.yosys ];
          } ''
            set -euo pipefail
            cat > run.ys <<EOF
            read_verilog -sv ${./fpga/rtl/task6_c_proj_requant_arith_selftest_top.sv}
            hierarchy -top task6_c_proj_requant_arith_selftest_top -check
            proc
            synth_xilinx -family xc7 -top task6_c_proj_requant_arith_selftest_top -noiopad
            write_json "$out"
            EOF
            yosys -s run.ys
          '';

        task6Int8L2MlpChainResidualAddSelftestXdc = mkXdc {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6Int8L2MlpChainResidualAddSelftestFasm = mkFasm {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest";
          xdc = task6Int8L2MlpChainResidualAddSelftestXdc;
          json = task6Int8L2MlpChainResidualAddSelftestJson;
          freqMHz = 50;
        };

        task6Int8L2MlpChainResidualAddSelftestBitstream = mkBitstream {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest";
          fasm = task6Int8L2MlpChainResidualAddSelftestFasm;
          framesBase = "task6-int8-l2-mlp-chain-residual-add-selftest";
        };

        task6Int8V4kL2ResidualAddOutputHeadSelftestXdc = mkXdc {
          name = "task6-int8-v4k-l2-residual-add-output-head-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6Int8V4kL2ResidualAddOutputHeadSelftestFasm = mkFasm {
          name = "task6-int8-v4k-l2-residual-add-output-head-selftest";
          xdc = task6Int8V4kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V4kL2ResidualAddOutputHeadSelftestJson;
          freqMHz = 50;
        };

        task6Int8V4kL2ResidualAddOutputHeadSelftestBitstream = mkBitstream {
          name = "task6-int8-v4k-l2-residual-add-output-head-selftest";
          fasm = task6Int8V4kL2ResidualAddOutputHeadSelftestFasm;
          framesBase = "task6-int8-v4k-l2-residual-add-output-head-selftest";
        };

        task6Int8V4kL2ResidualAddOutputHeadSelftest5MHzFasm = mkFasm {
          name = "task6-int8-v4k-l2-residual-add-output-head-selftest-5mhz";
          xdc = task6Int8V4kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V4kL2ResidualAddOutputHeadSelftestJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V4kL2ResidualAddOutputHeadSelftest5MHzBitstream = mkBitstream {
          name = "task6-int8-v4k-l2-residual-add-output-head-selftest-5mhz";
          fasm = task6Int8V4kL2ResidualAddOutputHeadSelftest5MHzFasm;
          framesBase = "task6-int8-v4k-l2-residual-add-output-head-selftest-5mhz";
        };

        task6Int8V6kL2ResidualAddOutputHeadSelftestXdc = mkXdc {
          name = "task6-int8-v6k-l2-residual-add-output-head-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6Int8V6kL2ResidualAddOutputHeadSelftest5MHzFasm = mkFasm {
          name = "task6-int8-v6k-l2-residual-add-output-head-selftest-5mhz";
          xdc = task6Int8V6kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V6kL2ResidualAddOutputHeadSelftestJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V6kL2ResidualAddOutputHeadSelftest5MHzBitstream = mkBitstream {
          name = "task6-int8-v6k-l2-residual-add-output-head-selftest-5mhz";
          fasm = task6Int8V6kL2ResidualAddOutputHeadSelftest5MHzFasm;
          framesBase = "task6-int8-v6k-l2-residual-add-output-head-selftest-5mhz";
        };

        task6Int8V8kL2ResidualAddOutputHeadSelftestXdc = mkXdc {
          name = "task6-int8-v8k-l2-residual-add-output-head-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6Int8V8kL2ResidualAddOutputHeadSelftest5MHzFasm = mkFasm {
          name = "task6-int8-v8k-l2-residual-add-output-head-selftest-5mhz";
          xdc = task6Int8V8kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V8kL2ResidualAddOutputHeadSelftestJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V8kL2ResidualAddOutputHeadSelftest5MHzBitstream = mkBitstream {
          name = "task6-int8-v8k-l2-residual-add-output-head-selftest-5mhz";
          fasm = task6Int8V8kL2ResidualAddOutputHeadSelftest5MHzFasm;
          framesBase = "task6-int8-v8k-l2-residual-add-output-head-selftest-5mhz";
        };

        task6Int8V9984L2ResidualAddOutputHeadSelftestXdc = mkXdc {
          name = "task6-int8-v9984-l2-residual-add-output-head-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6Int8V9984L2ResidualAddOutputHeadSelftest5MHzFasm = mkFasm {
          name = "task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz";
          xdc = task6Int8V9984L2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V9984L2ResidualAddOutputHeadSelftestJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V9984L2ResidualAddOutputHeadSelftest5MHzBitstream = mkBitstream {
          name = "task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz";
          fasm = task6Int8V9984L2ResidualAddOutputHeadSelftest5MHzFasm;
          framesBase = "task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz";
        };

        task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm = mkFasm {
          name = "task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
          xdc = task6Int8V9984L2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebugJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzBitstream = mkBitstream {
          name = "task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
          fasm = task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm;
          framesBase = "task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
        };

        task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm = mkFasm {
          name = "task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
          xdc = task6Int8V9984L2ResidualAddOutputHeadSelftestXdc;
          json = task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebugJson;
          seed = 2;
          freqMHz = 5;
        };

        task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzBitstream = mkBitstream {
          name = "task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
          fasm = task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm;
          framesBase = "task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
        };

        task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestXdc = mkXdc {
          name = "task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftest5MHzFasm = mkFasm {
          name = "task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-5mhz";
          xdc = task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftest5MHzBitstream = mkBitstream {
          name = "task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-5mhz";
          fasm = task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftest5MHzFasm;
          framesBase = "task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-5mhz";
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftestXdc = mkXdc {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/matmul_selftest.xdc ];
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftestFasm = mkFasm {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest";
          xdc = task6Int8V10kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V10kL2ResidualAddOutputHeadSelftestJson;
          freqMHz = 50;
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftestBitstream = mkBitstream {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest";
          fasm = task6Int8V10kL2ResidualAddOutputHeadSelftestFasm;
          framesBase = "task6-int8-v10k-l2-residual-add-output-head-selftest";
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftest5MHzFasm = mkFasm {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest-5mhz";
          xdc = task6Int8V10kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V10kL2ResidualAddOutputHeadSelftestJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftest5MHzBitstream = mkBitstream {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest-5mhz";
          fasm = task6Int8V10kL2ResidualAddOutputHeadSelftest5MHzFasm;
          framesBase = "task6-int8-v10k-l2-residual-add-output-head-selftest-5mhz";
        };

        task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugFasm = mkFasm {
          name = "task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug";
          xdc = task6Int8V4kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugJson;
          seed = 2;
          freqMHz = 50;
        };

        task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugBitstream = mkBitstream {
          name = "task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug";
          fasm = task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugFasm;
          framesBase = "task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug";
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugFasm = mkFasm {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug";
          xdc = task6Int8V10kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugJson;
          seed = 2;
          freqMHz = 50;
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugBitstream = mkBitstream {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug";
          fasm = task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugFasm;
          framesBase = "task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug";
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm = mkFasm {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
          xdc = task6Int8V10kL2ResidualAddOutputHeadSelftestXdc;
          json = task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugJson;
          seed = 2;
          freqMHz = 5;
        };

        task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebug5MHzBitstream = mkBitstream {
          name = "task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
          fasm = task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm;
          framesBase = "task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-5mhz";
        };

        task6Int8L2MlpChainResidualAddSelftestDebugFasm = mkFasm {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-debug";
          xdc = task6Int8L2MlpChainResidualAddSelftestXdc;
          json = task6Int8L2MlpChainResidualAddSelftestDebugJson;
          freqMHz = 50;
        };

        task6Int8L2MlpChainResidualAddSelftestDebugBitstream = mkBitstream {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-debug";
          fasm = task6Int8L2MlpChainResidualAddSelftestDebugFasm;
          framesBase = "task6-int8-l2-mlp-chain-residual-add-selftest-debug";
        };

        task6Int8L2MlpChainResidualAddSelftestValueDebugFasm = mkFasm {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-value-debug";
          xdc = task6Int8L2MlpChainResidualAddSelftestXdc;
          json = task6Int8L2MlpChainResidualAddSelftestValueDebugJson;
          freqMHz = 50;
        };

        task6Int8L2MlpChainResidualAddSelftestValueDebugBitstream = mkBitstream {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-value-debug";
          fasm = task6Int8L2MlpChainResidualAddSelftestValueDebugFasm;
          framesBase = "task6-int8-l2-mlp-chain-residual-add-selftest-value-debug";
        };

        task6Int8L2MlpChainResidualAddSelftestCProjDebugFasm = mkFasm {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug";
          xdc = task6Int8L2MlpChainResidualAddSelftestXdc;
          json = task6Int8L2MlpChainResidualAddSelftestCProjDebugJson;
          freqMHz = 50;
        };

        task6Int8L2MlpChainResidualAddSelftestCProjDebugBitstream = mkBitstream {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug";
          fasm = task6Int8L2MlpChainResidualAddSelftestCProjDebugFasm;
          framesBase = "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug";
        };

        task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugFasm = mkFasm {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug";
          xdc = task6Int8L2MlpChainResidualAddSelftestXdc;
          json = task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugJson;
          freqMHz = 50;
        };

        task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugBitstream = mkBitstream {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug";
          fasm = task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugFasm;
          framesBase = "task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug";
        };

        task6Int8L2MlpChainResidualAddSelftestJtagDebugFasm = mkFasm {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug";
          xdc = task6Int8L2MlpChainResidualAddSelftestXdc;
          json = task6Int8L2MlpChainResidualAddSelftestJtagDebugJson;
          freqMHz = 50;
        };

        task6Int8L2MlpChainResidualAddSelftestJtagDebugBitstream = mkBitstream {
          name = "task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug";
          fasm = task6Int8L2MlpChainResidualAddSelftestJtagDebugFasm;
          framesBase = "task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug";
        };

        task6CProjRequantArithSelftestXdc = mkXdc {
          name = "task6-c-proj-requant-arith-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/task6_c_proj_requant_arith_selftest.xdc ];
        };

        task6CProjRequantArithSelftestFasm = mkFasm {
          name = "task6-c-proj-requant-arith-selftest";
          xdc = task6CProjRequantArithSelftestXdc;
          json = task6CProjRequantArithSelftestJson;
          freqMHz = 50;
        };

        task6CProjRequantArithSelftestBitstream = mkBitstream {
          name = "task6-c-proj-requant-arith-selftest";
          fasm = task6CProjRequantArithSelftestFasm;
          framesBase = "task6-c-proj-requant-arith-selftest";
        };

        task6Int8Gemv64Utilization = mkMappedJsonUtilizationReport {
          name = "task6-int8-gemv64";
          capacities = tinyStoriesCapacities;
          topName = "task6_int8_gemv64_kernel";
          designJson = task6Int8Gemv64Json;
        };

        task6Int8Gemv64Lanes4Utilization = mkMappedJsonUtilizationReport {
          name = "task6-int8-gemv64-lanes4";
          capacities = tinyStoriesCapacities;
          topName = "task6_int8_gemv64_lanes4_kernel";
          designJson = task6Int8Gemv64Lanes4Json;
        };

        task6Int8Gemv64Lanes4PackedUtilization = mkMappedJsonUtilizationReport {
          name = "task6-int8-gemv64-lanes4-packed";
          capacities = tinyStoriesCapacities;
          topName = "task6_int8_gemv64_lanes4_packed_kernel";
          designJson = task6Int8Gemv64Lanes4PackedJson;
        };

        task6Int8Gemv64Lanes4PackedSyncMemUtilization = mkMappedJsonUtilizationReport {
          name = "task6-int8-gemv64-lanes4-packed-sync-mem";
          capacities = tinyStoriesCapacities;
          topName = "task6_int8_gemv64_lanes4_packed_sync_mem_kernel";
          designJson = task6Int8Gemv64Lanes4PackedSyncMemJson;
        };

        task6Int8Gemv64x256Lanes4PackedSyncMemUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-gemv64x256-lanes4-packed-sync-mem";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_gemv64x256_lanes4_packed_sync_mem_kernel";
            designJson = task6Int8Gemv64x256Lanes4PackedSyncMemJson;
          };

        task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_gemv64x256_lanes4_packed_sync_mem_local_io_kernel";
            designJson = task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoJson;
          };

        task6Int8L2CFcPostGeluRequantUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-l2-c-fc-post-gelu-requant";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_l2_c_fc_post_gelu_requant_kernel";
            designJson = task6Int8L2CFcPostGeluRequantJson;
          };

        task6Int8L2CProjFromPostGeluUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-l2-c-proj-from-post-gelu";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_l2_c_proj_from_post_gelu_kernel";
            designJson = task6Int8L2CProjFromPostGeluJson;
          };

        task6Int8L2MlpChainPostGeluCProjUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-l2-mlp-chain-post-gelu-c-proj";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_l2_mlp_chain_post_gelu_c_proj_kernel";
            designJson = task6Int8L2MlpChainPostGeluCProjJson;
          };

        task6Int8L2MlpChainCProjRequantUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-l2-mlp-chain-c-proj-requant";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_l2_mlp_chain_post_gelu_c_proj_requant_kernel";
            designJson = task6Int8L2MlpChainCProjRequantJson;
          };

        task6Int8L2MlpChainResidualAddUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-l2-mlp-chain-residual-add";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_l2_mlp_chain_residual_add_kernel";
            designJson = task6Int8L2MlpChainResidualAddJson;
          };

        task6Int8VocabOutputHeadTop1Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-vocab-output-head-top1";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_vocab_output_head_top1_kernel";
            designJson = task6Int8VocabOutputHeadTop1Json;
          };
        task6Int8Vocab10kOutputHeadTop1Utilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-vocab10k-output-head-top1";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_vocab_output_head_top1_kernel";
            designJson = task6Int8Vocab10kOutputHeadTop1Json;
          };

        task6Int8L2MlpChainResidualAddSelftestUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-l2-mlp-chain-residual-add-selftest";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_l2_mlp_chain_residual_add_selftest_top";
            designJson = task6Int8L2MlpChainResidualAddSelftestJson;
          };

        task6Int8V4kL2ResidualAddOutputHeadSelftestUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-v4k-l2-residual-add-output-head-selftest";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_v4k_l2_residual_add_output_head_selftest_top";
            designJson = task6Int8V4kL2ResidualAddOutputHeadSelftestJson;
          };

        task6Int8V10kL2ResidualAddOutputHeadSelftestUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-int8-v10k-l2-residual-add-output-head-selftest";
            capacities = tinyStoriesCapacities;
            topName = "task6_int8_v4k_l2_residual_add_output_head_selftest_top";
            designJson = task6Int8V10kL2ResidualAddOutputHeadSelftestJson;
          };

        task6CProjRequantArithSelftestUtilization =
          mkMappedJsonUtilizationReport {
            name = "task6-c-proj-requant-arith-selftest";
            capacities = tinyStoriesCapacities;
            topName = "task6_c_proj_requant_arith_selftest_top";
            designJson = task6CProjRequantArithSelftestJson;
          };

        task6L1CFcRedirectSimMain = pkgs.runCommand "task6-l1-c-fc-redirect-sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -I${task6L1CFcRedirectTbDataSv} \
            -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
            -f ${task6L1CFcRedirectSv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
        '';
        task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2SimMain =
          pkgs.runCommand
          "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';

        task6L1CProjRedirectSimMain = pkgs.runCommand "task6-l1-c-proj-redirect-sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -I${task6L1CProjRedirectTbDataSv} \
            -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
            -f ${task6L1CProjRedirectSv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
        '';

        task6L1CFcRedirectUi64BufferLiteSimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-ui64-buffer-lite-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectUi64BufferLiteSv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';

        task6L1CFcRedirectUi64BufferFifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-ui64-buffer-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectUi64BufferFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectBuffer165Fifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-buffer165-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectBuffer165Fifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexSpineFifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-spine-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexSpineFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexFanoutFifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-fanout-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexFanoutFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing2Fifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring2-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing2Fifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing3Fifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing3Fifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing3CtrlMergeFifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing3CtrlMergeFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing3Fork49StatevecSimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing3Fork49StatevecSv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing3SelectClusterFifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing3SelectClusterFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing3PostBranchFifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing3PostBranchFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2SimMain = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L1CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';

        task6L2CFcRedirectSimMain = pkgs.runCommand "task6-l2-c-fc-redirect-sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -I${task6L2CFcRedirectTbDataSv} \
            -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
            -f ${task6L2CFcRedirectSv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
        '';
        task6L2CFcRedirectPostBranchFifo2SimMain = pkgs.runCommand
          "task6-l2-c-fc-redirect-postbranch-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L2CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L2CFcRedirectPostBranchFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L2CFcRedirectDownstreamOutBufFifo2SimMain = pkgs.runCommand
          "task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L2CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L2CFcRedirectDownstreamOutBufFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L2CFcRedirectTile4x64SimMain = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile4x64-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L2CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L2CFcRedirectTile4x64Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L2CFcRedirectTile4x64PostBranchOutBufFifo2SimMain = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L2CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Sv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L2CFcRedirectTile64StorepathForkCtrlSimMain = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L2CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L2CFcRedirectTile64StorepathForkCtrlSv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';
        task6L2CFcRedirectTile64StorepathForksSimMain = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile64-storepath-forks-sim-main" {
            buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
          } ''
            set -euo pipefail
            mkdir -p "$out/obj_dir"
            verilator --binary --timing --language 1800-2017 -Wno-fatal \
              -I${task6L2CFcRedirectTbDataSv} \
              -top task6_contract_gemv_tb -Mdir "$out/obj_dir" -o sim_main \
              -f ${task6L2CFcRedirectTile64StorepathForksSv}/sources.f ${./sim/task6_contract_gemv_tb_main.sv}
          '';

        matmulSvSim = pkgs.runCommand "matmul-sv-sim.json" {
          buildInputs = [ pkgs.gawk pkgs.gnugrep ];
        } ''
                    set -euo pipefail
                    ${simMain}/obj_dir/sim_main 2>&1 | tee sim.log
                    pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: expected [0-9]+ got [0-9]+' sim.log | tail -n1 || true)"
                    if [ -z "$pass_line" ]; then
                      echo "SV simulation did not produce a PASS line" >&2
                      exit 1
                    fi
                    expected="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
                    got="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
                    cat > "$out" <<EOF
          {
            "status": "PASS",
            "expected": $expected,
            "got": $got
          }
          EOF
        '';

        task6L0Gemv64SvSim = pkgs.runCommand "task6-l0-gemv64-sv-sim.json" {
          buildInputs = [ pkgs.gawk pkgs.gnugrep ];
        } ''
          set -euo pipefail
          ${task6L0Gemv64SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
          pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
          if [ -z "$pass_line" ]; then
            echo "task6-l0-gemv64 SV simulation did not produce a PASS line" >&2
            exit 1
          fi
          stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
          outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
          cat > "$out" <<EOF
          {
            "status": "PASS",
            "stores": $stores,
            "outputs": $outputs
          }
          EOF
        '';

        task6L1CFcRedirectSvSim = pkgs.runCommand "task6-l1-c-fc-redirect-sv-sim.json" {
          buildInputs = [ pkgs.gawk pkgs.gnugrep ];
        } ''
          set -euo pipefail
          ${task6L1CFcRedirectSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
          pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
          if [ -z "$pass_line" ]; then
            echo "task6-l1-c-fc-redirect SV simulation did not produce a PASS line" >&2
            exit 1
          fi
          stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
          outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
          cat > "$out" <<EOF
          {
            "status": "PASS",
            "stores": $stores,
            "outputs": $outputs
          }
          EOF
        '';

        task6Int8Gemv64SvSim = pkgs.runCommand "task6-int8-gemv64-sv-sim.json" {
          buildInputs = [ pkgs.gawk pkgs.gnugrep ];
        } ''
          set -euo pipefail
          ${task6Int8Gemv64SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
          pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 GEMV stores [0-9]+ outputs [0-9]+ cycles [0-9]+' sim.log | tail -n1 || true)"
          if [ -z "$pass_line" ]; then
            echo "task6-int8-gemv64 SV simulation did not produce a PASS line" >&2
            exit 1
          fi
          stores="$(${pkgs.gawk}/bin/awk '{print $6}' <<<"$pass_line")"
          outputs="$(${pkgs.gawk}/bin/awk '{print $8}' <<<"$pass_line")"
          cycles="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
          cat > "$out" <<EOF
          {
            "status": "PASS",
            "stores": $stores,
            "outputs": $outputs,
            "cycles": $cycles
          }
          EOF
        '';

        task6Int8Gemv64Lanes4SvSim = pkgs.runCommand "task6-int8-gemv64-lanes4-sv-sim.json" {
          buildInputs = [ pkgs.gawk pkgs.gnugrep ];
        } ''
          set -euo pipefail
          ${task6Int8Gemv64Lanes4SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
          pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 GEMV4 stores [0-9]+ outputs [0-9]+ cycles [0-9]+' sim.log | tail -n1 || true)"
          if [ -z "$pass_line" ]; then
            echo "task6-int8-gemv64-lanes4 SV simulation did not produce a PASS line" >&2
            exit 1
          fi
          stores="$(${pkgs.gawk}/bin/awk '{print $6}' <<<"$pass_line")"
          outputs="$(${pkgs.gawk}/bin/awk '{print $8}' <<<"$pass_line")"
          cycles="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
          cat > "$out" <<EOF
          {
            "status": "PASS",
            "stores": $stores,
            "outputs": $outputs,
            "cycles": $cycles
          }
          EOF
        '';

        task6Int8Gemv64Lanes4PackedSvSim =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8Gemv64Lanes4PackedSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 GEMV4 packed stores [0-9]+ outputs [0-9]+ cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-gemv64-lanes4-packed SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $7}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $9}' <<<"$pass_line")"
            cycles="$(${pkgs.gawk}/bin/awk '{print $11}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs,
              "cycles": $cycles
            }
            EOF
          '';

        task6Int8Gemv64Lanes4PackedSyncMemSvSim =
          pkgs.runCommand "task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8Gemv64Lanes4PackedSyncMemSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 GEMV4 syncmem stores [0-9]+ outputs [0-9]+ cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-gemv64-lanes4-packed-sync-mem SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $7}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $9}' <<<"$pass_line")"
            cycles="$(${pkgs.gawk}/bin/awk '{print $11}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs,
              "cycles": $cycles
            }
            EOF
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemSvSim =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8Gemv64x256Lanes4PackedSyncMemSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 GEMV4x256 syncmem stores [0-9]+ outputs [0-9]+ cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-gemv64x256-lanes4-packed-sync-mem SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $7}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $9}' <<<"$pass_line")"
            cycles="$(${pkgs.gawk}/bin/awk '{print $11}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs,
              "cycles": $cycles
            }
            EOF
          '';

        task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoSvSim =
          pkgs.runCommand "task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 GEMV4x256 localio reads [0-9]+ outputs [0-9]+ compute_cycles [0-9]+ total_cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            reads="$(${pkgs.gawk}/bin/awk '{print $7}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $9}' <<<"$pass_line")"
            compute_cycles="$(${pkgs.gawk}/bin/awk '{print $11}' <<<"$pass_line")"
            total_cycles="$(${pkgs.gawk}/bin/awk '{print $13}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "reads": $reads,
              "outputs": $outputs,
              "compute_cycles": $compute_cycles,
              "cycles": $total_cycles
            }
            EOF
          '';

        task6Int8L2CFcContractLocalIoSvSim =
          pkgs.runCommand "task6-int8-l2-c-fc-contract-local-io-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8L2CFcContractLocalIoSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 L2 c_fc localio reads [0-9]+ outputs [0-9]+ compute_cycles [0-9]+ total_cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-l2-c-fc-contract-local-io SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            reads="$(${pkgs.gawk}/bin/awk '{print $8}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            compute_cycles="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            total_cycles="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "reads": $reads,
              "outputs": $outputs,
              "compute_cycles": $compute_cycles,
              "cycles": $total_cycles
            }
            EOF
          '';

        task6Int8L2CFcPostGeluRequantSvSim =
          pkgs.runCommand "task6-int8-l2-c-fc-post-gelu-requant-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8L2CFcPostGeluRequantSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 L2 c_fc postgelu requant reads [0-9]+ outputs [0-9]+ compute_cycles [0-9]+ total_cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-l2-c-fc-post-gelu-requant SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            reads="$(${pkgs.gawk}/bin/awk '{print $9}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $11}' <<<"$pass_line")"
            compute_cycles="$(${pkgs.gawk}/bin/awk '{print $13}' <<<"$pass_line")"
            total_cycles="$(${pkgs.gawk}/bin/awk '{print $15}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "reads": $reads,
              "outputs": $outputs,
              "compute_cycles": $compute_cycles,
              "cycles": $total_cycles
            }
            EOF
          '';

        task6Int8L2CProjFromPostGeluSvSim =
          pkgs.runCommand "task6-int8-l2-c-proj-from-post-gelu-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8L2CProjFromPostGeluSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 L2 c_proj from postgelu reads [0-9]+ outputs [0-9]+ compute_cycles [0-9]+ total_cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-l2-c-proj-from-post-gelu SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            reads="$(${pkgs.gawk}/bin/awk '{print $9}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $11}' <<<"$pass_line")"
            compute_cycles="$(${pkgs.gawk}/bin/awk '{print $13}' <<<"$pass_line")"
            total_cycles="$(${pkgs.gawk}/bin/awk '{print $15}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "reads": $reads,
              "outputs": $outputs,
              "compute_cycles": $compute_cycles,
              "cycles": $total_cycles
            }
            EOF
          '';

        task6Int8L2MlpChainPostGeluCProjSvSim =
          pkgs.runCommand "task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8L2MlpChainPostGeluCProjSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 L2 mlp chain postgelu c_proj reads [0-9]+ outputs [0-9]+ compute_cycles [0-9]+ total_cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-l2-mlp-chain-post-gelu-c-proj SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            reads="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            compute_cycles="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            total_cycles="$(${pkgs.gawk}/bin/awk '{print $16}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "reads": $reads,
              "outputs": $outputs,
              "compute_cycles": $compute_cycles,
              "cycles": $total_cycles
            }
            EOF
          '';

        task6Int8L2MlpChainCProjRequantSvSim =
          pkgs.runCommand "task6-int8-l2-mlp-chain-c-proj-requant-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8L2MlpChainCProjRequantSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 L2 mlp chain c_proj requant reads [0-9]+ outputs [0-9]+ compute_cycles [0-9]+ total_cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-l2-mlp-chain-c-proj-requant SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            reads="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            compute_cycles="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            total_cycles="$(${pkgs.gawk}/bin/awk '{print $16}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "reads": $reads,
              "outputs": $outputs,
              "compute_cycles": $compute_cycles,
              "cycles": $total_cycles
            }
            EOF
          '';

        task6Int8L2MlpChainResidualAddSvSim =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8L2MlpChainResidualAddSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 L2 mlp chain residual add reads [0-9]+ outputs [0-9]+ compute_cycles [0-9]+ total_cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-l2-mlp-chain-residual-add SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            reads="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            compute_cycles="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            total_cycles="$(${pkgs.gawk}/bin/awk '{print $16}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "reads": $reads,
              "outputs": $outputs,
              "compute_cycles": $compute_cycles,
              "cycles": $total_cycles
            }
            EOF
          '';

        task6Int8L2MlpChainResidualAddSelftestSvSim =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8L2MlpChainResidualAddSelftestSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 L2 residual add selftest led_pass cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-l2-mlp-chain-residual-add-selftest SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            cycles="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "cycles": $cycles
            }
            EOF
          '';

        task6Int8V4kL2ResidualAddOutputHeadSelftestSvSim =
          pkgs.runCommand "task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8V4kL2ResidualAddOutputHeadSelftestSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 v4k residual output-head selftest led_pass cycles [0-9]+ top_index [0-9]+ top_acc -?[0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-v4k-l2-residual-add-output-head-selftest SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            cycles="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            top_index="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            top_acc="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "cycles": $cycles,
              "top_index": $top_index,
              "top_acc": $top_acc
            }
            EOF
          '';

        task6Int8V10kL2ResidualAddOutputHeadSelftestSvSim =
          pkgs.runCommand "task6-int8-v10k-l2-residual-add-output-head-selftest-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Int8V10kL2ResidualAddOutputHeadSelftestSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 v4k residual output-head selftest led_pass cycles [0-9]+ top_index [0-9]+ top_acc -?[0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-int8-v10k-l2-residual-add-output-head-selftest SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            cycles="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            top_index="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            top_acc="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "cycles": $cycles,
              "top_index": $top_index,
              "top_acc": $top_acc
            }
            EOF
          '';

        task6TernaryV9984L2ResidualAddOutputHeadSelftestSvSim =
          pkgs.runCommand "task6-ternary-v9984-l2-residual-add-output-head-selftest-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6TernaryV9984L2ResidualAddOutputHeadSelftestSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 v4k residual output-head selftest led_pass cycles [0-9]+ top_index [0-9]+ top_acc -?[0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-ternary-v9984-l2-residual-add-output-head-selftest SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            cycles="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            top_index="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            top_acc="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "cycles": $cycles,
              "top_index": $top_index,
              "top_acc": $top_acc
            }
            EOF
          '';

        task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestSvSim =
          pkgs.runCommand "task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 int8 v4k residual output-head selftest led_pass cycles [0-9]+ top_index [0-9]+ top_acc -?[0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-ternary-base3-v10k-l2-residual-add-output-head-selftest SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            cycles="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            top_index="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            top_acc="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "cycles": $cycles,
              "top_index": $top_index,
              "top_acc": $top_acc
            }
            EOF
          '';

        task6Ddr3RowStreamCutoutSvSim =
          pkgs.runCommand "h2-ddr3-row-stream-cutout-rtl-proof.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6Ddr3RowStreamCutoutSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 ddr3 rowstream top1 cutout samples [0-9]+ rows_per_sample [0-9]+ total_rows [0-9]+ cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6 DDR3 rowstream cutout SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            samples="$(${pkgs.gawk}/bin/awk '{print $8}' <<<"$pass_line")"
            rows_per_sample="$(${pkgs.gawk}/bin/awk '{print $10}' <<<"$pass_line")"
            total_rows="$(${pkgs.gawk}/bin/awk '{print $12}' <<<"$pass_line")"
            cycles="$(${pkgs.gawk}/bin/awk '{print $14}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "artifact_name": "h2-ddr3-row-stream-cutout-rtl-proof",
              "status": "PASS",
              "date": "2026-04-30",
              "hypothesis": "A DDR-free RTL cutout can consume the packed full-vocab rowstream through a synthetic source, compute int8 dot products, and match the rowwise Q0.24 top1 replay.",
              "source_artifacts": {
                "baseline_bundle": "artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization",
                "ddr3_row_stream_interface_contract": "artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-interface-contract.json",
                "rowstream_pack_replay": "artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-pack-replay/summary.json",
                "rowstream_bin": "artifacts/task6/parallel-hypotheses/h2-ddr3-row-stream-pack-replay/rowstream.bin"
              },
              "metrics": {
                "sample_count": $samples,
                "rows_per_sample": $rows_per_sample,
                "total_rows_streamed": $total_rows,
                "cycles": $cycles
              },
              "validation": {
                "python_run": true,
                "simulation_run": true,
                "synthesis_run": false,
                "hardware_run": false,
                "validation_kind": "ddr-free-rowstream-rtl-cutout"
              },
              "decision": {
                "verdict": "promote-rtl-rowstream-cutout",
                "next_gate": "Integrate a measured DDR3 linear-read source for the same rowstream contract."
              }
            }
            EOF
          '';

        task6CProjRequantArithSelftestSvSim =
          pkgs.runCommand "task6-c-proj-requant-arith-selftest-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6CProjRequantArithSelftestSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: task6 c_proj requant arithmetic selftest cycles [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-c-proj-requant-arith-selftest SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            cycles="$(${pkgs.gawk}/bin/awk '{print $8}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "cycles": $cycles
            }
            EOF
          '';

        task6Int8L2CFcPostGeluRequantRtlProof =
          pkgs.runCommand "task6-int8-l2-c-fc-post-gelu-requant-rtl-proof" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_c_fc_post_gelu_requant_tb_data.py \
              --contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --downstream-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-downstream-int8-boundary.json
              } \
              --sim-result-json ${task6Int8L2CFcPostGeluRequantSvSim} \
              --yosys-stat-json ${task6Int8L2CFcPostGeluRequantYosysStat} \
              --mapped-utilization-summary-json ${task6Int8L2CFcPostGeluRequantUtilization}/summary.json \
              --out-json "$out/summary.json"
          '';

        task6Int8L2MlpChainPostGeluCProjRtlProof =
          pkgs.runCommand "task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_mlp_chain_post_gelu_c_proj_tb_data.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --sim-result-json ${task6Int8L2MlpChainPostGeluCProjSvSim} \
              --yosys-stat-json ${task6Int8L2MlpChainPostGeluCProjYosysStat} \
              --mapped-utilization-summary-json ${task6Int8L2MlpChainPostGeluCProjUtilization}/summary.json \
              --out-json "$out/summary.json"
          '';

        task6Int8L2MlpChainCProjRequantRtlProof =
          pkgs.runCommand "task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_mlp_chain_c_proj_requant_tb_data.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-output-boundary.json
              } \
              --sim-result-json ${task6Int8L2MlpChainCProjRequantSvSim} \
              --yosys-stat-json ${task6Int8L2MlpChainCProjRequantYosysStat} \
              --mapped-utilization-summary-json ${task6Int8L2MlpChainCProjRequantUtilization}/summary.json \
              --out-json "$out/summary.json"
          '';

        task6Int8L2ResidualAddBoundaryScout =
          pkgs.runCommand "task6-int8-l2-residual-add-boundary-scout" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/trace_int8_residual_add_boundary.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-candidate-json ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --out-json "$out/summary.json"
          '';

        task6Int8L2ResidualAddContract =
          pkgs.runCommand "task6-int8-l2-residual-add-contract" { } ''
            mkdir -p "$out"
            ${pythonWithTinyStoriesBin}/bin/python ${
              ./scripts/task6
            }/export_residual_add_contract.py \
              --model-path ${tinyStories1m.snapshot} \
              --output-dir "$out" \
              --adapter-path ${./TinyStories/model_adapter_representative_core.py} \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --vocab-size 1024 \
              --num-layers 1 \
              --max-position-embeddings 128 \
              --window-size 64 \
              --hidden-size 64 \
              --num-heads 16 \
              --token-id 0 \
              --model-label tiny-stories-v1k-h64-l1
          '';

        task6Int8L2ResidualAddBoundary =
          pkgs.runCommand "task6-int8-l2-residual-add-boundary" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./scripts/task6
            }/score_int8_residual_add_boundary.py \
              --residual-contract-manifest ${task6Int8L2ResidualAddContract}/manifest.json \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --out-json "$out/summary.json"
          '';

        task6Int8L2MlpChainResidualAddRtlProof =
          pkgs.runCommand "task6-int8-l2-mlp-chain-residual-add-rtl-proof" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_mlp_chain_residual_add_tb_data.py \
              --residual-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-residual-add-contract
              }/manifest.json \
              --residual-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-residual-add-boundary.json
              } \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --c-proj-output-boundary-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-proj-output-boundary.json
              } \
              --c-proj-requant-rtl-proof-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-mlp-chain-c-proj-requant-rtl-proof.json
              } \
              --sim-result-json ${task6Int8L2MlpChainResidualAddSvSim} \
              --yosys-stat-json ${task6Int8L2MlpChainResidualAddYosysStat} \
              --mapped-utilization-summary-json ${task6Int8L2MlpChainResidualAddUtilization}/summary.json \
              --out-json "$out/summary.json"
          '';

        task6Int8L2CProjFromPostGeluRtlProof =
          pkgs.runCommand "task6-int8-l2-c-proj-from-post-gelu-rtl-proof" { } ''
            mkdir -p "$out"
            ${pkgs.python3}/bin/python ${
              ./sim
            }/gen_task6_int8_l2_c_proj_from_post_gelu_tb_data.py \
              --c-fc-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_fc-contract
              }/manifest.json \
              --c-fc-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_fc
              }/manifest.json \
              --c-proj-contract-manifest ${
                ./artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract
              }/manifest.json \
              --c-proj-weight-pack-manifest ${
                ./artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj
              }/manifest.json \
              --post-gelu-requant-json ${
                ./artifacts/task6/parallel-hypotheses/h2-int8-l2-c-fc-post-gelu-requant-rtl-proof.json
              } \
              --sim-result-json ${task6Int8L2CProjFromPostGeluSvSim} \
              --yosys-stat-json ${task6Int8L2CProjFromPostGeluYosysStat} \
              --mapped-utilization-summary-json ${task6Int8L2CProjFromPostGeluUtilization}/summary.json \
              --out-json "$out/summary.json"
          '';

        task6L1CProjRedirectSvSim = pkgs.runCommand "task6-l1-c-proj-redirect-sv-sim.json" {
          buildInputs = [ pkgs.gawk pkgs.gnugrep ];
        } ''
          set -euo pipefail
          ${task6L1CProjRedirectSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
          pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
          if [ -z "$pass_line" ]; then
            echo "task6-l1-c-proj-redirect SV simulation did not produce a PASS line" >&2
            exit 1
          fi
          stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
          outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
          cat > "$out" <<EOF
          {
            "status": "PASS",
            "stores": $stores,
            "outputs": $outputs
          }
          EOF
        '';

        task6L1CFcRedirectUi64BufferLiteSvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectUi64BufferLiteSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-ui64-buffer-lite SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';

        task6L1CFcRedirectUi64BufferFifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectUi64BufferFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-ui64-buffer-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectBuffer165Fifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectBuffer165Fifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-buffer165-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexSpineFifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexSpineFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-spine-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexFanoutFifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexFanoutFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-fanout-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing2Fifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing2Fifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring2-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing3Fifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing3Fifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring3-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing3CtrlMergeFifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing3CtrlMergeFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing3Fork49StatevecSvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing3Fork49StatevecSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring3-fork49-statevec SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing3SelectClusterFifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing3SelectClusterFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing3PostBranchFifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing3PostBranchFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2SvSim = pkgs.runCommand
          "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2SvSim =
          pkgs.runCommand
          "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';

        task6L2CFcRedirectSvSim = pkgs.runCommand "task6-l2-c-fc-redirect-sv-sim.json" {
          buildInputs = [ pkgs.gawk pkgs.gnugrep ];
        } ''
          set -euo pipefail
          ${task6L2CFcRedirectSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
          pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
          if [ -z "$pass_line" ]; then
            echo "task6-l2-c-fc-redirect SV simulation did not produce a PASS line" >&2
            exit 1
          fi
          stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
          outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
          cat > "$out" <<EOF
          {
            "status": "PASS",
            "stores": $stores,
            "outputs": $outputs
          }
          EOF
        '';
        task6L2CFcRedirectPostBranchFifo2SvSim = pkgs.runCommand
          "task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L2CFcRedirectPostBranchFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l2-c-fc-redirect-postbranch-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L2CFcRedirectDownstreamOutBufFifo2SvSim = pkgs.runCommand
          "task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L2CFcRedirectDownstreamOutBufFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l2-c-fc-redirect-downstream-outbuf-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L2CFcRedirectTile4x64SvSim = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile4x64-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L2CFcRedirectTile4x64SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l2-c-fc-redirect-tile4x64 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L2CFcRedirectTile4x64PostBranchOutBufFifo2SvSim = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L2CFcRedirectTile4x64PostBranchOutBufFifo2SimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2 SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L2CFcRedirectTile64StorepathForkCtrlSvSim = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L2CFcRedirectTile64StorepathForkCtrlSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l2-c-fc-redirect-tile64-storepath-forkctrl SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';
        task6L2CFcRedirectTile64StorepathForksSvSim = pkgs.runCommand
          "task6-l2-c-fc-redirect-tile64-storepath-forks-sv-sim.json" {
            buildInputs = [ pkgs.gawk pkgs.gnugrep ];
          } ''
            set -euo pipefail
            ${task6L2CFcRedirectTile64StorepathForksSimMain}/obj_dir/sim_main 2>&1 | tee sim.log
            pass_line="$(${pkgs.gnugrep}/bin/grep -Eo 'PASS: stores [0-9]+ outputs [0-9]+' sim.log | tail -n1 || true)"
            if [ -z "$pass_line" ]; then
              echo "task6-l2-c-fc-redirect-tile64-storepath-forks SV simulation did not produce a PASS line" >&2
              exit 1
            fi
            stores="$(${pkgs.gawk}/bin/awk '{print $3}' <<<"$pass_line")"
            outputs="$(${pkgs.gawk}/bin/awk '{print $5}' <<<"$pass_line")"
            cat > "$out" <<EOF
            {
              "status": "PASS",
              "stores": $stores,
              "outputs": $outputs
            }
            EOF
          '';

        matmulSvWave = pkgs.runCommand "matmul-wave.vcd" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p obj_dir
          verilator --binary --trace -DENABLE_WAVES -DENABLE_WAVES_VCD --timing --language 1800-2017 -Wno-fatal \
            -I${tbDataSv} \
            -top tb -Mdir obj_dir -o sim_main \
            -f ${matmulSv}/sources.f ${./sim/tb_main.sv}
          ./obj_dir/sim_main
          if [ ! -f wave.vcd ]; then
            echo "wave.vcd was not produced by simulation" >&2
            exit 1
          fi
          cp wave.vcd "$out"
        '';

        task6L0Gemv64SvWave = pkgs.runCommand "task6-l0-gemv64-wave.vcd" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p obj_dir
          verilator --binary --trace -DENABLE_WAVES -DENABLE_WAVES_VCD --timing --language 1800-2017 -Wno-fatal \
            -I${task6L0Gemv64TbDataSv} \
            -top task6_l0_gemv64_tb -Mdir obj_dir -o sim_main \
            -f ${task6L0Gemv64Sv}/sources.f ${./sim/task6_l0_gemv64_tb_main.sv}
          ./obj_dir/sim_main
          if [ ! -f wave.vcd ]; then
            echo "wave.vcd was not produced by task6-l0-gemv64 simulation" >&2
            exit 1
          fi
          cp wave.vcd "$out"
        '';

      in {
        devShells.default = pkgs.mkShell {
          packages = [
            mlir
            circt
            yosysPkg
            torchMlir
            torchMlirPatched
            llvmPackages.clang
            llvmPackages.llvm
            pythonWithTorch
            pythonWithTorchAO
            pythonWithTinyStories
            pythonWithTinyStoriesTorchAO
            yosysSlang
            openXC7Nextpnr
            openXC7Prjxray
            openXC7Fasm
            prjxrayPythonDeps
            pkgs.cmake
            pkgs.ninja
            pkgs.gtkwave
            pkgs.nixfmt-classic
            pkgs.rr
          ];
          shellHook = ''
            export NEXTPNR_XILINX_DIR="${openXC7Nextpnr}/share/nextpnr"
            export NEXTPNR_XILINX_PYTHON_DIR="${openXC7Nextpnr}/share/nextpnr/python"
            export PRJXRAY_DB_DIR="${fpgaPrjxrayDb}"
            export PRJXRAY_PYTHON_DIR="${openXC7Prjxray}/usr/share/python3"
            export PYTHONPATH="${prjxrayPythonPath}''${PYTHONPATH:+:$PYTHONPATH}"
          '';
        };

        formatter = pkgs.nixfmt-classic;

        packages = {
          default = matmulSv;
          inherit torchao;
          torch-mlir = torchMlir;
          torch-mlir-patched = torchMlirPatched;
          torch-mlir-unpatched = torchMlirUnpatched;
          python-with-torchao = pythonWithTorchAO;
          python-with-tiny-stories = pythonWithTinyStories;
          python-with-tiny-stories-bin = pythonWithTinyStoriesBin;
          python-with-tiny-stories-torchao = pythonWithTinyStoriesTorchAO;
          model-registry = modelRegistryJson;
          tiny-stories-1m-snapshot = tinyStories1m.snapshot;
          tb-data-sv = tbDataSv;
          sim-main = simMain;
          matmul-sv-sim = matmulSvSim;
          matmul-sv-wave = matmulSvWave;
          task6-l0-gemv64-tb-data-sv = task6L0Gemv64TbDataSv;
          task6-l0-gemv64-sim-main = task6L0Gemv64SimMain;
          task6-l0-gemv64-yosys-stat = task6L0Gemv64YosysStat;
          task6-l0-gemv64-json = task6L0Gemv64Json;
          task6-l0-gemv64-utilization = task6L0Gemv64Utilization;
          task6-l0-gemv64-abc9-json = task6L0Gemv64Abc9Json;
          task6-l0-gemv64-abc9-utilization = task6L0Gemv64Abc9Utilization;
          task6-l0-gemv64-int16-json = task6L0Gemv64Int16Json;
          task6-l0-gemv64-int16-utilization = task6L0Gemv64Int16Utilization;
          task6-l0-gemv64-sv-sim = task6L0Gemv64SvSim;
          task6-l0-gemv64-sv-wave = task6L0Gemv64SvWave;
          task6-int8-gemv64-sim-main = task6Int8Gemv64SimMain;
          task6-int8-gemv64-sv-sim = task6Int8Gemv64SvSim;
          task6-int8-gemv64-yosys-stat = task6Int8Gemv64YosysStat;
          task6-int8-gemv64-json = task6Int8Gemv64Json;
          task6-int8-gemv64-utilization = task6Int8Gemv64Utilization;
          task6-int8-gemv64-lanes4-sim-main = task6Int8Gemv64Lanes4SimMain;
          task6-int8-gemv64-lanes4-sv-sim = task6Int8Gemv64Lanes4SvSim;
          task6-int8-gemv64-lanes4-yosys-stat = task6Int8Gemv64Lanes4YosysStat;
          task6-int8-gemv64-lanes4-json = task6Int8Gemv64Lanes4Json;
          task6-int8-gemv64-lanes4-utilization = task6Int8Gemv64Lanes4Utilization;
          task6-int8-gemv64-lanes4-packed-sim-main = task6Int8Gemv64Lanes4PackedSimMain;
          task6-int8-gemv64-lanes4-packed-sv-sim = task6Int8Gemv64Lanes4PackedSvSim;
          task6-int8-gemv64-lanes4-packed-yosys-stat = task6Int8Gemv64Lanes4PackedYosysStat;
          task6-int8-gemv64-lanes4-packed-json = task6Int8Gemv64Lanes4PackedJson;
          task6-int8-gemv64-lanes4-packed-utilization = task6Int8Gemv64Lanes4PackedUtilization;
          task6-int8-gemv64-lanes4-packed-sync-mem-sim-main =
            task6Int8Gemv64Lanes4PackedSyncMemSimMain;
          task6-int8-gemv64-lanes4-packed-sync-mem-sv-sim =
            task6Int8Gemv64Lanes4PackedSyncMemSvSim;
          task6-int8-gemv64-lanes4-packed-sync-mem-yosys-stat =
            task6Int8Gemv64Lanes4PackedSyncMemYosysStat;
          task6-int8-gemv64-lanes4-packed-sync-mem-json =
            task6Int8Gemv64Lanes4PackedSyncMemJson;
          task6-int8-gemv64-lanes4-packed-sync-mem-utilization =
            task6Int8Gemv64Lanes4PackedSyncMemUtilization;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-sim-main =
            task6Int8Gemv64x256Lanes4PackedSyncMemSimMain;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-sv-sim =
            task6Int8Gemv64x256Lanes4PackedSyncMemSvSim;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-yosys-stat =
            task6Int8Gemv64x256Lanes4PackedSyncMemYosysStat;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-json =
            task6Int8Gemv64x256Lanes4PackedSyncMemJson;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-utilization =
            task6Int8Gemv64x256Lanes4PackedSyncMemUtilization;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-sim-main =
            task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoSimMain;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-sv-sim =
            task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoSvSim;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-yosys-stat =
            task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoYosysStat;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-json =
            task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoJson;
          task6-int8-gemv64x256-lanes4-packed-sync-mem-local-io-utilization =
            task6Int8Gemv64x256Lanes4PackedSyncMemLocalIoUtilization;
          task6-int8-l2-c-fc-contract-local-io-tb-data-sv =
            task6Int8L2CFcContractLocalIoTbDataSv;
          task6-int8-l2-c-fc-contract-local-io-sim-main =
            task6Int8L2CFcContractLocalIoSimMain;
          task6-int8-l2-c-fc-contract-local-io-sv-sim =
            task6Int8L2CFcContractLocalIoSvSim;
          task6-int8-l2-c-fc-scale-bias-output-boundary =
            task6Int8L2CFcScaleBiasOutputBoundary;
          task6-int8-l2-c-fc-downstream-int8-boundary =
            task6Int8L2CFcDownstreamInt8Boundary;
          task6-int8-l2-c-proj-from-post-gelu-boundary =
            task6Int8L2CProjFromPostGeluBoundary;
          task6-int8-l2-c-proj-output-boundary =
            task6Int8L2CProjOutputBoundary;
          task6-int8-l2-c-proj-from-post-gelu-tb-data-sv =
            task6Int8L2CProjFromPostGeluTbDataSv;
          task6-int8-l2-c-proj-from-post-gelu-sim-main =
            task6Int8L2CProjFromPostGeluSimMain;
          task6-int8-l2-c-proj-from-post-gelu-sv-sim =
            task6Int8L2CProjFromPostGeluSvSim;
          task6-int8-l2-c-proj-from-post-gelu-yosys-stat =
            task6Int8L2CProjFromPostGeluYosysStat;
          task6-int8-l2-c-proj-from-post-gelu-json =
            task6Int8L2CProjFromPostGeluJson;
          task6-int8-l2-c-proj-from-post-gelu-utilization =
            task6Int8L2CProjFromPostGeluUtilization;
          task6-int8-l2-c-proj-from-post-gelu-rtl-proof =
            task6Int8L2CProjFromPostGeluRtlProof;
          task6-int8-l2-mlp-chain-post-gelu-c-proj-tb-data-sv =
            task6Int8L2MlpChainPostGeluCProjTbDataSv;
          task6-int8-l2-mlp-chain-post-gelu-c-proj-sim-main =
            task6Int8L2MlpChainPostGeluCProjSimMain;
          task6-int8-l2-mlp-chain-post-gelu-c-proj-sv-sim =
            task6Int8L2MlpChainPostGeluCProjSvSim;
          task6-int8-l2-mlp-chain-post-gelu-c-proj-yosys-stat =
            task6Int8L2MlpChainPostGeluCProjYosysStat;
          task6-int8-l2-mlp-chain-post-gelu-c-proj-json =
            task6Int8L2MlpChainPostGeluCProjJson;
          task6-int8-l2-mlp-chain-post-gelu-c-proj-utilization =
            task6Int8L2MlpChainPostGeluCProjUtilization;
          task6-int8-l2-mlp-chain-post-gelu-c-proj-rtl-proof =
            task6Int8L2MlpChainPostGeluCProjRtlProof;
          task6-int8-l2-mlp-chain-c-proj-requant-tb-data-sv =
            task6Int8L2MlpChainCProjRequantTbDataSv;
          task6-int8-l2-mlp-chain-c-proj-requant-sim-main =
            task6Int8L2MlpChainCProjRequantSimMain;
          task6-int8-l2-mlp-chain-c-proj-requant-sv-sim =
            task6Int8L2MlpChainCProjRequantSvSim;
          task6-int8-l2-mlp-chain-c-proj-requant-yosys-stat =
            task6Int8L2MlpChainCProjRequantYosysStat;
          task6-int8-l2-mlp-chain-c-proj-requant-json =
            task6Int8L2MlpChainCProjRequantJson;
          task6-int8-l2-mlp-chain-c-proj-requant-utilization =
            task6Int8L2MlpChainCProjRequantUtilization;
          task6-int8-l2-mlp-chain-c-proj-requant-rtl-proof =
            task6Int8L2MlpChainCProjRequantRtlProof;
          task6-int8-l2-mlp-chain-residual-add-tb-data-sv =
            task6Int8L2MlpChainResidualAddTbDataSv;
          task6-int8-l2-mlp-chain-residual-add-sim-main =
            task6Int8L2MlpChainResidualAddSimMain;
          task6-int8-l2-mlp-chain-residual-add-sv-sim =
            task6Int8L2MlpChainResidualAddSvSim;
          task6-int8-l2-mlp-chain-residual-add-yosys-stat =
            task6Int8L2MlpChainResidualAddYosysStat;
          task6-int8-l2-mlp-chain-residual-add-json =
            task6Int8L2MlpChainResidualAddJson;
          task6-int8-l2-mlp-chain-residual-add-utilization =
            task6Int8L2MlpChainResidualAddUtilization;
          task6-int8-l2-mlp-chain-residual-add-rtl-proof =
            task6Int8L2MlpChainResidualAddRtlProof;
          task6-int8-vocab-output-head-top1-yosys-stat =
            task6Int8VocabOutputHeadTop1YosysStat;
          task6-int8-vocab-output-head-top1-json =
            task6Int8VocabOutputHeadTop1Json;
          task6-int8-vocab-output-head-top1-utilization =
            task6Int8VocabOutputHeadTop1Utilization;
          task6-int8-vocab10k-output-head-top1-json =
            task6Int8Vocab10kOutputHeadTop1Json;
          task6-int8-vocab10k-output-head-top1-utilization =
            task6Int8Vocab10kOutputHeadTop1Utilization;
          task6-full-vocab-rowwise-topk-replay =
            task6FullVocabRowwiseTopkReplay;
          task6-ddr3-row-stream-interface-contract =
            task6Ddr3RowStreamInterfaceContract;
          task6-ddr3-row-stream-pack-replay =
            task6Ddr3RowStreamPackReplay;
          task6-ddr3-row-stream-cutout-tb-data =
            task6Ddr3RowStreamCutoutTbData;
          task6-ddr3-row-stream-cutout-sim-main =
            task6Ddr3RowStreamCutoutSimMain;
          task6-ddr3-row-stream-cutout-sv-sim =
            task6Ddr3RowStreamCutoutSvSim;
          task6-ddr3-board-support-inventory =
            task6Ddr3BoardSupportInventory;
          task6-ypcb-ddr3-lane-report =
            task6YpcbDdr3LaneReport;
          task6-litex-boards-ypcb-master =
            task6LitexBoardsYpcbMasterRunner;
          task6-litex-boards-ypcb-validated =
            task6LitexBoardsYpcbValidatedRunner;
          task6-litex-boards-ypcb-jtag-only =
            task6LitexBoardsYpcbJtagOnlyRunner;
          task6-litex-boards-ypcb-master-help =
            task6LitexBoardsYpcbMasterHelp;
          task6-litex-boards-ypcb-validated-help =
            task6LitexBoardsYpcbValidatedHelp;
          task6-litedram-open-controller-probe =
            task6LiteDramOpenControllerProbe;
          task6-ypcb-litedram-config =
            task6YpcbLiteDramConfig;
          task6-ypcb-litedram-no-odelay-config =
            task6YpcbLiteDramNoOdelayConfig;
          task6-ypcb-litedram-no-odelay-lowrate-config =
            task6YpcbLiteDramNoOdelayLowrateConfig;
          task6-ypcb-litedram-rtl-elaboration =
            task6YpcbLiteDramRtlElaboration;
          task6-ypcb-litedram-no-odelay-rtl-elaboration =
            task6YpcbLiteDramNoOdelayRtlElaboration;
          task6-ypcb-litedram-no-odelay-lowrate-rtl-elaboration =
            task6YpcbLiteDramNoOdelayLowrateRtlElaboration;
          task6-ypcb-litedram-no-odelay-lowrate-dqs0-rtl-elaboration =
            task6YpcbLiteDramNoOdelayLowrateDqs0RtlElaboration;
          task6-ypcb-litedram-no-odelay-rtl-check =
            task6YpcbLiteDramNoOdelayRtlCheck;
          task6-ypcb-litedram-no-odelay-lowrate-rtl-check =
            task6YpcbLiteDramNoOdelayLowrateRtlCheck;
          task6-ypcb-litedram-no-odelay-lowrate-dqs0-rtl-check =
            task6YpcbLiteDramNoOdelayLowrateDqs0RtlCheck;
          task6-ypcb-uberddr3-bist-yosys-json =
            task6YpcbUberDdr3BistYosysJson;
          task6-ypcb-uberddr3-bist-xdc =
            task6YpcbUberDdr3BistXdc;
          task6-ypcb-uberddr3-bist-fasm =
            task6YpcbUberDdr3BistFasm;
          task6-ypcb-uberddr3-bist-bitstream =
            task6YpcbUberDdr3BistBitstream;
          task6-ypcb-litedram-open-synth-json =
            task6YpcbLiteDramOpenSynthJson;
          task6-ypcb-litedram-open-synth-utilization =
            task6YpcbLiteDramOpenSynthUtilization;
          task6-ypcb-litedram-init-bandwidth-probe-json =
            task6YpcbLiteDramInitBandwidthProbeJson;
          task6-ypcb-litedram-init-bandwidth-probe-utilization =
            task6YpcbLiteDramInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-init-status-only-chain0-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-json =
            task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeJson;
          task6-ypcb-litedram-no-odelay-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeUtilization;
          task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-utilization =
            task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeUtilization;
          task6-ypcb-litedram-init-bandwidth-probe-xdc =
            task6YpcbLiteDramInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeXdc;
          task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-xdc =
            task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeXdc;
          task6-ypcb-litedram-init-bandwidth-probe-fasm =
            task6YpcbLiteDramInitBandwidthProbeFasm;
          task6-ypcb-litedram-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-init-status-only-chain0-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-fasm =
            task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeFasm;
          task6-ypcb-litedram-no-odelay-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-dqs0-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateDqs0InitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-nowrite-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateNoWriteInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-phase-matrix-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowratePhaseMatrixInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-source-command-matrix-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateSourceCommandMatrixInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-source-order-matrix-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateSourceOrderMatrixInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-byte-phase-assoc-matrix-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateBytePhaseAssocMatrixInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-init-status-only-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-init-status-only-chain0-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateInitStatusOnlyChain0InitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-half-order-matrix-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateHalfOrderMatrixInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-displacement-map-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateDisplacementMapInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-csr-echo-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateCsrEchoInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-wbitslip-sweep-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateWbitslipSweepInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-rbitslip-sweep-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateRbitslipSweepInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-map-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeMapInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-bist-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompBistInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-readscan-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeReadscanInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-expected-read-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeExpectedReadInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-packing-classifier-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativePackingClassifierInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-address-classifier-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeAddressClassifierInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-edge-comp-addrwalk-native-cmdaddr-trace-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeBitstream;
          task6-ypcb-litedram-no-odelay-lowrate-lane7-locator-init-bandwidth-probe-bitstream =
            task6YpcbLiteDramNoOdelayLowrateLane7LocatorInitBandwidthProbeBitstream;
          task6-ypcb-litedram-init-bandwidth-probe-iopad-json =
            task6YpcbLiteDramInitBandwidthProbeIopadJson;
          task6-ypcb-litedram-init-bandwidth-probe-iopad-fasm =
            task6YpcbLiteDramInitBandwidthProbeIopadFasm;
          task6-ypcb-litedram-init-bandwidth-probe-iopad-bitstream =
            task6YpcbLiteDramInitBandwidthProbeIopadBitstream;
          task6-odelay-obuf-cutout-json =
            task6OdelayObufCutoutJson;
          task6-odelay-obuf-cutout-fasm =
            task6OdelayObufCutoutFasm;
          task6-odelay-obufds-cutout-json =
            task6OdelayObufdsCutoutJson;
          task6-odelay-obufds-cutout-fasm =
            task6OdelayObufdsCutoutFasm;
          task6-no-odelay-obuf-cutout-json =
            task6NoOdelayObufCutoutJson;
          task6-no-odelay-obuf-cutout-fasm =
            task6NoOdelayObufCutoutFasm;
          task6-no-odelay-obufds-cutout-json =
            task6NoOdelayObufdsCutoutJson;
          task6-no-odelay-obufds-cutout-fasm =
            task6NoOdelayObufdsCutoutFasm;
          task6-int8-l2-mlp-chain-residual-add-selftest-top =
            task6Int8L2MlpChainResidualAddSelftestTop;
          task6-int8-l2-mlp-chain-residual-add-selftest-sim-main =
            task6Int8L2MlpChainResidualAddSelftestSimMain;
          task6-int8-l2-mlp-chain-residual-add-selftest-sv-sim =
            task6Int8L2MlpChainResidualAddSelftestSvSim;
          task6-int8-l2-mlp-chain-residual-add-selftest-json =
            task6Int8L2MlpChainResidualAddSelftestJson;
          task6-int8-l2-mlp-chain-residual-add-selftest-debug-json =
            task6Int8L2MlpChainResidualAddSelftestDebugJson;
          task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-json =
            task6Int8L2MlpChainResidualAddSelftestValueDebugJson;
          task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-json =
            task6Int8L2MlpChainResidualAddSelftestCProjDebugJson;
          task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-json =
            task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugJson;
          task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug-json =
            task6Int8L2MlpChainResidualAddSelftestJtagDebugJson;
          task6-int8-l2-mlp-chain-residual-add-selftest-utilization =
            task6Int8L2MlpChainResidualAddSelftestUtilization;
          task6-int8-l2-mlp-chain-residual-add-selftest-xdc =
            task6Int8L2MlpChainResidualAddSelftestXdc;
          task6-int8-l2-mlp-chain-residual-add-selftest-fasm =
            task6Int8L2MlpChainResidualAddSelftestFasm;
          task6-int8-l2-mlp-chain-residual-add-selftest-bitstream =
            task6Int8L2MlpChainResidualAddSelftestBitstream;
          task6-int8-v4k-l2-residual-add-output-head-selftest-tb-data-sv =
            task6Int8V4kL2ResidualAddOutputHeadSelftestTbDataSv;
          task6-int8-v4k-l2-residual-add-output-head-selftest-top =
            task6Int8V4kL2ResidualAddOutputHeadSelftestTop;
          task6-int8-v4k-l2-residual-add-output-head-selftest-sim-main =
            task6Int8V4kL2ResidualAddOutputHeadSelftestSimMain;
          task6-int8-v4k-l2-residual-add-output-head-selftest-sv-sim =
            task6Int8V4kL2ResidualAddOutputHeadSelftestSvSim;
          task6-int8-v10k-l2-residual-add-output-head-selftest-tb-data-sv =
            task6Int8V10kL2ResidualAddOutputHeadSelftestTbDataSv;
          task6-int8-v10k-l2-residual-add-output-head-selftest-top =
            task6Int8V10kL2ResidualAddOutputHeadSelftestTop;
          task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-tb-data-sv =
            task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTbDataSv;
          task6-output-head-v10k-quantization-sweep =
            task6OutputHeadV10kQuantizationSweep;
          task6-output-head-v10k-multisample-quantization-sweep =
            task6OutputHeadV10kMultisampleQuantizationSweep;
          task6-output-head-full-pretrained-multisample-quantization-sweep =
            task6OutputHeadFullPretrainedMultisampleQuantizationSweep;
          task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-top =
            task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestTop;
          task6-int8-v6k-l2-residual-add-output-head-selftest-tb-data-sv =
            task6Int8V6kL2ResidualAddOutputHeadSelftestTbDataSv;
          task6-int8-v6k-l2-residual-add-output-head-selftest-top =
            task6Int8V6kL2ResidualAddOutputHeadSelftestTop;
          task6-int8-v8k-l2-residual-add-output-head-selftest-tb-data-sv =
            task6Int8V8kL2ResidualAddOutputHeadSelftestTbDataSv;
          task6-int8-v8k-l2-residual-add-output-head-selftest-top =
            task6Int8V8kL2ResidualAddOutputHeadSelftestTop;
          task6-int8-v9984-l2-residual-add-output-head-selftest-tb-data-sv =
            task6Int8V9984L2ResidualAddOutputHeadSelftestTbDataSv;
          task6-int8-v9984-l2-residual-add-output-head-selftest-top =
            task6Int8V9984L2ResidualAddOutputHeadSelftestTop;
          task6-ternary-v9984-l2-residual-add-output-head-selftest-tb-data-sv =
            task6TernaryV9984L2ResidualAddOutputHeadSelftestTbDataSv;
          task6-ternary-v9984-l2-residual-add-output-head-selftest-top =
            task6TernaryV9984L2ResidualAddOutputHeadSelftestTop;
          task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-tb-data-sv =
            task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTbDataSv;
          task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-top =
            task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestTop;
          task6-int8-v10k-l2-residual-add-output-head-selftest-sim-main =
            task6Int8V10kL2ResidualAddOutputHeadSelftestSimMain;
          task6-int8-v10k-l2-residual-add-output-head-selftest-sv-sim =
            task6Int8V10kL2ResidualAddOutputHeadSelftestSvSim;
          task6-ternary-v9984-l2-residual-add-output-head-selftest-sim-main =
            task6TernaryV9984L2ResidualAddOutputHeadSelftestSimMain;
          task6-ternary-v9984-l2-residual-add-output-head-selftest-sv-sim =
            task6TernaryV9984L2ResidualAddOutputHeadSelftestSvSim;
          task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-sim-main =
            task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestSimMain;
          task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-sv-sim =
            task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestSvSim;
          task6-int8-v4k-l2-residual-add-output-head-selftest-json =
            task6Int8V4kL2ResidualAddOutputHeadSelftestJson;
          task6-int8-v4k-l2-residual-add-output-head-selftest-utilization =
            task6Int8V4kL2ResidualAddOutputHeadSelftestUtilization;
          task6-int8-v10k-l2-residual-add-output-head-selftest-json =
            task6Int8V10kL2ResidualAddOutputHeadSelftestJson;
          task6-int8-v10k-l2-residual-add-output-head-selftest-utilization =
            task6Int8V10kL2ResidualAddOutputHeadSelftestUtilization;
          task6-int8-v6k-l2-residual-add-output-head-selftest-json =
            task6Int8V6kL2ResidualAddOutputHeadSelftestJson;
          task6-int8-v8k-l2-residual-add-output-head-selftest-json =
            task6Int8V8kL2ResidualAddOutputHeadSelftestJson;
          task6-int8-v9984-l2-residual-add-output-head-selftest-json =
            task6Int8V9984L2ResidualAddOutputHeadSelftestJson;
          task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-json =
            task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebugJson;
          task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-json =
            task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebugJson;
          task6-ternary-base3-v10k-l2-residual-add-output-head-selftest-jtag-debug-json =
            task6TernaryBase3V10kL2ResidualAddOutputHeadSelftestJtagDebugJson;
          task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-json =
            task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestJson;
          task6-int8-v4k-l2-residual-add-output-head-selftest-xdc =
            task6Int8V4kL2ResidualAddOutputHeadSelftestXdc;
          task6-int8-v4k-l2-residual-add-output-head-selftest-fasm =
            task6Int8V4kL2ResidualAddOutputHeadSelftestFasm;
          task6-int8-v4k-l2-residual-add-output-head-selftest-bitstream =
            task6Int8V4kL2ResidualAddOutputHeadSelftestBitstream;
          task6-int8-v4k-l2-residual-add-output-head-selftest-5mhz-fasm =
            task6Int8V4kL2ResidualAddOutputHeadSelftest5MHzFasm;
          task6-int8-v4k-l2-residual-add-output-head-selftest-5mhz-bitstream =
            task6Int8V4kL2ResidualAddOutputHeadSelftest5MHzBitstream;
          task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug-json =
            task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugJson;
          task6-int8-v6k-l2-residual-add-output-head-selftest-xdc =
            task6Int8V6kL2ResidualAddOutputHeadSelftestXdc;
          task6-int8-v6k-l2-residual-add-output-head-selftest-5mhz-fasm =
            task6Int8V6kL2ResidualAddOutputHeadSelftest5MHzFasm;
          task6-int8-v6k-l2-residual-add-output-head-selftest-5mhz-bitstream =
            task6Int8V6kL2ResidualAddOutputHeadSelftest5MHzBitstream;
          task6-int8-v8k-l2-residual-add-output-head-selftest-xdc =
            task6Int8V8kL2ResidualAddOutputHeadSelftestXdc;
          task6-int8-v8k-l2-residual-add-output-head-selftest-5mhz-fasm =
            task6Int8V8kL2ResidualAddOutputHeadSelftest5MHzFasm;
          task6-int8-v8k-l2-residual-add-output-head-selftest-5mhz-bitstream =
            task6Int8V8kL2ResidualAddOutputHeadSelftest5MHzBitstream;
          task6-int8-v9984-l2-residual-add-output-head-selftest-xdc =
            task6Int8V9984L2ResidualAddOutputHeadSelftestXdc;
          task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz-fasm =
            task6Int8V9984L2ResidualAddOutputHeadSelftest5MHzFasm;
          task6-int8-v9984-l2-residual-add-output-head-selftest-5mhz-bitstream =
            task6Int8V9984L2ResidualAddOutputHeadSelftest5MHzBitstream;
          task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz-fasm =
            task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm;
          task6-int8-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz-bitstream =
            task6Int8V9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzBitstream;
          task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz-fasm =
            task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm;
          task6-ternary-v9984-l2-residual-add-output-head-selftest-jtag-debug-5mhz-bitstream =
            task6TernaryV9984L2ResidualAddOutputHeadSelftestJtagDebug5MHzBitstream;
          task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-xdc =
            task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftestXdc;
          task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-5mhz-fasm =
            task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftest5MHzFasm;
          task6-int8-v10k-padded-tile64-l2-residual-add-output-head-selftest-5mhz-bitstream =
            task6Int8V10kPaddedTile64L2ResidualAddOutputHeadSelftest5MHzBitstream;
          task6-int8-v10k-l2-residual-add-output-head-selftest-xdc =
            task6Int8V10kL2ResidualAddOutputHeadSelftestXdc;
          task6-int8-v10k-l2-residual-add-output-head-selftest-fasm =
            task6Int8V10kL2ResidualAddOutputHeadSelftestFasm;
          task6-int8-v10k-l2-residual-add-output-head-selftest-bitstream =
            task6Int8V10kL2ResidualAddOutputHeadSelftestBitstream;
          task6-int8-v10k-l2-residual-add-output-head-selftest-5mhz-fasm =
            task6Int8V10kL2ResidualAddOutputHeadSelftest5MHzFasm;
          task6-int8-v10k-l2-residual-add-output-head-selftest-5mhz-bitstream =
            task6Int8V10kL2ResidualAddOutputHeadSelftest5MHzBitstream;
          task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-json =
            task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugJson;
          task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug-fasm =
            task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugFasm;
          task6-int8-v4k-l2-residual-add-output-head-selftest-jtag-debug-bitstream =
            task6Int8V4kL2ResidualAddOutputHeadSelftestJtagDebugBitstream;
          task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-fasm =
            task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugFasm;
          task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-bitstream =
            task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebugBitstream;
          task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-5mhz-fasm =
            task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebug5MHzFasm;
          task6-int8-v10k-l2-residual-add-output-head-selftest-jtag-debug-5mhz-bitstream =
            task6Int8V10kL2ResidualAddOutputHeadSelftestJtagDebug5MHzBitstream;
          task6-int8-l2-mlp-chain-residual-add-selftest-debug-fasm =
            task6Int8L2MlpChainResidualAddSelftestDebugFasm;
          task6-int8-l2-mlp-chain-residual-add-selftest-debug-bitstream =
            task6Int8L2MlpChainResidualAddSelftestDebugBitstream;
          task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-fasm =
            task6Int8L2MlpChainResidualAddSelftestValueDebugFasm;
          task6-int8-l2-mlp-chain-residual-add-selftest-value-debug-bitstream =
            task6Int8L2MlpChainResidualAddSelftestValueDebugBitstream;
          task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-fasm =
            task6Int8L2MlpChainResidualAddSelftestCProjDebugFasm;
          task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-debug-bitstream =
            task6Int8L2MlpChainResidualAddSelftestCProjDebugBitstream;
          task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-fasm =
            task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugFasm;
          task6-int8-l2-mlp-chain-residual-add-selftest-c-proj-requant-debug-bitstream =
            task6Int8L2MlpChainResidualAddSelftestCProjRequantDebugBitstream;
          task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug-fasm =
            task6Int8L2MlpChainResidualAddSelftestJtagDebugFasm;
          task6-int8-l2-mlp-chain-residual-add-selftest-jtag-debug-bitstream =
            task6Int8L2MlpChainResidualAddSelftestJtagDebugBitstream;
          task6-c-proj-requant-arith-selftest-sim-main =
            task6CProjRequantArithSelftestSimMain;
          task6-c-proj-requant-arith-selftest-sv-sim =
            task6CProjRequantArithSelftestSvSim;
          task6-c-proj-requant-arith-selftest-json =
            task6CProjRequantArithSelftestJson;
          task6-c-proj-requant-arith-selftest-utilization =
            task6CProjRequantArithSelftestUtilization;
          task6-c-proj-requant-arith-selftest-xdc =
            task6CProjRequantArithSelftestXdc;
          task6-c-proj-requant-arith-selftest-fasm =
            task6CProjRequantArithSelftestFasm;
          task6-c-proj-requant-arith-selftest-bitstream =
            task6CProjRequantArithSelftestBitstream;
          task6-led-map-json = task6LedMapJson;
          task6-led-map-xdc = task6LedMapXdc;
          task6-led-map-fasm = task6LedMapFasm;
          task6-led-map-bitstream = task6LedMapBitstream;
          task6-ternip-upstream-repro = task6TernipUpstreamRepro;
          task6-ternip-reduced-config = task6TernipReducedConfig;
          task6-ternip-reduced-elab-json = task6TernipReducedElabJson;
          task6-ternip-reduced-verilator-lint-report =
            task6TernipReducedVerilatorLintReport;
          task6-int8-l2-residual-add-boundary-scout =
            task6Int8L2ResidualAddBoundaryScout;
          task6-int8-l2-residual-add-contract =
            task6Int8L2ResidualAddContract;
          task6-int8-l2-residual-add-boundary =
            task6Int8L2ResidualAddBoundary;
          task6-int8-l2-c-fc-post-gelu-requant-tb-data-sv =
            task6Int8L2CFcPostGeluRequantTbDataSv;
          task6-int8-l2-c-fc-post-gelu-requant-sim-main =
            task6Int8L2CFcPostGeluRequantSimMain;
          task6-int8-l2-c-fc-post-gelu-requant-sv-sim =
            task6Int8L2CFcPostGeluRequantSvSim;
          task6-int8-l2-c-fc-post-gelu-requant-yosys-stat =
            task6Int8L2CFcPostGeluRequantYosysStat;
          task6-int8-l2-c-fc-post-gelu-requant-json =
            task6Int8L2CFcPostGeluRequantJson;
          task6-int8-l2-c-fc-post-gelu-requant-utilization =
            task6Int8L2CFcPostGeluRequantUtilization;
          task6-int8-l2-c-fc-post-gelu-requant-rtl-proof =
            task6Int8L2CFcPostGeluRequantRtlProof;
          task6-l1-c-proj-redirect-tb-data-sv = task6L1CProjRedirectTbDataSv;
          task6-l1-c-proj-redirect-sim-main = task6L1CProjRedirectSimMain;
          task6-l1-c-proj-redirect-json = task6L1CProjRedirectJson;
          task6-l1-c-proj-redirect-utilization = task6L1CProjRedirectUtilization;
          task6-l1-c-proj-redirect-abc9-json = task6L1CProjRedirectAbc9Json;
          task6-l1-c-proj-redirect-abc9-utilization =
            task6L1CProjRedirectAbc9Utilization;
          task6-l1-c-proj-redirect-sv-sim = task6L1CProjRedirectSvSim;
          task6-l1-c-fc-redirect-tb-data-sv = task6L1CFcRedirectTbDataSv;
          task6-l1-c-fc-redirect-sim-main = task6L1CFcRedirectSimMain;
          task6-l1-c-fc-redirect-yosys-stat = task6L1CFcRedirectYosysStat;
          task6-l1-c-fc-redirect-json = task6L1CFcRedirectJson;
          task6-l1-c-fc-redirect-utilization = task6L1CFcRedirectUtilization;
          task6-l1-c-fc-redirect-abc9-json = task6L1CFcRedirectAbc9Json;
          task6-l1-c-fc-redirect-abc9-utilization =
            task6L1CFcRedirectAbc9Utilization;
          task6-l1-c-fc-redirect-ui64-buffer-lite-sim-main =
            task6L1CFcRedirectUi64BufferLiteSimMain;
          task6-l1-c-fc-redirect-ui64-buffer-lite-json =
            task6L1CFcRedirectUi64BufferLiteJson;
          task6-l1-c-fc-redirect-ui64-buffer-lite-utilization =
            task6L1CFcRedirectUi64BufferLiteUtilization;
          task6-l1-c-fc-redirect-ui64-buffer-lite-sv-sim =
            task6L1CFcRedirectUi64BufferLiteSvSim;
          task6-l1-c-fc-redirect-ui64-buffer-fifo2-sim-main =
            task6L1CFcRedirectUi64BufferFifo2SimMain;
          task6-l1-c-fc-redirect-ui64-buffer-fifo2-json =
            task6L1CFcRedirectUi64BufferFifo2Json;
          task6-l1-c-fc-redirect-ui64-buffer-fifo2-utilization =
            task6L1CFcRedirectUi64BufferFifo2Utilization;
          task6-l1-c-fc-redirect-ui64-buffer-fifo2-sv-sim =
            task6L1CFcRedirectUi64BufferFifo2SvSim;
          task6-l1-c-fc-redirect-buffer165-fifo2-sim-main =
            task6L1CFcRedirectBuffer165Fifo2SimMain;
          task6-l1-c-fc-redirect-buffer165-fifo2-json =
            task6L1CFcRedirectBuffer165Fifo2Json;
          task6-l1-c-fc-redirect-buffer165-fifo2-utilization =
            task6L1CFcRedirectBuffer165Fifo2Utilization;
          task6-l1-c-fc-redirect-buffer165-fifo2-sv-sim =
            task6L1CFcRedirectBuffer165Fifo2SvSim;
          task6-l1-c-fc-redirect-index-spine-fifo2-sim-main =
            task6L1CFcRedirectIndexSpineFifo2SimMain;
          task6-l1-c-fc-redirect-index-spine-fifo2-json =
            task6L1CFcRedirectIndexSpineFifo2Json;
          task6-l1-c-fc-redirect-index-spine-fifo2-utilization =
            task6L1CFcRedirectIndexSpineFifo2Utilization;
          task6-l1-c-fc-redirect-index-spine-fifo2-abc9-json =
            task6L1CFcRedirectIndexSpineFifo2Abc9Json;
          task6-l1-c-fc-redirect-index-spine-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexSpineFifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-spine-fifo2-sv-sim =
            task6L1CFcRedirectIndexSpineFifo2SvSim;
          task6-l1-c-fc-redirect-index-fanout-fifo2-sim-main =
            task6L1CFcRedirectIndexFanoutFifo2SimMain;
          task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-json =
            task6L1CFcRedirectIndexFanoutFifo2Abc9Json;
          task6-l1-c-fc-redirect-index-fanout-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexFanoutFifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-fanout-fifo2-sv-sim =
            task6L1CFcRedirectIndexFanoutFifo2SvSim;
          task6-l1-c-fc-redirect-index-ring2-fifo2-sim-main =
            task6L1CFcRedirectIndexRing2Fifo2SimMain;
          task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-json =
            task6L1CFcRedirectIndexRing2Fifo2Abc9Json;
          task6-l1-c-fc-redirect-index-ring2-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexRing2Fifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-ring2-fifo2-sv-sim =
            task6L1CFcRedirectIndexRing2Fifo2SvSim;
          task6-l1-c-fc-redirect-index-ring3-fifo2-sim-main =
            task6L1CFcRedirectIndexRing3Fifo2SimMain;
          task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-json =
            task6L1CFcRedirectIndexRing3Fifo2Abc9Json;
          task6-l1-c-fc-redirect-index-ring3-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexRing3Fifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-ring3-fifo2-sv-sim =
            task6L1CFcRedirectIndexRing3Fifo2SvSim;
          task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sim-main =
            task6L1CFcRedirectIndexRing3CtrlMergeFifo2SimMain;
          task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-json =
            task6L1CFcRedirectIndexRing3CtrlMergeFifo2Json;
          task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-json =
            task6L1CFcRedirectIndexRing3CtrlMergeFifo2Abc9Json;
          task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexRing3CtrlMergeFifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-ring3-ctrlmerge-fifo2-sv-sim =
            task6L1CFcRedirectIndexRing3CtrlMergeFifo2SvSim;
          task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sim-main =
            task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2SimMain;
          task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-json =
            task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Abc9Json;
          task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-ring3-ui1buf263-fifo2-sv-sim =
            task6L1CFcRedirectIndexRing3Ui1Buf263Fifo2SvSim;
          task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sim-main =
            task6L1CFcRedirectIndexRing3Fork49StatevecSimMain;
          task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-json =
            task6L1CFcRedirectIndexRing3Fork49StatevecAbc9Json;
          task6-l1-c-fc-redirect-index-ring3-fork49-statevec-abc9-utilization =
            task6L1CFcRedirectIndexRing3Fork49StatevecAbc9Utilization;
          task6-l1-c-fc-redirect-index-ring3-fork49-statevec-sv-sim =
            task6L1CFcRedirectIndexRing3Fork49StatevecSvSim;
          task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sim-main =
            task6L1CFcRedirectIndexRing3SelectClusterFifo2SimMain;
          task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-json =
            task6L1CFcRedirectIndexRing3SelectClusterFifo2Abc9Json;
          task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexRing3SelectClusterFifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-ring3-selectcluster-fifo2-sv-sim =
            task6L1CFcRedirectIndexRing3SelectClusterFifo2SvSim;
          task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sim-main =
            task6L1CFcRedirectIndexRing3PostBranchFifo2SimMain;
          task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-json =
            task6L1CFcRedirectIndexRing3PostBranchFifo2Abc9Json;
          task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexRing3PostBranchFifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-ring3-postbranch-fifo2-sv-sim =
            task6L1CFcRedirectIndexRing3PostBranchFifo2SvSim;
          task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sim-main =
            task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2SimMain;
          task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-yosys-stat =
            task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2YosysStat;
          task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-json =
            task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Abc9Json;
          task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization =
            task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2Abc9Utilization;
          task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim =
            task6L1CFcRedirectIndexRing3PostBranchOutBufFifo2SvSim;
          task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sim-main =
            task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2SimMain;
          task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-yosys-stat =
            task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2YosysStat;
          task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-json =
            task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Abc9Json;
          task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-abc9-utilization =
            task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2Abc9Utilization;
          task6-l1-c-fc-redirect-lsq-index-ring3-postbranch-outbuf-fifo2-sv-sim =
            task6L1CFcRedirectLsqIndexRing3PostBranchOutBufFifo2SvSim;
          task6-l1-c-fc-redirect-staged-abc9-json =
            task6L1CFcRedirectStagedAbc9.json;
          task6-l1-c-fc-redirect-staged-abc9-utilization =
            task6L1CFcRedirectStagedAbc9Utilization;
          task6-l1-c-fc-redirect-sv-sim = task6L1CFcRedirectSvSim;
          task6-l2-c-fc-redirect-tb-data-sv = task6L2CFcRedirectTbDataSv;
          task6-l2-c-fc-redirect-sim-main = task6L2CFcRedirectSimMain;
          task6-l2-c-fc-redirect-json = task6L2CFcRedirectJson;
          task6-l2-c-fc-redirect-utilization = task6L2CFcRedirectUtilization;
          task6-l2-c-fc-redirect-sv-sim = task6L2CFcRedirectSvSim;
          task6-l2-c-fc-redirect-tile64-yosys-stat =
            task6L2CFcRedirectTile64YosysStat;
          task6-l2-c-fc-redirect-tile64-abc9-json =
            task6L2CFcRedirectTile64Abc9Json;
          task6-l2-c-fc-redirect-tile64-abc9-utilization =
            task6L2CFcRedirectTile64Abc9Utilization;
          task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-json =
            task6L2CFcRedirectTile64PostBranchOutBufFifo2Abc9Json;
          task6-l2-c-fc-redirect-tile64-postbranch-outbuf-fifo2-abc9-utilization =
            task6L2CFcRedirectTile64PostBranchOutBufFifo2Abc9Utilization;
          task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sim-main =
            task6L2CFcRedirectTile64StorepathForkCtrlSimMain;
          task6-l2-c-fc-redirect-tile64-storepath-forkctrl-abc9-json =
            task6L2CFcRedirectTile64StorepathForkCtrlAbc9Json;
          task6-l2-c-fc-redirect-tile64-storepath-forkctrl-abc9-utilization =
            task6L2CFcRedirectTile64StorepathForkCtrlAbc9Utilization;
          task6-l2-c-fc-redirect-tile64-storepath-forkctrl-sv-sim =
            task6L2CFcRedirectTile64StorepathForkCtrlSvSim;
          task6-l2-c-fc-redirect-tile64-storepath-forks-sim-main =
            task6L2CFcRedirectTile64StorepathForksSimMain;
          task6-l2-c-fc-redirect-tile64-storepath-forks-abc9-json =
            task6L2CFcRedirectTile64StorepathForksAbc9Json;
          task6-l2-c-fc-redirect-tile64-storepath-forks-abc9-utilization =
            task6L2CFcRedirectTile64StorepathForksAbc9Utilization;
          task6-l2-c-fc-redirect-tile64-storepath-forks-sv-sim =
            task6L2CFcRedirectTile64StorepathForksSvSim;
          task6-l2-c-fc-redirect-tile4x64-sim-main =
            task6L2CFcRedirectTile4x64SimMain;
          task6-l2-c-fc-redirect-tile4x64-abc9-json =
            task6L2CFcRedirectTile4x64Abc9Json;
          task6-l2-c-fc-redirect-tile4x64-abc9-utilization =
            task6L2CFcRedirectTile4x64Abc9Utilization;
          task6-l2-c-fc-redirect-tile4x64-sv-sim =
            task6L2CFcRedirectTile4x64SvSim;
          task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sim-main =
            task6L2CFcRedirectTile4x64PostBranchOutBufFifo2SimMain;
          task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-yosys-stat =
            task6L2CFcRedirectTile4x64PostBranchOutBufFifo2YosysStat;
          task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-json =
            task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Abc9Json;
          task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization =
            task6L2CFcRedirectTile4x64PostBranchOutBufFifo2Abc9Utilization;
          task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim =
            task6L2CFcRedirectTile4x64PostBranchOutBufFifo2SvSim;
          task6-l2-c-fc-redirect-postbranch-fifo2-sim-main =
            task6L2CFcRedirectPostBranchFifo2SimMain;
          task6-l2-c-fc-redirect-postbranch-fifo2-abc9-json =
            task6L2CFcRedirectPostBranchFifo2Abc9Json;
          task6-l2-c-fc-redirect-postbranch-fifo2-abc9-utilization =
            task6L2CFcRedirectPostBranchFifo2Abc9Utilization;
          task6-l2-c-fc-redirect-postbranch-fifo2-sv-sim =
            task6L2CFcRedirectPostBranchFifo2SvSim;
          task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sim-main =
            task6L2CFcRedirectDownstreamOutBufFifo2SimMain;
          task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-json =
            task6L2CFcRedirectDownstreamOutBufFifo2Abc9Json;
          task6-l2-c-fc-redirect-downstream-outbuf-fifo2-abc9-utilization =
            task6L2CFcRedirectDownstreamOutBufFifo2Abc9Utilization;
          task6-l2-c-fc-redirect-downstream-outbuf-fifo2-sv-sim =
            task6L2CFcRedirectDownstreamOutBufFifo2SvSim;
          matmul-selftest-bitstream = matmulSelftestBitstream;
          matmul-selftest-fasm = matmulSelftestFasm;
          matmul-selftest-top = matmulSelftestTop;
          matmul-selftest-xdc = matmulSelftestXdc;
          matmul-selftest-json = matmulSelftestJson;
          tiny-stories-1m-selftest-all-memory-top =
            tinyStories1mSelftestAllMemory.top;
          tiny-stories-1m-selftest-all-memory-model-opt-il =
            tinyStories1mSelftestAllMemory.modelOptIl;
          tiny-stories-1m-selftest-all-memory-model-shell-il =
            tinyStories1mSelftestAllMemory.modelShellIl;
          tiny-stories-1m-selftest-all-memory-external-memory-plan =
            tinyStories1mSelftestAllMemory.externalMemoryPlan;
          tiny-stories-1m-selftest-all-memory-json =
            tinyStories1mSelftestAllMemory.json;
          tiny-stories-1m-selftest-all-memory-yosys-json =
            tinyStories1mSelftestAllMemory.yosysJson;
          tiny-stories-1m-selftest-all-memory-utilization =
            tinyStories1mSelftestAllMemory.utilizationReport;
          tiny-stories-1m-selftest-all-memory-stage-stats =
            tinyStories1mSelftestAllMemory.rtlilStageStats.bundle;
          tiny-stories-1m-baseline-float-selftest-all-memory-top =
            tinyStories1mBaselineFloatSelftestAllMemory.top;
          tiny-stories-1m-baseline-float-selftest-all-memory-model-opt-il =
            tinyStories1mBaselineFloatSelftestAllMemory.modelOptIl;
          tiny-stories-1m-baseline-float-selftest-all-memory-model-shell-il =
            tinyStories1mBaselineFloatSelftestAllMemory.modelShellIl;
          tiny-stories-1m-baseline-float-selftest-all-memory-external-memory-plan =
            tinyStories1mBaselineFloatSelftestAllMemory.externalMemoryPlan;
          tiny-stories-1m-baseline-float-selftest-all-memory-json =
            tinyStories1mBaselineFloatSelftestAllMemory.json;
          tiny-stories-1m-baseline-float-selftest-all-memory-yosys-json =
            tinyStories1mBaselineFloatSelftestAllMemory.yosysJson;
          tiny-stories-1m-baseline-float-selftest-all-memory-utilization =
            tinyStories1mBaselineFloatSelftestAllMemory.utilizationReport;
          tiny-stories-1m-baseline-float-selftest-all-memory-stage-stats =
            tinyStories1mBaselineFloatSelftestAllMemory.rtlilStageStats.bundle;
          tiny-stories-1m-baseline-float-selftest-top4-memory-top =
            tinyStories1mBaselineFloatSelftestTop4Memory.top;
          tiny-stories-1m-baseline-float-selftest-top4-memory-model-opt-il =
            tinyStories1mBaselineFloatSelftestTop4Memory.modelOptIl;
          tiny-stories-1m-baseline-float-selftest-top4-memory-model-shell-il =
            tinyStories1mBaselineFloatSelftestTop4Memory.modelShellIl;
          tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan =
            tinyStories1mBaselineFloatSelftestTop4Memory.externalMemoryPlan;
          tiny-stories-1m-baseline-float-selftest-top4-memory-json =
            tinyStories1mBaselineFloatSelftestTop4Memory.json;
          tiny-stories-1m-baseline-float-selftest-top4-memory-yosys-json =
            tinyStories1mBaselineFloatSelftestTop4Memory.yosysJson;
          tiny-stories-1m-baseline-float-selftest-top4-memory-utilization =
            tinyStories1mBaselineFloatSelftestTop4Memory.utilizationReport;
          tiny-stories-1m-baseline-float-selftest-top4-memory-stage-stats =
            tinyStories1mBaselineFloatSelftestTop4Memory.rtlilStageStats.bundle;
          tiny-stories-1m-baseline-float-selftest-top4-memory-stage6a-stats =
            tinyStories1mBaselineFloatSelftestTop4Memory.rtlilStageStats.reports.stage6a;
          tiny-stories-1m-baseline-float-selftest-top32-memory-top =
            tinyStories1mBaselineFloatSelftestTop32Memory.top;
          tiny-stories-1m-baseline-float-selftest-top32-memory-model-opt-il =
            tinyStories1mBaselineFloatSelftestTop32Memory.modelOptIl;
          tiny-stories-1m-baseline-float-selftest-top32-memory-model-shell-il =
            tinyStories1mBaselineFloatSelftestTop32Memory.modelShellIl;
          tiny-stories-1m-baseline-float-selftest-top32-memory-external-memory-plan =
            tinyStories1mBaselineFloatSelftestTop32Memory.externalMemoryPlan;
          tiny-stories-1m-baseline-float-selftest-top32-memory-json =
            tinyStories1mBaselineFloatSelftestTop32Memory.json;
          tiny-stories-1m-baseline-float-selftest-top32-memory-yosys-json =
            tinyStories1mBaselineFloatSelftestTop32Memory.yosysJson;
          tiny-stories-1m-baseline-float-selftest-top32-memory-utilization =
            tinyStories1mBaselineFloatSelftestTop32Memory.utilizationReport;
          tiny-stories-1m-baseline-float-selftest-top32-memory-stage-stats =
            tinyStories1mBaselineFloatSelftestTop32Memory.rtlilStageStats.bundle;
          tiny-stories-1m-baseline-float-selftest-top32-memory-stage6a-stats =
            tinyStories1mBaselineFloatSelftestTop32Memory.rtlilStageStats.reports.stage6a;
          tiny-stories-1m-baseline-float-selftest-top34-memory-top =
            tinyStories1mBaselineFloatSelftestTop34Memory.top;
          tiny-stories-1m-baseline-float-selftest-top34-memory-model-opt-il =
            tinyStories1mBaselineFloatSelftestTop34Memory.modelOptIl;
          tiny-stories-1m-baseline-float-selftest-top34-memory-model-shell-il =
            tinyStories1mBaselineFloatSelftestTop34Memory.modelShellIl;
          tiny-stories-1m-baseline-float-selftest-top34-memory-external-memory-plan =
            tinyStories1mBaselineFloatSelftestTop34Memory.externalMemoryPlan;
          tiny-stories-1m-baseline-float-selftest-top34-memory-json =
            tinyStories1mBaselineFloatSelftestTop34Memory.json;
          tiny-stories-1m-baseline-float-selftest-top34-memory-yosys-json =
            tinyStories1mBaselineFloatSelftestTop34Memory.yosysJson;
          tiny-stories-1m-baseline-float-selftest-top34-memory-utilization =
            tinyStories1mBaselineFloatSelftestTop34Memory.utilizationReport;
          tiny-stories-1m-baseline-float-selftest-top34-memory-stage8h-il =
            tinyStories1mBaselineFloatSelftestTop34Memory.stages.stage8h;
          tiny-stories-1m-baseline-float-selftest-top34-memory-stage9-debug =
            tinyStories1mBaselineFloatSelftestTop34Memory.stage9Debug;
          tiny-stories-1m-baseline-float-selftest-top34-memory-stage-stats =
            tinyStories1mBaselineFloatSelftestTop34Memory.rtlilStageStats.bundle;
          tiny-stories-1m-baseline-float-selftest-top34-memory-stage6a-stats =
            tinyStories1mBaselineFloatSelftestTop34Memory.rtlilStageStats.reports.stage6a;
          tiny-stories-1m-representative-core-selftest-all-memory-top =
            tinyStories1mRepresentativeCoreSelftestAllMemory.top;
          tiny-stories-1m-representative-core-selftest-all-memory-model-opt-il =
            tinyStories1mRepresentativeCoreSelftestAllMemory.modelOptIl;
          tiny-stories-1m-representative-core-selftest-all-memory-model-shell-il =
            tinyStories1mRepresentativeCoreSelftestAllMemory.modelShellIl;
          tiny-stories-1m-representative-core-selftest-all-memory-external-memory-plan =
            tinyStories1mRepresentativeCoreSelftestAllMemory.externalMemoryPlan;
          tiny-stories-1m-representative-core-selftest-all-memory-json =
            tinyStories1mRepresentativeCoreSelftestAllMemory.json;
          tiny-stories-1m-representative-core-selftest-all-memory-yosys-json =
            tinyStories1mRepresentativeCoreSelftestAllMemory.yosysJson;
          tiny-stories-1m-representative-core-selftest-all-memory-utilization =
            tinyStories1mRepresentativeCoreSelftestAllMemory.utilizationReport;
          tiny-stories-1m-representative-core-selftest-all-memory-stage-stats =
            tinyStories1mRepresentativeCoreSelftestAllMemory.rtlilStageStats.bundle;
          tiny-stories-1m-representative-core-selftest-top4-memory-top =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.top;
          tiny-stories-1m-representative-core-selftest-top4-memory-model-opt-il =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.modelOptIl;
          tiny-stories-1m-representative-core-selftest-top4-memory-model-shell-il =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.modelShellIl;
          tiny-stories-1m-representative-core-selftest-top4-memory-external-memory-plan =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.externalMemoryPlan;
          tiny-stories-1m-representative-core-selftest-top4-memory-json =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.json;
          tiny-stories-1m-representative-core-selftest-top4-memory-yosys-json =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.yosysJson;
          tiny-stories-1m-representative-core-selftest-top4-memory-utilization =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.utilizationReport;
          tiny-stories-1m-representative-core-selftest-top4-memory-stage-stats =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.rtlilStageStats.bundle;
          tiny-stories-1m-representative-core-selftest-top4-memory-stage6a-stats =
            tinyStories1mRepresentativeCoreSelftestTop4Memory.rtlilStageStats.reports.stage6a;
          tiny-stories-1m-representative-core-all-memory-vs-top4-memory-stage-stats =
            tinyStories1mRepresentativeCoreAllMemoryVsTop4MemoryStageStats;
          tiny-stories-1m-representative-core-all-memory-vs-top4-memory-utilization =
            tinyStories1mRepresentativeCoreAllMemoryVsTop4MemoryUtilization;
          tiny-stories-1m-representative-core-all-memory-vs-top4-memory-compare =
            tinyStories1mRepresentativeCoreAllMemoryVsTop4MemoryComparison;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-top =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.top;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-model-opt-il =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.modelOptIl;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-model-shell-il =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.modelShellIl;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-external-memory-plan =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.externalMemoryPlan;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-json =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.json;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-yosys-json =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.yosysJson;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-utilization =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.utilizationReport;
          tiny-stories-1m-representative-core-selftest-top4-memory-abc9-stage-stats =
            tinyStories1mRepresentativeCoreSelftestTop4MemoryAbc9.rtlilStageStats.bundle;
          tiny-stories-1m-representative-core-sweep-manifest =
            representativeCoreSweepManifest;
          tiny-stories-1m-representative-core-sweep-all-memory-vs-top4-memory-summary =
            representativeCoreSweepSummary;
          tiny-stories-1m-top4-memory-stage-stats-baseline-vs-representative-core =
            tinyStories1mRepresentativeCoreVsBaselineFloatTop4MemoryStageStats;
          tiny-stories-1m-baseline-float-vs-representative-core-torch-op-coverage =
            tinyStories1mBaselineFloatVsRepresentativeCoreTorchOpCoverage;
          tiny-stories-1m-baseline-float-vs-representative-core-cf-op-coverage =
            tinyStories1mBaselineFloatVsRepresentativeCoreCfOpCoverage;
          tiny-stories-1m-baseline-float-vs-representative-core-op-coverage =
            tinyStories1mBaselineFloatVsRepresentativeCoreMlirOpCoverage;
          task6-uberddr3-source-summary = task6UberDdr3SourceSummary;
          task6-uberddr3-controller-yosys-json =
            task6UberDdr3ControllerYosysJson;
        } // task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeByCommandIndex.json
          // task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeByCommandIndex.fasm
          // task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrTraceInitBandwidthProbeByCommandIndex.bitstream
          // task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrSingleReadInitBandwidthProbeByStartIndex.json
          // task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrSingleReadInitBandwidthProbeByStartIndex.fasm
          // task6YpcbLiteDramNoOdelayLowrateEdgeCompAddrwalkNativeCmdaddrSingleReadInitBandwidthProbeByStartIndex.bitstream
          // representativeCoreSweepPackages // pipelineStagePackages
          // pipelineMetadataPackages;

        checks = {
          nix = pkgs.runCommand "llm2fpga-nix" {
            nativeBuildInputs =
              [ pkgs.statix pkgs.deadnix pkgs.nixfmt-classic ];
          } ''
            cd ${./.}
            deadnix --fail .
            statix check .
            nixfmt --check .
            mkdir -p "$out"
          '';

          python = pkgs.runCommand "llm2fpga-python" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
            cd ${./.}
            python - <<'PY'
            import pathlib

            for path in pathlib.Path(".").rglob("*.py"):
              if path.is_file():
                source = path.read_text(encoding="utf-8")
                compile(source, str(path), "exec")
            PY
            mkdir -p "$out"
          '';

          systemverilog = pkgs.runCommand "llm2fpga-systemverilog" {
            nativeBuildInputs = [ pkgs.verilator ];
          } ''
            verilator \
              --lint-only \
              --timing \
              --language 1800-2017 \
              --top-module tb \
              --Wall \
              --Wno-fatal \
              --Wno-TIMESCALEMOD \
              -I${tbDataSv} \
              -f ${matmulSv}/sources.f \
              ${./sim}/tb_main.sv
            verilator \
              --lint-only \
              --timing \
              --language 1800-2017 \
              --top-module task6_l0_gemv64_tb \
              --Wall \
              --Wno-fatal \
              --Wno-TIMESCALEMOD \
              -I${task6L0Gemv64TbDataSv} \
              -f ${task6L0Gemv64Sv}/sources.f \
              ${./sim}/task6_l0_gemv64_tb_main.sv
            mkdir -p "$out"
          '';

          shell = pkgs.runCommand "llm2fpga-shell" {
            nativeBuildInputs = [ pkgs.shellcheck pkgs.findutils ];
          } ''
            cd ${./.}
            if ! find . -name '*.sh' -type f | grep -q .; then
              mkdir -p "$out"
              exit 0
            fi
            find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -s bash -x
            mkdir -p "$out"
          '';
        };
      });
}
