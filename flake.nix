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
      url = "git+https://github.com/RCoeurjoly/nextpnr-xilinx?ref=stable-backports&submodules=1";
      flake = false;
    };
    ypcbHack = {
      url = "github:RCoeurjoly/ypcb_00338_1p1_hack";
      flake = false;
    };
    # openXC7.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-llvm21,
      flake-utils,
      yosys,
      circt-nix,
      nix-eda,
      openXC7,
      nextpnrXilinxFork,
      ypcbHack,
      ...
    }:
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
        openXC7Nextpnr = openXC7Packages.nextpnr-xilinx.overrideAttrs (old: {
          src = nextpnrXilinxFork;
          # installPhase = ''
          #   mkdir -p $out/bin
          #   cp nextpnr-xilinx $out/bin/
          #   cp bba/bbasm $out/bin/bbasm
          #   mkdir -p $out/share/nextpnr/external
          #   cp -rv ../xilinx/external/prjxray-db $out/share/nextpnr/external/
          #   cp -rv ../xilinx/external/nextpnr-xilinx-meta $out/share/nextpnr/external/
          #   cp -rv ../xilinx/python/ $out/share/nextpnr/python/
          #   cp ../xilinx/constids.inc $out/share/nextpnr
          # '';
        });
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
        fpgaPartFile =
          "${fpgaPrjxrayFamilyDb}/${fpgaPartName}/part.yaml";
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
          export PYTHONPATH="${./src}:${
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

        matmulBitstreamTop = pkgs.runCommand "matmul-bitstream-top.sv" { } ''
          cat > "$out" <<'EOF'
          module matmul_bitstream_top(
            input logic clock,
            input logic reset,
            input logic in3_valid,
            input logic out0_ready,
            input logic in0_ld0_addr_ready,
            input logic in1_ld0_addr_ready,
            output logic in2_st0_done_ready,
            input logic in2_st0_ready,
            input logic [31:0] in0_ld0_data,
            input logic in0_ld0_data_valid,
            input logic [31:0] in1_ld0_data,
            input logic in1_ld0_data_valid,
            output logic [31:0] in2_st0,
            output logic in2_st0_valid,
            output logic in2_st0_done_valid,
            output logic out0_valid,
            output logic [3:0] in0_ld0_addr,
            output logic in0_ld0_addr_valid,
            output logic [3:0] in1_ld0_addr,
            output logic in1_ld0_addr_valid,
            output logic in0_ld0_data_ready,
            output logic in1_ld0_data_ready,
            output logic in3_ready
          );

            main u_dut(
              .clock(clock),
              .reset(reset),
              .in3_valid(in3_valid),
              .out0_ready(out0_ready),
              .in0_ld0_addr_ready(in0_ld0_addr_ready),
              .in1_ld0_addr_ready(in1_ld0_addr_ready),
              .in2_st0_ready(in2_st0_ready),
              .in2_st0_done_ready(in2_st0_done_ready),
              .in2_st0_done_valid(in2_st0_done_valid),
              .in2_st0(in2_st0),
              .in2_st0_valid(in2_st0_valid),
              .out0_valid(out0_valid),
              .in0_ld0_addr(in0_ld0_addr),
              .in0_ld0_addr_valid(in0_ld0_addr_valid),
              .in1_ld0_addr(in1_ld0_addr),
              .in1_ld0_addr_valid(in1_ld0_addr_valid),
              .in0_ld0_data(in0_ld0_data),
              .in0_ld0_data_valid(in0_ld0_data_valid),
              .in1_ld0_data(in1_ld0_data),
              .in1_ld0_data_valid(in1_ld0_data_valid),
              .in0_ld0_data_ready(in0_ld0_data_ready),
              .in1_ld0_data_ready(in1_ld0_data_ready),
              .in3_ready(in3_ready)
            );
          endmodule
          EOF
        '';

        matmulBitstreamJson = pkgs.runCommand "matmul-bitstream.json" { } ''
        ${yosysPkg}/bin/yosys -m ${yosysSlang}/share/yosys/plugins/slang.so -q -p "
            read_rtlil ${matmulIl}
            read_slang ${matmulBitstreamTop}
            hierarchy -top matmul_bitstream_top -check
            proc
            opt
            memory
            flatten
            synth_xilinx -family xc7 -top matmul_bitstream_top -flatten -noiopad
            write_json $out
          "
        '';

        boardXdc = "${ypcbHack}/constraints/ypcb003381p1.xdc";

        matmulBitstreamXdc = pkgs.runCommand "matmul-bitstream.xdc" { inherit boardXdc; } ''
          cat "$boardXdc" > "$out"

          cat >> "$out" <<'EOF'
          # Map accelerator top-level ports to known board pins
          set_property PACKAGE_PIN AA28 [get_ports {clock}]
          set_property IOSTANDARD LVCMOS18 [get_ports {clock}]
          set_property PACKAGE_PIN R28 [get_ports {reset}]
          set_property IOSTANDARD LVCMOS18 [get_ports {reset}]

          # Matmul accelerator interface constraints
          set_property IOSTANDARD LVCMOS33 [get_ports {in3_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {out0_ready}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in0_ld0_addr_ready}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in1_ld0_addr_ready}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in2_st0_done_ready}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in2_st0_done_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in2_st0_ready}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in0_ld0_data_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in1_ld0_data_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in2_st0_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {out0_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in0_ld0_addr_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in1_ld0_addr_valid}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in0_ld0_data_ready}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in1_ld0_data_ready}]
          set_property IOSTANDARD LVCMOS33 [get_ports {in3_ready}]
          EOF
          for i in $(seq 0 3); do
            {
              echo "set_property IOSTANDARD LVCMOS33 [get_ports {in0_ld0_addr[$i]}]"
              echo "set_property IOSTANDARD LVCMOS33 [get_ports {in1_ld0_addr[$i]}]"
            } >> "$out"
          done

          for i in $(seq 0 31); do
            {
              echo "set_property IOSTANDARD LVCMOS33 [get_ports {in0_ld0_data[$i]}]"
              echo "set_property IOSTANDARD LVCMOS33 [get_ports {in1_ld0_data[$i]}]"
              echo "set_property IOSTANDARD LVCMOS33 [get_ports {in2_st0[$i]}]"
            } >> "$out"
          done
        '';

        matmulFasm = pkgs.runCommand "matmul-bitstream.fasm" { } ''
          chipdb=${openXC7Chipdb}/xc7k480tffg1156.bin
          if [ ! -f "$chipdb" ]; then
            echo "chipdb file missing: $chipdb" >&2
            exit 1
          fi

          export OMP_NUM_THREADS=1
          ${openXC7Nextpnr}/bin/nextpnr-xilinx \
            --chipdb "${openXC7Chipdb}/xc7k480tffg1156.bin" \
            --xdc ${matmulBitstreamXdc} \
            --json ${matmulBitstreamJson} \
            --fasm $out
        '';

        matmulBitstream = pkgs.runCommand "matmul.bit" {
          nativeBuildInputs = [ openXC7Fasm openXC7Prjxray prjxrayPythonDeps ];
        } ''
          set -euo pipefail
          export PYTHONPATH="${openXC7Fasm}/lib/python3.12/site-packages:${prjxrayPythonDeps}/${pkgs.python312.sitePackages}:${openXC7Prjxray}/usr/share/python3''${PYTHONPATH:+:$PYTHONPATH}"
          export PRJXRAY_PYTHON_DIR="${openXC7Prjxray}/usr/share/python3"
          export PRJXRAY_DB_DIR="${fpgaPrjxrayFamilyDb}"
          tmpdir="$(mktemp -d)"
          frames="$tmpdir/matmul.frm"
          fasm2frames \
            --db-root "${fpgaPrjxrayFamilyDb}" \
            --part ${fpgaPartName} \
            ${matmulFasm} "$frames"
          xc7frames2bit \
            --part_file "${fpgaPartFile}" \
            --frm_file "$frames" \
            --output_file "$out"
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
            pkgs.cmake
            pkgs.ninja
            pkgs.gtkwave
            pkgs.nixfmt-classic
            pkgs.rr
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
          matmul-bitstream = matmulBitstream;
          matmul-fasm = matmulFasm;
          matmul-bitstream-fasm = matmulFasm;
          matmul-bitstream-top = matmulBitstreamTop;
          matmul-bitstream-xdc = matmulBitstreamXdc;
          matmul-bitstream-json = matmulBitstreamJson;
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
