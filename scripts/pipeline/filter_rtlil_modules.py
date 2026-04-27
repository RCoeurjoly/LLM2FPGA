#!/usr/bin/env python3
"""Filter whole RTLIL module definitions by module-name regex."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


MODULE_RE = re.compile(r"^module (\S+)")
ATTRIBUTE_RE = re.compile(r"^attribute\s")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Input RTLIL file.")
    parser.add_argument("--output", required=True, help="Output RTLIL file.")
    parser.add_argument(
        "--drop-module-regex",
        default=None,
        help="Drop any module whose full RTLIL module name matches this regex.",
    )
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

    if args.drop_module_regex is None and not args.drop_escaped_uppercase_modules:
        raise SystemExit(
            "filter_rtlil_modules.py requires either --drop-module-regex or "
            "--drop-escaped-uppercase-modules"
        )

    drop_re = re.compile(args.drop_module_regex) if args.drop_module_regex is not None else None

    def should_drop(name: str) -> bool:
        if drop_re is not None and drop_re.search(name):
            return True
        return (
            args.drop_escaped_uppercase_modules
            and name.startswith("\\")
            and len(name) > 1
            and name[1].isupper()
        )

    dropping = False
    at_top_level = True
    pending_attributes: list[str] = []
    with input_path.open("r", encoding="utf-8", errors="ignore") as src, output_path.open(
        "w", encoding="utf-8"
    ) as dst:
        for line in src:
            module_match = MODULE_RE.match(line)
            if module_match is not None:
                dropping = should_drop(module_match.group(1))
                at_top_level = False
                if not dropping:
                    dst.writelines(pending_attributes)
                    pending_attributes.clear()
                    dst.write(line)
                else:
                    pending_attributes.clear()
                continue

            if dropping:
                if line == "end\n":
                    dropping = False
                    at_top_level = True
                continue

            if at_top_level and ATTRIBUTE_RE.match(line):
                pending_attributes.append(line)
                continue

            if pending_attributes:
                dst.writelines(pending_attributes)
                pending_attributes.clear()

            dst.write(line)
            if line == "end\n":
                at_top_level = True


if __name__ == "__main__":
    main()
