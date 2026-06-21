#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


OP_RE = re.compile(r"^\s*(?:%[\w\d_:.#-]+(?:\s*,\s*%[\w\d_:.#-]+)*\s*=\s*)?([A-Za-z_][\w.]+)\b")
FP_EXTERN_RE = re.compile(r"hw\.module\.extern\s+@([A-Za-z_][A-Za-z0-9_]*)")
HW_EXTERNS_PATH = Path("direct-hw-externs.txt")
HW_EXTERNS_VERILOG_PATH = Path("direct-hw-externs-verilog.sv")
FP_PRIM_FILE_NAME = "zz_circt_fp_primitives.sv"
RETURN_RE = re.compile(r"->\s*tensor<([^>]+)>")
TENSOR_RE = re.compile(r"tensor<([^>]+)>")
ELEMENT_RE = re.compile(r"x([if])(\d+)$|^([if])(\d+)$")

SUPPORTED_FUNCTIONAL_OPS: set[str] = set()
IGNORED_OPS = {
    "builtin.module",
    "func.func",
    "func.return",
    "module",
}
OP_PREFIXES = ("%", "arith.", "cf.", "func.", "linalg.", "math.", "tensor.")
STATUS_SMOKE_FALLBACK = "smoke_fallback"
STATUS_HW_LOWERED = "hw_lowered"
STATUS_UNSUPPORTED_MLIR_FORMAT = "unsupported_mlir_format"
VERILATOR_EXPECT_PATTERNS = (
    "expected_output_hex",
    "expected_output",
    "output_hex",
    "output",
)


def get_sv_export_mode() -> str:
    mode = os.environ.get("CIRCT_SV_EXPORT_MODE", "single").strip().lower()
    return mode if mode in {"single", "split"} else "single"


def get_sv_export_args() -> list[str]:
    args: list[str] = []
    strip_suffix = os.environ.get("CIRCT_STRIP_DEBUGINFO_SUFFIX", "").strip()
    if strip_suffix:
        args.append(f"--strip-debuginfo-with-pred=drop-suffix={strip_suffix}")
    return args


def write_sv_sources_file(sv_dir: Path, sources: Path, include_fp_primitives: bool) -> None:
    source_files = sorted(sv_dir.glob("*.sv"))
    lines = [str(path) for path in source_files if path.is_file()]

    if include_fp_primitives:
        fp_prim_path = sv_dir / FP_PRIM_FILE_NAME
        if fp_prim_path.exists() and str(fp_prim_path) not in lines:
            lines.append(str(fp_prim_path))

    sources.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def parse_tensor_type(type_text: str) -> dict[str, object]:
    parts = type_text.split("x")
    element = parts[-1]
    dims = [int(part) for part in parts[:-1] if part != "?"]
    match = ELEMENT_RE.search(type_text)
    if match is None:
        raise ValueError(f"unsupported tensor element type in tensor<{type_text}>")
    kind = match.group(1) or match.group(3)
    bits = int(match.group(2) or match.group(4))
    return {
        "dims": dims,
        "element": element,
        "element_kind": kind,
        "element_bits": bits,
        "element_count": math.prod(dims) if dims else 1,
    }


def find_output_tensor(mlir_text: str) -> dict[str, object] | None:
    main_match = re.search(r"func\.func\s+@main\b.*", mlir_text)
    if main_match is not None:
        line = main_match.group(0)
        return_match = RETURN_RE.search(line)
        if return_match is not None:
            return parse_tensor_type(return_match.group(1))

    matches = list(TENSOR_RE.finditer(mlir_text))
    if not matches:
        return None
    return parse_tensor_type(matches[-1].group(1))


def normalize_hex_string(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, int):
        if value < 0:
            return None
        return format(value, "x")
    if isinstance(value, str):
        text = value.strip().lower().replace("_", "")
        if text.startswith("0x"):
            text = text[2:]
        if text == "":
            return None
        if all(ch in "0123456789abcdef" for ch in text):
            return text
        return None
    return None


def extract_expected_hex(payload: object) -> str | None:
    if not isinstance(payload, dict):
        return None
    for key in VERILATOR_EXPECT_PATTERNS:
        if key not in payload:
            continue
        hex_value = normalize_hex_string(payload[key])
        if hex_value is not None:
            return hex_value
    nested = payload.get("fixture") if "fixture" in payload else None
    if isinstance(nested, dict):
        for key in VERILATOR_EXPECT_PATTERNS:
            if key not in nested:
                continue
            hex_value = normalize_hex_string(nested[key])
            if hex_value is not None:
                return hex_value
    return None


def write_file(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


SAMPLE_LINES_PER_OP = 5


def load_text_or_json(path: Path | None) -> object | None:
    if path is None:
        return None
    if not path.exists():
        return None
    payload = path.read_text(encoding="utf-8")
    stripped = payload.strip()
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            return json.loads(stripped)
        except json.JSONDecodeError:
            return {"raw": payload}
    return {"raw": payload}


def load_lines(path: Path | None) -> list[str]:
    if path is None or not path.exists():
        return []
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def collect_ops(
    mlir_text: str,
) -> tuple[Counter[str], dict[str, list[str]], dict[str, int]]:
    ops: Counter[str] = Counter()
    samples: dict[str, list[str]] = defaultdict(list)
    first_line: dict[str, int] = {}
    for lineno, line in enumerate(mlir_text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if stripped.startswith(("#", "}", "loc(", "dense_resource<")):
            continue
        if not stripped.startswith(OP_PREFIXES):
            continue
        match = OP_RE.match(line)
        if match is None:
            continue
        op = match.group(1)
        if "." not in op:
            continue
        if op in IGNORED_OPS:
            continue
        ops[op] += 1
        if op not in first_line:
            first_line[op] = lineno
        if len(samples[op]) < SAMPLE_LINES_PER_OP:
            samples[op].append(stripped)
    return ops, samples, first_line


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def normalize_path_argument(path_like: Path | str | None) -> Path | None:
    if path_like is None:
        return None
    text = str(path_like).strip().strip()
    # Nix-shell escaping can pass shell-quoted paths (eg. '...'). Strip
    # wrapping single/double quotes so Path can resolve the real file.
    if len(text) >= 2 and (
        (text[0] == "'" and text[-1] == "'")
        or (text[0] == '"' and text[-1] == '"')
    ):
        text = text[1:-1].strip()
    if text == "":
        return None
    return Path(text)


def is_hw_mlir(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    return "hw.module" in text and "hw." in text


def is_linalg_mlir(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    return "linalg." in text and "func.func @main" in text


def extract_cutpoint_snippet(
    mlir_text: str, cutpoint: str, context_lines: int = 12
) -> dict[str, object] | None:
    lines = mlir_text.splitlines()
    matches = []
    for index, line in enumerate(lines):
        if cutpoint in line:
            matches.append(index)
    if not matches:
        return None
    line = matches[0]
    start = max(0, line - context_lines)
    end = min(len(lines), line + context_lines + 1)
    snippet = "\n".join(lines[start:end])
    return {
        "cutpoint": cutpoint,
        "line": line + 1,
        "context_line_start": start + 1,
        "context_line_end": end,
        "snippet": snippet,
    }


def smoke_hw_mlir(output_bits: int) -> str:
    return "\n".join(
        [
            "module {",
            f"  hw.module @main(out out : i{output_bits}) {{",
            f"    %c0_i{output_bits} = hw.constant 0 : i{output_bits}",
            f"    hw.output %c0_i{output_bits} : i{output_bits}",
            "  }",
            "}",
            "",
        ]
    )


def run_circt(circt_opt: Path, args: list[str], stdout: Path | None = None) -> None:
    command = [str(circt_opt), *args]
    if stdout is None:
        subprocess.run(command, check=True)
        return
    with stdout.open("w", encoding="utf-8") as handle:
        subprocess.run(command, check=True, stdout=handle)


def emit_smoke_sv(out_dir: Path, circt_opt: Path, output_tensor: dict[str, object] | None) -> None:
    element_count = int(output_tensor["element_count"]) if output_tensor is not None else 1
    element_bits = int(output_tensor["element_bits"]) if output_tensor is not None else 8
    output_bits = max(1, element_count * element_bits)

    direct_hw = out_dir / "direct-hw.mlir"
    sv_mlir_dir = out_dir / "direct-sv-mlir"
    sv_dir = out_dir / "sv"
    sv_mlir = sv_mlir_dir / "model.sv.mlir"
    sources = out_dir / "sources.f"

    direct_hw.write_text(smoke_hw_mlir(output_bits), encoding="utf-8")
    sv_mlir_dir.mkdir(parents=True, exist_ok=True)
    sv_dir.mkdir(parents=True, exist_ok=True)
    run_circt(circt_opt, [str(direct_hw), "-lower-hw-to-sv", "-o", str(sv_mlir)])
    export_flags = get_sv_export_args()
    if get_sv_export_mode() == "split":
        run_circt(
            circt_opt,
            [
                str(sv_mlir),
                "--export-split-verilog",
                *export_flags,
                f"dir-name={sv_dir}",
                "-o",
                "/dev/null",
            ],
        )
        write_sv_sources_file(sv_dir, sources, include_fp_primitives=False)
    else:
        main_sv = sv_dir / "main.sv"
        run_circt(
            circt_opt,
            [str(sv_mlir), *export_flags, "--export-verilog", "-o", "/dev/null"],
            stdout=main_sv,
        )
        write_sv_sources_file(sv_dir, sources, include_fp_primitives=False)


def emit_hw_sv(out_dir: Path, circt_opt: Path, input_hw_mlir: Path) -> None:
    direct_hw = input_hw_mlir
    sv_mlir_dir = out_dir / "direct-sv-mlir"
    sv_dir = out_dir / "sv"
    sv_mlir = sv_mlir_dir / "model.sv.mlir"
    lowered_seq_mlir = out_dir / "direct-seq-lowered.sv.mlir"
    main_sv = sv_dir / "main.sv"
    sources = out_dir / "sources.f"

    sv_mlir_dir.mkdir(parents=True, exist_ok=True)
    sv_dir.mkdir(parents=True, exist_ok=True)

    # Lower seq dialect before export. This is required because export-verilog
    # does not support seq ops directly, and the linalg/hw pipelines can still
    # retain seq.hlmem/seq.compreg in representative slices.
    run_circt(
        circt_opt,
        [
            str(direct_hw),
            "-lower-seq-hlmem",
            "-lower-seq-fifo",
            "-lower-seq-shiftreg",
            "-canonicalize",
            "-cse",
            "-o",
            str(lowered_seq_mlir),
        ],
    )
    export_flags = get_sv_export_args()
    run_circt(
        circt_opt,
        [
            str(lowered_seq_mlir),
            "-lower-seq-to-sv",
            "-lower-hw-to-sv",
            "-canonicalize",
            "-cse",
            "-o",
            str(sv_mlir),
        ],
    )
    if get_sv_export_mode() == "split":
        run_circt(
            circt_opt,
            [
                str(sv_mlir),
                "--export-split-verilog",
                *export_flags,
                f"dir-name={sv_dir}",
                "-o",
                "/dev/null",
            ],
        )
    else:
        run_circt(
            circt_opt,
            [str(sv_mlir), *export_flags, "--export-verilog", "-o", "/dev/null"],
            stdout=main_sv,
        )

    mlir_text = sv_mlir.read_text(encoding="utf-8", errors="ignore")
    hw_externs = sorted(set(FP_EXTERN_RE.findall(mlir_text)))
    hw_externs_path = out_dir / HW_EXTERNS_PATH
    hw_externs_path.write_text("\n".join(hw_externs) + ("\n" if hw_externs else ""), encoding="utf-8")

    sources_f = []
    fp_prim_source = os.environ.get("FP_PRIMS_SV")
    if hw_externs:
        if fp_prim_source is None:
            # Keep the emitted SV for downstream diagnosis; lint should include this
            # metadata in its manifest as a potential failure mode.
            pass
        else:
            fp_prim_sv = Path(fp_prim_source)
            if fp_prim_sv.exists():
                fp_copy = sv_dir / FP_PRIM_FILE_NAME
                shutil.copy2(fp_prim_sv, fp_copy)
    write_sv_sources_file(sv_dir, sources, include_fp_primitives=True)


def emit_sv_from_mlir(
    out_dir: Path, circt_opt: Path, input_mlir: Path,
    output_tensor: dict[str, object] | None
) -> str:
    if is_hw_mlir(input_mlir):
        emit_hw_sv(out_dir, circt_opt, input_mlir)
        return STATUS_HW_LOWERED

    if is_linalg_mlir(input_mlir):
        return STATUS_UNSUPPORTED_MLIR_FORMAT

    # Placeholder path for now keeps the pipeline usable while the
    # linalg-to-hw focused frontend is implemented.
    emit_smoke_sv(out_dir, circt_opt, output_tensor)
    return STATUS_SMOKE_FALLBACK


def emit_functional_tb(tb_sv: Path, expected_hex: str, width: int) -> str:
    expected = expected_hex.lower().rjust((width + 3) // 4, "0")
    expected = expected[-((width + 3) // 4) :]
    tb = "\n".join(
        [
            "`timescale 1ns/1ps",
            "module tb;",
            f"  logic [{width - 1}:0] out;",
            f"  main u_main(.out(out));",
            "  initial begin",
            "    #1;",
            "    if (out === " + f"{width}'h{expected}" + ") begin",
            "      $display(\"SV_OUTPUT_OK:0x%0h\", out);",
            "      $finish;",
            "    end else begin",
            f"      $display(\"SV_OUTPUT_MISMATCH: expected 0x{expected} got %0h\", out);",
            "      $fatal(1);",
            "    end",
            "  end",
            "endmodule",
            "",
        ]
    )
    write_file(tb_sv, tb)
    return tb


def run_verilator_compare(sv_dir: Path, tb_sv: Path, out_dir: Path) -> dict[str, object]:
    build_dir = out_dir / "sim_obj"
    build_dir.mkdir(parents=True, exist_ok=True)
    binary = build_dir / "sim_main"
    source_files = [str(tb_sv)] + [str(path) for path in sv_dir.glob("*.sv")]
    command = [
        "verilator",
        "--binary",
        "--timing",
        "--language",
        "1800-2017",
        "-Wno-fatal",
        "-Mdir",
        str(build_dir),
        "-o",
        "sim_main",
        *source_files,
    ]
    try:
        compile_proc = subprocess.run(
            command, check=False, text=True, capture_output=True
        )
    except FileNotFoundError:
        return {
            "status": "verilator_not_available",
            "verilator_compile_exit": -1,
            "verilator_compile_stdout": "",
            "verilator_compile_stderr": "verilator executable not found",
        }
    compile_result = {
        "verilator_compile_exit": compile_proc.returncode,
        "verilator_compile_stdout": compile_proc.stdout,
        "verilator_compile_stderr": compile_proc.stderr,
    }
    if compile_proc.returncode != 0:
        return {"status": "verilator_compile_failed", **compile_result}

    try:
        run_proc = subprocess.run(
            [str(binary)], check=False, text=True, capture_output=True
        )
    except FileNotFoundError:
        return {
            **compile_result,
            "status": "verilator_binary_missing",
            "verilator_run_exit": -1,
            "verilator_run_stdout": "",
            "verilator_run_stderr": "Verilator binary not produced or not found",
        }
    run_result = {
        "verilator_run_exit": run_proc.returncode,
        "verilator_run_stdout": run_proc.stdout,
        "verilator_run_stderr": run_proc.stderr,
    }
    return {"status": "verilator_pass" if run_proc.returncode == 0 else "verilator_fail", **compile_result, **run_result}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fast Task 6 direct-lowering loop for Linalg MLIR."
    )
    parser.add_argument("--input-linalg", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument(
        "--mode",
        choices=("fail-fast", "sv-smoke", "functional"),
        default="fail-fast",
    )
    parser.add_argument("--cutpoint", default=None)
    parser.add_argument("--fixture-json", type=Path)
    parser.add_argument("--circt-opt", type=Path)
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Write diagnostics and exit 0 instead of failing on unsupported ops.",
    )
    args = parser.parse_args()

    input_linalg = args.input_linalg
    normalized_cutpoint = normalize_path_argument(args.cutpoint)
    if normalized_cutpoint is not None and normalized_cutpoint.name.endswith(".mlir"):
        input_linalg = normalized_cutpoint
        args.out_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(input_linalg, args.out_dir / "cutpoint-input.mlir")

    mlir_text = input_linalg.read_text(encoding="utf-8")
    ops, unsupported_op_samples, first_op_line = collect_ops(mlir_text)
    output_tensor = find_output_tensor(mlir_text)
    cutpoint_payload = (
        load_text_or_json(normalized_cutpoint) if normalized_cutpoint is not None else None
    )
    if args.cutpoint is None:
        cutpoint_payload = None
    normalized_cutpoint_value = (
        str(normalized_cutpoint) if normalized_cutpoint is not None else args.cutpoint
    )
    cutpoint_snippet = (
        extract_cutpoint_snippet(mlir_text, cutpoint_payload.get("cutpoint", args.cutpoint))
        if normalized_cutpoint is not None
        and normalized_cutpoint_value is not None
        and not str(normalized_cutpoint).endswith(".mlir")
        else None
    ) if isinstance(cutpoint_payload, dict) else (
        extract_cutpoint_snippet(mlir_text, normalized_cutpoint_value)
        if normalized_cutpoint is not None
        and normalized_cutpoint_value is not None
        and not str(normalized_cutpoint).endswith(".mlir")
        else None
    )
    fixture_payload = load_text_or_json(args.fixture_json)
    unsupported = {
        op: count
        for op, count in sorted(ops.items())
        if op not in SUPPORTED_FUNCTIONAL_OPS
    }
    first_blocker = next(iter(unsupported), None) if unsupported else None

    args.out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "input_linalg": str(args.input_linalg),
        "effective_input_linalg": str(input_linalg),
        "mode": args.mode,
        "cutpoint": str(normalized_cutpoint)
        if normalized_cutpoint is not None
        else args.cutpoint,
        "cutpoint_payload": cutpoint_payload,
        "cutpoint_snippet": cutpoint_snippet,
        "fixture_json": str(args.fixture_json)
        if args.fixture_json is not None
        else None,
        "fixture_payload": fixture_payload,
        "output_tensor": output_tensor,
        "op_counts": dict(sorted(ops.items())),
        "unsupported_op_counts": unsupported,
        "unsupported_op_samples": {
            op: lines for op, lines in unsupported_op_samples.items() if op in unsupported
        },
        "sv_hw_externs": [],
        "sv_fp_primitive_file": None,
        "first_unsupported_op": first_blocker,
        "first_unsupported_line": first_op_line.get(first_blocker)
        if first_blocker is not None
        else None,
        "status": "unknown",
        "functional_equivalence": "not_claimed",
    }

    if args.cutpoint is not None and normalized_cutpoint is not None:
        if normalized_cutpoint.name.endswith(".mlir"):
            cutpoint_payload = {
                "kind": "mlir",
                "path": str(normalized_cutpoint),
            }
        cutpoint_out = args.out_dir / "cutpoint.json"
        cutpoint_out.write_text(
            json.dumps(cutpoint_payload, indent=2, sort_keys=True) + "\n"
            if isinstance(cutpoint_payload, (dict, list))
            else json.dumps({"value": cutpoint_payload}, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if not str(normalized_cutpoint).endswith(".mlir"):
            snippet = extract_cutpoint_snippet(mlir_text, normalized_cutpoint_value)
            if snippet is not None:
                write_json(args.out_dir / "cutpoint-snippet.json", snippet)

    if args.fixture_json is not None and args.fixture_json.exists():
        shutil.copy2(args.fixture_json, args.out_dir / "fixture.json")

    if args.mode == "fail-fast" and unsupported:
        manifest["status"] = "unsupported_ops"
        write_json(args.out_dir / "direct-lower-manifest.json", manifest)
        if args.report_only:
            return
        first_op = next(iter(unsupported))
        raise SystemExit(
            f"unsupported op in {args.mode} mode: {first_op} "
            f"({unsupported[first_op]} occurrence(s)); see "
            f"{args.out_dir / 'direct-lower-manifest.json'}"
        )

    if args.mode == "functional":
        if args.circt_opt is None:
            manifest["status"] = "missing_circt_opt"
            write_json(args.out_dir / "direct-lower-manifest.json", manifest)
            raise SystemExit("--mode functional requires --circt-opt")
        manifest["functional_equivalence"] = "not_claimed"
        emit_status = emit_sv_from_mlir(args.out_dir, args.circt_opt, input_linalg, output_tensor)
        manifest["sv_input_status"] = emit_status
        manifest["sv_hw_externs"] = load_lines(args.out_dir / HW_EXTERNS_PATH)
        fp_prim_path = args.out_dir / "sv" / FP_PRIM_FILE_NAME
        manifest["sv_fp_primitive_file"] = str(fp_prim_path) if fp_prim_path.exists() else None
        if emit_status == STATUS_UNSUPPORTED_MLIR_FORMAT:
            manifest["status"] = "functional_not_supported_for_current_cutpoint"
            manifest["functional_compare"] = {
                "status": "not_compared_missing_hw_cutpoint",
            }
            write_json(args.out_dir / "direct-lower-manifest.json", manifest)
            return
        manifest["status"] = "smoke_emitted"
        expected_hex = extract_expected_hex(fixture_payload) or ""
        if expected_hex:
            if emit_status == STATUS_SMOKE_FALLBACK:
                manifest["functional_compare"] = {
                    "status": "not_compared_smoke_fallback_no_hw_cutpoint"
                }
                manifest["status"] = "functional_not_compared_smoke_fallback"
                write_json(args.out_dir / "direct-lower-manifest.json", manifest)
                return
            output_bits = (
                max(1, int(output_tensor["element_count"]) * int(output_tensor["element_bits"]))
                if output_tensor is not None
                else 1
            )
            tb_sv = args.out_dir / "direct-functional-tb.sv"
            emit_functional_tb(tb_sv, expected_hex, output_bits)
            compare = run_verilator_compare(args.out_dir / "sv", tb_sv, args.out_dir)
            manifest["functional_compare"] = compare
            if compare.get("status") == "verilator_pass":
                manifest["functional_equivalence"] = "fixture_match_pending_verification"
            manifest["status"] = compare["status"]
        else:
            manifest["functional_compare"] = {"status": "not_compared_no_expected_fixture"}
            manifest["status"] = "functional_not_compared_missing_fixture"
        write_json(args.out_dir / "direct-lower-manifest.json", manifest)
        return

    if args.mode == "sv-smoke":
        if args.circt_opt is None:
            manifest["status"] = "missing_circt_opt"
            write_json(args.out_dir / "direct-lower-manifest.json", manifest)
            raise SystemExit("--mode sv-smoke requires --circt-opt")
        emit_status = emit_sv_from_mlir(
            args.out_dir, args.circt_opt, input_linalg, output_tensor
        )
        manifest["sv_input_status"] = emit_status
        manifest["sv_hw_externs"] = load_lines(args.out_dir / HW_EXTERNS_PATH)
        fp_prim_path = args.out_dir / "sv" / FP_PRIM_FILE_NAME
        manifest["sv_fp_primitive_file"] = str(fp_prim_path) if fp_prim_path.exists() else None
        if emit_status == STATUS_HW_LOWERED:
            manifest["status"] = "sv_smoke_emitted_hw"
        elif emit_status == STATUS_SMOKE_FALLBACK:
            manifest["status"] = "sv_smoke_emitted_fallback"
        else:
            manifest["status"] = "sv_smoke_not_supported_format"
        manifest["functional_equivalence"] = "not_claimed"
        write_json(args.out_dir / "direct-lower-manifest.json", manifest)
        return

    manifest["status"] = "functional_lowering_ready"
    write_json(args.out_dir / "direct-lower-manifest.json", manifest)


if __name__ == "__main__":
    main()
