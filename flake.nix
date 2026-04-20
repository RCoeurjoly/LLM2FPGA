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
    circt-src = {
      type = "github";
      owner = "RCoeurjoly";
      repo = "circt";
      ref = "task3";
      flake = false;
    };
    circt-nix = {
      url = "git+https://github.com/dtzSiFive/circt-nix?ref=main";
      inputs."circt-src".follows = "circt-src";
      inputs."llvm-submodule-src" = {
        type = "github";
        owner = "llvm";
        repo = "llvm-project";
        rev = "972cd847efb20661ea7ee8982dd19730aa040c75";
        flake = false;
      };
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
  };

  outputs = inputs@{ nixpkgs, nixpkgs-llvm21, flake-utils, yosys, circt-nix
    , nix-eda, openXC7, nextpnrXilinxFork, ypcbHack, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgsLlvm21 = import nixpkgs-llvm21 { inherit system; };
        circtPkgs = circt-nix.packages.${system};
        circtBase =
          (circtPkgs.circt.override { enableSlang = false; }).overrideAttrs
          (old: {
            patches = (old.patches or [ ]) ++ [
              # ./patches/circt-task3-rfp/0003-flatten-memref-shape-ops.patch
              # ./patches/circt-task3-rfp/0004-handle-cfg-threaded-memrefs.patch
              # ./patches/circt-task3-rfp/0005-support-extra-frontend-ops-in-handshake-to-hw.patch
              # ./patches/circt-task3-rfp/0008-mark-assert-and-math-illegal-in-handshake-to-hw.patch
              # ./patches/circt-task3-rfp/0009-handle-dense-resource-globals-in-flatten-memrefs.patch
              # ./patches/circt-task3-rfp/0010-lower-func-conversion-priority-in-handshake-to-hw.patch
              # ./patches/circt-task3-rfp/0011-legalize-unrealized-conversion-casts-in-handshake-to-hw.patch
              # ./patches/circt-task3-rfp/0012-defer-func-lowering-until-body-is-legal.patch
              # ./patches/circt-task3-rfp/0013-handle-memref-model-io-and-cache-submodule-lookups.patch
              # ./patches/circt-task3-rfp/0014-update-buffer-lowering-test-for-constant-order.patch
              # ./patches/circt-task3-rfp/0015-lower-float-ops-as-externs-in-handshake-to-hw.patch
            ];
          });
        # Keep reviewer builds on a pinned upstream CIRCT plus the checked-in
        # Task 3 patch stack. Local fast iteration should use local binaries via
        # scripts/dev rather than a flake input override.
        circt = circtBase;
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
        pythonWithTorch = python.withPackages (ps: [ ps.torch ps.packaging ]);
        pythonWithTinyStories =
          python.withPackages (ps: [ ps.torch ps.packaging ps.transformers ]);
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
        torchMlir = pkgsLlvm21.callPackage ./torch-mlir.nix {
          inherit python;
          nanobind = nanobindBootstrap;
          inherit (torchMlirLlvmPackages) tblgen;
          mlir = mlirForTorchMlir;
          inherit (torchMlirLlvmPackages) llvm;
        };

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
          inherit (pipelineLib) registerModel;
          inherit pythonWithTorch pythonWithTinyStories torchMlir python;
          inherit tinyStories1m;
          inherit fpPrimsSv;
          compilePyTorch = ./scripts/compile-pytorch.py;
          matmulPy = ./src/matmul.py;
          matmulAdapterPy = ./src/matmul_adapter.py;
          matmulSrcDir = ./src;
          simDir = ./sim;
        };

        pipelineStagePackages =
          pipelineLib.pipelineStagePackagesFromRegistry modelRegistry;

        matmulSv = modelRegistry.matmul.pipeline.sv;
        matmulIl = modelRegistry.matmul.pipeline.il;
        tinyStories1mBaselineFloatSv =
          modelRegistry."tiny-stories-1m-baseline-float".pipeline.sv;
        tinyStories1mBaselineFloatIl =
          modelRegistry."tiny-stories-1m-baseline-float".pipeline.il;
        tinyStories1mBaselineFloatMainSv =
          "${tinyStories1mBaselineFloatSv}/sv/main.sv";
        fpgaCapacities = {
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

        synthStageNames = [
          "stage1"
          "stage2"
          "stage3"
          "stage4"
          "stage5"
          "stage6"
          "stage7"
          "stage8"
          "stage9"
        ];

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

        mkSynthJsonStages = { name, modelIl, topName, topSv ? null
          , quiet ? false, memoryLimitKb ? null }: rec {
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

            stage5 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage5";
              stageLabel = "stage5 synth_xilinx fine:fine";
              inputIl = stage4;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run fine:fine"
              ];
            };

            stage6 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage6";
              stageLabel = "stage6 synth_xilinx map_cells:map_cells";
              inputIl = stage5;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run map_cells:map_cells"
              ];
            };

            stage7 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage7";
              stageLabel = "stage7 synth_xilinx map_ffs:map_ffs";
              inputIl = stage6;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run map_ffs:map_ffs"
              ];
            };

            stage8 = mkSynthStageIl {
              inherit name topName quiet memoryLimitKb;
              stageId = "stage8";
              stageLabel = "stage8 final synth/write";
              inputIl = stage7;
              commands = [
                "synth_xilinx -family xc7 -top ${topName} -noiopad -run map_luts:check"
              ];
            };

            stage9 = mkSynthStageJson {
              inherit name quiet memoryLimitKb;
              stageId = "stage9";
              stageLabel = "stage9 write_json";
              inputIl = stage8;
            };

            json = stage9;
          };

        mkSynthJson = { name, modelIl, topName, topSv ? null, quiet ? false
          , memoryLimitKb ? null }:
          pkgs.runCommand "${name}.json" { } ''
            cat > run.ys <<EOF
            read_rtlil ${modelIl}
            ${pkgs.lib.optionalString (topSv != null) "read_slang ${topSv}"}
            hierarchy -top ${topName} -check
            proc
            synth_xilinx -family xc7 -top ${topName} -noiopad -json $out
            EOF

            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}

            echo "[mkSynthJson:${name}] stage8 final synth/write" >&2
            ${yosysPkg}/bin/yosys ${pkgs.lib.optionalString quiet "-q"} ${
              pkgs.lib.optionalString (topSv != null)
              "-m ${yosysSlang}/share/yosys/plugins/slang.so"
            } -s run.ys

            if [ ! -e "$out" ]; then
              echo "mkSynthJson expected output path was not created: $out" >&2
              echo "--- run.ys ---" >&2
              cat run.ys >&2
              exit 1
            fi
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

        mkSynthStagePackages = prefix: stages:
          builtins.listToAttrs (map (stageName: {
            name = "${prefix}-${stageName}";
            value = builtins.getAttr stageName stages;
          }) synthStageNames);

        mkExternalizedMemoryPlan =
          { name, modelIl, minModuleBits ? (128 * 1024) }:
          pkgs.runCommand "${name}-external-memory-plan" { } ''
            ${pkgs.python311}/bin/python3 ${
              ./scripts/pipeline/externalize_large_memories.py
            } \
              --input ${modelIl} \
              --output-script externalize.ys \
              --output-report report.json \
              --min-module-bits ${toString minModuleBits}
            mkdir -p "$out"
            cp externalize.ys "$out/externalize.ys"
            cp report.json "$out/report.json"
          '';

        mkTinyStoriesSelftestBundle = { name, topName, mainSv, modelIl
          , capacities, externalMemoryMinModuleBits ? (128 * 1024) }:
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
            };
            utilizationReport = mkMappedJsonUtilizationReport {
              inherit name capacities topName;
              designJson = stages.json;
            };
          in { inherit stages utilizationReport; };

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

        tinyStories1mBaselineFloatSynthStages = mkSynthJsonStages {
          name = "tiny-stories-1m-baseline-float";
          modelIl = tinyStories1mBaselineFloatIl;
          topName = "main";
          quiet = true;
        };
        tinyStories1mBaselineFloatUtilizationReport =
          mkMappedJsonUtilizationReport {
            name = "tiny-stories-1m-baseline-float";
            capacities = fpgaCapacities;
            topName = "main";
            designJson = tinyStories1mBaselineFloatSynthStages.json;
          };
        tinyStories1mBaselineFloatSelftestAllMemory =
          mkTinyStoriesSelftestBundle {
            name = "tiny-stories-1m-baseline-float-selftest-all-memory";
            topName = "tiny_stories_selftest_top";
            mainSv = tinyStories1mBaselineFloatMainSv;
            modelIl = tinyStories1mBaselineFloatIl;
            capacities = fpgaCapacities;
          };
        synthStagePackages =
          mkSynthStagePackages "tiny-stories-1m-baseline-float"
          tinyStories1mBaselineFloatSynthStages // mkSynthStagePackages
          "tiny-stories-1m-baseline-float-selftest-all-memory"
          tinyStories1mBaselineFloatSelftestAllMemory.stages;

        matmulBitstreamTop = ./fpga/rtl/matmul_bitstream_top.sv;
        matmulBitstreamJson = mkSynthJson {
          name = "matmul-bitstream";
          modelIl = matmulIl;
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

        matmulSelftestTop = ./fpga/rtl/matmul_selftest_top.sv;
        matmulSelftestJson = mkSynthJson {
          name = "matmul-selftest";
          modelIl = matmulIl;
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
          inherit circt;
          python-with-torch = pythonWithTorch;
          yosys = yosysPkg;
          yosys-slang = yosysSlang;
          torch-mlir = torchMlir;
          tb-data-sv = tbDataSv;
          sim-main = simMain;
          matmul-sv-sim = matmulSvSim;
          matmul-sv-wave = matmulSvWave;
          matmul-bitstream = matmulBitstream;
          matmul-fasm = matmulFasm;
          matmul-bitstream-fasm = matmulFasm;
          matmul-bitstream-xdc = matmulBitstreamXdc;
          matmul-bitstream-json = matmulBitstreamJson;
          matmul-selftest-bitstream = matmulSelftestBitstream;
          matmul-selftest-fasm = matmulSelftestFasm;
          matmul-selftest-xdc = matmulSelftestXdc;
          matmul-selftest-json = matmulSelftestJson;
          tiny-stories-1m-baseline-float-utilization =
            tinyStories1mBaselineFloatUtilizationReport;
          tiny-stories-1m-baseline-float-selftest-all-memory-utilization =
            tinyStories1mBaselineFloatSelftestAllMemory.utilizationReport;
          tiny-stories-1m-snapshot = tinyStories1m.snapshot;
        } // pipelineStagePackages // synthStagePackages;

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
