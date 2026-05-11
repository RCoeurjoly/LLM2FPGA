#!/usr/bin/env python3
"""Correlate rowstream loader seed/variant placement drift against calibration outcome.

This is a lightweight planning tool to replace a brittle single-feature gate with a
data-backed view.  It compares each candidate FASM against a baseline and records
seed/variant metadata plus optional calibration status from run JSON.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
import re
from typing import Any


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
    return [name for name, pattern in CRITICAL_CLASS_PATTERNS if pattern.search(feature)]


def critical_features(features: set[str]) -> dict[str, set[str]]:
    by_class: dict[str, set[str]] = {name: set() for name, _ in CRITICAL_CLASS_PATTERNS}
    for feature in features:
        for name in class_names(feature):
            by_class[name].add(feature)
    return by_class


def counter_delta(before: Counter[str], after: Counter[str]) -> dict[str, dict[str, int]]:
    keys = sorted(set(before) | set(after))
    return {
        key: {"baseline": before[key], "candidate": after[key]}
        for key in keys
        if before[key] != after[key]
    }


def _coerce_bool(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    return None


def _find_run_payload(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    if path.is_file():
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    candidates = [
        path / "boot-diagnostic.json",
        path / "summary.json",
        path / "verdict.json",
        path / "readback" / "decoded-tdo7.json",
    ]
    for candidate in candidates:
        if not candidate.is_file():
            continue
        with candidate.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    return None


def extract_calibration_state(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {"status": "unknown", "boot_done": None, "calib_seen": None, "boot_mismatch": None}

    payload = _find_run_payload(path)
    if payload is None:
        return {"status": "unknown", "boot_done": None, "calib_seen": None, "boot_mismatch": None}

    if "result" in payload and isinstance(payload["result"], dict):
        status = payload["result"].get("calibration")
        if status in {"pass", "fail"}:
            data = payload["result"]
            return {
                "status": status,
                "boot_done": _coerce_bool(data.get("boot_done", payload.get("boot_done"))),
                "calib_seen": _coerce_bool(data.get("calib_seen", payload.get("calib_seen"))),
                "boot_mismatch": _coerce_bool(payload.get("boot_mismatch", data.get("boot_mismatch"))),
            }

    debug_payload = payload.get("debug", payload)
    if not isinstance(debug_payload, dict):
        return {"status": "unknown", "boot_done": None, "calib_seen": None, "boot_mismatch": None}

    boot_done = _coerce_bool(debug_payload.get("boot_done"))
    calib_seen = _coerce_bool(debug_payload.get("calib_seen"))
    calib_complete = _coerce_bool(debug_payload.get("calib_complete"))
    boot_mismatch = _coerce_bool(debug_payload.get("boot_mismatch"))

    if boot_done is False:
        status = "fail"
    elif boot_mismatch is True:
        status = "fail"
    elif calib_seen is True and (calib_complete in (None, True)):
        status = "pass"
    elif calib_seen is False:
        status = "fail"
    else:
        status = "unknown"

    return {
        "status": status,
        "boot_done": boot_done,
        "calib_seen": calib_seen,
        "boot_mismatch": boot_mismatch,
    }


def compare_candidate(
    baseline_features: set[str],
    candidate_fasm: Path,
    baseline_name: str,
    ignore_tiles: set[str],
    max_examples: int = 16,
) -> dict[str, Any]:
    candidate_features = parse_fasm(candidate_fasm)
    baseline_filtered = {
        feature for feature in baseline_features if tile_name(feature) not in ignore_tiles
    }
    candidate_filtered = {
        feature for feature in candidate_features if tile_name(feature) not in ignore_tiles
    }

    added = candidate_filtered - baseline_filtered
    removed = baseline_filtered - candidate_filtered
    common = baseline_filtered & candidate_filtered

    baseline_classes = critical_features(baseline_filtered)
    candidate_classes = critical_features(candidate_filtered)

    class_reports: dict[str, Any] = {}
    critical_added_total = 0
    critical_removed_total = 0
    changed_tiles_total = 0
    hard_fail_added_total = 0
    hard_fail_removed_total = 0
    hard_fail_changed_tiles_total = 0

    for name, _pattern in CRITICAL_CLASS_PATTERNS:
        class_added = candidate_classes[name] - baseline_classes[name]
        class_removed = baseline_classes[name] - candidate_classes[name]
        baseline_tiles = Counter(tile_name(feature) for feature in baseline_classes[name])
        candidate_tiles = Counter(tile_name(feature) for feature in candidate_classes[name])
        tile_deltas = counter_delta(baseline_tiles, candidate_tiles)

        critical_added_total += len(class_added)
        critical_removed_total += len(class_removed)
        changed_tiles_total += len(tile_deltas)
        if name in HARD_FAIL_CLASSES:
            hard_fail_added_total += len(class_added)
            hard_fail_removed_total += len(class_removed)
            hard_fail_changed_tiles_total += len(tile_deltas)

        class_reports[name] = {
            "added": sorted(class_added),
            "removed": sorted(class_removed),
            "added_count": len(class_added),
            "removed_count": len(class_removed),
            "added_examples": sorted(class_added)[:max_examples],
            "removed_examples": sorted(class_removed)[:max_examples],
            "changed_tile_count": len(tile_deltas),
            "changed_tiles": dict(list(tile_deltas.items())[:max_examples]),
            "baseline_feature_count": len(baseline_classes[name]),
            "candidate_feature_count": len(candidate_classes[name]),
        }

    return {
        "baseline": baseline_name,
        "candidate": str(candidate_fasm),
        "summary": {
            "baseline_feature_count": len(baseline_filtered),
            "candidate_feature_count": len(candidate_filtered),
            "common_feature_count": len(common),
            "total_added_count": len(added),
            "total_removed_count": len(removed),
            "critical_added_count": critical_added_total,
            "critical_removed_count": critical_removed_total,
            "critical_changed_tile_count": changed_tiles_total,
            "hard_fail_added_count": hard_fail_added_total,
            "hard_fail_removed_count": hard_fail_removed_total,
            "hard_fail_changed_tile_count": hard_fail_changed_tiles_total,
            "ignored_tile_count": len(ignore_tiles),
            "ignored_tiles": sorted(ignore_tiles),
        },
        "classes": class_reports,
    }


def summarize_correlation(samples: list[dict[str, Any]]) -> dict[str, Any]:
    known_samples = [s for s in samples if s["calibration"]["status"] in {"pass", "fail"}]
    pass_samples = [s for s in known_samples if s["calibration"]["status"] == "pass"]
    fail_samples = [s for s in known_samples if s["calibration"]["status"] == "fail"]

    if not pass_samples or not fail_samples:
        return {
            "pass_sample_count": len(pass_samples),
            "fail_sample_count": len(fail_samples),
            "reliability_note": "insufficient known calibration labels for correlation",
            "pass_preferred_features": {},
            "fail_preferred_features": {},
        }

    pass_total = len(pass_samples)
    fail_total = len(fail_samples)

    pass_counts: Counter[tuple[str, str, str]] = Counter()
    fail_counts: Counter[tuple[str, str, str]] = Counter()

    def walk(sample: dict[str, Any], target: Counter[tuple[str, str, str]]) -> None:
        for class_name, report in sample["feature_report"]["classes"].items():
            for feature in report.get("added", []):
                target[(feature, class_name, "added")] += 1
            for feature in report.get("removed", []):
                target[(feature, class_name, "removed")] += 1

    for sample in pass_samples:
        walk(sample, pass_counts)
    for sample in fail_samples:
        walk(sample, fail_counts)

    all_keys = set(pass_counts) | set(fail_counts)
    pass_preferred: dict[str, Any] = {}
    fail_preferred: dict[str, Any] = {}

    for feature, class_name, change_type in sorted(all_keys):
        pass_seen = pass_counts.get((feature, class_name, change_type), 0)
        fail_seen = fail_counts.get((feature, class_name, change_type), 0)
        if pass_seen == pass_total and fail_seen == 0:
            pass_preferred.setdefault(class_name, []).append(
                {
                    "feature": feature,
                    "change": change_type,
                    "pass_seen": pass_seen,
                    "fail_seen": fail_seen,
                }
            )
        if fail_seen == fail_total and pass_seen == 0:
            fail_preferred.setdefault(class_name, []).append(
                {
                    "feature": feature,
                    "change": change_type,
                    "pass_seen": pass_seen,
                    "fail_seen": fail_seen,
                }
            )

    return {
        "pass_sample_count": len(pass_samples),
        "fail_sample_count": len(fail_samples),
        "pass_preferred_features": pass_preferred,
        "fail_preferred_features": fail_preferred,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-fasm", required=True, type=Path)
    parser.add_argument("--samples-json", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--out-csv", type=Path)
    parser.add_argument("--label", default="task6-ddr3-seed-correlation")
    parser.add_argument("--ignore-tile", action="append", default=[])
    parser.add_argument("--max-examples", type=int, default=32)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    samples_payload = json.loads(args.samples_json.read_text(encoding="utf-8"))
    if not isinstance(samples_payload, list):
        raise SystemExit("--samples-json must contain a JSON array")

    baseline_features = parse_fasm(args.baseline_fasm)
    sample_reports: list[dict[str, Any]] = []
    for item in samples_payload:
        if not isinstance(item, dict):
            raise SystemExit("each sample entry must be an object")
        label = item.get("label")
        fasm = item.get("fasm")
        if not isinstance(label, str):
            raise SystemExit("each sample requires a string label")
        if not isinstance(fasm, str):
            raise SystemExit(f"sample {label!r} requires fasm")
        run_json = item.get("run_json")

        calibrated = extract_calibration_state(Path(run_json) if run_json is not None else None)
        if manual := item.get("calibration_status"):
            if manual in {"pass", "fail", "unknown"}:
                calibrated["status"] = manual

        feature_report = compare_candidate(
            baseline_features=baseline_features,
            candidate_fasm=Path(fasm),
            baseline_name=str(args.baseline_fasm),
            ignore_tiles=set(args.ignore_tile),
            max_examples=args.max_examples,
        )

        sample_reports.append(
            {
                "label": label,
                "seed": item.get("seed"),
                "version": item.get("version"),
                "variant": item.get("variant"),
                "notes": item.get("notes"),
                "calibration": calibrated,
                "feature_report": feature_report,
            }
        )

    correlation = summarize_correlation(sample_reports)

    out_payload = {
        "schema": "task6-ddr3-seed-correlation-v1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "label": args.label,
        "baseline_fasm": str(args.baseline_fasm),
        "samples": sample_reports,
        "correlation": correlation,
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(out_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if args.out_csv is not None:
        args.out_csv.parent.mkdir(parents=True, exist_ok=True)
        with args.out_csv.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
                    "label",
                    "seed",
                    "version",
                    "variant",
                    "calibration_status",
                    "boot_done",
                    "calib_seen",
                    "boot_mismatch",
                    "total_added",
                    "total_removed",
                    "hard_fail_added",
                    "hard_fail_removed",
                    "hard_changed_tiles",
                    "critical_notes",
                ]
            )
            for sample in sample_reports:
                summary = sample["feature_report"]["summary"]
                calib = sample["calibration"]
                writer.writerow(
                    [
                        sample["label"],
                        sample.get("seed", ""),
                        sample.get("version", ""),
                        sample.get("variant", ""),
                        calib["status"],
                        calib.get("boot_done", ""),
                        calib.get("calib_seen", ""),
                        calib.get("boot_mismatch", ""),
                        summary["total_added_count"],
                        summary["total_removed_count"],
                        summary["hard_fail_added_count"],
                        summary["hard_fail_removed_count"],
                        summary["hard_fail_changed_tile_count"],
                        sample.get("notes", ""),
                    ]
                )

    print(json.dumps({"label": args.label, "samples": len(sample_reports), "baseline": str(args.baseline_fasm)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
