#!/usr/bin/env python3
"""Generate a no-DM YPCB LiteDRAM/LiteX core RTL bundle."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any

import yaml
from litex.build.generic_platform import IOStandard, Misc, Pins, Subsignal
from litex.build.xilinx import XilinxPlatform
from litex.soc.integration.builder import Builder
from migen import log2_int

from litedram import gen as litedram_gen
from litedram import modules as litedram_modules
from litedram import phy as litedram_phys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-yml", required=True, type=Path)
    parser.add_argument("--config-summary-json", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--name", default="ypcb_litedram_core")
    parser.add_argument("--device", default="xc7k480tffg1156-1")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--artifact-name", default="h2-ypcb-litedram-rtl-elaboration")
    return parser.parse_args()


def load_core_config(path: Path) -> dict[str, Any]:
    config = yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.Loader)
    for key, value in list(config.items()):
        replacements = {"False": False, "True": True, "None": None}
        if isinstance(value, str) and value in replacements:
            config[key] = replacements[value]
        if "clk_freq" in key:
            config[key] = float(config[key])
        if key == "sdram_module":
            config[key] = getattr(litedram_modules, config[key])
        if key == "sdram_phy":
            config[key] = getattr(litedram_phys, config[key])
    return config


def pin_string(pins: list[str]) -> str:
    return " ".join(pins)


def make_no_dm_dram_ios(pin_mapping: dict[str, Any]):
    def get_dram_ios_no_dm(core_config: dict[str, Any]):
        assert core_config["memtype"] in ["DDR3"]
        module = core_config["sdram_module"]
        return [
            ("ddram", 0,
                Subsignal("a",       Pins(pin_string(pin_mapping["a"])), IOStandard("SSTL15")),
                Subsignal("ba",      Pins(pin_string(pin_mapping["ba"])), IOStandard("SSTL15")),
                Subsignal("ras_n",   Pins(pin_mapping["ras_n"]), IOStandard("SSTL15")),
                Subsignal("cas_n",   Pins(pin_mapping["cas_n"]), IOStandard("SSTL15")),
                Subsignal("we_n",    Pins(pin_mapping["we_n"]), IOStandard("SSTL15")),
                Subsignal("cs_n",    Pins(pin_string(pin_mapping["cs_n"])), IOStandard("SSTL15")),
                Subsignal("dq",      Pins(pin_string(pin_mapping["dq"])), IOStandard("SSTL15"), Misc("IN_TERM=UNTUNED_SPLIT_40")),
                Subsignal("dqs_p",   Pins(pin_string(pin_mapping["dqs_p"])), IOStandard("DIFF_SSTL15"), Misc("IN_TERM=UNTUNED_SPLIT_40")),
                Subsignal("dqs_n",   Pins(pin_string(pin_mapping["dqs_n"])), IOStandard("DIFF_SSTL15"), Misc("IN_TERM=UNTUNED_SPLIT_40")),
                Subsignal("clk_p",   Pins(pin_string(pin_mapping["clk_p"])), IOStandard("DIFF_SSTL15")),
                Subsignal("clk_n",   Pins(pin_string(pin_mapping["clk_n"])), IOStandard("DIFF_SSTL15")),
                Subsignal("cke",     Pins(pin_string(pin_mapping["cke"])), IOStandard("SSTL15")),
                Subsignal("odt",     Pins(pin_string(pin_mapping["odt"])), IOStandard("SSTL15")),
                Subsignal("reset_n", Pins(pin_mapping["reset_n"]), IOStandard("SSTL15")),
                Misc("SLEW=FAST"),
            ),
        ]

    return get_dram_ios_no_dm


def strip_trailing_whitespace(root: Path) -> list[str]:
    cleaned = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        try:
            original = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        stripped = "\n".join(line.rstrip() for line in original.splitlines())
        if original.endswith("\n"):
            stripped += "\n"
        if stripped != original:
            path.write_text(stripped, encoding="utf-8")
            cleaned.append(str(path.relative_to(root)))
    return cleaned


def summarize_generated_files(out_dir: Path) -> list[dict[str, Any]]:
    files = []
    for path in sorted(out_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(out_dir)
        files.append({
            "path": str(rel),
            "bytes": path.stat().st_size,
        })
    return files


def main() -> None:
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    config_summary = json.loads(args.config_summary_json.read_text(encoding="utf-8"))
    pin_mapping = config_summary["ypcb_open_board_facts"]["ddr3_pin_mapping"]
    core_config = load_core_config(args.config_yml)

    original_get_dram_ios = litedram_gen.get_dram_ios
    litedram_gen.get_dram_ios = make_no_dm_dram_ios(pin_mapping)
    build_dir = out_dir / "build"
    csr_json = out_dir / "csr.json"
    csr_csv = out_dir / "csr.csv"
    try:
        platform = XilinxPlatform(args.device, io=[], toolchain="openxc7")
        soc = litedram_gen.LiteDRAMCore(platform, core_config, integrated_rom_size=0xC000)
        builder = Builder(
            soc,
            output_dir=str(build_dir),
            compile_gateware=False,
            compile_software=False,
            csr_json=str(csr_json),
            csr_csv=str(csr_csv),
        )
        builder.build(build_name=args.name, regular_comb=False)
    finally:
        litedram_gen.get_dram_ios = original_get_dram_ios

    sanitized_files = strip_trailing_whitespace(out_dir)
    verilog_candidates = sorted((build_dir / "gateware").glob("*.v"))
    if not verilog_candidates:
        raise SystemExit("LiteDRAM/LiteX elaboration did not produce Verilog")
    top_verilog = next(
        (path for path in verilog_candidates if path.name == f"{args.name}.v"),
        verilog_candidates[0],
    )
    verilog_text = top_verilog.read_text(encoding="utf-8")
    ddram_dm_mentions = len(re.findall(r"\bddram_dm\b", verilog_text))
    odelaye2_mentions = len(re.findall(r"\bODELAYE2\b", verilog_text))
    idelaye2_mentions = len(re.findall(r"\bIDELAYE2\b", verilog_text))
    sdram_phy_name = core_config["sdram_phy"].__name__

    summary = {
        "artifact_name": args.artifact_name,
        "status": "PASS" if ddram_dm_mentions == 0 else "PARTIAL",
        "date": args.date,
        "hypothesis": (
            "The open LiteDRAM/LiteX core can elaborate for YPCB DDR3 CH0 with "
            f"a custom no-dm {sdram_phy_name} pad description and without "
            "invoking Vivado or MIG."
        ),
        "source_artifacts": {
            "config_bundle": str(args.config_summary_json.parent),
            "config_summary_json": str(args.config_summary_json),
            "config_yml": str(args.config_yml),
            "baseline_bundle": (
                "artifacts/task6/baselines/"
                "tiny-stories-1m-baseline-float-selftest-all-memory-utilization"
            ),
        },
        "policy": {
            "vivado_mig_lane": "rejected",
            "controller_path": "LiteDRAM/LiteX only",
            "mig_files_used_for_controller_generation": False,
            "gateware_compile_invoked": False,
            "litex_platform_toolchain": "openxc7",
        },
        "core_config": {
            "device": args.device,
            "sdram_module": core_config["sdram_module"].__name__,
            "sdram_module_nb": core_config["sdram_module_nb"],
            "sdram_phy": sdram_phy_name,
            "memtype": core_config["memtype"],
            "sys_clk_freq": core_config["sys_clk_freq"],
            "input_clk_freq": core_config["input_clk_freq"],
            "iodelay_clk_freq": core_config["iodelay_clk_freq"],
        },
        "generated": {
            "top_verilog": str(top_verilog.relative_to(out_dir)),
            "csr_json": str(csr_json.relative_to(out_dir)),
            "csr_csv": str(csr_csv.relative_to(out_dir)),
            "file_count": len(summarize_generated_files(out_dir)),
            "trailing_whitespace_sanitized_files": sanitized_files,
            "files": summarize_generated_files(out_dir),
        },
        "validation": {
            "rtl_elaborated": True,
            "synthesis_run": False,
            "place_and_route_run": False,
            "hardware_run": False,
            "ddram_dm_top_port_mentions": ddram_dm_mentions,
            "odelaye2_mentions": odelaye2_mentions,
            "idelaye2_mentions": idelaye2_mentions,
            "ddram_dq_top_port_mentions": len(re.findall(r"\bddram_dq\b", verilog_text)),
            "ddram_dqs_p_top_port_mentions": len(re.findall(r"\bddram_dqs_p\b", verilog_text)),
            "ddram_dqs_n_top_port_mentions": len(re.findall(r"\bddram_dqs_n\b", verilog_text)),
        },
        "decision": {
            "verdict": (
                "promote-open-litedram-rtl-generation"
                if ddram_dm_mentions == 0
                else "fix-no-dm-top-port"
            ),
            "next_gate": (
                "Synthesize the generated LiteDRAM core with Yosys/openXC7 "
                "or wrap it in a minimal init/bandwidth probe, still without "
                "Vivado or MIG."
            ),
        },
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n",
        encoding="utf-8",
    )
    if summary["status"] != "PASS":
        raise SystemExit("LiteDRAM RTL elaborated, but no-dm validation failed")


if __name__ == "__main__":
    main()
