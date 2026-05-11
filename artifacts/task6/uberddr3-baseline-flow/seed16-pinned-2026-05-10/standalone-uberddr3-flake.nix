{
  description = "UberDDR3 open-source YPCB-00338-1P1 self-test build";

  inputs = { llm2fpga.url = "path:/home/roland/LLM2FPGA"; };

  outputs = inputs@{ llm2fpga, ... }:
    llm2fpga.inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import llm2fpga.inputs.nixpkgs { inherit system; };

        yosysPkg = llm2fpga.inputs.yosys.packages.${system}.default;

        openXC7Packages = llm2fpga.inputs.openXC7.packages.${system};
        openXC7Fasm = openXC7Packages.fasm;
        openXC7Nextpnr =
          builtins.storePath /nix/store/s6x1p5v3ny9cfg72clb1ihss42rxvxdf-nextpnr-xilinx-0.8.2;
        openXC7Chipdb =
          builtins.storePath /nix/store/v2kv2919v2p3haa1vib80j888xr6z9lx-nextpnr-xilinx-chipdb-0.8.2;
        openXC7Prjxray = openXC7Packages.prjxray;
        patchedPrjxrayPython = "${openXC7Prjxray}/usr/share/python3";

        fpgaPartFamily = "kintex7";
        fpgaPartName = "xc7k480tffg1156-1";
        fpgaPrjxrayDb =
          builtins.storePath /nix/store/gl1flrglzi2qbn0q5ayk0bc812b7lxmg-task6-prjxray-db-kintex7-lioi3-tbytesrc-oclkm-imux31;
        patchedPrjxrayDb = fpgaPrjxrayDb;
        fpgaPrjxrayFamilyDb = "${patchedPrjxrayDb}/${fpgaPartFamily}";
        fpgaPartFile = "${fpgaPrjxrayFamilyDb}/${fpgaPartName}/part.yaml";
        fpgaChipdb = "${openXC7Chipdb}/xc7k480tffg1156.bin";

        prjxrayPythonDeps = pkgs.python312.withPackages (ps: [
          ps.intervaltree
          ps.progressbar2
          ps.pyjson5
          ps.pyyaml
          ps.simplejson
        ]);
        prjxrayPythonPath =
          "${patchedPrjxrayPython}:${openXC7Fasm}/lib/python3.12/site-packages:${prjxrayPythonDeps}/${pkgs.python312.sitePackages}:${openXC7Prjxray}/usr/share/python3";

        ypcbHack = llm2fpga.inputs.ypcbHack;
        task6Uberddr3Source =
          builtins.storePath /nix/store/7ng23drmbd4gcyl9czbqhbnwhigmfg70-task6-ypcb-uberddr3-source;
        ypcbTop = ./example_demo/ypcb_00338_1p1/ypcb_00338_1p1_ddr3_selftest.v;
        ypcbClk = ./example_demo/ypcb_00338_1p1/clk_wiz_ypcb.v;
        ypcbJtagWb2 = ./example_demo/ypcb_00338_1p1/jtag_wb2_bridge.v;
        ypcbBistTop = ./fpga/rtl/ypcb_uberddr3_bist_top.sv;
        topName = "ypcb_00338_1p1_ddr3_selftest";
        bistTopName = "task6_ypcb_uberddr3_bist_top";

        ypcbXdc = pkgs.runCommand "ypcb-00338-1p1-ddr3-selftest.xdc" { } ''
          cat > "$out" <<'EOF'
          create_clock -period 5.000 -name i_clk200 [get_ports i_clk200_p]
          set_property PACKAGE_PIN AH27 [get_ports i_clk200_p]
          set_property PACKAGE_PIN AH28 [get_ports i_clk200_n]
          set_property IOSTANDARD LVDS_25 [get_ports i_clk200_p]
          set_property IOSTANDARD LVDS_25 [get_ports i_clk200_n]

          set_property PACKAGE_PIN R28 [get_ports SYS_RSTN]
          set_property IOSTANDARD LVCMOS18 [get_ports SYS_RSTN]

          set_property PACKAGE_PIN AA28 [get_ports SYS_CLK]
          set_property IOSTANDARD LVCMOS18 [get_ports SYS_CLK]

          set_property PACKAGE_PIN P30 [get_ports {led_3bits_tri_o[0]}]
          set_property PACKAGE_PIN M30 [get_ports {led_3bits_tri_o[1]}]
          set_property PACKAGE_PIN N30 [get_ports {led_3bits_tri_o[2]}]
          set_property IOSTANDARD LVCMOS18 [get_ports {led_3bits_tri_o[0]}]
          set_property IOSTANDARD LVCMOS18 [get_ports {led_3bits_tri_o[1]}]
          set_property IOSTANDARD LVCMOS18 [get_ports {led_3bits_tri_o[2]}]
          EOF

          ${pkgs.gawk}/bin/awk '
            function indexOfNet(net) {
              if (match(net, /\[[0-9]+\]/)) {
                return substr(net, RSTART + 1, RLENGTH - 2) + 0
              }
              return -1
            }
            function keepNet(net, idx) {
              if (net ~ /^ddr3_dq\[/) return idx >= 0 && idx < 16
              if (net ~ /^ddr3_dqs_[pn]\[/) return idx >= 0 && idx < 2
              if (net ~ /^ddr3_addr\[/) return idx >= 0 && idx < 15
              if (net ~ /^ddr3_ba\[/) return idx >= 0 && idx < 3
              if (net ~ /^ddr3_ck_[pn]\[/) return idx == 0
              if (net ~ /^ddr3_(cke|cs_n|odt)\[/) return idx == 0
              return net ~ /^ddr3_(ras_n|cas_n|we_n|reset_n)$/
            }
            function portNet(net) {
              if (net == "ddr3_ck_p[0]") return "ddr3_ck_p"
              if (net == "ddr3_ck_n[0]") return "ddr3_ck_n"
              if (net == "ddr3_cke[0]") return "ddr3_cke"
              if (net == "ddr3_cs_n[0]") return "ddr3_cs_n"
              if (net == "ddr3_odt[0]") return "ddr3_odt"
              return net
            }
            function ioStandard(net) {
              if (net ~ /^ddr3_ck_[pn]\[/) return "DIFF_SSTL15"
              if (net ~ /^ddr3_dqs_[pn]\[/) return "DIFF_SSTL15"
              return "SSTL15"
            }
            match($0, /^NET[[:space:]]+"([^"]+)"[[:space:]]+LOC = "([^"]+)"/, m) {
              net = m[1]
              pin = m[2]
              idx = indexOfNet(net)
              if (!keepNet(net, idx)) next
              port = portNet(net)
              print "set_property PACKAGE_PIN " pin " [get_ports {" port "}]" >> out
              print "set_property IOSTANDARD " ioStandard(net) " [get_ports {" port "}]" >> out
              if (net !~ /^ddr3_ck_[pn]\[/) {
                print "set_property SLEW FAST [get_ports {" port "}]" >> out
                print "set_property VCCAUX_IO HIGH [get_ports {" port "}]" >> out
              }
              if (net ~ /^ddr3_dq\[/ || net ~ /^ddr3_dqs_[pn]\[/) {
                print "set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {" port "}]" >> out
              }
            }
          ' out="$out" ${ypcbHack}/constraints/MEMORY_CH0.ucf

          cat >> "$out" <<'EOF'
          EOF
        '';

        ypcbBistXdc = pkgs.runCommand "ypcb-uberddr3-bist.xdc" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
          set -euo pipefail
          python3 - <<'PY' > "$out"
          import re
          from pathlib import Path

          platform = Path("${./vendor/litex_boards/platforms/ypcb_00338_1p1.py}").read_text()
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
          print("set_property LOC AA28 [get_ports {clk50}]")
          print("set_property IOSTANDARD LVCMOS18 [get_ports {clk50}]")
          print("create_clock -name clk50 -period 20.000 [get_ports clk50]")
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

        ypcbJson = pkgs.runCommand "ypcb-ddr3-selftest.json" {
          nativeBuildInputs = [ yosysPkg ];
        } ''
          cat > run.ys <<EOF
          read_verilog -sv ${ypcbTop} ${ypcbClk} ${ypcbJtagWb2} \
            ${./rtl/ddr3_controller.v} \
            ${./rtl/ddr3_phy.v} \
            ${./rtl/ddr3_top.v} \
            ${./rtl/ecc/ecc_enc.sv} \
            ${./rtl/ecc/ecc_dec.sv}
          synth_xilinx -flatten -abc9 -arch xc7 -top ${topName}
          write_json $out
          EOF
          ${yosysPkg}/bin/yosys -s run.ys
        '';

        ypcbBistJson = pkgs.runCommand "ypcb-uberddr3-bist.json" {
          nativeBuildInputs = [ yosysPkg ];
        } ''
          cat > run.ys <<EOF
          read_verilog -lib +/xilinx/cells_sim.v
          read_verilog -lib +/xilinx/cells_xtra.v
          read_verilog -sv \
            ${task6Uberddr3Source}/rtl/ddr3_top.v \
            ${task6Uberddr3Source}/rtl/ddr3_controller.v \
            ${task6Uberddr3Source}/rtl/ddr3_phy.v \
            ${task6Uberddr3Source}/rtl/ecc/ecc_dec.sv \
            ${task6Uberddr3Source}/rtl/ecc/ecc_enc.sv \
            ${ypcbBistTop}
          hierarchy -top ${bistTopName} -check
          synth_xilinx -family xc7 -top ${bistTopName} -noiopad
          stat -top ${bistTopName}
          write_json $out
          EOF
          ${yosysPkg}/bin/yosys -s run.ys
        '';

        ypcbBistPackedJson = pkgs.runCommand "ypcb-uberddr3-bist-packed.json" { } ''
          ${openXC7Nextpnr}/bin/nextpnr-xilinx \
            --chipdb "${fpgaChipdb}" \
            --xdc ${ypcbBistXdc} \
            --json ${ypcbBistJson} \
            --seed 16 \
            --freq 25 \
            --pack-only \
            --write "$out"
        '';

        ypcbBistLockedJson = pkgs.runCommand "ypcb-uberddr3-bist-locked.json" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
          set -euo pipefail
          python3 ${./scripts/task6/apply_nextpnr_bel_locks.py} \
            --input-json ${ypcbBistPackedJson} \
            --lock-json ${./fpga/constraints/ypcb_ddr3_known_good_uberddr3_bel_locks.json} \
            --output-json "$out" \
            --prefix uberddr3. \
            --cell-type SLICE_LUTX \
            --cell-type SLICE_FFX \
            --cell-type CARRY4 \
            --cell-type SELMUX2_1
        '';

        ypcbBistCarryLockedJson = pkgs.runCommand "ypcb-uberddr3-bist-carry-locked.json" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
          set -euo pipefail
          python3 ${./scripts/task6/apply_nextpnr_bel_locks.py} \
            --input-json ${ypcbBistPackedJson} \
            --lock-json ${./fpga/constraints/ypcb_ddr3_known_good_uberddr3_bel_locks.json} \
            --output-json "$out" \
            --prefix uberddr3. \
            --cell-type CARRY4
        '';

        ypcbFasm = pkgs.runCommand "ypcb-ddr3-selftest.fasm" { } ''
          ${openXC7Nextpnr}/bin/nextpnr-xilinx \
            --chipdb "${fpgaChipdb}" \
            --xdc ${ypcbXdc} \
            --json ${ypcbJson} \
            --fasm "$out"
          cat >> "$out" <<'EOF'
          HCLK_IOI3_X1Y26.VREF.V_750_MV
          HCLK_IOI3_X1Y78.VREF.V_750_MV
          HCLK_IOI3_X1Y130.VREF.V_750_MV
          HCLK_IOI3_X1Y182.VREF.V_750_MV
          HCLK_IOI3_X1Y234.VREF.V_750_MV
          HCLK_IOI3_X1Y286.VREF.V_750_MV
          HCLK_IOI3_X1Y338.VREF.V_750_MV
          HCLK_IOI3_X1Y390.VREF.V_750_MV
          EOF
        '';

        mkYpcbBistFasm = { name, seed, json ? ypcbBistJson, noPack ? false }:
          pkgs.runCommand "${name}.fasm" { } ''
            ${openXC7Nextpnr}/bin/nextpnr-xilinx \
              --chipdb "${fpgaChipdb}" \
              --xdc ${ypcbBistXdc} \
              --json ${json} \
              --seed ${toString seed} \
              --freq 25 \
              ${if noPack then "--no-pack" else ""} \
              --fasm "$out"
            cat >> "$out" <<'EOF'
            HCLK_IOI3_X1Y26.VREF.V_750_MV
            HCLK_IOI3_X1Y78.VREF.V_750_MV
            HCLK_IOI3_X1Y130.VREF.V_750_MV
            HCLK_IOI3_X1Y182.VREF.V_750_MV
            HCLK_IOI3_X1Y234.VREF.V_750_MV
            HCLK_IOI3_X1Y286.VREF.V_750_MV
            HCLK_IOI3_X1Y338.VREF.V_750_MV
            HCLK_IOI3_X1Y390.VREF.V_750_MV
            EOF
          '';

        ypcbBitstream = pkgs.runCommand "ypcb-ddr3-selftest.bit" {
          nativeBuildInputs = [ openXC7Fasm openXC7Prjxray prjxrayPythonDeps ];
        } ''
          set -euo pipefail
          export PYTHONPATH="${prjxrayPythonPath}''${PYTHONPATH:+:$PYTHONPATH}"
          export PRJXRAY_PYTHON_DIR="${openXC7Prjxray}/usr/share/python3"
          export PRJXRAY_DB_DIR="${fpgaPrjxrayFamilyDb}"
          frames="$(mktemp -t ypcb-ddr3-selftest.XXXXXX.frm)"
          fasm2frames \
            --db-root "${fpgaPrjxrayFamilyDb}" \
            --part ${fpgaPartName} \
            ${ypcbFasm} "$frames"
          xc7frames2bit \
            --part_file "${fpgaPartFile}" \
            --frm_file "$frames" \
            --output_file "$out"
        '';

        mkYpcbBistBitstream = { name, fasm }:
          pkgs.runCommand "${name}.bit" {
            nativeBuildInputs = [ openXC7Fasm openXC7Prjxray prjxrayPythonDeps ];
          } ''
            set -euo pipefail
            export PYTHONPATH="${prjxrayPythonPath}''${PYTHONPATH:+:$PYTHONPATH}"
            export PRJXRAY_PYTHON_DIR="${openXC7Prjxray}/usr/share/python3"
            export PRJXRAY_DB_DIR="${fpgaPrjxrayFamilyDb}"
            frames="$(mktemp -t ${name}.XXXXXX.frm)"
            fasm2frames \
              --db-root "${fpgaPrjxrayFamilyDb}" \
              --part ${fpgaPartName} \
              ${fasm} "$frames"
            xc7frames2bit \
              --part_file "${fpgaPartFile}" \
              --frm_file "$frames" \
              --output_file "$out"
          '';

        ypcbBistSeed15Fasm =
          mkYpcbBistFasm { name = "ypcb-uberddr3-bist-seed15"; seed = 15; };
        ypcbBistSeed16Fasm =
          mkYpcbBistFasm { name = "ypcb-uberddr3-bist-seed16"; seed = 16; };
        ypcbBistSeed17Fasm =
          mkYpcbBistFasm { name = "ypcb-uberddr3-bist-seed17"; seed = 17; };
        ypcbBistSeed18Fasm =
          mkYpcbBistFasm { name = "ypcb-uberddr3-bist-seed18"; seed = 18; };
        ypcbBistLockedSeed16Fasm =
          mkYpcbBistFasm {
            name = "ypcb-uberddr3-bist-locked-seed16";
            seed = 16;
            json = ypcbBistLockedJson;
            noPack = true;
          };
        ypcbBistCarryLockedSeed16Fasm =
          mkYpcbBistFasm {
            name = "ypcb-uberddr3-bist-carry-locked-seed16";
            seed = 16;
            json = ypcbBistCarryLockedJson;
            noPack = true;
          };

        ypcbBistSeed15Bitstream =
          mkYpcbBistBitstream { name = "ypcb-uberddr3-bist-seed15"; fasm = ypcbBistSeed15Fasm; };
        ypcbBistSeed16Bitstream =
          mkYpcbBistBitstream { name = "ypcb-uberddr3-bist-seed16"; fasm = ypcbBistSeed16Fasm; };
        ypcbBistSeed17Bitstream =
          mkYpcbBistBitstream { name = "ypcb-uberddr3-bist-seed17"; fasm = ypcbBistSeed17Fasm; };
        ypcbBistSeed18Bitstream =
          mkYpcbBistBitstream { name = "ypcb-uberddr3-bist-seed18"; fasm = ypcbBistSeed18Fasm; };
        ypcbBistLockedSeed16Bitstream =
          mkYpcbBistBitstream {
            name = "ypcb-uberddr3-bist-locked-seed16";
            fasm = ypcbBistLockedSeed16Fasm;
          };
        ypcbBistCarryLockedSeed16Bitstream =
          mkYpcbBistBitstream {
            name = "ypcb-uberddr3-bist-carry-locked-seed16";
            fasm = ypcbBistCarryLockedSeed16Fasm;
          };
      in {
        packages = {
          ypcb-ddr3-selftest-json = ypcbJson;
          ypcb-ddr3-selftest-xdc = ypcbXdc;
          ypcb-ddr3-selftest-fasm = ypcbFasm;
          ypcb-ddr3-selftest-bitstream = ypcbBitstream;
          ypcb-uberddr3-bist-json = ypcbBistJson;
          ypcb-uberddr3-bist-packed-json = ypcbBistPackedJson;
          ypcb-uberddr3-bist-locked-json = ypcbBistLockedJson;
          ypcb-uberddr3-bist-carry-locked-json = ypcbBistCarryLockedJson;
          ypcb-uberddr3-bist-xdc = ypcbBistXdc;
          ypcb-uberddr3-bist-seed15-fasm = ypcbBistSeed15Fasm;
          ypcb-uberddr3-bist-seed16-fasm = ypcbBistSeed16Fasm;
          ypcb-uberddr3-bist-seed17-fasm = ypcbBistSeed17Fasm;
          ypcb-uberddr3-bist-seed18-fasm = ypcbBistSeed18Fasm;
          ypcb-uberddr3-bist-locked-seed16-fasm = ypcbBistLockedSeed16Fasm;
          ypcb-uberddr3-bist-carry-locked-seed16-fasm = ypcbBistCarryLockedSeed16Fasm;
          ypcb-uberddr3-bist-seed15-bitstream = ypcbBistSeed15Bitstream;
          ypcb-uberddr3-bist-seed16-bitstream = ypcbBistSeed16Bitstream;
          ypcb-uberddr3-bist-seed17-bitstream = ypcbBistSeed17Bitstream;
          ypcb-uberddr3-bist-seed18-bitstream = ypcbBistSeed18Bitstream;
          ypcb-uberddr3-bist-locked-seed16-bitstream = ypcbBistLockedSeed16Bitstream;
          ypcb-uberddr3-bist-carry-locked-seed16-bitstream = ypcbBistCarryLockedSeed16Bitstream;
          ypcb-uberddr3-bist-bitstream = ypcbBistSeed16Bitstream;
          default = ypcbBistSeed16Bitstream;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            yosysPkg
            openXC7Nextpnr
            openXC7Fasm
            openXC7Prjxray
            prjxrayPythonDeps
            pkgs.openfpgaloader
            pkgs.openocd
          ];
          shellHook = ''
            export NEXTPNR_XILINX_DIR="${openXC7Nextpnr}/share/nextpnr"
            export NEXTPNR_XILINX_PYTHON_DIR="${openXC7Nextpnr}/share/nextpnr/python"
            export PRJXRAY_DB_DIR="${fpgaPrjxrayDb}"
            export PRJXRAY_PYTHON_DIR="${openXC7Prjxray}/usr/share/python3"
            export PYTHONPATH="${prjxrayPythonPath}''${PYTHONPATH:+:$PYTHONPATH}"
          '';
        };
      });
}
