#!/usr/bin/env python3
"""Wrap raw Yosys stat output or an explicit bottleneck into one JSON report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--status", required=True, choices=["ok", "oom-bottleneck"])
    parser.add_argument("--input-filelist", required=True)
    parser.add_argument("--memory-inventory", required=True)
    parser.add_argument("--raw-yosys-json")
    parser.add_argument("--exit-code", type=int)
    parser.add_argument("--top", default="main")
    return parser.parse_args()


def load_json(path: str | None) -> dict | None:
    if path is None:
        return None
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> None:
    args = parse_args()
    inventory = load_json(args.memory_inventory)
    raw_yosys = load_json(args.raw_yosys_json)

    payload = {
        "status": args.status,
        "tool": "yosys-slang",
        "top": args.top,
        "input_filelist": args.input_filelist,
        "memory_inventory": inventory,
    }

    if args.status == "ok":
        payload["report_kind"] = "yosys-stat"
        payload["yosys_stat"] = raw_yosys
    else:
        payload["report_kind"] = "explicit-bottleneck-report"
        payload["diagnostic"] = {
            "exit_code": args.exit_code,
            "reason": "Yosys was killed while processing the emitted SystemVerilog bundle.",
            "likely_cause": "out-of-memory during SystemVerilog frontend or elaboration",
        }

    Path(args.output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
