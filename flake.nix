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
        "git+https://github.com/RCoeurjoly/nextpnr-xilinx?ref=fix-net-old-indices-upstream-pr&submodules=1";
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
        torchao = python.pkgs.buildPythonPackage rec {
          pname = "torchao";
          version = "0.15.0";
          format = "wheel";
          src = pkgs.fetchurl {
            url =
              "https://files.pythonhosted.org/packages/f6/3b/6b9d5618720f63dbc2e2509cd6b57aae9c0d61b738d1d2172f4d5d9efaab/torchao-0.15.0-py3-none-any.whl";
            hash = "sha256-PzgSZ2BI74oqDp1JLRLYlxunp+uxb1SqVvaQQU4TDSw=";
          };
          propagatedBuildInputs = [ python.pkgs.torch python.pkgs.packaging ];
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
        # Local copy of the source-based package proposed in:
        # https://github.com/NixOS/nixpkgs/pull/490242
        # Built out-of-tree against a separate LLVM/MLIR derivation so torch-mlir
        # changes do not force rebuilding LLVM. The current baseline-float Task 3
        # reviewer path is being validated against upstream-unpatched torch-mlir;
        # keep the historical patch stack available for follow-up quantized
        # experiments until that cleanup is fully settled.
        mkTorchMlir = applyTask3RfpPatches: pkgsLlvm21.callPackage ./torch-mlir.nix {
          inherit applyTask3RfpPatches python;
          nanobind = nanobindBootstrap;
          inherit (torchMlirLlvmPackages) tblgen;
          mlir = mlirForTorchMlir;
          inherit (torchMlirLlvmPackages) llvm;
        };
        torchMlirPatched = mkTorchMlir true;
        torchMlirUnpatched = mkTorchMlir false;
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
          inherit pythonWithTorch pythonWithTorchAO pythonWithTinyStories
            pythonWithTinyStoriesTorchAO torchMlir python;
          inherit tinyStories1m;
          inherit fpPrimsSv;
          compilePyTorch = ./scripts/compile-pytorch.py;
          matmulPy = ./src/matmul.py;
          matmulAdapterPy = ./src/matmul_adapter.py;
          matmulSrcDir = ./src;
          torchaoInt8DynamicLinearAdapterPy =
            ./src/torchao_int8_dynamic_linear_adapter.py;
          torchaoInt8WeightOnlyLinearAdapterPy =
            ./src/torchao_int8_weight_only_linear_adapter.py;
          torchaoAttentionBlockAdapterPy =
            ./src/torchao_attention_block_adapter.py;
          pt2eQuantLinearAdapterPy = ./src/pt2e_quant_linear_adapter.py;
          pt2eStaticQuantLinearAdapterPy =
            ./src/pt2e_static_quant_linear_adapter.py;
          pt2eStaticQuantEmbeddingAdapterPy =
            ./src/pt2e_static_quant_embedding_adapter.py;
          pt2eStaticQuantEmbeddingComposableAdapterPy =
            ./src/pt2e_static_quant_embedding_composable_adapter.py;
          pt2eStaticQuantLayerNormAdapterPy =
            ./src/pt2e_static_quant_layer_norm_adapter.py;
          pt2eStaticQuantSoftmaxAdapterPy =
            ./src/pt2e_static_quant_softmax_adapter.py;
          pt2eStaticQuantAttentionBlockAdapterPy =
            ./src/pt2e_static_quant_attention_block_adapter.py;
          pt2eStaticQuantAttentionBlockNoSoftmaxAdapterPy =
            ./src/pt2e_static_quant_attention_block_no_softmax_adapter.py;
          pt2eStaticQuantAttentionBlockNoLayerNormAdapterPy =
            ./src/pt2e_static_quant_attention_block_no_layer_norm_adapter.py;
          pt2eStaticQuantAttentionSoftmaxAdapterPy =
            ./src/pt2e_static_quant_attention_softmax_adapter.py;
          pt2eStaticQuantAttentionValueMatmulAdapterPy =
            ./src/pt2e_static_quant_attention_value_matmul_adapter.py;
          pt2eStaticQuantMatmulX86AdapterPy =
            ./src/pt2e_static_quant_matmul_x86_adapter.py;
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
        matmulSv = matmulPipeline.sv;
        matmulIl = matmulPipeline.il;
        tinyStories1mPipeline = modelPipelines."tiny-stories-1m";
        tinyStories1mSv = tinyStories1mPipeline.sv;
        tinyStories1mIl = tinyStories1mPipeline.il;
        tinyStories1mBaselineFloatPipeline =
          modelPipelines."tiny-stories-1m-baseline-float";
        tinyStories1mBaselineFloatIl = tinyStories1mBaselineFloatPipeline.il;
        tinyStoriesCapacities = {
          slices = 74650;
          clb_luts = 298600;
          clb_ffs = 597200;
          dsp = 1920;
          bram36 = 955;
          bram_kb = 34380;
        };

        boardXdc = "${ypcbHack}/constraints/ypcb003381p1.xdc";
        mkTopSv = name: src:
          pkgs.runCommand "${name}.sv" { } ''
            cp ${src} "$out"
          '';

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
          , topSv ? null, quiet ? false, memoryLimitKb ? null
          , preCommands ? [ ], commands }:
          pkgs.runCommand "${name}-${stageId}.il" { } ''
            cat > run.ys <<EOF
            ${builtins.concatStringsSep "\n" (
              [ "read_rtlil ${inputIl}" ]
              ++ pkgs.lib.optional (topSv != null) "read_slang ${topSv}"
              ++ [ "hierarchy -top ${topName} -check" ]
              ++ preCommands
              ++ commands
              ++ [ "write_rtlil $out" ]
            )}
            EOF

            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}

            echo "[mkSynthJson:${name}] ${stageLabel}" >&2
            ${yosysPkg}/bin/yosys ${
              pkgs.lib.optionalString quiet "-q"
            } ${
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
          , quiet ? false, memoryLimitKb ? null }:
          rec {
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
          , memoryLimitKb ? null, staged ? false, }:
          if staged then
            (mkSynthJsonStages {
              inherit name modelIl topName topSv quiet memoryLimitKb;
            }).json
          else
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

        mkSynthStagePackages = prefix: stages:
          builtins.listToAttrs (map (stageName: {
            name = "${prefix}-${stageName}";
            value = builtins.getAttr stageName stages;
          }) synthStageNames);

        mkExternalizedMemoryPlan =
          { name, modelIl, minModuleBits ? (128 * 1024) }:
          pkgs.runCommand "${name}-external-memory-plan" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
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

        mkTinyStoriesSelftestBundle =
          { name, topName, mainSv, modelIl, capacities
          , externalMemoryMinModuleBits ? (128 * 1024) }:
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
            json = stages.json;
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
          in {
            inherit top modelOptIl modelShellIl externalMemoryPlan stages json
              yosysJson utilizationReport;
          };

        mkXdc = { name, includeBoardXdc ? true, extraConstraints ? [ ] }:
          let
            constraintFiles = (if includeBoardXdc then [ boardXdc ] else [ ])
              ++ extraConstraints;
          in pkgs.runCommand "${name}.xdc" { inherit constraintFiles; } ''
            cat $constraintFiles > "$out"
          '';

        mkMappedJsonUtilizationReport =
          { name, designJson, topName, capacities }:
          pkgs.runCommand "${name}-utilization" {
            buildInputs = [ pkgs.python311 ];
          } ''
            cat <<'PY' | sed 's/^            //' | ${pkgs.python311}/bin/python3
            import json
            import re
            from collections import Counter

            design_json = "${designJson}"
            top_name = "${topName}"

            modules_line_re = re.compile(r'^  "modules": \{$')
            module_line_re = re.compile(r'^    "([^"]+)": \{$')
            cells_line_re = re.compile(r'^\s*"cells": \{$')
            type_line_re = re.compile(r'^\s*"type": "([^"]+)"')
            end_cells_re = re.compile(r'^      }\s*,?\s*$')
            end_module_re = re.compile(r'^    }\s*,?\s*$')
            end_modules_re = re.compile(r'^  }\s*,?\s*$')

            in_modules = False
            current_module = None
            in_cells = False
            module_counts = {}

            with open(design_json, "r", encoding="utf-8") as f:
              for line in f:
                line = line.rstrip("\n")
                if not in_modules:
                  if modules_line_re.match(line):
                    in_modules = True
                  continue

                if current_module is None:
                  module_match = module_line_re.match(line)
                  if module_match:
                    current_module = module_match.group(1)
                    module_counts[current_module] = Counter()
                    continue
                  if end_modules_re.match(line):
                    break
                  continue

                if not in_cells:
                  if cells_line_re.match(line):
                    in_cells = True
                    continue
                  if end_module_re.match(line):
                    current_module = None
                  continue

                type_match = type_line_re.match(line)
                if type_match:
                  module_counts[current_module][type_match.group(1)] += 1
                  continue

                if end_cells_re.match(line):
                  in_cells = False

            if top_name not in module_counts:
              raise SystemExit(f"top module not found in mapped JSON: {top_name}")

            memo = {}
            visiting = set()

            def hierarchical_counts(module_name: str) -> Counter:
              if module_name in memo:
                return memo[module_name]
              if module_name in visiting:
                raise SystemExit(f"cycle detected while expanding module hierarchy: {module_name}")
              visiting.add(module_name)
              total = Counter()
              for cell_type, cell_count in module_counts.get(module_name, {}).items():
                if cell_type in module_counts:
                  child_counts = hierarchical_counts(cell_type)
                  for child_type, child_count in child_counts.items():
                    total[child_type] += child_count * cell_count
                else:
                  total[cell_type] += cell_count
              visiting.remove(module_name)
              memo[module_name] = total
              return total

            counts = hierarchical_counts(top_name)

            def count(name: str) -> int:
              return counts.get(name, 0)

            def pct(used, cap):
              return None if cap == 0 else (used * 100.0 / cap)

            capacities = {
              "slices": ${toString capacities.slices},
              "clb_luts": ${toString capacities.clb_luts},
              "clb_ffs": ${toString capacities.clb_ffs},
              "dsp": ${toString capacities.dsp},
              "bram36": ${toString capacities.bram36},
              "bram_kb": ${toString capacities.bram_kb},
            }

            usage = {
              "lut_total": sum(count(name) for name in ["LUT1", "LUT2", "LUT3", "LUT4", "LUT5", "LUT6"]),
              "muxf7": count("MUXF7"),
              "muxf8": count("MUXF8"),
              "ff_total": sum(count(name) for name in ["FDRE", "FDSE", "FDCE", "FDPE"]),
              "dsp_total": sum(count(name) for name in ["DSP48E1", "DSP48E2", "DSP48A", "DSP48A1", "DSP48"]),
              "bram36_total": sum(count(name) for name in ["RAMB36E1", "RAMB36E2", "FIFO36E1", "FIFO36E2"]),
              "bram18_total": sum(count(name) for name in ["RAMB18E1", "RAMB18E2", "FIFO18E1", "FIFO18E2"]),
              "lutram_ram32m": count("RAM32M"),
              "lutram_ram64m": count("RAM64M"),
            }
            usage["bram36_equivalent"] = usage["bram36_total"] + (usage["bram18_total"] / 2.0)

            summary = {
              "top_module": top_name,
              "capacities": capacities,
              "usage": usage,
              "utilization": {
                "lut_pct": pct(usage["lut_total"], capacities["clb_luts"]),
                "ff_pct": pct(usage["ff_total"], capacities["clb_ffs"]),
                "dsp_pct": pct(usage["dsp_total"], capacities["dsp"]),
                "bram36_equivalent_pct": pct(usage["bram36_equivalent"], capacities["bram36"]),
              },
            }
            summary["fits"] = {
              "lut": usage["lut_total"] <= capacities["clb_luts"],
              "ff": usage["ff_total"] <= capacities["clb_ffs"],
              "dsp": usage["dsp_total"] <= capacities["dsp"],
              "bram36_equivalent": usage["bram36_equivalent"] <= capacities["bram36"],
            }
            summary["fits"]["overall"] = all(summary["fits"].values())

            stat = {
              "top_module": top_name,
              "hierarchical": True,
              "num_cells_by_type": dict(sorted(counts.items())),
            }

            with open("stat.json", "w", encoding="utf-8") as f:
              json.dump(stat, f, indent=2, sort_keys=True)
              f.write("\n")

            with open("summary.json", "w", encoding="utf-8") as f:
              json.dump(summary, f, indent=2, sort_keys=True)
              f.write("\n")

            with open("summary.txt", "w", encoding="utf-8") as f:
              f.write(f"top_module: {summary['top_module']}\n")
              f.write(f"lut_total: {usage['lut_total']} / {capacities['clb_luts']} ({summary['utilization']['lut_pct']}%)\n")
              f.write(f"ff_total: {usage['ff_total']} / {capacities['clb_ffs']} ({summary['utilization']['ff_pct']}%)\n")
              f.write(f"dsp_total: {usage['dsp_total']} / {capacities['dsp']} ({summary['utilization']['dsp_pct']}%)\n")
              f.write(f"bram36_equivalent: {usage['bram36_equivalent']} / {capacities['bram36']} ({summary['utilization']['bram36_equivalent_pct']}%)\n")
              f.write(f"muxf7: {usage['muxf7']}\n")
              f.write(f"muxf8: {usage['muxf8']}\n")
              f.write(f"lutram_ram32m: {usage['lutram_ram32m']}\n")
              f.write(f"lutram_ram64m: {usage['lutram_ram64m']}\n")
              f.write(f"fits_overall: {summary['fits']['overall']}\n")
            PY

            mkdir -p "$out"
            cp stat.json "$out/stat.json"
            cp summary.json "$out/summary.json"
            cp summary.txt "$out/summary.txt"
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

        matmulBitstreamTop =
          mkTopSv "matmul-bitstream-top" ./fpga/rtl/matmul_bitstream_top.sv;
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

        matmulSelftestTop =
          mkTopSv "matmul-selftest-top" ./fpga/rtl/matmul_selftest_top.sv;
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
        tinyStories1mUtilizationStages = mkSynthJsonStages {
          name = "tiny-stories-1m-utilization";
          topName = "main";
          modelIl = tinyStories1mIl;
          quiet = true;
        };
        tinyStories1mUtilizationJson = tinyStories1mUtilizationStages.json;
        tinyStories1mUtilizationReport = mkMappedJsonUtilizationReport {
          name = "tiny-stories-1m";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = tinyStories1mUtilizationJson;
        };
        tinyStories1mBaselineFloatUtilizationStages = mkSynthJsonStages {
          name = "tiny-stories-1m-baseline-float-utilization";
          topName = "main";
          modelIl = tinyStories1mBaselineFloatIl;
          quiet = true;
        };
        tinyStories1mBaselineFloatUtilizationJson =
          tinyStories1mBaselineFloatUtilizationStages.json;
        tinyStories1mBaselineFloatUtilizationReport =
          mkMappedJsonUtilizationReport {
            name = "tiny-stories-1m-baseline-float";
            capacities = tinyStoriesCapacities;
            topName = "main";
            designJson = tinyStories1mBaselineFloatUtilizationJson;
          };
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
        synthStagePackages =
          mkSynthStagePackages "tiny-stories-1m-utilization"
          tinyStories1mUtilizationStages
          // mkSynthStagePackages "tiny-stories-1m-selftest-all-memory"
          tinyStories1mSelftestAllMemory.stages
          // mkSynthStagePackages "tiny-stories-1m-baseline-float-utilization"
          tinyStories1mBaselineFloatUtilizationStages
          // mkSynthStagePackages
          "tiny-stories-1m-baseline-float-selftest-all-memory"
          tinyStories1mBaselineFloatSelftestAllMemory.stages;

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
            pythonWithTorchAO
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
          inherit circt torchao;
          python-with-torch = pythonWithTorch;
          python-with-torchao = pythonWithTorchAO;
          python-with-tiny-stories = pythonWithTinyStories;
          python-with-tiny-stories-torchao = pythonWithTinyStoriesTorchAO;
          yosys = yosysPkg;
          yosys-slang = yosysSlang;
          torch-mlir = torchMlir;
          torch-mlir-patched = torchMlirPatched;
          torch-mlir-unpatched = torchMlirUnpatched;
          torch-mlir-llvm = torchMlirLlvmPackages.llvm;
          torch-mlir-mlir = mlirForTorchMlir;
          model-registry = modelRegistryJson;
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
          tiny-stories-1m-utilization-json = tinyStories1mUtilizationJson;
          tiny-stories-1m-utilization = tinyStories1mUtilizationReport;
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
          tiny-stories-1m-baseline-float-utilization-json =
            tinyStories1mBaselineFloatUtilizationJson;
          tiny-stories-1m-baseline-float-utilization =
            tinyStories1mBaselineFloatUtilizationReport;
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
          tiny-stories-1m-snapshot = tinyStories1m.snapshot;
        } // pipelineStagePackages // pipelineMetadataPackages
          // synthStagePackages;

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
