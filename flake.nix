{
  description = "LLM2FPGA";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-llvm21.url =
      "github:NixOS/nixpkgs/346dd96ad74dc4457a9db9de4f4f57dab2e5731d";
    flake-utils.url = "github:numtide/flake-utils";
    # Clone with submodules
    yosys.url = "git+https://github.com/YosysHQ/yosys?submodules=1";
    circt-nix.url = "github:dtzSiFive/circt-nix";
    nix-eda.url = "github:fossi-foundation/nix-eda";
  };

  outputs =
    { nixpkgs, nixpkgs-llvm21, flake-utils, yosys, circt-nix, nix-eda, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgsLlvm21 = import nixpkgs-llvm21 { inherit system; };
        circtPkgs = circt-nix.packages.${system};
        inherit (circtPkgs) circt;
        yosysPkg = nix-eda.packages.${system}.yosysFull;
        yosysPkgWithPythonEnv = if yosysPkg ? python3-env then
          yosysPkg
        else
          (yosysPkg // { python3-env = pkgs.python311; });
        nixEdaSource = nix-eda.outPath;
        yosysSlang = import "${nixEdaSource}/nix/yosys-slang.nix" {
          inherit (pkgs) cmake fmt jq lib;
          yosys = yosysPkgWithPythonEnv;
          clang18Stdenv = pkgs.clangStdenv;
          hash = "sha256-bZEQwDjGZyekhn0J3LJUzRVqh1rMtnjfjOo1vgS5CFE=";
          fetchGitHubSnapshot =
            pkgs.callPackage "${nixEdaSource}/nix/fetch_github_snapshot.nix"
            { };
        };
        llvmPackages = pkgsLlvm21.llvmPackages_21;
        inherit (llvmPackages) mlir;
        python = pkgs.python311;
        pythonWithTorch = python.withPackages (ps: [ ps.torch ps.packaging ]);
        # Torch-MLIR is not available in nixpkgs, pending this PR: https://github.com/NixOS/nixpkgs/pull/490242
        # For the moment, we consume the wheel
        torchMlir = pkgs.callPackage ./torch-mlir.nix {
          inherit pkgs;
          inherit python;
        };

        matmulTorch = pkgs.runCommand "matmul-torch.mlir" {
          buildInputs = [ pythonWithTorch ];
        } ''
          export MATMUL_PY=${./src/matmul.py}
          export PYTHONPATH="${./.}:${
            ./sim
          }:${torchMlir}/${python.sitePackages}:''${PYTHONPATH:-}"
          python ${./src/compile-pytorch.py} > "$out"
        '';

        matmulLinalg = pkgs.runCommand "matmul-linalg.mlir" { } ''
          ${torchMlir}/${python.sitePackages}/torch_mlir/_mlir_libs/torch-mlir-opt ${matmulTorch} \
            --torch-function-to-torch-backend-pipeline \
            --torch-backend-to-linalg-on-tensors-backend-pipeline \
            -canonicalize > $out
        '';

        matmulCf = pkgs.runCommand "matmul-cf.mlir" { } ''
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

        matmulCfStats = pkgs.runCommand "matmul-cf.stats" { } ''
          ${mlir}/bin/mlir-opt ${matmulCf} --print-op-stats -o /dev/null > $out || true
        '';

        matmulHandshake = pkgs.runCommand "matmul-handshake.mlir" { } ''
          ${circt}/bin/circt-opt ${matmulCf} \
            -flatten-memref \
            -flatten-memref-calls \
            -canonicalize \
            -handshake-legalize-memrefs \
            --lower-cf-to-handshake \
            -handshake-insert-buffers \
            -canonicalize > $out
        '';

        matmulHsExt = pkgs.runCommand "matmul-hs-ext.mlir" { } ''
          ${circt}/bin/circt-opt ${matmulHandshake} \
            -handshake-lower-extmem-to-hw \
            -handshake-materialize-forks-sinks \
            -canonicalize > $out
        '';

        matmulHw0 = pkgs.runCommand "matmul-hw0.mlir" { } ''
          ${circt}/bin/circt-opt ${matmulHsExt} \
            -lower-handshake-to-hw \
            -canonicalize > $out
        '';

        matmulHw = pkgs.runCommand "matmul-hw.mlir" { } ''
          ${circt}/bin/circt-opt ${matmulHw0} \
            -lower-esi-types \
            -lower-esi-ports \
            -lower-esi-to-hw \
            -canonicalize > $out
        '';

        matmulHwClean = pkgs.runCommand "matmul-hw-clean.mlir" { } ''
          ${circt}/bin/circt-opt ${matmulHw} \
            -firrtl-inner-symbol-dce \
            -symbol-dce \
            -canonicalize > $out
        '';

        matmulSv = pkgs.runCommand "matmul.sv" { } ''
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

        matmulIl = pkgs.runCommand "matmul.il" { } ''
          set -euo pipefail
          ${yosysPkg}/bin/yosys -m ${yosysSlang}/share/yosys/plugins/slang.so -qp \
              "read_slang ${matmulSv}; proc; opt; memory; flatten; opt; write_rtlil $out" \
              > /dev/null
        '';

        matmulYosysStat = pkgs.runCommand "matmul-yosys.stat" { } ''
          set -euo pipefail
          ${yosysPkg}/bin/yosys -p \
              "read_rtlil ${matmulIl}; tee -o $out stat -json"
        '';

        tbDataSv = pkgs.runCommand "tb-data-sv" { } ''
          mkdir -p "$out"
          MATMUL_PY=${./src/matmul.py} \
          ${pythonWithTorch}/bin/python ${
            ./sim
          }/gen_tb_data.py > "$out/tb_data.sv"
        '';

        simMain = pkgs.runCommand "sim-main" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p "$out/obj_dir"
          verilator --binary --timing --language 1800-2017 -Wno-fatal \
            -I${tbDataSv} \
            -top tb -Mdir "$out/obj_dir" -o sim_main \
            ${matmulSv} ${./sim/tb_main.sv}
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

        matmulSvWave = pkgs.runCommand "matmul-wave.vcd" {
          buildInputs = [ pkgs.verilator pkgs.gcc pkgs.gnumake ];
        } ''
          set -euo pipefail
          mkdir -p obj_dir
          verilator --binary --trace -DENABLE_WAVES -DENABLE_WAVES_VCD --timing --language 1800-2017 -Wno-fatal \
            -I${tbDataSv} \
            -top tb -Mdir obj_dir -o sim_main \
            ${matmulSv} ${./sim/tb_main.sv}
          ./obj_dir/sim_main
          if [ ! -f wave.vcd ]; then
            echo "wave.vcd was not produced by simulation" >&2
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
            llvmPackages.clang
            llvmPackages.llvm
            pythonWithTorch
            yosysSlang
            pkgs.cmake
            pkgs.ninja
            pkgs.gtkwave
            pkgs.nixfmt-classic
          ];
        };

        packages = {
          default = matmulSv;
          torch-mlir = torchMlir;
          tb-data-sv = tbDataSv;
          sim-main = simMain;
          matmul-sv-sim = matmulSvSim;
          matmul-sv-wave = matmulSvWave;
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
          matmul-il = matmulIl;
          matmul-yosys-stat = matmulYosysStat;
        };

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
              --Wall \
              --Wno-fatal \
              -I${tbDataSv} \
              ${matmulSv} \
              ${./sim}/tb_main.sv
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
