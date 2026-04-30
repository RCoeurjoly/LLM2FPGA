#!/usr/bin/env python3
"""Summarize YPCB DDR3 board support for the Task 6 external-memory lane."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mig-prj", required=True, type=Path)
    parser.add_argument("--mig-prj-artifact-label")
    parser.add_argument("--memory-ch0-ucf", required=True, type=Path)
    parser.add_argument("--memory-ch0-ucf-artifact-label")
    parser.add_argument("--board-xml", required=True, type=Path)
    parser.add_argument("--board-xml-artifact-label")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--artifact-name", default="h2-ddr3-board-support-inventory")
    parser.add_argument("--date", default=dt.date.today().isoformat())
    return parser.parse_args()


def child_text(node: ET.Element, name: str) -> str | None:
    child = node.find(name)
    if child is None or child.text is None:
        return None
    return child.text.strip()


def parse_int(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def parse_mig_project(path: Path) -> dict[str, Any]:
    root = ET.parse(path).getroot()
    controller = root.find("Controller")
    if controller is None:
        raise SystemExit(f"{path} does not contain a MIG Controller node")

    pin_selection = controller.find("PinSelection")
    pin_counts: dict[str, int] = {}
    pin_names: list[str] = []
    if pin_selection is not None:
        for pin in pin_selection.findall("Pin"):
            name = pin.attrib["name"]
            pin_names.append(name)
            base = re.sub(r"\[[0-9]+\]$", "", name)
            pin_counts[base] = pin_counts.get(base, 0) + 1

    axi_parameters = {}
    axi_node = controller.find("AXIParameters")
    if axi_node is not None:
        for child in list(axi_node):
            if child.text is not None:
                axi_parameters[child.tag] = child.text.strip()

    sys_clk = controller.find("System_Clock/Pin")
    timing = controller.find("TimingParameters/Parameters")

    return {
        "module_name": child_text(root, "ModuleName"),
        "target_fpga": child_text(root, "TargetFPGA"),
        "system_clock": child_text(root, "SystemClock"),
        "reference_clock": child_text(root, "ReferenceClock"),
        "sys_reset_polarity": child_text(root, "SysResetPolarity"),
        "controller": {
            "memory_device": child_text(controller, "MemoryDevice"),
            "time_period_ps": parse_int(child_text(controller, "TimePeriod")),
            "input_clk_freq_mhz": parse_int(child_text(controller, "InputClkFreq")),
            "phy_ratio": child_text(controller, "PHYRatio"),
            "data_width": parse_int(child_text(controller, "DataWidth")),
            "data_mask": parse_int(child_text(controller, "DataMask")),
            "ecc": child_text(controller, "ECC"),
            "row_address_bits": parse_int(child_text(controller, "RowAddress")),
            "col_address_bits": parse_int(child_text(controller, "ColAddress")),
            "bank_address_bits": parse_int(child_text(controller, "BankAddress")),
            "memory_size_bytes": parse_int(child_text(controller, "C0_MEM_SIZE")),
            "user_memory_address_map": child_text(
                controller,
                "UserMemoryAddressMap",
            ),
            "port_interface": child_text(controller, "PortInterface"),
            "system_clock_pin": dict(sys_clk.attrib) if sys_clk is not None else None,
            "timing_parameters": dict(timing.attrib) if timing is not None else None,
            "axi_parameters": axi_parameters,
        },
        "pin_selection": {
            "total_pins": len(pin_names),
            "counts_by_signal": pin_counts,
        },
    }


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
    }


def parse_board_xml(path: Path) -> dict[str, Any]:
    root = ET.parse(path).getroot()
    ddr_interfaces: list[dict[str, Any]] = []
    for interface in root.findall(".//interface"):
        name = interface.attrib.get("name", "")
        if "ddr3" not in name.lower():
            continue
        preferred = [
            dict(ip.attrib)
            for ip in interface.findall(".//preferred_ip")
        ]
        if not preferred:
            continue
        ddr_interfaces.append(
            {
                "name": name,
                "mode": interface.attrib.get("mode"),
                "type": interface.attrib.get("type"),
                "preset_proc": interface.attrib.get("preset_proc"),
                "preferred_ip": preferred,
            }
        )
    return {"ddr3_interfaces": ddr_interfaces}


def main() -> None:
    args = parse_args()
    mig = parse_mig_project(args.mig_prj)
    ucf = parse_ucf(args.memory_ch0_ucf)
    board = parse_board_xml(args.board_xml)

    data_width = mig["controller"]["data_width"] or 0
    logical_payload_width = 64 if mig["controller"]["ecc"] == "Enabled" else data_width
    time_period_ps = mig["controller"]["time_period_ps"] or 0
    peak_mt_s = 1_000_000 / time_period_ps if time_period_ps else None
    peak_payload_mb_s = (
        peak_mt_s * logical_payload_width / 8 if peak_mt_s is not None else None
    )

    payload = {
        "artifact_name": args.artifact_name,
        "status": "PASS",
        "date": args.date,
        "hypothesis": (
            "Before wiring the Task 6 rowstream to external memory, summarize "
            "the available YPCB DDR3 board metadata and distinguish board facts "
            "from controller-integration evidence."
        ),
        "source_artifacts": {
            "mig_prj": args.mig_prj_artifact_label or str(args.mig_prj),
            "memory_ch0_ucf": (
                args.memory_ch0_ucf_artifact_label or str(args.memory_ch0_ucf)
            ),
            "board_xml": args.board_xml_artifact_label or str(args.board_xml),
            "baseline_bundle": (
                "artifacts/task6/baselines/"
                "tiny-stories-1m-baseline-float-selftest-all-memory-utilization"
            ),
        },
        "board_support": {
            "mig_project": mig,
            "memory_ch0_ucf": ucf,
            "board_xml": board,
        },
        "derived": {
            "logical_payload_width_bits": logical_payload_width,
            "ddr_peak_mt_s_from_mig_time_period": peak_mt_s,
            "peak_payload_mb_s_before_controller_overhead": peak_payload_mb_s,
            "task6_4_lane_required_useful_mb_s": 212.5,
            "task6_4_lane_peak_margin_x": (
                peak_payload_mb_s / 212.5 if peak_payload_mb_s is not None else None
            ),
        },
        "validation": {
            "python_run": True,
            "simulation_run": False,
            "synthesis_run": False,
            "hardware_run": False,
            "validation_kind": "ddr3-board-support-inventory",
        },
        "decision": {
            "verdict": "promote-ddr3-board-support-inventory",
            "next_gate": (
                "Choose a controller path and build the smallest DDR3 init/"
                "linear-read bandwidth probe before connecting it to the "
                "rowstream cutout."
            ),
            "controller_note": (
                "The checked board support is Vivado MIG-oriented. This is "
                "board metadata, not open-toolchain DDR3 controller evidence."
            ),
        },
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
