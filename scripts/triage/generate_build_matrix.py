#!/usr/bin/env python3
"""Generate a build-matrix JSON from a Hugging Face model TSV."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--models",
        required=True,
        help="Input TSV with at least model_id and revision columns",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output JSON path (GitHub Actions matrix format)",
    )
    return parser.parse_args()


def slugify(value: str) -> str:
    slug = value.lower()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = slug.strip("-")
    return slug[:96] or "model"


def to_int(value: str, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def read_models(path: Path) -> list[dict[str, object]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames is None:
            raise RuntimeError(f"{path} has no header row")
        missing = [name for name in ("model_id", "revision") if name not in reader.fieldnames]
        if missing:
            raise RuntimeError(f"{path} is missing required columns: {', '.join(missing)}")

        include: list[dict[str, object]] = []
        for idx, row in enumerate(reader, start=1):
            model_id = str(row.get("model_id") or "").strip()
            revision = str(row.get("revision") or "").strip()
            if not model_id or not revision:
                continue
            rank = to_int(str(row.get("rank") or idx), idx)
            include.append(
                {
                    "rank": rank,
                    "name": f"{rank:03d}-{slugify(model_id)}",
                    "model_id": model_id,
                    "revision": revision,
                    "downloads": to_int(str(row.get("downloads") or "0"), 0),
                    "likes": to_int(str(row.get("likes") or "0"), 0),
                    "library_name": str(row.get("library_name") or ""),
                    "pipeline_tag": str(row.get("pipeline_tag") or ""),
                    "gated": str(row.get("gated") or ""),
                    "private": str(row.get("private") or ""),
                }
            )
    return include


def main() -> int:
    args = parse_args()
    models_path = Path(args.models)
    output_path = Path(args.output)

    include = read_models(models_path)
    payload = {"include": include}

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(include)} matrix entries to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
