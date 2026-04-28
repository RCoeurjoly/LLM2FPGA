#!/usr/bin/env python3
"""Extract compact Task 6 run metrics into CSV rows."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]

FIELDNAMES = [
    "artifact",
    "source_path",
    "kind",
    "verdict",
    "lut",
    "ff",
    "dsp",
    "bram36",
    "bram36_equiv",
    "lut_pct",
    "ff_pct",
    "dsp_pct",
    "bram36_pct",
    "wall_s",
    "rss_kb",
    "hwm_kb",
    "verilator_status",
    "stores",
    "outputs",
    "cycles_per_token",
    "bytes_per_token",
    "fail_reason",
    "top_owners",
    "top_leaf_cell_types",
]

LUT_CELL_TYPES = {
    "CFGLUT5",
    "LUT1",
    "LUT2",
    "LUT3",
    "LUT4",
    "LUT5",
    "LUT6",
    "LUT6_2",
}
FF_CELL_TYPES = {"FDCE", "FDPE", "FDRE", "FDSE", "LDCE", "LDPE"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", help="Artifact directories or summary files")
    parser.add_argument("--out", required=True, help="CSV path to write")
    parser.add_argument(
        "--artifact",
        action="append",
        default=[],
        help="Optional artifact name override. May be repeated to match inputs.",
    )
    return parser.parse_args()


def relpath(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def maybe_number(text: str) -> int | float | None:
    text = text.strip().replace(",", "")
    text = re.sub(r"\s*(s|KB|KiB)$", "", text)
    if text in {"", "n/a", "None"}:
        return None
    try:
        if "." in text:
            return float(text)
        return int(text)
    except ValueError:
        return None


def metric_from_md(text: str, label: str) -> int | float | None:
    match = re.search(rf"^- {re.escape(label)}:\s+`?([^`\n]+?)`?\s*$", text, re.M)
    if match is None:
        return None
    return maybe_number(match.group(1))


def text_metric(text: str, label: str) -> str:
    match = re.search(rf"^- {re.escape(label)}:\s+`?([^`\n]+?)`?\s*$", text, re.M)
    return match.group(1).strip() if match else ""


def parse_percent_resource(resources: dict[str, Any], name: str, pct_name: str | None = None) -> tuple[Any, Any]:
    item = resources.get(name) or {}
    pct_item = resources.get(pct_name) if pct_name else None
    if isinstance(pct_item, dict):
        return item.get("used"), pct_item.get("pct")
    return item.get("used"), item.get("pct")


def cell_count_score(counts: dict[str, int]) -> tuple[int, int]:
    lut_like = 0
    ff_like = 0
    for cell_type, count in counts.items():
        if cell_type in LUT_CELL_TYPES:
            lut_like += int(count)
        elif cell_type in FF_CELL_TYPES:
            ff_like += int(count)
    return lut_like, ff_like


def module_lookup(modules: dict[str, Any], name: str) -> dict[str, Any] | None:
    if name in modules:
        return modules[name]
    escaped = "\\" + name
    if escaped in modules:
        return modules[escaped]
    return None


def top_owner_rows(payload: dict[str, Any]) -> list[tuple[int, int, int, str]]:
    modules = payload.get("modules") or {}
    if not isinstance(modules, dict):
        return []

    root_name = payload.get("top") or payload.get("top_module")
    if not isinstance(root_name, str):
        return []

    root = module_lookup(modules, root_name)
    if root is None:
        return []

    direct_counts = root.get("direct_cell_counts") or {}
    # TinyStories selftest wraps the actual synthesized model in `main`.
    # Attribute the owner rows to `main`'s direct children so repeated
    # handshake primitives are weighted by their actual instance counts.
    main_module = module_lookup(modules, "main")
    if main_module is not None and direct_counts.get("main") == 1:
        direct_counts = main_module.get("direct_cell_counts") or {}

    rows: list[tuple[int, int, int, str]] = []
    for owner_type, instances in direct_counts.items():
        owner_module = module_lookup(modules, owner_type)
        if owner_module is None:
            counts = {owner_type: 1}
        else:
            counts = owner_module.get("leaf_cell_counts") or {}
        lut_like, ff_like = cell_count_score(counts)
        lut_total = int(instances) * lut_like
        ff_total = int(instances) * ff_like
        if lut_total or ff_total:
            rows.append((
                lut_total,
                ff_total,
                int(instances),
                owner_type.lstrip("\\"),
            ))
    rows.sort(reverse=True)
    return rows


def top_owners_from_stat(stat_path: Path, limit: int = 20) -> str:
    if not stat_path.exists():
        return ""
    payload = read_json(stat_path)
    rows = top_owner_rows(payload)
    if rows:
        return "; ".join(
            f"{name}:count={count},lut={lut},ff={ff}"
            for lut, ff, count, name in rows[:limit]
        )

    rows: list[tuple[int, int, str]] = []
    for module_name, module in (payload.get("modules") or {}).items():
        clean_name = module_name.lstrip("\\")
        if clean_name in {"main", "tiny_stories_selftest_top"}:
            continue
        counts = module.get("leaf_cell_counts") or {}
        lut_like, ff_like = cell_count_score(counts)
        if lut_like or ff_like:
            rows.append((lut_like, ff_like, clean_name))
    rows.sort(reverse=True)
    return "; ".join(f"{name}:lut={lut},ff={ff}" for lut, ff, name in rows[:limit])


def top_leaf_cell_types(summary: dict[str, Any], limit: int = 20) -> str:
    rows = summary.get("top_leaf_cell_types") or []
    return "; ".join(f"{row.get('type')}={row.get('count')}" for row in rows[:limit])


def row_from_utilization(path: Path, artifact: str) -> dict[str, Any]:
    summary_path = path / "summary.json"
    stat_path = path / "stat.json"
    summary = read_json(summary_path)
    resources = summary.get("resources") or {}
    lut, lut_pct = parse_percent_resource(resources, "clb_luts")
    ff, ff_pct = parse_percent_resource(resources, "clb_ffs")
    dsp, dsp_pct = parse_percent_resource(resources, "dsp")
    bram36, bram36_pct = parse_percent_resource(resources, "bram36")
    bram36_equiv, _ = parse_percent_resource(resources, "bram36_equiv")
    return {
        "artifact": artifact,
        "source_path": relpath(path),
        "kind": "utilization",
        "verdict": "",
        "lut": lut,
        "ff": ff,
        "dsp": dsp,
        "bram36": bram36,
        "bram36_equiv": bram36_equiv,
        "lut_pct": lut_pct,
        "ff_pct": ff_pct,
        "dsp_pct": dsp_pct,
        "bram36_pct": bram36_pct,
        "wall_s": "",
        "rss_kb": "",
        "hwm_kb": "",
        "verilator_status": "",
        "stores": "",
        "outputs": "",
        "cycles_per_token": "",
        "bytes_per_token": "",
        "fail_reason": "",
        "top_owners": top_owners_from_stat(stat_path),
        "top_leaf_cell_types": top_leaf_cell_types(summary),
    }


def row_from_monitored_run(path: Path, artifact: str) -> dict[str, Any]:
    row = row_from_utilization(path / "utilization", artifact)
    row["source_path"] = relpath(path)
    row["kind"] = "monitored-utilization-run"
    summary_txt = path / "summary.txt"
    readme = path / "README.md"
    text = ""
    if summary_txt.exists():
        text += summary_txt.read_text(encoding="utf-8", errors="replace")
    if readme.exists():
        text += "\n" + readme.read_text(encoding="utf-8", errors="replace")
    status_match = re.search(r"(?im)^(?:exit status|exit_status):\s*`?(\d+)`?", text)
    wall_match = re.search(r"(?im)^(?:wall(?: time)?|wall_seconds):\s*`?([0-9.]+)", text)
    rss_match = re.search(
        r"(?im)^(?:peak sampled `?VmRSS`?|peak_vmrss_kb):\s*`?([0-9,]+)",
        text,
    )
    hwm_match = re.search(
        r"(?im)^(?:peak sampled `?VmHWM`?|peak_vmhwm_kb):\s*`?([0-9,]+)",
        text,
    )
    if status_match:
        row["verdict"] = "pass" if status_match.group(1) == "0" else "fail"
    if wall_match:
        row["wall_s"] = maybe_number(wall_match.group(1))
    if rss_match:
        row["rss_kb"] = maybe_number(rss_match.group(1))
    if hwm_match:
        row["hwm_kb"] = maybe_number(hwm_match.group(1))
    return row


def row_from_stage_summary(path: Path, artifact: str) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    pass_line = text_metric(text, "Verilator result")
    stores = outputs = ""
    pass_match = re.search(r"stores\s+(\d+)\s+outputs\s+(\d+)", pass_line)
    if pass_match:
        stores = int(pass_match.group(1))
        outputs = int(pass_match.group(2))
    verdict = ""
    verdict_match = re.search(r"(?ms)^## Verdict\s*\n\s*- `([^`]+)`", text)
    if verdict_match:
        verdict = verdict_match.group(1)
    return {
        "artifact": artifact,
        "source_path": relpath(path.parent),
        "kind": "stage-local-summary",
        "verdict": verdict,
        "lut": metric_from_md(text, "CLB LUTs"),
        "ff": metric_from_md(text, "CLB FFs"),
        "dsp": metric_from_md(text, "DSP48E1"),
        "bram36": metric_from_md(text, "BRAM36"),
        "bram36_equiv": "",
        "lut_pct": "",
        "ff_pct": "",
        "dsp_pct": "",
        "bram36_pct": "",
        "wall_s": metric_from_md(text, "utilization replay wall-clock"),
        "rss_kb": metric_from_md(text, "utilization replay peak RSS"),
        "hwm_kb": "",
        "verilator_status": pass_line,
        "stores": stores,
        "outputs": outputs,
        "cycles_per_token": "",
        "bytes_per_token": "",
        "fail_reason": "" if verdict == "pass" else verdict,
        "top_owners": "",
        "top_leaf_cell_types": "",
    }


def classify_input(path: Path, artifact: str) -> dict[str, Any]:
    if path.is_file():
        if path.name == "summary.md":
            return row_from_stage_summary(path, artifact)
        raise SystemExit(f"unsupported input file: {path}")
    if (path / "utilization" / "summary.json").exists():
        return row_from_monitored_run(path, artifact)
    if (path / "summary.json").exists():
        return row_from_utilization(path, artifact)
    if (path / "summary.md").exists():
        return row_from_stage_summary(path / "summary.md", artifact)
    raise SystemExit(f"unsupported artifact path: {path}")


def main() -> None:
    args = parse_args()
    rows = []
    for index, raw_input in enumerate(args.inputs):
        path = Path(raw_input)
        artifact = args.artifact[index] if index < len(args.artifact) else path.name
        rows.append(classify_input(path, artifact))

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
