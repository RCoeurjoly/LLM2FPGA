#!/usr/bin/env python3
"""Compare two nextpnr SDF files with Task 6 focused delay summaries."""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
from pathlib import Path
import re
import statistics


DELAY_RE = re.compile(r"\((-?\d+(?:\.\d+)?):(-?\d+(?:\.\d+)?):(-?\d+(?:\.\d+)?)\)")
ENTRY_RE = re.compile(r"^\s*\((INTERCONNECT|IOPATH)\s+(.+)$")

CATEGORY_PATTERNS = {
    "pcie": re.compile(r"pcie|pcie_7x|pcie_ingress|pcie_core", re.I),
    "gt": re.compile(r"GTXE2|GTPE2|GTX|GTP|pipe_|pci_exp", re.I),
    "ddr3_phy": re.compile(r"ddr3_phy|uberddr3|ddram|DQS|DQ", re.I),
    "idelay": re.compile(r"IDELAY|ODELAY|IODELAY", re.I),
    "iserdes": re.compile(r"ISERDES", re.I),
    "oserdes": re.compile(r"OSERDES", re.I),
    "clocking": re.compile(r"BUFG|BUFH|MMCM|PLL|clk|clock", re.I),
    "reset": re.compile(r"reset|rst", re.I),
    "cdc": re.compile(r"cdc|sync|xpm", re.I),
    "rowstream_top1": re.compile(r"top1|rowstream|cutout", re.I),
    "bscan": re.compile(r"BSCAN|jtag", re.I),
}


@dataclass(frozen=True)
class SdfEntry:
    kind: str
    text: str
    key: str
    delay_ps: float
    categories: tuple[str, ...]


def normalize_name(text: str) -> str:
    text = text.replace("\\", "")
    text = text.replace("impl.", "")
    text = re.sub(r"\$abc\$\d+", "$abc$", text)
    text = re.sub(r"\$\d+", "$N", text)
    return text


def entry_key(kind: str, body: str) -> str:
    tokens = body.split()
    if kind == "INTERCONNECT" and len(tokens) >= 2:
        # Source logic names often change after synthesis; destination is the
        # useful stable anchor for comparing routed delay into a primitive pin.
        return f"{kind}:{normalize_name(tokens[1])}"
    if kind == "IOPATH" and len(tokens) >= 2:
        return f"{kind}:{normalize_name(tokens[0])}->{normalize_name(tokens[1])}"
    return f"{kind}:{normalize_name(body)}"


def categories(text: str) -> tuple[str, ...]:
    found = [name for name, pattern in CATEGORY_PATTERNS.items() if pattern.search(text)]
    return tuple(found) if found else ("other",)


def parse_sdf(path: Path) -> list[SdfEntry]:
    entries: list[SdfEntry] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = ENTRY_RE.match(raw)
        if not match:
            continue
        delay_values = [float(value) for triple in DELAY_RE.findall(raw) for value in triple]
        if not delay_values:
            continue
        kind = match.group(1)
        body = match.group(2)
        entries.append(
            SdfEntry(
                kind=kind,
                text=raw.strip(),
                key=entry_key(kind, body),
                delay_ps=max(delay_values),
                categories=categories(raw),
            )
        )
    return entries


def stats(values: list[float]) -> dict[str, float | int | None]:
    if not values:
        return {"count": 0, "min_ps": None, "median_ps": None, "p95_ps": None, "max_ps": None}
    ordered = sorted(values)
    p95_index = min(len(ordered) - 1, int(round((len(ordered) - 1) * 0.95)))
    return {
        "count": len(values),
        "min_ps": ordered[0],
        "median_ps": statistics.median(ordered),
        "p95_ps": ordered[p95_index],
        "max_ps": ordered[-1],
    }


def summarize(entries: list[SdfEntry], top_n: int) -> dict[str, object]:
    by_category: dict[str, list[float]] = defaultdict(list)
    for entry in entries:
        for category in entry.categories:
            by_category[category].append(entry.delay_ps)
    return {
        "entry_count": len(entries),
        "by_category": {key: stats(values) for key, values in sorted(by_category.items())},
        "top": [
            {
                "delay_ps": entry.delay_ps,
                "kind": entry.kind,
                "categories": list(entry.categories),
                "key": entry.key,
                "text": entry.text,
            }
            for entry in sorted(entries, key=lambda item: item.delay_ps, reverse=True)[:top_n]
        ],
    }


def compare(good: list[SdfEntry], bad: list[SdfEntry], top_n: int) -> dict[str, object]:
    good_by_key = {entry.key: entry for entry in good}
    bad_by_key = {entry.key: entry for entry in bad}
    common_keys = sorted(set(good_by_key) & set(bad_by_key))
    changed = []
    for key in common_keys:
        good_entry = good_by_key[key]
        bad_entry = bad_by_key[key]
        changed.append(
            {
                "key": key,
                "delta_ps": bad_entry.delay_ps - good_entry.delay_ps,
                "good_ps": good_entry.delay_ps,
                "bad_ps": bad_entry.delay_ps,
                "bad_categories": list(bad_entry.categories),
                "good_text": good_entry.text,
                "bad_text": bad_entry.text,
            }
        )
    changed_by_abs = sorted(changed, key=lambda item: abs(item["delta_ps"]), reverse=True)
    worse = sorted(changed, key=lambda item: item["delta_ps"], reverse=True)
    better = sorted(changed, key=lambda item: item["delta_ps"])
    return {
        "common_key_count": len(common_keys),
        "good_only_count": len(set(good_by_key) - set(bad_by_key)),
        "bad_only_count": len(set(bad_by_key) - set(good_by_key)),
        "largest_absolute_deltas": changed_by_abs[:top_n],
        "largest_bad_slower_deltas": worse[:top_n],
        "largest_bad_faster_deltas": better[:top_n],
    }


def write_markdown(report: dict[str, object], path: Path) -> None:
    lines = [
        "# Task 6 SDF Delay Comparison",
        "",
        f"- good SDF: `{report['inputs']['good_sdf']}`",
        f"- bad SDF: `{report['inputs']['bad_sdf']}`",
        f"- common keys: `{report['comparison']['common_key_count']}`",
        f"- good-only keys: `{report['comparison']['good_only_count']}`",
        f"- bad-only keys: `{report['comparison']['bad_only_count']}`",
        "",
        "## Category Summary",
        "",
        "| Category | Good count | Good max ps | Bad count | Bad max ps |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    good_categories = report["good"]["by_category"]
    bad_categories = report["bad"]["by_category"]
    for category in sorted(set(good_categories) | set(bad_categories)):
        good_stats = good_categories.get(category, {})
        bad_stats = bad_categories.get(category, {})
        lines.append(
            f"| `{category}` | {good_stats.get('count', 0)} | {good_stats.get('max_ps')} | "
            f"{bad_stats.get('count', 0)} | {bad_stats.get('max_ps')} |"
        )
    lines.extend(["", "## Largest Bad-Slower Deltas", ""])
    for item in report["comparison"]["largest_bad_slower_deltas"][:20]:
        lines.append(f"- `{item['delta_ps']}` ps: `{item['key']}`")
    lines.extend(["", "## Bad Top Delays", ""])
    for item in report["bad"]["top"][:20]:
        lines.append(f"- `{item['delay_ps']}` ps {item['categories']}: `{item['key']}`")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--good-sdf", required=True, type=Path)
    parser.add_argument("--bad-sdf", required=True, type=Path)
    parser.add_argument("--label", default="seed20-sdf")
    parser.add_argument("--out-dir", type=Path, default=Path("artifacts/task6/sdf-comparisons"))
    parser.add_argument("--top-n", type=int, default=100)
    args = parser.parse_args()

    good_entries = parse_sdf(args.good_sdf)
    bad_entries = parse_sdf(args.bad_sdf)
    out_dir = args.out_dir / args.label
    out_dir.mkdir(parents=True, exist_ok=True)

    report = {
        "schema": "task6-sdf-delay-compare-v1",
        "inputs": {
            "good_sdf": str(args.good_sdf),
            "bad_sdf": str(args.bad_sdf),
        },
        "good": summarize(good_entries, args.top_n),
        "bad": summarize(bad_entries, args.top_n),
        "comparison": compare(good_entries, bad_entries, args.top_n),
    }
    (out_dir / "summary.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(report, out_dir / "README.md")
    print(out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
