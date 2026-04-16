#!/usr/bin/env python3
"""Summarize emitted SV memory modules and bundle size metrics."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


MODULE_RE = re.compile(r"^\s*module\s+(\w+)\s*\(", re.MULTILINE)
MEM_RE = re.compile(r"\breg\s*\[(\d+):(\d+)\]\s+\w+\s*\[(\d+):(\d+)\]")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-filelist", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--top-count", type=int, default=20)
    return parser.parse_args()


def filelist_entries(path: Path) -> list[Path]:
    entries: list[Path] = []
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
      line = raw.strip()
      if not line or line.startswith("#"):
          continue
      entries.append(Path(line))
    return entries


def inventory_memory_modules(entries: list[Path]) -> dict:
    modules = []
    total_bits = 0
    for entry in entries:
        if not entry.name.startswith("handshake_memory") or entry.suffix != ".sv":
            continue
        text = entry.read_text(encoding="utf-8", errors="ignore")
        module_match = MODULE_RE.search(text)
        mem_match = MEM_RE.search(text)
        width_bits = None
        depth = None
        memory_bits = None
        if mem_match is not None:
            width_bits = abs(int(mem_match.group(1)) - int(mem_match.group(2))) + 1
            depth = abs(int(mem_match.group(3)) - int(mem_match.group(4))) + 1
            memory_bits = width_bits * depth
            total_bits += memory_bits
        modules.append({
            "module": module_match.group(1) if module_match is not None else entry.stem,
            "file": str(entry),
            "width_bits": width_bits,
            "depth": depth,
            "memory_bits": memory_bits,
        })

    modules.sort(key=lambda row: row["memory_bits"] or 0, reverse=True)
    largest_four_bits = sum((row["memory_bits"] or 0) for row in modules[:4])
    return {
        "module_count": len(modules),
        "total_memory_bits": total_bits,
        "largest_four_memory_bits": largest_four_bits,
        "modules": modules,
    }


def bundle_metrics(entries: list[Path]) -> dict:
    total_bytes = sum(entry.stat().st_size for entry in entries if entry.exists())
    main_sv = next((entry for entry in entries if entry.name == "main.sv"), None)
    main_lines = None
    main_bytes = None
    if main_sv is not None:
        main_bytes = main_sv.stat().st_size
        with main_sv.open("r", encoding="utf-8", errors="ignore") as handle:
            main_lines = sum(1 for _ in handle)
    return {
        "file_count": len(entries),
        "total_bytes": total_bytes,
        "main_sv": {
            "path": str(main_sv) if main_sv is not None else None,
            "bytes": main_bytes,
            "lines": main_lines,
        },
    }


def main() -> None:
    args = parse_args()
    input_path = Path(args.input_filelist)
    output_path = Path(args.output)

    entries = filelist_entries(input_path)
    memory_inventory = inventory_memory_modules(entries)
    payload = {
        "input_filelist": str(input_path),
        "bundle_metrics": bundle_metrics(entries),
        "memory_inventory": {
            "module_count": memory_inventory["module_count"],
            "total_memory_bits": memory_inventory["total_memory_bits"],
            "largest_four_memory_bits": memory_inventory["largest_four_memory_bits"],
            "top_modules": memory_inventory["modules"][:args.top_count],
        },
    }
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
