#!/usr/bin/env python3
"""Generate TinyStories selftest top wrapper from the current main.sv."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


LOAD_PORT_RE = re.compile(
    r"^(in\d+)_ld0_(addr|addr_valid|addr_ready|data|data_valid|data_ready)$"
)


@dataclass(frozen=True)
class Port:
    name: str
    direction: str
    decl: str
    bits: int | None


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def parse_decl_bits(decl: str) -> int | None:
    decl = decl.strip()
    if not decl:
        return 1
    if "struct" in decl or "union" in decl:
        return None
    ranges = re.findall(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]", decl)
    if not ranges:
        return 1
    bits = 1
    for msb_s, lsb_s in ranges:
        bits *= abs(int(msb_s) - int(lsb_s)) + 1
    return bits


def strip_line_comments(text: str) -> str:
    return re.sub(r"//.*", "", text)


def parse_main_ports(main_sv: Path) -> list[Port]:
    text = main_sv.read_text(encoding="utf-8")
    m = re.search(r"\bmodule\s+main\s*\((.*?)\);\s", text, flags=re.S)
    if m is None:
        die(f"unable to find module header in {main_sv}")
    header = strip_line_comments(m.group(1))
    raw_tokens = [t.strip() for t in header.replace("\n", " ").split(",") if t.strip()]

    ports: list[Port] = []
    current_direction: str | None = None
    current_decl: str = ""

    for token in raw_tokens:
        token = re.sub(r"\s+", " ", token).strip()
        direction: str | None = None
        rest = token
        md = re.match(r"^(input|output)\b(.*)$", rest)
        if md is not None:
            direction = md.group(1)
            rest = md.group(2).strip()

        mn = re.search(r"([A-Za-z_][A-Za-z0-9_$]*)\s*$", rest)
        if mn is None:
            die(f"unable to parse port name from token: {token!r}")
        name = mn.group(1)
        decl = rest[: mn.start(1)].strip()

        if direction is not None:
            current_direction = direction
            current_decl = decl
        else:
            if decl:
                current_decl = decl

        if current_direction is None:
            die(f"direction not known for token: {token!r}")

        ports.append(
            Port(
                name=name,
                direction=current_direction,
                decl=current_decl,
                bits=parse_decl_bits(current_decl),
            )
        )

    return ports


def port_sort_key(prefix: str) -> tuple[int, str]:
    m = re.fullmatch(r"in(\d+)", prefix)
    if m is None:
        return (10**9, prefix)
    return (int(m.group(1)), prefix)


def data_expr(prefix: str, data_bits: int, has_addr: bool, addr_bits: int) -> str:
    if not has_addr:
        if data_bits == 64:
            return "64'h0123_4567_89AB_CDEF"
        if data_bits == 32:
            return "32'h1357_9BDF"
        return "'0"
    addr_q = f"{prefix}_addr_q"
    if data_bits == addr_bits:
        return addr_q
    if data_bits > addr_bits:
        pad = data_bits - addr_bits
        return f"{{{{{pad}{{1'b0}}}}, {addr_q}}}"
    return f"{addr_q}[{data_bits - 1}:0]"


def choose_start_channel(inputs: dict[str, Port], outputs: dict[str, Port]) -> tuple[str, str]:
    candidates: list[tuple[int, str, str]] = []
    for name in inputs:
        if re.fullmatch(r"in\d+_valid", name) is None:
            continue
        base = name[: -len("_valid")]
        ready = f"{base}_ready"
        if ready in outputs:
            idx = int(base[2:])
            candidates.append((idx, name, ready))
    if not candidates:
        die("unable to detect start valid/ready channel")
    candidates.sort()
    _, valid, ready = candidates[-1]
    return valid, ready


def choose_done_channel(inputs: dict[str, Port], outputs: dict[str, Port]) -> tuple[str, str]:
    candidates: list[tuple[int, str, str]] = []
    for name in outputs:
        if re.fullmatch(r"out\d+_valid", name) is None:
            continue
        base = name[: -len("_valid")]
        ready = f"{base}_ready"
        if ready in inputs:
            idx = int(base[3:])
            candidates.append((idx, name, ready))
    if not candidates:
        die("unable to detect completion valid/ready channel")
    candidates.sort()
    _, valid, ready = candidates[0]
    return valid, ready


def choose_store_prefix(ports: list[Port]) -> str:
    prefixes = {
        m.group(1)
        for p in ports
        if (m := re.fullmatch(r"(in\d+)_st0(?:_done)?(?:_valid|_ready)?", p.name)) is not None
    }
    if not prefixes:
        die("unable to detect store channel prefix")
    return sorted(prefixes, key=port_sort_key)[0]


def generate_wrapper(ports: list[Port]) -> str:
    by_name = {p.name: p for p in ports}
    inputs = {p.name: p for p in ports if p.direction == "input"}
    outputs = {p.name: p for p in ports if p.direction == "output"}

    start_valid, start_ready = choose_start_channel(inputs, outputs)
    done_valid, done_ready = choose_done_channel(inputs, outputs)

    store_prefix = choose_store_prefix(ports)
    store_payload = f"{store_prefix}_st0"
    store_valid = f"{store_prefix}_st0_valid"
    store_ready = f"{store_prefix}_st0_ready"
    store_done_valid = f"{store_prefix}_st0_done_valid"
    store_done_ready = f"{store_prefix}_st0_done_ready"

    for req in [store_payload, store_valid, store_ready, store_done_valid, store_done_ready]:
        if req not in by_name:
            die(f"store signal missing from main.sv interface: {req}")

    load_signals: dict[str, dict[str, Port]] = {}
    for p in ports:
        m = LOAD_PORT_RE.fullmatch(p.name)
        if m is None:
            continue
        prefix, kind = m.group(1), m.group(2)
        load_signals.setdefault(prefix, {})[kind] = p

    load_prefixes: list[str] = []
    for prefix, sigs in load_signals.items():
        data = f"{prefix}_ld0_data"
        data_valid = f"{prefix}_ld0_data_valid"
        addr_ready = f"{prefix}_ld0_addr_ready"
        addr_valid = f"{prefix}_ld0_addr_valid"
        if data in inputs and data_valid in inputs and addr_ready in inputs and addr_valid in outputs:
            load_prefixes.append(prefix)
    load_prefixes.sort(key=port_sort_key)

    lines: list[str] = []
    lines.append("// Auto-generated by scripts/pipeline/gen_tiny_stories_selftest_top.py.")
    lines.append("module tiny_stories_selftest_top(")
    lines.append("  input logic SYS_CLK,")
    lines.append("  input logic SYS_RSTN,")
    lines.append("  output logic [2:0] led_3bits_tri_o")
    lines.append(");")
    lines.append("")
    lines.append("  localparam logic [31:0] TIMEOUT_CYCLES = 32'd50000000;")
    lines.append("  localparam logic [7:0] BOOT_RESET_CYCLES = 8'd16;")
    lines.append("")
    lines.append("  logic reset;")
    lines.append("  logic [7:0] boot_count;")
    lines.append("  logic [31:0] cycle_count;")
    lines.append("  logic [25:0] blink_count;")
    lines.append("  logic pass_latched;")
    lines.append("  logic fail_latched;")
    lines.append("")

    for p in ports:
        if p.name in ("clock", "reset"):
            continue
        if not p.decl:
            lines.append(f"  logic {p.name};")
        elif p.decl.startswith("["):
            lines.append(f"  logic {p.decl} {p.name};")
        else:
            lines.append(f"  {p.decl} {p.name};")
    lines.append("")

    for prefix in load_prefixes:
        lines.append(f"  logic {prefix}_pending;")
        addr_name = f"{prefix}_ld0_addr"
        if addr_name in outputs:
            addr_decl = outputs[addr_name].decl
            if not addr_decl:
                lines.append(f"  logic {prefix}_addr_q;")
            elif addr_decl.startswith("["):
                lines.append(f"  logic {addr_decl} {prefix}_addr_q;")
            else:
                lines.append(f"  {addr_decl} {prefix}_addr_q;")
    lines.append("")
    lines.append("  logic store_done_pending;")
    lines.append("")

    lines.append("  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin")
    lines.append("    if (!SYS_RSTN) begin")
    lines.append("      boot_count <= 8'd0;")
    lines.append("    end else if (boot_count <= BOOT_RESET_CYCLES) begin")
    lines.append("      boot_count <= boot_count + 8'd1;")
    lines.append("    end")
    lines.append("  end")
    lines.append("  assign reset = (boot_count <= BOOT_RESET_CYCLES);")
    lines.append("")

    lines.append("  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin")
    lines.append("    if (!SYS_RSTN) begin")
    lines.append(f"      {start_valid} <= 1'b1;")
    lines.append("    end else if (reset) begin")
    lines.append(f"      {start_valid} <= 1'b1;")
    lines.append(f"    end else if ({start_valid} && {start_ready}) begin")
    lines.append(f"      {start_valid} <= 1'b0;")
    lines.append("    end")
    lines.append("  end")
    lines.append("")

    lines.append("  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin")
    lines.append("    if (!SYS_RSTN) begin")
    for prefix in load_prefixes:
        lines.append(f"      {prefix}_pending <= 1'b0;")
        addr_name = f"{prefix}_ld0_addr"
        if addr_name in outputs:
            lines.append(f"      {prefix}_addr_q <= '0;")
    lines.append("    end else if (reset) begin")
    for prefix in load_prefixes:
        lines.append(f"      {prefix}_pending <= 1'b0;")
        addr_name = f"{prefix}_ld0_addr"
        if addr_name in outputs:
            lines.append(f"      {prefix}_addr_q <= '0;")
    lines.append("    end else begin")
    for prefix in load_prefixes:
        addr_valid = f"{prefix}_ld0_addr_valid"
        addr_ready = f"{prefix}_ld0_addr_ready"
        data_valid = f"{prefix}_ld0_data_valid"
        data_ready = f"{prefix}_ld0_data_ready"
        lines.append(
            f"      if (!{prefix}_pending && {addr_valid} && {addr_ready}) begin"
        )
        lines.append(f"        {prefix}_pending <= 1'b1;")
        addr_name = f"{prefix}_ld0_addr"
        if addr_name in outputs:
            lines.append(f"        {prefix}_addr_q <= {addr_name};")
        lines.append(
            f"      end else if ({prefix}_pending && {data_valid} && {data_ready}) begin"
        )
        lines.append(f"        {prefix}_pending <= 1'b0;")
        lines.append("      end")
    lines.append("    end")
    lines.append("  end")
    lines.append("")

    driven_inputs: set[str] = {start_valid}
    driven_inputs.add(done_ready)

    for prefix in load_prefixes:
        addr_ready = f"{prefix}_ld0_addr_ready"
        data = f"{prefix}_ld0_data"
        data_valid = f"{prefix}_ld0_data_valid"
        driven_inputs.update({addr_ready, data, data_valid})

        data_bits = inputs[data].bits
        if data_bits is None:
            die(f"unable to derive bit width for {data}")
        addr_name = f"{prefix}_ld0_addr"
        has_addr = addr_name in outputs
        addr_bits = outputs[addr_name].bits if has_addr else 0
        if has_addr and addr_bits is None:
            die(f"unable to derive bit width for {addr_name}")
        expr = data_expr(prefix, data_bits, has_addr, addr_bits)

        lines.append(f"  assign {addr_ready} = ~{prefix}_pending;")
        lines.append(f"  assign {data_valid} = {prefix}_pending;")
        lines.append(f"  assign {data} = {expr};")
        lines.append("")

    lines.append(f"  assign {done_ready} = 1'b1;")
    lines.append("")

    lines.append("  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin")
    lines.append("    if (!SYS_RSTN) begin")
    lines.append("      store_done_pending <= 1'b0;")
    lines.append("    end else if (reset) begin")
    lines.append("      store_done_pending <= 1'b0;")
    lines.append("    end else begin")
    lines.append(
        f"      if (!store_done_pending && {store_valid} && {store_ready}) begin"
    )
    lines.append("        store_done_pending <= 1'b1;")
    lines.append(f"      end else if (store_done_pending && {store_done_ready}) begin")
    lines.append("        store_done_pending <= 1'b0;")
    lines.append("      end")
    lines.append("    end")
    lines.append("  end")
    lines.append("")
    lines.append(f"  assign {store_ready} = ~store_done_pending;")
    lines.append(f"  assign {store_done_valid} = store_done_pending;")
    lines.append("")
    driven_inputs.update({store_ready, store_done_valid})

    for name in sorted(inputs):
        if name in ("clock", "reset"):
            continue
        if name in driven_inputs:
            continue
        lines.append(f"  assign {name} = '0;")
    if len(inputs) > len(driven_inputs):
        lines.append("")

    lines.append("  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin")
    lines.append("    if (!SYS_RSTN) begin")
    lines.append("      pass_latched <= 1'b0;")
    lines.append("      fail_latched <= 1'b0;")
    lines.append("      cycle_count <= 32'd0;")
    lines.append("      blink_count <= 26'd0;")
    lines.append("    end else begin")
    lines.append("      blink_count <= blink_count + 26'd1;")
    lines.append("      if (reset) begin")
    lines.append("        pass_latched <= 1'b0;")
    lines.append("        fail_latched <= 1'b0;")
    lines.append("        cycle_count <= 32'd0;")
    lines.append("      end else if (!(pass_latched || fail_latched)) begin")
    lines.append(f"        if ({done_valid}) begin")
    lines.append("          pass_latched <= 1'b1;")
    lines.append("        end else if (cycle_count >= TIMEOUT_CYCLES) begin")
    lines.append("          fail_latched <= 1'b1;")
    lines.append("        end else begin")
    lines.append("          cycle_count <= cycle_count + 32'd1;")
    lines.append("        end")
    lines.append("      end")
    lines.append("    end")
    lines.append("  end")
    lines.append("")
    lines.append("  assign led_3bits_tri_o[0] = blink_count[25];")
    lines.append("  assign led_3bits_tri_o[1] = pass_latched;")
    lines.append("  assign led_3bits_tri_o[2] = fail_latched;")
    lines.append("")

    lines.append("  main u_dut(")
    for idx, p in enumerate(ports):
        if p.name == "clock":
            conn = "SYS_CLK"
        elif p.name == "reset":
            conn = "reset"
        else:
            conn = p.name
        trailer = "," if idx < len(ports) - 1 else ""
        lines.append(f"    .{p.name}({conn}){trailer}")
    lines.append("  );")
    lines.append("endmodule")
    lines.append("")

    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--main-sv", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    ports = parse_main_ports(args.main_sv)
    wrapper = generate_wrapper(ports)
    args.out.write_text(wrapper, encoding="utf-8")


if __name__ == "__main__":
    main()
