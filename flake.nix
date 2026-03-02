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
    # openXC7.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixpkgs-llvm21, flake-utils, yosys, circt-nix, nix-eda
    , openXC7, nextpnrXilinxFork, ypcbHack, ... }:
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
        openXC7Packages = openXC7.packages.${system};
        openXC7Fasm = openXC7Packages.fasm;
        openXC7Nextpnr = openXC7Packages.nextpnr-xilinx.overrideAttrs
          (_: { src = nextpnrXilinxFork; });
        openXC7Chipdb = openXC7Packages.nextpnr-xilinx-chipdb.kintex7.override {
          chipdbFootprints = [ "xc7k480tffg1156" ];
          "nextpnr-xilinx" = openXC7Nextpnr;
        };
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
        # Torch-MLIR is not available in nixpkgs, pending this PR: https://github.com/NixOS/nixpkgs/pull/490242
        # For the moment, we consume the wheel
        torchMlir = pkgs.callPackage ./torch-mlir.nix {
          inherit pkgs;
          inherit python;
        };

        pipelineScripts = ./scripts/pipeline;

        # TinyStories-1M torch-MLIR boundary artifact (Task 3a/3b input).
        # Kept local and out of git due file size; see TinyStories/README.md.
        tinyStories1mTorchInput =
          pkgs.runCommand "tiny-stories-1m-torch-input.mlir" { } ''
                        set -euo pipefail
                        src="${./TinyStories}/tinystories_1m_torch.mlir"
                        if [ ! -f "$src" ]; then
                          cat >&2 <<'EOF'
            Missing TinyStories/tinystories_1m_torch.mlir

            This file is intentionally not committed (size). Provide it locally via one of:
            1) cp /home/roland/private_LLM2FPGA/TinyStories/tinystories_1m_torch.mlir TinyStories/
            2) regenerate it with TinyStories/compile-pytorch.py inside the dev shell
            EOF
                          exit 1
                        fi
                        cp "$src" "$out"
          '';

        mkTorchDerivation = { name, torchMlirInput }:
          pkgs.runCommand "${name}-torch.mlir" { } ''
            cp ${torchMlirInput} "$out"
          '';

        mkLinalgDerivation = { name, torch }:
          pkgs.runCommand "${name}-linalg.mlir" {
            buildInputs = [ torchMlir ];
          } ''
            export TORCH_MLIR_OPT=${torchMlir}/${python.sitePackages}/torch_mlir/_mlir_libs/torch-mlir-opt
            ${pkgs.bash}/bin/bash ${pipelineScripts}/torch_to_linalg.sh ${torch} "$out"
          '';

        mkCfDerivation = { name, linalg, linalgLowering ? "affine" }:
          pkgs.runCommand "${name}-cf.mlir" { buildInputs = [ mlir ]; } ''
            export MLIR_OPT=${mlir}/bin/mlir-opt
            export LINALG_LOWERING=${linalgLowering}
            ${pkgs.bash}/bin/bash ${pipelineScripts}/linalg_to_cf.sh ${linalg} "$out"
          '';

        mkCfStatsDerivation = { name, cf }:
          pkgs.runCommand "${name}-cf.stats" { buildInputs = [ mlir ]; } ''
            export MLIR_OPT=${mlir}/bin/mlir-opt
            ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_stats.sh ${cf} "$out"
          '';

        mkHandshakeDerivation =
          { name, cf, handshakeInsertBuffers ? true, circtPkg ? circt }:
          pkgs.runCommand "${name}-handshake.mlir" {
            buildInputs = [ mlir circtPkg ];
          } ''
            export MLIR_OPT=${mlir}/bin/mlir-opt
            export CIRCT_OPT=${circtPkg}/bin/circt-opt
            if [ "${if handshakeInsertBuffers then "1" else "0"}" = "1" ]; then
              export HANDSHAKE_INSERT_BUFFERS=1
            else
              export HANDSHAKE_INSERT_BUFFERS=0
            fi
            ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_to_handshake.sh ${cf} "$out"
          '';

        mkHsExtDerivation = { name, handshake, circtPkg ? circt }:
          pkgs.runCommand "${name}-hs-ext.mlir" {
            buildInputs = [ circtPkg ];
          } ''
            export CIRCT_OPT=${circtPkg}/bin/circt-opt
            ${pkgs.bash}/bin/bash ${pipelineScripts}/handshake_to_hs_ext.sh ${handshake} "$out"
          '';

        mkHw0Derivation = { name, hsExt, circtPkg ? circt }:
          pkgs.runCommand "${name}-hw0.mlir" { buildInputs = [ circtPkg ]; } ''
            export CIRCT_OPT=${circtPkg}/bin/circt-opt
            ${pkgs.bash}/bin/bash ${pipelineScripts}/hs_ext_to_hw0.sh ${hsExt} "$out"
          '';

        mkHwDerivation = { name, hw0, circtPkg ? circt }:
          pkgs.runCommand "${name}-hw.mlir" { buildInputs = [ circtPkg ]; } ''
            export CIRCT_OPT=${circtPkg}/bin/circt-opt
            ${pkgs.bash}/bin/bash ${pipelineScripts}/hw0_to_hw.sh ${hw0} "$out"
          '';

        mkHwCleanDerivation = { name, hw, circtPkg ? circt }:
          pkgs.runCommand "${name}-hw-clean.mlir" {
            buildInputs = [ circtPkg ];
          } ''
            export CIRCT_OPT=${circtPkg}/bin/circt-opt
            ${pkgs.bash}/bin/bash ${pipelineScripts}/hw_to_hw_clean.sh ${hw} "$out"
          '';

        mkSvDerivation = { name, hwClean, circtPkg ? circt }:
          pkgs.runCommand "${name}.sv" { buildInputs = [ circtPkg ]; } ''
            export CIRCT_OPT=${circtPkg}/bin/circt-opt
            ${pkgs.bash}/bin/bash ${pipelineScripts}/hw_clean_to_sv.sh ${hwClean} "$out"
          '';

        mkIlDerivation = { name, sv }:
          pkgs.runCommand "${name}.il" { buildInputs = [ yosysPkg ]; } ''
            export YOSYS=${yosysPkg}/bin/yosys
            export YOSYS_SLANG_SO=${yosysSlang}/share/yosys/plugins/slang.so
            ${pkgs.bash}/bin/bash ${pipelineScripts}/sv_to_il.sh ${sv} "$out"
          '';

        mkYosysStatDerivation = { name, sv }:
          pkgs.runCommand "${name}-yosys.stat" {
            buildInputs = [ yosysPkg ];
          } ''
            export YOSYS=${yosysPkg}/bin/yosys
            export YOSYS_SLANG_SO=${yosysSlang}/share/yosys/plugins/slang.so
            ${pkgs.bash}/bin/bash ${pipelineScripts}/sv_to_yosys_stat.sh ${sv} "$out"
          '';

        mkPipeline = { name, torchMlirInput, linalgLowering ? "affine"
          , handshakeInsertBuffers ? true, circtPkg ? circt }: rec {
            torch = mkTorchDerivation { inherit name torchMlirInput; };
            linalg = mkLinalgDerivation { inherit name torch; };
            cf = mkCfDerivation { inherit name linalg linalgLowering; };
            cfStats = mkCfStatsDerivation { inherit name cf; };
            handshake = mkHandshakeDerivation {
              inherit name cf handshakeInsertBuffers circtPkg;
            };
            hsExt = mkHsExtDerivation { inherit name handshake circtPkg; };
            hw0 = mkHw0Derivation { inherit name hsExt circtPkg; };
            hw = mkHwDerivation { inherit name hw0 circtPkg; };
            hwClean = mkHwCleanDerivation { inherit name hw circtPkg; };
            sv = mkSvDerivation { inherit name hwClean circtPkg; };
            il = mkIlDerivation { inherit name sv; };
            yosysStat = mkYosysStatDerivation { inherit name sv; };
          };

        registerModel = { name, torchMlirInput ? null, torchInputCommand ? null
          , torchInputBuildInputs ? [ ], linalgLowering ? "affine"
          , handshakeInsertBuffers ? true, circtPkg ? circt }:
          let
            resolvedTorchInput = if torchMlirInput != null then
              torchMlirInput
            else if torchInputCommand != null then
              pkgs.runCommand "${name}-torch-input.mlir" {
                buildInputs = torchInputBuildInputs;
              } ''
                set -euo pipefail
                ${torchInputCommand}
              ''
            else
              throw
              "registerModel(${name}): provide torchMlirInput or torchInputCommand";
            pipeline = mkPipeline {
              inherit name linalgLowering handshakeInsertBuffers circtPkg;
              torchMlirInput = resolvedTorchInput;
            };
          in {
            inherit name linalgLowering handshakeInsertBuffers circtPkg;
            torchInput = resolvedTorchInput;
            inherit pipeline;
          };

        # One-block model registration. Add entries here to get the full
        # torch->...->yosys-stat package ladder exposed automatically.
        modelRegistry = {
          matmul = registerModel {
            name = "matmul";
            torchInputBuildInputs = [ pythonWithTorch ];
            torchInputCommand = ''
              export MATMUL_PY=${./src/matmul.py}
              export PYTHONPATH="${./src}:${
                ./sim
              }:${torchMlir}/${python.sitePackages}:''${PYTHONPATH:-}"
              python ${./src/compile-pytorch.py} > "$out"
            '';
          };
          "tiny-stories-1m" = registerModel {
            name = "tiny-stories-1m";
            torchMlirInput = tinyStories1mTorchInput;
          };
        };

        modelPipelines =
          pkgs.lib.mapAttrs (_: model: model.pipeline) modelRegistry;

        mkPipelineStagePackages = name: pipeline: {
          "${name}-torch" = pipeline.torch;
          "${name}-linalg" = pipeline.linalg;
          "${name}-cf" = pipeline.cf;
          "${name}-cf-stats" = pipeline.cfStats;
          "${name}-handshake" = pipeline.handshake;
          "${name}-hs-ext" = pipeline.hsExt;
          "${name}-hw0" = pipeline.hw0;
          "${name}-hw" = pipeline.hw;
          "${name}-hw-clean" = pipeline.hwClean;
          "${name}-sv" = pipeline.sv;
          "${name}-il" = pipeline.il;
          "${name}-yosys-stat" = pipeline.yosysStat;
        };

        pipelineStagePackages =
          pkgs.lib.concatMapAttrs mkPipelineStagePackages modelPipelines;

        matmulPipeline = modelPipelines.matmul;
        matmulSv = matmulPipeline.sv;
        matmulIl = matmulPipeline.il;

        boardXdc = "${ypcbHack}/constraints/ypcb003381p1.xdc";
        mkTopSv = name: src:
          pkgs.runCommand "${name}.sv" { } ''
            cp ${src} "$out"
          '';

        mkMatmulJson = { name, topName, topSv }:
          pkgs.runCommand "${name}.json" { } ''
            ${yosysPkg}/bin/yosys -m ${yosysSlang}/share/yosys/plugins/slang.so -q -p "
                read_rtlil ${matmulIl}
                read_slang ${topSv}
                hierarchy -top ${topName} -check
                proc
                opt
                memory
                flatten
                synth_xilinx -family xc7 -top ${topName} -flatten -noiopad
                write_json $out
              "
          '';

        mkXdc = { name, includeBoardXdc ? true, extraConstraints ? [ ] }:
          let
            constraintFiles = (if includeBoardXdc then [ boardXdc ] else [ ])
              ++ extraConstraints;
          in pkgs.runCommand "${name}.xdc" { inherit constraintFiles; } ''
            cat $constraintFiles > "$out"
          '';

        mkFasm = { name, xdc, json }:
          pkgs.runCommand "${name}.fasm" { } ''
            if [ ! -f "${fpgaChipdb}" ]; then
              echo "chipdb file missing: ${fpgaChipdb}" >&2
              exit 1
            fi

            export OMP_NUM_THREADS=1
            ${openXC7Nextpnr}/bin/nextpnr-xilinx \
              --chipdb "${fpgaChipdb}" \
              --xdc ${xdc} \
              --json ${json} \
              --fasm "$out"
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

        matmulBitstreamTop =
          mkTopSv "matmul-bitstream-top" ./fpga/rtl/matmul_bitstream_top.sv;
        matmulBitstreamJson = mkMatmulJson {
          name = "matmul-bitstream";
          topName = "matmul_bitstream_top";
          topSv = matmulBitstreamTop;
        };
        matmulBitstreamXdc = mkXdc {
          name = "matmul-bitstream";
          extraConstraints = [ ./fpga/constraints/matmul_bitstream_ports.xdc ];
        };
        matmulFasm = mkFasm {
          name = "matmul-bitstream";
          xdc = matmulBitstreamXdc;
          json = matmulBitstreamJson;
        };
        matmulBitstream = mkBitstream {
          name = "matmul";
          fasm = matmulFasm;
          framesBase = "matmul";
        };

        matmulSelftestTop =
          mkTopSv "matmul-selftest-top" ./fpga/rtl/matmul_selftest_top.sv;
        matmulSelftestJson = mkMatmulJson {
          name = "matmul-selftest";
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
          torch-mlir = torchMlir;
          tb-data-sv = tbDataSv;
          sim-main = simMain;
          matmul-sv-sim = matmulSvSim;
          matmul-sv-wave = matmulSvWave;
          matmul-bitstream = matmulBitstream;
          matmul-fasm = matmulFasm;
          matmul-bitstream-fasm = matmulFasm;
          matmul-bitstream-top = matmulBitstreamTop;
          matmul-bitstream-xdc = matmulBitstreamXdc;
          matmul-bitstream-json = matmulBitstreamJson;
          matmul-selftest-bitstream = matmulSelftestBitstream;
          matmul-selftest-fasm = matmulSelftestFasm;
          matmul-selftest-top = matmulSelftestTop;
          matmul-selftest-xdc = matmulSelftestXdc;
          matmul-selftest-json = matmulSelftestJson;
        } // pipelineStagePackages;

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
