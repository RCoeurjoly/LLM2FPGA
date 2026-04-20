#!/usr/bin/env python3
"""Filter whole RTLIL module definitions by module-name regex."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


MODULE_RE = re.compile(r"^module (\S+)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Input RTLIL file.")
    parser.add_argument("--output", required=True, help="Output RTLIL file.")
    parser.add_argument(
        "--drop-escaped-uppercase-modules",
        action="store_true",
        help="Drop module definitions whose RTLIL name starts with a backslash followed by an uppercase letter.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    if not args.drop_escaped_uppercase_modules:
        raise SystemExit(
            "filter_rtlil_modules.py requires --drop-escaped-uppercase-modules"
        )

    def should_drop(name: str) -> bool:
        return (
            args.drop_escaped_uppercase_modules
            and name.startswith("\\")
            and len(name) > 1
            and name[1].isupper()
        )

    dropping = False
    with input_path.open("r", encoding="utf-8", errors="ignore") as src, output_path.open(
        "w", encoding="utf-8"
    ) as dst:
        for line in src:
            module_match = MODULE_RE.match(line)
            if module_match is not None:
                dropping = should_drop(module_match.group(1))
                if not dropping:
                    dst.write(line)
                continue

            if dropping:
                if line == "end\n":
                    dropping = False
                continue

            dst.write(line)


if __name__ == "__main__":
    main()
