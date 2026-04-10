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
              ./patches/circt-task3-rfp/0007-lower-lazy-fork-to-hw.patch
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
        # changes do not force rebuilding LLVM. Reviewer builds use the pinned
        # upstream torch-mlir source from torch-mlir.nix; local compiler
        # iteration should continue through scripts/dev and a local binary.
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
            cat > run.ys <<'EOF'
            ${script}
            EOF
            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}
            ${yosysPkg}/bin/yosys ${
              pkgs.lib.optionalString quiet "-q"
            } -m ${yosysSlang}/share/yosys/plugins/slang.so -s run.ys
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

        mkSynthJson = { name, modelIl, topName, topSv ? null, quiet ? false
          , memoryLimitKb ? null, staged ? false, }:
          pkgs.runCommand "${name}.json" { } ''
            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}

            if ${if staged then "true" else "false"}; then
              printf '%s\n' \
                'read_rtlil ${modelIl}' \
                ${pkgs.lib.optionalString (topSv != null)
                "'read_slang ${topSv}' \\"}
                'hierarchy -top ${topName} -check' \
                'synth_xilinx -family xc7 -top ${topName} -noiopad -run begin:prepare' \
                'write_rtlil stage1.il' \
                > stage1.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -m ${yosysSlang}/share/yosys/plugins/slang.so -s stage1.ys

              printf '%s\n' \
                'read_rtlil stage1.il' \
                'hierarchy -top ${topName} -check' \
                'synth_xilinx -family xc7 -top ${topName} -noiopad -run coarse:map_memory' \
                'write_rtlil stage2.il' \
                > stage2.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s stage2.ys

              printf '%s\n' \
                'read_rtlil stage2.il' \
                'hierarchy -top ${topName} -check' \
                'opt -fast -full' \
                'write_rtlil stage3.il' \
                > stage3.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s stage3.ys

              awk '
                /^module / { mod = $2 }
                /^[[:space:]]*cell \$mem/ { mods[mod] = 1 }
                END {
                  for (mod in mods)
                    print mod
                }
              ' stage3.il | sort > stage4-modules.txt

              printf '%s\n' \
                'read_rtlil stage3.il' \
                'hierarchy -top ${topName} -check' \
                > stage4.ys

              while IFS= read -r moduleName; do
                printf '%s\n' \
                  "cd $moduleName" \
                  'memory_map' \
                  'cd ..' \
                  >> stage4.ys
              done < stage4-modules.txt

              printf '%s\n' \
                'write_rtlil stage4.il' \
                >> stage4.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s stage4.ys

              printf '%s\n' \
                'read_rtlil stage4.il' \
                'hierarchy -top ${topName} -check' \
                'synth_xilinx -family xc7 -top ${topName} -noiopad -run fine:fine' \
                'write_rtlil stage5.il' \
                > stage5.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s stage5.ys

              printf '%s\n' \
                'read_rtlil stage5.il' \
                'hierarchy -top ${topName} -check' \
                'synth_xilinx -family xc7 -top ${topName} -noiopad -run map_cells:map_cells' \
                'write_rtlil stage6.il' \
                > stage6.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s stage6.ys

              printf '%s\n' \
                'read_rtlil stage6.il' \
                'hierarchy -top ${topName} -check' \
                'synth_xilinx -family xc7 -top ${topName} -noiopad -run map_ffs:map_ffs' \
                'write_rtlil stage7.il' \
                > stage7.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s stage7.ys

              printf '%s\n' \
                'read_rtlil stage7.il' \
                'hierarchy -top ${topName} -check' \
                'synth_xilinx -family xc7 -top ${topName} -noiopad -run map_luts:check' \
                'write_rtlil stage8.il' \
                > stage8.ys
            else
              printf '%s\n' \
                'read_rtlil ${modelIl}' \
                ${pkgs.lib.optionalString (topSv != null)
                "'read_slang ${topSv}' \\"}
                'hierarchy -top ${topName} -check' \
                "synth_xilinx -family xc7 -top ${topName} -noiopad -json $out" \
                > stage8.ys
            fi

            ${yosysPkg}/bin/yosys ${pkgs.lib.optionalString quiet "-q"} ${
              pkgs.lib.optionalString (!staged)
              "-m ${yosysSlang}/share/yosys/plugins/slang.so"
            } -s stage8.ys

            ${pkgs.lib.optionalString staged ''
              ${pkgs.python311}/bin/python3 ${
                ./scripts/pipeline/filter_rtlil_modules.py
              } \
                --input stage8.il \
                --output stage8-stripped.il \
                --drop-escaped-uppercase-modules

              printf '%s\n' \
                'read_rtlil stage8-stripped.il' \
                "write_json $out" \
                > stage9.ys

              ${yosysPkg}/bin/yosys ${
                pkgs.lib.optionalString quiet "-q"
              } -s stage9.ys
            ''}

            if [ ! -e "$out" ]; then
              echo "mkSynthJson expected output path was not created: $out" >&2
              echo "--- stage8.ys ---" >&2
              cat stage8.ys >&2
              if [ -f stage9.ys ]; then
                echo "--- stage9.ys ---" >&2
                cat stage9.ys >&2
              fi
              echo "--- workspace ---" >&2
              ls -lah >&2
              echo "--- json files ---" >&2
              find . -maxdepth 2 -name '*.json' -print >&2 || true
              exit 1
            fi
          '';

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
            buildInputs = [ yosysPkg pkgs.jq ];
          } ''
            cat > run.ys <<'EOF'
            read_json ${designJson}
            tee -o stat.json stat -top ${topName} -hierarchy -json
            EOF

            ${yosysPkg}/bin/yosys -q -s run.ys

            top_key="\\${topName}"
            jq \
              --arg top_key "$top_key" \
              --argjson slices ${toString capacities.slices} \
              --argjson clb_luts ${toString capacities.clb_luts} \
              --argjson clb_ffs ${toString capacities.clb_ffs} \
              --argjson dsp ${toString capacities.dsp} \
              --argjson bram36 ${toString capacities.bram36} \
              --argjson bram_kb ${toString capacities.bram_kb} \
              '
                def count($obj; $key):
                  (($obj.num_cells_by_type[$key].count // "0") | tonumber);
                def pct($used; $cap):
                  if $cap == 0 then null else ($used * 100.0 / $cap) end;

                (.modules[$top_key] // .design) as $top
                | ($top.num_cells_by_type // {}) as $cells
                | {
                    top_module: ($top_key | ltrimstr("\\")),
                    capacities: {
                      slices: $slices,
                      clb_luts: $clb_luts,
                      clb_ffs: $clb_ffs,
                      dsp: $dsp,
                      bram36: $bram36,
                      bram_kb: $bram_kb
                    },
                    usage: {
                      lut_total:
                        (count($top; "LUT1") + count($top; "LUT2") +
                         count($top; "LUT3") + count($top; "LUT4") +
                         count($top; "LUT5") + count($top; "LUT6")),
                      muxf7: count($top; "MUXF7"),
                      muxf8: count($top; "MUXF8"),
                      ff_total:
                        (count($top; "FDRE") + count($top; "FDSE") +
                         count($top; "FDCE") + count($top; "FDPE")),
                      dsp_total:
                        (count($top; "DSP48E1") + count($top; "DSP48E2") +
                         count($top; "DSP48A") + count($top; "DSP48A1") +
                         count($top; "DSP48")),
                      bram36_total:
                        (count($top; "RAMB36E1") + count($top; "RAMB36E2") +
                         count($top; "FIFO36E1") + count($top; "FIFO36E2")),
                      bram18_total:
                        (count($top; "RAMB18E1") + count($top; "RAMB18E2") +
                         count($top; "FIFO18E1") + count($top; "FIFO18E2")),
                      lutram_ram32m: count($top; "RAM32M"),
                      lutram_ram64m: count($top; "RAM64M")
                    }
                  }
                | .usage.bram36_equivalent =
                    (.usage.bram36_total + (.usage.bram18_total / 2.0))
                | .utilization = {
                    lut_pct: pct(.usage.lut_total; .capacities.clb_luts),
                    ff_pct: pct(.usage.ff_total; .capacities.clb_ffs),
                    dsp_pct: pct(.usage.dsp_total; .capacities.dsp),
                    bram36_equivalent_pct:
                      pct(.usage.bram36_equivalent; .capacities.bram36)
                  }
                | .fits = {
                    lut: (.usage.lut_total <= .capacities.clb_luts),
                    ff: (.usage.ff_total <= .capacities.clb_ffs),
                    dsp: (.usage.dsp_total <= .capacities.dsp),
                    bram36_equivalent:
                      (.usage.bram36_equivalent <= .capacities.bram36),
                    overall:
                      ((.usage.lut_total <= .capacities.clb_luts) and
                       (.usage.ff_total <= .capacities.clb_ffs) and
                       (.usage.dsp_total <= .capacities.dsp) and
                       (.usage.bram36_equivalent <= .capacities.bram36))
                  }
              ' stat.json > summary.json

            jq -r '
              [
                "top_module: " + .top_module,
                "lut_total: " + (.usage.lut_total | tostring) + " / " + (.capacities.clb_luts | tostring) + " (" + (.utilization.lut_pct | tostring) + "%)",
                "ff_total: " + (.usage.ff_total | tostring) + " / " + (.capacities.clb_ffs | tostring) + " (" + (.utilization.ff_pct | tostring) + "%)",
                "dsp_total: " + (.usage.dsp_total | tostring) + " / " + (.capacities.dsp | tostring) + " (" + (.utilization.dsp_pct | tostring) + "%)",
                "bram36_equivalent: " + (.usage.bram36_equivalent | tostring) + " / " + (.capacities.bram36 | tostring) + " (" + (.utilization.bram36_equivalent_pct | tostring) + "%)",
                "muxf7: " + (.usage.muxf7 | tostring),
                "muxf8: " + (.usage.muxf8 | tostring),
                "lutram_ram32m: " + (.usage.lutram_ram32m | tostring),
                "lutram_ram64m: " + (.usage.lutram_ram64m | tostring),
                "fits_overall: " + (.fits.overall | tostring)
              ] | .[]
            ' summary.json > summary.txt

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
        tinyStories1mUtilizationJson = mkSynthJson {
          name = "tiny-stories-1m-utilization";
          topName = "main";
          modelIl = tinyStories1mIl;
          staged = true;
          quiet = true;
        };
        tinyStories1mUtilizationReport = mkMappedJsonUtilizationReport {
          name = "tiny-stories-1m";
          capacities = tinyStoriesCapacities;
          topName = "main";
          designJson = tinyStories1mUtilizationJson;
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
          tiny-stories-1m-snapshot = tinyStories1m.snapshot;
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
