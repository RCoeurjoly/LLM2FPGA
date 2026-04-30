#!/usr/bin/env python3
"""Probe the open LiteDRAM/LiteX controller path for the YPCB DDR3 lane."""

from __future__ import annotations

import argparse
import datetime as dt
import importlib
import inspect
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--memory-ch0-ucf", required=True, type=Path)
    parser.add_argument("--memory-ch0-ucf-artifact-label")
    parser.add_argument("--part0-pins-xml", required=True, type=Path)
    parser.add_argument("--part0-pins-xml-artifact-label")
    parser.add_argument("--board-xml", required=True, type=Path)
    parser.add_argument("--board-xml-artifact-label")
    parser.add_argument("--memory-part", default="MT41K256M8DA-125")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--artifact-name", default="h2-litedram-open-controller-probe")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    return parser.parse_args()


def module_info(name: str) -> dict[str, Any]:
    module = importlib.import_module(name)
    return {
        "module": name,
        "file": getattr(module, "__file__", None),
        "package": getattr(module, "__package__", None),
    }


def find_classes(module_name: str, pattern: str) -> list[str]:
    module = importlib.import_module(module_name)
    regex = re.compile(pattern)
    return sorted(
        name
        for name, value in inspect.getmembers(module, inspect.isclass)
        if regex.search(name) and getattr(value, "__module__", "") == module.__name__
    )


def parse_ucf(path: Path) -> dict[str, Any]:
    line_re = re.compile(r'NET\s+"(?P<net>[^"]+)"\s+LOC\s+=\s+"(?P<loc>[^"]+)"')
    nets: dict[str, list[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = line_re.search(line)
        if match is None:
            continue
        net = match.group("net")
        loc = match.group("loc")
        base = re.sub(r"\[[0-9]+\]$", "", net)
        nets.setdefault(base, []).append(loc)
    return {
        "total_constrained_nets": sum(len(values) for values in nets.values()),
        "counts_by_net": {key: len(values) for key, values in sorted(nets.items())},
        "single_ended_controls_present": sorted(
            key for key, values in nets.items() if len(values) == 1
        ),
    }


def parse_part0_pins(path: Path) -> dict[str, Any]:
    root = ET.parse(path).getroot()
    pins: dict[str, dict[str, str]] = {}
    for pin in root.findall(".//pin"):
        name = pin.attrib.get("name")
        if not name:
            continue
        pins[name] = dict(pin.attrib)
    wanted = {
        "default_50mhz_clk0",
        "default_200mhz_clk1_p",
        "default_200mhz_clk1_n",
        "default_200mhz_clk2_p",
        "default_200mhz_clk2_n",
        "SW_RESET",
    }
    return {name: pins[name] for name in sorted(wanted) if name in pins}


def parse_clock_components(path: Path) -> dict[str, Any]:
    root = ET.parse(path).getroot()
    clocks: dict[str, dict[str, Any]] = {}
    for component in root.findall(".//component"):
        name = component.attrib.get("name", "")
        if "clk" not in name:
            continue
        params: dict[str, str] = {}
        for parameter in component.findall(".//parameter"):
            param_name = parameter.attrib.get("name")
            value = parameter.attrib.get("value")
            if param_name and value:
                params[param_name] = value
        clocks[name] = {
            "display_name": component.attrib.get("display_name"),
            "sub_type": component.attrib.get("sub_type"),
            "parameters": params,
        }
    return clocks


def main() -> None:
    args = parse_args()
    litex_info = module_info("litex")
    litedram_info = module_info("litedram")
    modules_info = module_info("litedram.modules")
    s7phy_info = module_info("litedram.phy.s7ddrphy")

    mt41k_classes = find_classes("litedram.modules", r"MT41K")
    ddrphy_classes = find_classes("litedram.phy.s7ddrphy", r"DDRPHY$")
    exact_part_root = args.memory_part.split("-")[0].upper()
    exact_candidates = [
        name for name in mt41k_classes if exact_part_root.replace("DA", "") in name.upper()
    ]

    ucf = parse_ucf(args.memory_ch0_ucf)
    part0_pins = parse_part0_pins(args.part0_pins_xml)
    clocks = parse_clock_components(args.board_xml)

    required_counts = {
        "ddr3_dq": 72,
        "ddr3_dqs_p": 9,
        "ddr3_dqs_n": 9,
        "ddr3_addr": 15,
        "ddr3_ba": 3,
    }
    count_mismatches = {
        key: {
            "expected": expected,
            "observed": ucf["counts_by_net"].get(key, 0),
        }
        for key, expected in required_counts.items()
        if ucf["counts_by_net"].get(key, 0) != expected
    }
    has_kintex7_phy = "K7DDRPHY" in ddrphy_classes
    has_mt41k_family = bool(mt41k_classes)
    status = (
        "PASS"
        if not count_mismatches and has_kintex7_phy and has_mt41k_family
        else "PARTIAL"
    )

    payload = {
        "artifact_name": args.artifact_name,
        "status": status,
        "date": args.date,
        "hypothesis": (
            "The Task 6 DDR3 lane can proceed through an open LiteDRAM/LiteX "
            "controller path by first proving that the pinned environment can "
            "import the controller stack and see a Kintex-7 PHY plus Micron "
            "MT41K module definitions."
        ),
        "source_artifacts": {
            "memory_ch0_ucf": (
                args.memory_ch0_ucf_artifact_label or str(args.memory_ch0_ucf)
            ),
            "part0_pins_xml": (
                args.part0_pins_xml_artifact_label or str(args.part0_pins_xml)
            ),
            "board_xml": args.board_xml_artifact_label or str(args.board_xml),
            "baseline_bundle": (
                "artifacts/task6/baselines/"
                "tiny-stories-1m-baseline-float-selftest-all-memory-utilization"
            ),
        },
        "policy": {
            "vivado_mig_lane": "rejected",
            "controller_path": "LiteDRAM/LiteX only",
            "mig_files_used_for_controller_generation": False,
        },
        "imports": {
            "litex": litex_info,
            "litedram": litedram_info,
            "litedram_modules": modules_info,
            "litedram_s7ddrphy": s7phy_info,
        },
        "detected_litedram": {
            "dram_module_class_count": len(find_classes("litedram.modules", r".*")),
            "mt41k_classes": mt41k_classes,
            "requested_memory_part": args.memory_part,
            "requested_part_exact_candidates": exact_candidates,
            "s7ddrphy_classes": ddrphy_classes,
            "has_kintex7_phy": has_kintex7_phy,
        },
        "ypcb_open_board_facts": {
            "memory_ch0_ucf": ucf,
            "part0_pins": part0_pins,
            "clock_components": clocks,
        },
        "validation": {
            "python_run": True,
            "simulation_run": False,
            "synthesis_run": False,
            "hardware_run": False,
            "validation_kind": "litedram-litex-open-controller-import-probe",
            "count_mismatches": count_mismatches,
        },
        "decision": {
            "verdict": (
                "promote-litedram-open-controller-probe"
                if status == "PASS"
                else "continue-litedram-open-controller-probe"
            ),
            "next_gate": (
                "Instantiate a minimal YPCB LiteDRAM/LiteX target/config and "
                "generate the DDR3 init plus linear-read bandwidth probe RTL."
            ),
            "notes": [
                "Do not use Vivado MIG for the Task 6 implementation lane.",
                "If the exact MT41K256M8DA class is absent, add a small custom "
                "LiteDRAM module derived from Micron MT41K256M8 geometry/timing.",
                "Keep rowstream integration blocked until DDR3 init and linear "
                "read bandwidth are measured on board.",
            ],
        },
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if status != "PASS":
        raise SystemExit("LiteDRAM/LiteX open-controller probe is incomplete")


if __name__ == "__main__":
    main()
