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
        circtBase =
          (circtPkgs.circt.override { enableSlang = false; }).overrideAttrs
          (old: {
            patches = (old.patches or [ ]) ++ [
              ./patches/circt-task3-rfp/0003-flatten-memref-shape-ops.patch
              ./patches/circt-task3-rfp/0004-handle-cfg-threaded-memrefs.patch
              ./patches/circt-task3-rfp/0005-support-extra-frontend-ops-in-handshake-to-hw.patch
              ./patches/circt-task3-rfp/0006-add-lsq-memory-lowering.patch
              ./patches/circt-task3-rfp/0008-mark-assert-and-math-illegal-in-handshake-to-hw.patch
              ./patches/circt-task3-rfp/0009-handle-dense-resource-globals-in-flatten-memrefs.patch
              ./patches/circt-task3-rfp/0010-lower-func-conversion-priority-in-handshake-to-hw.patch
              ./patches/circt-task3-rfp/0011-legalize-unrealized-conversion-casts-in-handshake-to-hw.patch
              ./patches/circt-task3-rfp/0012-defer-func-lowering-until-body-is-legal.patch
              ./patches/circt-task3-rfp/0013-handle-memref-model-io-and-cache-submodule-lookups.patch
              ./patches/circt-task3-rfp/0014-update-buffer-lowering-test-for-constant-order.patch
              ./patches/circt-task3-rfp/0015-lower-float-ops-as-externs-in-handshake-to-hw.patch
            ];
          });
        circt = circtBase;
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
        python = pkgsLlvm21.python311;
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
        pythonWithTinyStoriesTorchAO = python.withPackages
          (ps: [ ps.torch ps.packaging ps.transformers torchao ]);
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
        torchMlirPatched = pkgsLlvm21.callPackage ./torch-mlir.nix {
          inherit python;
          applyTask3RfpPatches = true;
        };
        torchMlirUnpatched = pkgsLlvm21.callPackage ./torch-mlir.nix {
          inherit python;
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
        pipelineLib = import ./nix/pipeline.nix {
          inherit pkgs mlir circt yosysPkg yosysSlang torchMlir python;
          inherit pipelineScripts;
        };
        modelRegistry = import ./nix/models.nix {
          inherit (pipelineLib) registerModel registerQuantizedModel;
          inherit pythonWithTorch pythonWithTinyStories
            pythonWithTinyStoriesTorchAO torchMlir python;
          inherit tinyStories1m;
          inherit fpPrimsSv;
          compilePyTorch = ./scripts/compile-pytorch.py;
          matmulPy = ./src/matmul.py;
          matmulAdapterPy = ./src/matmul_adapter.py;
          matmulSrcDir = ./src;
          tinyStoriesTorchaoAdapterPy = ./TinyStories/model_adapter_torchao.py;
          tinyStoriesPt2eStaticQuantAdapterPy =
            ./TinyStories/model_adapter_pt2e_static_quant.py;
          simDir = ./sim;
        };
        modelPipelines = pipelineLib.modelPipelinesFromRegistry modelRegistry;
        pipelineStagePackages =
          pipelineLib.pipelineStagePackagesFromRegistry modelRegistry;
        pipelineMetadataPackages =
          pipelineLib.metadataPackagesFromRegistry modelRegistry;
        modelRegistryJson = pipelineLib.registryIndexPackage modelRegistry;

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
            -f ${matmulSv}/sources.f ${./sim/tb_main.sv}
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
            -f ${matmulSv}/sources.f ${./sim/tb_main.sv}
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
          python-with-tiny-stories-torchao = pythonWithTinyStoriesTorchAO;
          model-registry = modelRegistryJson;
          tiny-stories-1m-snapshot = tinyStories1m.snapshot;
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
        } // pipelineStagePackages // pipelineMetadataPackages;

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
              -f ${matmulSv}/sources.f \
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
