#!/usr/bin/env python3
"""Fetch top Hugging Face text-generation models and write a TSV list."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_EXCLUDE_RE = (
    ""
)


@dataclass
class ModelEntry:
    model_id: str
    revision: str
    downloads: int
    likes: int
    library_name: str
    pipeline_tag: str
    gated: str
    private: bool


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--limit",
        type=int,
        default=100,
        help="Number of models to write (after filtering)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output TSV path",
    )
    parser.add_argument(
        "--pipeline-tag",
        default="text-generation",
        help="Hugging Face pipeline_tag query",
    )
    parser.add_argument(
        "--only-transformers",
        action="store_true",
        help="Keep only entries with library_name=transformers",
    )
    parser.add_argument(
        "--allow-gated",
        action="store_true",
        default=True,
        help="Include gated models",
    )
    parser.add_argument(
        "--allow-private",
        action="store_true",
        help="Include private models",
    )
    parser.add_argument(
        "--exclude-regex",
        default=DEFAULT_EXCLUDE_RE,
        help="Optional regex applied to model id and tags",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=50,
        help="Maximum number of API pages to scan",
    )
    parser.add_argument(
        "--raw-json",
        help="Optional path to dump fetched raw API payload",
    )
    parser.add_argument(
        "--token-env",
        default="HF_TOKEN",
        help="Environment variable containing Hugging Face token (optional)",
    )
    return parser.parse_args()


def fetch_page(
    *,
    pipeline_tag: str,
    offset: int,
    limit: int,
    token: str | None,
) -> list[dict[str, Any]]:
    params = {
        "pipeline_tag": pipeline_tag,
        "sort": "downloads",
        "direction": "-1",
        "limit": str(limit),
        "offset": str(offset),
        "full": "true",
    }
    url = "https://huggingface.co/api/models?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url)
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = response.read().decode("utf-8")
    data = json.loads(payload)
    if not isinstance(data, list):
        raise RuntimeError(f"Unexpected API response at offset={offset}: {type(data)}")
    return data


def normalize(entry: dict[str, Any]) -> ModelEntry | None:
    model_id = entry.get("id")
    if not model_id:
        return None
    revision = entry.get("sha") or "main"
    downloads = int(entry.get("downloads") or 0)
    likes = int(entry.get("likes") or 0)
    library_name = str(entry.get("library_name") or "")
    pipeline_tag = str(entry.get("pipeline_tag") or "")
    gated_raw = entry.get("gated", False)
    gated = str(gated_raw).lower() if gated_raw is not None else "false"
    private = bool(entry.get("private", False))
    return ModelEntry(
        model_id=model_id,
        revision=revision,
        downloads=downloads,
        likes=likes,
        library_name=library_name,
        pipeline_tag=pipeline_tag,
        gated=gated,
        private=private,
    )


def is_gated(value: str) -> bool:
    return value not in ("false", "0", "", "none")


def main() -> int:
    args = parse_args()
    token = None
    if args.token_env:
        token = os.environ.get(args.token_env)
    exclude_re = re.compile(args.exclude_regex) if args.exclude_regex else None

    raw_pages: list[dict[str, Any]] = []
    selected: list[ModelEntry] = []
    seen: set[str] = set()

    offset = 0
    page_size = 100
    pages_scanned = 0
    no_growth_pages = 0
    while len(selected) < args.limit and pages_scanned < args.max_pages:
        before = len(selected)
        page = fetch_page(
            pipeline_tag=args.pipeline_tag,
            offset=offset,
            limit=page_size,
            token=token,
        )
        if not page:
            break
        pages_scanned += 1
        raw_pages.extend(page)
        for raw in page:
            entry = normalize(raw)
            if entry is None:
                continue
            if entry.model_id in seen:
                continue
            if args.only_transformers and entry.library_name not in ("", "transformers"):
                continue
            if (not args.allow_private) and entry.private:
                continue
            if (not args.allow_gated) and is_gated(entry.gated):
                continue

            raw_tags = raw.get("tags") or []
            tags = [str(t) for t in raw_tags if isinstance(t, str)]
            haystack = " ".join([entry.model_id] + tags)
            if exclude_re and exclude_re.search(haystack):
                continue

            selected.append(entry)
            seen.add(entry.model_id)
            if len(selected) >= args.limit:
                break
        offset += page_size
        if len(selected) == before:
            no_growth_pages += 1
        else:
            no_growth_pages = 0
        if no_growth_pages >= 3:
            print(
                "warning: stopping early because pagination made no progress",
                file=sys.stderr,
            )
            break

    if args.raw_json:
        Path(args.raw_json).write_text(json.dumps(raw_pages, indent=2), encoding="utf-8")

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(
            [
                "rank",
                "model_id",
                "revision",
                "downloads",
                "likes",
                "library_name",
                "pipeline_tag",
                "gated",
                "private",
            ]
        )
        for idx, entry in enumerate(selected, start=1):
            writer.writerow(
                [
                    idx,
                    entry.model_id,
                    entry.revision,
                    entry.downloads,
                    entry.likes,
                    entry.library_name,
                    entry.pipeline_tag,
                    entry.gated,
                    "true" if entry.private else "false",
                ]
            )

    print(f"wrote {len(selected)} models to {out_path}")
    if len(selected) < args.limit:
        print(
            f"warning: requested {args.limit} models but only found {len(selected)}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
