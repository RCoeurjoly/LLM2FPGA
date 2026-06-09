#!/usr/bin/env python3
"""Audit generated Task 6 combined XDC against source PCIe and DDR XDCs."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Iterable


IMPORTANT_PATTERNS = {
    "clock": re.compile(r"\bcreate_(?:generated_)?clock\b", re.I),
    "clock_groups": re.compile(r"\bset_clock_groups\b", re.I),
    "false_path": re.compile(r"\bset_false_path\b", re.I),
    "max_min_delay": re.compile(r"\bset_(?:max|min)_delay\b", re.I),
    "input_output_delay": re.compile(r"\bset_(?:input|output)_delay\b", re.I),
    "internal_vref": re.compile(r"\bINTERNAL_VREF\b", re.I),
    "startup": re.compile(r"\bBITSTREAM\.STARTUP\b|\bMATCH_CYCLE\b", re.I),
    "idelay": re.compile(r"\bI?DELAY(?:CTRL)?\b|\bODELAY\b|IODELAY", re.I),
    "placement": re.compile(r"\b(?:LOC|BEL|PACKAGE_PIN)\b", re.I),
    "pcie_gt": re.compile(r"\bPCIE\b|\bGTXE2\b|\bGTPE2\b|\bGTP\b|\bGTX\b", re.I),
    "ddr": re.compile(r"ddram|DDR3|DQS|DQ\[|SSTL|DCI|ODT|RTT|VREF", re.I),
}

TARGET_RE = re.compile(r"\[get_(?P<kind>ports|nets|cells|pins|clocks)\s+\{?(?P<target>[^}\]]+)\}?\]")
COMMENT_RE = re.compile(r"\s*#.*$")
DDR_DQ_RE = re.compile(r"ddram_dq\[(\d+)\]")
DDR_DQS_RE = re.compile(r"ddram_dqs_[pn]\[(\d+)\]")

PCIE_UBERDDR3_BYTE_LANES = 2
PCIE_UBERDDR3_DQ_BITS = PCIE_UBERDDR3_BYTE_LANES * 8


@dataclass(frozen=True)
class Constraint:
    file: str
    line_no: int
    text: str
    op: str
    categories: tuple[str, ...]
    targets: tuple[str, ...]


def clean_line(line: str) -> str:
    line = COMMENT_RE.sub("", line).strip()
    return re.sub(r"\s+", " ", line)


def classify(text: str) -> tuple[str, ...]:
    return tuple(name for name, pattern in IMPORTANT_PATTERNS.items() if pattern.search(text))


def op_name(text: str) -> str:
    if not text:
        return ""
    return text.split(None, 1)[0]


def targets(text: str) -> tuple[str, ...]:
    found = []
    for match in TARGET_RE.finditer(text):
        kind = match.group("kind")
        for target in match.group("target").split():
            found.append(f"{kind}:{target}")
    return tuple(found)


def read_constraints(path: Path) -> list[Constraint]:
    constraints: list[Constraint] = []
    for index, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        text = clean_line(raw)
        if not text:
            continue
        constraints.append(
            Constraint(
                file=str(path),
                line_no=index,
                text=text,
                op=op_name(text),
                categories=classify(text),
                targets=targets(text),
            )
        )
    return constraints


def as_key(constraint: Constraint) -> str:
    return constraint.text


def summarize(constraints: Iterable[Constraint]) -> dict[str, object]:
    constraints = list(constraints)
    category_counts = Counter(cat for item in constraints for cat in item.categories)
    op_counts = Counter(item.op for item in constraints)
    return {
        "constraint_count": len(constraints),
        "op_counts": dict(sorted(op_counts.items())),
        "category_counts": dict(sorted(category_counts.items())),
    }


def compact(items: list[Constraint], limit: int) -> list[dict[str, object]]:
    return [
        {
            "file": item.file,
            "line": item.line_no,
            "op": item.op,
            "categories": list(item.categories),
            "targets": list(item.targets),
            "text": item.text,
        }
        for item in items[:limit]
    ]


def expected_ddr_skip_reason(constraint: Constraint) -> str | None:
    """Classify DDR source constraints intentionally dropped by the combiner."""

    dq_match = DDR_DQ_RE.search(constraint.text)
    if dq_match and int(dq_match.group(1)) >= PCIE_UBERDDR3_DQ_BITS:
        return "expected_2_byte_lane_dq_filter"

    dqs_match = DDR_DQS_RE.search(constraint.text)
    if dqs_match and int(dqs_match.group(1)) >= PCIE_UBERDDR3_BYTE_LANES:
        return "expected_2_byte_lane_dqs_filter"

    if "clk50" in constraint.text:
        return "expected_combined_top_clk50_replaced_by_pcie_clk_50"

    if "SYS_RSTN" in constraint.text:
        return "expected_combined_top_SYS_RSTN_replaced_by_pcie_sys_rst_n"

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pcie-xdc", required=True, type=Path)
    parser.add_argument("--ddr-xdc", required=True, type=Path)
    parser.add_argument("--combined-xdc", required=True, type=Path)
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--max-examples", type=int, default=64)
    args = parser.parse_args()

    pcie = read_constraints(args.pcie_xdc)
    ddr = read_constraints(args.ddr_xdc)
    combined = read_constraints(args.combined_xdc)
    combined_keys = {as_key(item) for item in combined}

    missing_pcie = [item for item in pcie if as_key(item) not in combined_keys]
    missing_ddr = [item for item in ddr if as_key(item) not in combined_keys]
    expected_missing_ddr: dict[str, list[Constraint]] = defaultdict(list)
    suspicious_missing_ddr = []
    for item in missing_ddr:
        reason = expected_ddr_skip_reason(item)
        if reason:
            expected_missing_ddr[reason].append(item)
        else:
            suspicious_missing_ddr.append(item)

    important_missing_ddr = [item for item in suspicious_missing_ddr if item.categories]
    important_missing_pcie = [item for item in missing_pcie if item.categories]

    by_category: dict[str, list[dict[str, object]]] = defaultdict(list)
    for item in important_missing_ddr + important_missing_pcie:
        for category in item.categories:
            by_category[category].append({"file": item.file, "line": item.line_no, "text": item.text})

    report = {
        "schema": "task6-xdc-constraint-audit-v1",
        "inputs": {
            "pcie_xdc": str(args.pcie_xdc),
            "ddr_xdc": str(args.ddr_xdc),
            "combined_xdc": str(args.combined_xdc),
        },
        "summaries": {
            "pcie": summarize(pcie),
            "ddr": summarize(ddr),
            "combined": summarize(combined),
        },
        "missing": {
            "pcie_count": len(missing_pcie),
            "ddr_count": len(missing_ddr),
            "expected_ddr_count": sum(len(items) for items in expected_missing_ddr.values()),
            "suspicious_ddr_count": len(suspicious_missing_ddr),
            "important_pcie_count": len(important_missing_pcie),
            "important_ddr_count": len(important_missing_ddr),
            "pcie_examples": compact(missing_pcie, args.max_examples),
            "ddr_examples": compact(missing_ddr, args.max_examples),
            "expected_ddr_by_reason": {
                reason: {
                    "count": len(items),
                    "examples": compact(items, args.max_examples),
                }
                for reason, items in sorted(expected_missing_ddr.items())
            },
            "suspicious_ddr_examples": compact(suspicious_missing_ddr, args.max_examples),
            "important_pcie_examples": compact(important_missing_pcie, args.max_examples),
            "important_ddr_examples": compact(important_missing_ddr, args.max_examples),
            "important_by_category": {key: value[: args.max_examples] for key, value in sorted(by_category.items())},
        },
        "verdict": "PASS" if not important_missing_pcie and not important_missing_ddr else "REVIEW",
    }

    text = json.dumps(report, indent=2, sort_keys=True)
    if args.out_json:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
