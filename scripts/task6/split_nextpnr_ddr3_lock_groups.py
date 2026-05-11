#!/usr/bin/env python3
"""Split known-good DDR3 BEL lock files into functional placement groups.

The lock file is expected to be produced by
``extract_nextpnr_ddr3_bel_locks.py``.  This helper emits one lock file per
group plus a manifest for sweep automation.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_GROUPS: tuple[tuple[str, str], ...] = (
    (
        "clocking",
        r"(^|[._])(?:clk(?:25|50|100|200)?|clock_|dcm|pll|plle2_adv|mmcme2_adv|BUFGCTRL|BUFG|BUFIO|BUFR|HCLK_(?:IOI3|_)?|clock)(?:$|[._])|ddr3_clocks",
    ),
    (
        "dqs",
        r"genblk7|_dqs|DQS|dqs|dqs[0-9]",
    ),
    (
        "dq",
        r"genblk5|_data|data|IDELAYE2_data|ISERDESE2_data|OSERDESE2_data",
    ),
    (
        "command_addr",
        r"genblk1|_cmd|OSERDESE2_cmd|ISERDESE2_cmd|IDELAYE2_cmd|ddram_(addr|ba|cas_n|ras_n|we_n|cke|cs_n|odt)|command|addr",
    ),
    (
        "reset_init",
        r"ddram_reset_n|ddr3_reset|reset_n|reset|rst_n|rst|sys_rst|boot_init",
    ),
    (
        "jtag_debug",
        r"BSCAN|JTAG|USER|debug|TAP|sdr_debug|debug1",
    ),
)


def load_locks(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    source = path.name
    locks = payload.get("locks")
    if not isinstance(locks, list):
        raise SystemExit("lock JSON must include a list under key 'locks'")
    return {"source": source}, locks


def split_groups(
    locks: list[dict[str, Any]],
    group_patterns: list[tuple[str, str]],
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, int]]:
    import re

    compiled = [(name, re.compile(pattern, re.IGNORECASE)) for name, pattern in group_patterns]
    groups: dict[str, list[dict[str, Any]]] = {name: [] for name, _ in compiled}
    groups.setdefault("other", [])

    counts: dict[str, int] = {name: 0 for name, _ in compiled}
    counts["other"] = 0

    for lock in locks:
        if not isinstance(lock, dict):
            continue
        cell = str(lock.get("cell", ""))
        scope = str(lock.get("scope", "unknown"))
        haystack = f"{cell} {scope}"

        assigned = "other"
        for group_name, pattern in compiled:
            if pattern.search(haystack):
                assigned = group_name
                counts[group_name] += 1
                break
        if assigned == "other":
            counts["other"] += 1
        groups.setdefault(assigned, []).append(lock)

    # Ensure we only emit recognized group keys (including empty groups when
    # explicit patterns exist but no locks matched).
    for name in [name for name, _ in group_patterns] + ["other"]:
        groups.setdefault(name, [])
        groups[name] = groups[name]

    return groups, counts


def write_group_file(path: Path, source: dict[str, Any], group_name: str, locks: list[dict[str, Any]]) -> None:
    payload = {
        "format": "task6.nextpnr-ddr3-bel-locks.v1",
        "group": group_name,
        "source_placed_json": source.get("source"),
        "group_lock_count": len(locks),
        "locks": locks,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--locks-json", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument(
        "--group",
        action="append",
        default=[],
        help="optional custom group as name:regex (can be passed multiple times)",
    )
    parser.add_argument("--manifest", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.group:
        custom_groups: list[tuple[str, str]] = []
        for item in args.group:
            name, colon, expr = item.partition(":")
            if not colon or not name or not expr:
                raise SystemExit(f"invalid --group value: {item!r}; expected name:regex")
            custom_groups.append((name.strip(), expr.strip()))
    else:
        custom_groups = list(DEFAULT_GROUPS)

    source, locks = load_locks(args.locks_json)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    groups, counts = split_groups(locks, custom_groups)

    group_files: dict[str, str] = {}
    for name, _ in custom_groups:
        out_path = args.out_dir / f"{name}-locks.json"
        write_group_file(out_path, source, name, groups[name])
        group_files[name] = str(out_path)

    other_path = args.out_dir / "other-locks.json"
    write_group_file(other_path, source, "other", groups["other"])
    group_files["other"] = str(other_path)

    manifest = {
        "schema": "task6-ddr3-ddr3-lock-groups.v1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": {
            "locks_json": str(args.locks_json),
            "lock_count": len(locks),
            "group_count": len(group_files),
        },
        "groups": {
            "defined": [name for name, _ in custom_groups],
            "unmatched": len(groups["other"]),
            "counts": counts,
            "files": group_files,
        },
    }
    args.manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(json.dumps({"groups": len(group_files), "source": str(args.locks_json), "out_dir": str(args.out_dir)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
