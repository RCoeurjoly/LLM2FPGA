#!/usr/bin/env python3
"""Report the active YPCB/UberDDR3 clocking contract.

This is intentionally a static source-of-truth check.  It does not prove timing
closure, but it catches the class of regressions where DDR3 clocks silently stop
being generated from one root clock before we spend board time on the bitstream.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any


PLL_RE = re.compile(
    r"PLLE2_BASE\s*#\s*\((?P<params>.*?)\)\s*(?P<inst>[A-Za-z0-9_]+)\s*\(",
    re.S,
)
PARAM_RE = re.compile(r"\.(?P<name>[A-Za-z0-9_]+)\((?P<value>[^)]+)\)")
PORT_RE = re.compile(r"\.(?P<name>[A-Za-z0-9_]+)\((?P<value>[^)]+)\)")
BUFG_RE = re.compile(
    r"BUFG\s+(?P<inst>[A-Za-z0-9_]+)\s*\(\s*\.I\((?P<input>[^)]+)\),\s*\.O\((?P<output>[^)]+)\)\s*\);",
    re.S,
)
CLOCK_CONSTRAINT_RE = re.compile(r'\("(?P<name>[^"]+)",\s*(?P<mhz>[0-9.]+)\)')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", required=True, type=Path)
    parser.add_argument("--clock-constraints", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument(
        "--artifact-name",
        default="task6-ypcb-uberddr3-clock-discipline-report",
    )
    return parser.parse_args()


def clean_sv_value(value: str) -> str:
    return value.strip().strip()


def parse_pll(source: str) -> dict[str, Any]:
    match = PLL_RE.search(source)
    if match is None:
        raise SystemExit("active top does not contain a PLLE2_BASE instance")
    params = {
        param.group("name"): clean_sv_value(param.group("value"))
        for param in PARAM_RE.finditer(match.group("params"))
    }
    inst_start = match.end() - 1
    depth = 0
    end = inst_start
    for end in range(inst_start, len(source)):
        char = source[end]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                break
    port_blob = source[inst_start + 1 : end]
    ports = {
        port.group("name"): clean_sv_value(port.group("value"))
        for port in PORT_RE.finditer(port_blob)
    }
    return {
        "instance": match.group("inst"),
        "params": params,
        "ports": ports,
    }


def parse_bufgs(source: str) -> list[dict[str, str]]:
    return [
        {
            "instance": match.group("inst"),
            "input": clean_sv_value(match.group("input")),
            "output": clean_sv_value(match.group("output")),
        }
        for match in BUFG_RE.finditer(source)
    ]


def parse_clock_constraints(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8")
    return [
        {"name": match.group("name"), "mhz": float(match.group("mhz"))}
        for match in CLOCK_CONSTRAINT_RE.finditer(text)
    ]


def derive_pll_outputs(pll: dict[str, Any]) -> list[dict[str, Any]]:
    params = pll["params"]
    ports = pll["ports"]
    input_period = float(params["CLKIN1_PERIOD"])
    input_mhz = 1000.0 / input_period
    mult = float(params["CLKFBOUT_MULT"])
    divclk = float(params["DIVCLK_DIVIDE"])
    vco_mhz = input_mhz * mult / divclk
    outputs: list[dict[str, Any]] = []
    for index in range(6):
        clkout = f"CLKOUT{index}"
        divide_name = f"{clkout}_DIVIDE"
        if divide_name not in params:
            continue
        net = ports.get(clkout, "")
        if not net:
            continue
        outputs.append(
            {
                "port": clkout,
                "raw_net": net,
                "divide": float(params[divide_name]),
                "phase_degrees": float(params.get(f"{clkout}_PHASE", "0.0")),
                "mhz": vco_mhz / float(params[divide_name]),
            }
        )
    return outputs


def main() -> None:
    args = parse_args()
    source = args.top.read_text(encoding="utf-8")
    pll = parse_pll(source)
    bufgs = parse_bufgs(source)
    constraints = parse_clock_constraints(args.clock_constraints)
    outputs = derive_pll_outputs(pll)
    output_by_raw = {output["raw_net"]: output for output in outputs}
    bufg_clocks = []
    for bufg in bufgs:
        source_output = output_by_raw.get(bufg["input"])
        bufg_clocks.append(
            {
                **bufg,
                "source": "pll_output" if source_output else "unknown",
                "mhz": source_output["mhz"] if source_output else None,
                "phase_degrees": source_output["phase_degrees"] if source_output else None,
            }
        )

    root_clock = pll["ports"].get("CLKIN1")
    required_outputs = {"controller_clk", "ddr3_clk", "ddr3_clk_90", "ref_clk"}
    bufg_outputs = {clock["output"] for clock in bufg_clocks}
    missing_required = sorted(required_outputs - bufg_outputs)
    independent_roots = sorted(
        {
            clock["input"]
            for clock in bufg_clocks
            if clock["source"] != "pll_output"
        }
    )

    status = "PASS" if not missing_required and not independent_roots else "FAIL"
    payload = {
        "artifact_name": args.artifact_name,
        "status": status,
        "date": args.date,
        "hypothesis": (
            "The active YPCB/UberDDR3 top should generate all DDR3 controller, "
            "PHY, phase, and IDELAY reference clocks from one root clock source."
        ),
        "active_top": str(args.top),
        "clock_constraints": str(args.clock_constraints),
        "pll": {
            "instance": pll["instance"],
            "root_clock_net": root_clock,
            "input_period_ns": float(pll["params"]["CLKIN1_PERIOD"]),
            "outputs": outputs,
        },
        "bufg_clocks": bufg_clocks,
        "nextpnr_clock_constraints": constraints,
        "validation": {
            "static_source_check": True,
            "simulation_run": False,
            "hardware_run": False,
            "single_pll_root": root_clock == "clk50",
            "required_outputs_present": not missing_required,
            "no_independent_bufg_roots": not independent_roots,
            "missing_required_outputs": missing_required,
            "independent_bufg_roots": independent_roots,
        },
        "decision": {
            "verdict": (
                "clock-discipline-static-check-passes"
                if status == "PASS"
                else "fix-clock-discipline-before-board-run"
            ),
            "next_gate": (
                "Keep this report with each DDR3 board experiment; board "
                "calibration remains the oracle, but this catches accidental "
                "clock-source drift before hardware-on-loop runs."
            ),
        },
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
