#!/usr/bin/env python3
"""Generate blackbox stubs for unresolved helper modules in split SV output."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


DECL_RE = re.compile(
    r"^\s*(?:wire|logic)\s*(\[[^]]+\])?\s*([A-Za-z_][A-Za-z0-9_$]*)\s*;"
)
INST_START_RE = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_$]*)\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\(\s*(?://.*)?$"
)
CONN_RE = re.compile(r"\.(\w+)\s*\(\s*([^)]+?)\s*\)")


def parse_width(range_text: str | None) -> int:
    if not range_text:
        return 1
    m = re.fullmatch(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]", range_text.strip())
    if m is None:
        raise SystemExit(f"unable to parse bit range: {range_text!r}")
    msb, lsb = int(m.group(1)), int(m.group(2))
    return abs(msb - lsb) + 1


def read_defined_modules(sources_f: Path) -> set[str]:
    modules: set[str] = set()
    for line in sources_f.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        modules.add(Path(line).stem)
    return modules


def read_signal_widths(main_sv: Path) -> dict[str, int]:
    widths = {"clock": 1, "reset": 1}
    for line in main_sv.read_text(encoding="utf-8").splitlines():
        m = DECL_RE.match(line)
        if m is None:
            continue
        widths[m.group(2)] = parse_width(m.group(1))
    return widths


def read_missing_instances(
    main_sv: Path, defined_modules: set[str]
) -> dict[str, dict[str, str]]:
    lines = main_sv.read_text(encoding="utf-8").splitlines()
    missing: dict[str, dict[str, str]] = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        start = INST_START_RE.match(line)
        if start is None:
            i += 1
            continue

        module_name = start.group(1)
        if module_name == "module":
            i += 1
            continue

        block = [line]
        i += 1
        while i < len(lines):
            block.append(lines[i])
            if ");" in lines[i]:
                i += 1
                break
            i += 1

        if module_name in defined_modules or module_name in missing:
            continue

        ports: dict[str, str] = {}
        for block_line in block[1:]:
            stripped = block_line.lstrip()
            if stripped.startswith("//"):
                continue
            m = CONN_RE.search(block_line)
            if m is None:
                continue
            ports[m.group(1)] = m.group(2)

        if ports:
            missing[module_name] = ports

    return missing


def infer_direction(port: str) -> str:
    if port in {"clock", "reset"}:
        return "input"
    if re.fullmatch(r"in\d+(?:_valid)?", port):
        return "input"
    if re.fullmatch(r"out\d+_ready", port):
        return "input"
    if re.fullmatch(r"in\d+_ready", port):
        return "output"
    if re.fullmatch(r"out\d+(?:_valid)?", port):
        return "output"
    raise SystemExit(f"unable to infer port direction for {port!r}")


def infer_width(signal: str, widths: dict[str, int]) -> int:
    signal = signal.strip()
    if signal in widths:
        return widths[signal]
    m = re.fullmatch(r"(\d+)'[bdhoBDHO][0-9a-fA-F_xXzZ]+", signal)
    if m is not None:
        return int(m.group(1))
    if signal in {"'0", "'1"}:
        return 1
    raise SystemExit(f"unable to infer width for signal {signal!r}")


def port_sort_key(name: str) -> tuple[int, str]:
    if name in {"clock", "reset"}:
        return (0, name)
    if name.startswith("in"):
        return (1, name)
    if name.startswith("out"):
        return (2, name)
    return (3, name)


def format_decl(direction: str, port: str, width: int) -> str:
    if width == 1:
        return f"  {direction} logic {port}"
    return f"  {direction} logic [{width - 1}:0] {port}"


def emit_blackboxes(
    main_sv: Path, widths: dict[str, int], instances: dict[str, dict[str, str]]
) -> str:
    if not instances:
        return ""

    chunks = [
        "// Auto-generated blackbox stubs for unresolved helper modules.",
        f"// Source: {main_sv}",
        "",
    ]

    for module_name in sorted(instances):
        ports = instances[module_name]
        ordered_ports = sorted(ports, key=port_sort_key)
        chunks.append("(* blackbox *)")
        chunks.append(f"module {module_name}(")
        for idx, port in enumerate(ordered_ports):
            direction = infer_direction(port)
            width = infer_width(ports[port], widths)
            trailer = "," if idx < len(ordered_ports) - 1 else ""
            chunks.append(f"{format_decl(direction, port, width)}{trailer}")
        chunks.append(");")
        chunks.append("endmodule")
        chunks.append("")

    return "\n".join(chunks)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources-f", type=Path, required=True)
    ap.add_argument("--main-sv", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    defined = read_defined_modules(args.sources_f)
    widths = read_signal_widths(args.main_sv)
    missing = read_missing_instances(args.main_sv, defined)
    text = emit_blackboxes(args.main_sv, widths, missing)
    args.out.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
