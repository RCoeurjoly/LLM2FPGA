#!/usr/bin/env python3
"""Compare routed FASM files for DDR3-sensitive physical changes.

This is intentionally a conservative gate.  It does not prove that a design
will calibrate, but it catches nextpnr/openXC7 physical movement in resources
that have repeatedly correlated with YPCB DDR3 calibration regressions.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Iterable


CRITICAL_CLASS_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("idelay", re.compile(r"(?:^|[._])I(?:O_)?IDELAY|IDELAYCTRL|IDELAY_Y", re.I)),
    ("iserdes_oserdes", re.compile(r"ISERDES|OSERDES|SERDES", re.I)),
    ("iob", re.compile(r"(?:^|[._])IOB(?:[._]|$)|LIOB|RIOB|IOI", re.I)),
    ("pll_mmcm_site", re.compile(r"PLLE2_ADV|MMCME2_ADV", re.I)),
    ("clock_route", re.compile(r"BUFG|BUFIO|BUFR|CLK_|CMT_|HCLK", re.I)),
    ("bscan_jtag", re.compile(r"BSCAN|JTAG", re.I)),
)

HARD_FAIL_CLASSES = {
    "idelay",
    "iserdes_oserdes",
    "iob",
    "pll_mmcm_site",
    "bscan_jtag",
}


def parse_fasm(path: Path) -> set[str]:
    features: set[str] = set()
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            features.add(line)
    return features


def tile_name(feature: str) -> str:
    return feature.split(".", 1)[0]


def class_names(feature: str) -> list[str]:
    return [
        name
        for name, pattern in CRITICAL_CLASS_PATTERNS
        if pattern.search(feature)
    ]


def critical_features(features: Iterable[str]) -> dict[str, set[str]]:
    by_class: dict[str, set[str]] = {name: set() for name, _ in CRITICAL_CLASS_PATTERNS}
    for feature in features:
        for name in class_names(feature):
            by_class[name].add(feature)
    return by_class


def sample(values: Iterable[str], limit: int) -> list[str]:
    return sorted(values)[:limit]


def counter_delta(before: Counter[str], after: Counter[str]) -> dict[str, dict[str, int]]:
    keys = sorted(set(before) | set(after))
    return {
        key: {"baseline": before[key], "candidate": after[key]}
        for key in keys
        if before[key] != after[key]
    }


def build_report(
    baseline: Path,
    candidate: Path,
    label: str,
    max_examples: int,
    ignored_tiles: set[str],
) -> dict[str, object]:
    baseline_features = parse_fasm(baseline)
    candidate_features = parse_fasm(candidate)
    baseline_features = {
        feature for feature in baseline_features if tile_name(feature) not in ignored_tiles
    }
    candidate_features = {
        feature for feature in candidate_features if tile_name(feature) not in ignored_tiles
    }

    added = candidate_features - baseline_features
    removed = baseline_features - candidate_features
    common = baseline_features & candidate_features

    baseline_classes = critical_features(baseline_features)
    candidate_classes = critical_features(candidate_features)

    class_reports: dict[str, object] = {}
    critical_added_total = 0
    critical_removed_total = 0
    moved_tile_total = 0
    hard_added_total = 0
    hard_removed_total = 0
    hard_moved_tile_total = 0

    for name, _pattern in CRITICAL_CLASS_PATTERNS:
        class_added = candidate_classes[name] - baseline_classes[name]
        class_removed = baseline_classes[name] - candidate_classes[name]
        baseline_tiles = Counter(tile_name(feature) for feature in baseline_classes[name])
        candidate_tiles = Counter(tile_name(feature) for feature in candidate_classes[name])
        tile_deltas = counter_delta(baseline_tiles, candidate_tiles)

        critical_added_total += len(class_added)
        critical_removed_total += len(class_removed)
        moved_tile_total += len(tile_deltas)
        if name in HARD_FAIL_CLASSES:
            hard_added_total += len(class_added)
            hard_removed_total += len(class_removed)
            hard_moved_tile_total += len(tile_deltas)

        class_reports[name] = {
            "baseline_feature_count": len(baseline_classes[name]),
            "candidate_feature_count": len(candidate_classes[name]),
            "added_count": len(class_added),
            "removed_count": len(class_removed),
            "changed_tile_count": len(tile_deltas),
            "changed_tiles": dict(list(tile_deltas.items())[:max_examples]),
            "added_examples": sample(class_added, max_examples),
            "removed_examples": sample(class_removed, max_examples),
        }

    status = "PASS"
    reasons: list[str] = []
    if hard_added_total or hard_removed_total:
        status = "FAIL"
        reasons.append(
            "DDR3 PHY/JTAG site-level FASM features changed relative to the baseline"
        )
    elif hard_moved_tile_total:
        status = "FAIL"
        reasons.append("DDR3 PHY/JTAG site-level tile feature counts changed")
    elif critical_added_total or critical_removed_total or moved_tile_total:
        status = "WARN"
        reasons.append(
            "DDR3 PHY/JTAG sites match, but clock/routing FASM changed relative to the baseline"
        )

    if not reasons:
        reasons.append("critical DDR3/clock/JTAG FASM footprint matches baseline")

    return {
        "label": label,
        "status": status,
        "reasons": reasons,
        "baseline_fasm": str(baseline),
        "candidate_fasm": str(candidate),
        "summary": {
            "baseline_feature_count": len(baseline_features),
            "candidate_feature_count": len(candidate_features),
            "common_feature_count": len(common),
            "total_added_count": len(added),
            "total_removed_count": len(removed),
            "critical_added_count": critical_added_total,
            "critical_removed_count": critical_removed_total,
            "critical_changed_tile_count": moved_tile_total,
            "hard_fail_added_count": hard_added_total,
            "hard_fail_removed_count": hard_removed_total,
            "hard_fail_changed_tile_count": hard_moved_tile_total,
            "ignored_tile_count": len(ignored_tiles),
            "ignored_tiles": sorted(ignored_tiles),
        },
        "critical_classes": class_reports,
        "total_added_examples": sample(added, max_examples),
        "total_removed_examples": sample(removed, max_examples),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Gate nextpnr/openXC7 FASM movement before DDR3 board runs."
    )
    parser.add_argument("--baseline-fasm", required=True, type=Path)
    parser.add_argument("--candidate-fasm", required=True, type=Path)
    parser.add_argument("--label", default="task6-ddr3-physical-stability")
    parser.add_argument("--out-json", type=Path)
    parser.add_argument("--max-examples", type=int, default=16)
    parser.add_argument(
        "--ignore-tile",
        action="append",
        default=[],
        help="Ignore one physical FASM tile. Repeat for multiple tiles.",
    )
    parser.add_argument(
        "--fail-on-change",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Return non-zero when DDR3-sensitive physical features changed.",
    )
    args = parser.parse_args()

    report = build_report(
        baseline=args.baseline_fasm,
        candidate=args.candidate_fasm,
        label=args.label,
        max_examples=args.max_examples,
        ignored_tiles=set(args.ignore_tile),
    )
    text = json.dumps(report, indent=2, sort_keys=True)
    if args.out_json:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(text + "\n", encoding="utf-8")
    print(text)

    if args.fail_on_change and report["status"] != "PASS":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
