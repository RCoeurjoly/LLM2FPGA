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
      url = "path:/home/roland/circt-nix";
      # Develop CIRCT from local checkout while keeping LLVM as a separate
      # pinned input inside circt-nix.
      inputs."circt-src" = {
        url = "path:/home/roland/circt";
        flake = false;
      };
      inputs."llvm-submodule-src" = {
        url = "path:/home/roland/circt/llvm";
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
    torch-mlir-src = {
      url = "github:llvm/torch-mlir";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, nixpkgs-llvm21, flake-utils, yosys, circt-nix
    , nix-eda, openXC7, nextpnrXilinxFork, ypcbHack, torch-mlir-src, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgsLlvm21 = import nixpkgs-llvm21 { inherit system; };
        circtPkgs = circt-nix.packages.${system};
        # Local circt-nix still wires slang 9.x, while current CIRCT requests 10.x.
        # We do not use the Verilog import frontend in this lowering pipeline.
        circt = circtPkgs.circt.override { enableSlang = false; };
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
        # Local copy of the source-based package proposed in:
        # https://github.com/NixOS/nixpkgs/pull/490242
        # Built out-of-tree against a separate LLVM/MLIR derivation so torch-mlir
        # changes do not force rebuilding LLVM.
        torchMlir = pkgsLlvm21.callPackage ./torch-mlir.nix {
          inherit python;
          src = torch-mlir-src;
          nanobind = nanobindBootstrap;
          inherit (torchMlirLlvmPackages) tblgen;
          mlir = mlirForTorchMlir;
          inherit (torchMlirLlvmPackages) llvm;
        };

        pipelineScripts = ./scripts/pipeline;
        tinyStories1mRevision = "77f1b168e219585646439073245fe87e56b3023e";
        tinyStories1mFetch = file: hash:
          pkgs.fetchurl {
            url =
              "https://huggingface.co/roneneldan/TinyStories-1M/resolve/${tinyStories1mRevision}/${file}";
            inherit hash;
          };
        tinyStories1mSnapshot =
          pkgs.runCommand "tinystories-1m-hf-snapshot" { } ''
            mkdir -p "$out"
            cp ${
              tinyStories1mFetch "config.json"
              "sha256-/3TDDV67WrHaDy6kea33GXxQS0K1UiqFjDNKuR7UlYw="
            } "$out/config.json"
            cp ${
              tinyStories1mFetch "pytorch_model.bin"
              "sha256-B/lgnqiCuBY/87I9QOK4LLcV1AljG+sVyEsWTzh32uc="
            } "$out/pytorch_model.bin"
          '';

        pipelineLib = import ./nix/pipeline.nix {
          inherit pkgs mlir circt yosysPkg yosysSlang torchMlir python;
          inherit pipelineScripts;
          fpPrimsSv = ./rtl/fp/circt_fp_primitives.sv;
        };

        modelRegistry = import ./nix/models.nix {
          inherit (pipelineLib) registerModel;
          inherit pythonWithTorch pythonWithTinyStories torchMlir python;
          inherit tinyStories1mSnapshot tinyStories1mRevision;
          matmulPy = ./src/matmul.py;
          matmulCompilePy = ./src/compile-pytorch.py;
          matmulSrcDir = ./src;
          simDir = ./sim;
          tinyStoriesCompilePy = ./TinyStories/compile-pytorch.py;
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
        tinyStoriesQuantInt8Pipeline =
          modelPipelines."tiny-stories-1m-quant-int8";
        tinyStoriesQuantInt8Il = tinyStoriesQuantInt8Pipeline.il;

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
            export outPath="$out"
            ${pkgs.perl}/bin/perl -0pi -e 's/\$out/$ENV{outPath}/g' run.ys
            ${pkgs.lib.optionalString (memoryLimitKb != null) ''
              ulimit -v ${toString memoryLimitKb}
            ''}
            ${yosysPkg}/bin/yosys ${
              pkgs.lib.optionalString quiet "-q"
            } -m ${yosysSlang}/share/yosys/plugins/slang.so -s run.ys
          '';

        mkModelJson =
          { name, modelIl, topName, topSv, flatten ? false, fastSynth ? false }:
          pkgs.runCommand "${name}.json" { } ''
            ${yosysPkg}/bin/yosys -m ${yosysSlang}/share/yosys/plugins/slang.so -p "
              read_rtlil ${modelIl}
              read_slang ${topSv}
              hierarchy -top ${topName} -check
              ${
                if fastSynth then ''
                  synth_xilinx -family xc7 -top ${topName} ${
                    pkgs.lib.optionalString flatten "-flatten"
                  } -noiopad -run begin:map_dsp
                  techmap -map +/cmp2lut.v -map +/cmp2lcu.v -D LUT_WIDTH=6
                  alumacc
                  opt -fast
                  memory -nomap
                  opt_clean
                  synth_xilinx -family xc7 -top ${topName} -noiopad -run map_memory:map_ffs
                  opt_expr -mux_undef -noclkinv
                  abc -fast -luts 2:2,3,6:5
                  clean
                  techmap -map +/xilinx/ff_map.v
                  xilinx_srl -fixed -minlen 3
                  techmap -map +/xilinx/lut_map.v -map +/xilinx/cells_map.v -D LUT_WIDTH=6
                  xilinx_dffopt
                  opt_lut_ins -tech xilinx
                  synth_xilinx -family xc7 -top ${topName} -noiopad -run finalize:json -json $out
                '' else ''
                  synth_xilinx -family xc7 -top ${topName} ${
                    pkgs.lib.optionalString flatten "-flatten"
                  } -noiopad -json $out
                ''
              }
            "
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

        mkNextpnrUtilizationReport = { name, xdc, json }:
          pkgs.runCommand "${name}-nextpnr-utilization" {
            nativeBuildInputs = [ pkgs.python311 ];
          } ''
            set -euo pipefail
            if [ ! -f "${fpgaChipdb}" ]; then
              echo "chipdb file missing: ${fpgaChipdb}" >&2
              exit 1
            fi

            ${openXC7Nextpnr}/bin/nextpnr-xilinx \
              --chipdb "${fpgaChipdb}" \
              --xdc ${xdc} \
              --json ${json} \
              --write routed.json \
              > nextpnr.log 2>&1

            ${pkgs.python311}/bin/python3 - <<'PY'
            import json
            import pathlib
            import re

            log_path = pathlib.Path("nextpnr.log")
            lines = log_path.read_text(encoding="utf-8").splitlines()
            start = None
            for idx, line in enumerate(lines):
              if line.strip() == "Info: Device utilisation:":
                start = idx + 1
                break
            if start is None:
              raise SystemExit("nextpnr log did not contain a device utilisation section")

            resources = {}
            summary_lines = []
            pattern = re.compile(
              r"^Info:\s+(?P<name>.+?):\s+(?P<used>\d+)/\s*(?P<available>\d+)\s+(?P<pct>\d+)%$"
            )
            for line in lines[start:]:
              if not line.strip():
                break
              match = pattern.match(line)
              if match is None:
                continue
              name = match.group("name").strip()
              entry = {
                "used": int(match.group("used")),
                "available": int(match.group("available")),
                "percent": int(match.group("pct")),
              }
              resources[name] = entry
              summary_lines.append(
                f"{name}: {entry['used']} / {entry['available']} ({entry['percent']}%)"
              )

            if not resources:
              raise SystemExit("nextpnr device utilisation section was present but no resources were parsed")

            primary_names = [
              "SLICE_LUTX",
              "SLICE_FFX",
              "CARRY4",
              "RAMB18E1",
              "RAMB36E1",
              "DSP48E1",
              "PAD",
            ]
            summary = {
              "resources": resources,
              "primary": {
                name: resources[name]
                for name in primary_names
                if name in resources
              },
            }
            pathlib.Path("summary.json").write_text(
              json.dumps(summary, indent=2, sort_keys=True) + "\n",
              encoding="utf-8",
            )
            pathlib.Path("summary.txt").write_text(
              "\n".join(summary_lines) + "\n",
              encoding="utf-8",
            )
            PY

            mkdir -p "$out"
            cp nextpnr.log "$out/nextpnr.log"
            cp routed.json "$out/routed.json"
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
        matmulBitstreamJson = mkModelJson {
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
        matmulSelftestJson = mkModelJson {
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

        tinyStoriesSelftestTop =
          pkgs.runCommand "tiny-stories-selftest-top.sv" { } ''
            ${python}/bin/python \
              ${./scripts/pipeline/gen_tiny_stories_selftest_top.py} \
              --main-sv ${tinyStoriesQuantInt8Pipeline.svSplit}/sv/main.sv \
              --out "$out"
          '';
        tinyStoriesSelftestModelOptIl = mkYosysRtlil {
          name = "tiny-stories-quant-int8-selftest-model-opt";
          script = ''
            read_rtlil ${tinyStoriesQuantInt8Il}
            hierarchy -top main -check
            proc
            opt_expr
            opt_clean
            clean
            write_rtlil $out
          '';
        };
        tinyStoriesSelftestJson = mkModelJson {
          name = "tiny-stories-quant-int8-selftest";
          modelIl = tinyStoriesSelftestModelOptIl;
          topName = "tiny_stories_selftest_top";
          topSv = tinyStoriesSelftestTop;
        };
        tinyStoriesSelftestXdc = mkXdc {
          name = "tiny-stories-quant-int8-selftest";
          includeBoardXdc = false;
          extraConstraints = [ ./fpga/constraints/tiny_stories_selftest.xdc ];
        };
        tinyStoriesSelftestFasm = mkFasm {
          name = "tiny-stories-quant-int8-selftest";
          xdc = tinyStoriesSelftestXdc;
          json = tinyStoriesSelftestJson;
        };
        tinyStoriesSelftestBitstream = mkBitstream {
          name = "tiny-stories-quant-int8-selftest";
          fasm = tinyStoriesSelftestFasm;
          framesBase = "tiny-stories-quant-int8-selftest";
        };
        tinyStoriesSelftestUtilizationReport = mkMappedJsonUtilizationReport {
          name = "tiny-stories-quant-int8-selftest";
          designJson = tinyStoriesSelftestJson;
          topName = "tiny_stories_selftest_top";
          capacities = {
            slices = 74650;
            clb_luts = 298600;
            clb_ffs = 597200;
            dsp = 1920;
            bram36 = 955;
            bram_kb = 34380;
          };
        };
        tinyStoriesSelftestNextpnrUtilizationReport =
          mkNextpnrUtilizationReport {
            name = "tiny-stories-quant-int8-selftest";
            xdc = tinyStoriesSelftestXdc;
            json = tinyStoriesSelftestJson;
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
          tiny-stories-quant-int8-selftest-bitstream =
            tinyStoriesSelftestBitstream;
          tiny-stories-quant-int8-selftest-fasm = tinyStoriesSelftestFasm;
          tiny-stories-quant-int8-selftest-model-opt-il =
            tinyStoriesSelftestModelOptIl;
          tiny-stories-quant-int8-selftest-top = tinyStoriesSelftestTop;
          tiny-stories-quant-int8-selftest-xdc = tinyStoriesSelftestXdc;
          tiny-stories-quant-int8-selftest-json = tinyStoriesSelftestJson;
          tiny-stories-quant-int8-selftest-utilization =
            tinyStoriesSelftestUtilizationReport;
          tiny-stories-quant-int8-selftest-utilization2 =
            tinyStoriesSelftestUtilizationReport;
          tiny-stories-quant-int8-selftest-nextpnr-utilization =
            tinyStoriesSelftestNextpnrUtilizationReport;
          tiny-stories-1m-quant-int8-sv-split =
            tinyStoriesQuantInt8Pipeline.svSplit;
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

          # systemverilog = pkgs.runCommand "llm2fpga-systemverilog" {
          #   nativeBuildInputs = [ pkgs.verilator ];
          # } ''
          #   verilator \
          #     --lint-only \
          #     --timing \
          #     --Wall \
          #     --Wno-fatal \
          #     -I${tbDataSv} \
          #     ${matmulSv} \
          #     ${./sim}/tb_main.sv
          #   mkdir -p "$out"
          # '';

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
