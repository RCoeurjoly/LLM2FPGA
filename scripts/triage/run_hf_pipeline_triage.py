#!/usr/bin/env python3
"""Run stage-by-stage pipeline triage for a list of Hugging Face models."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


STAGES = [
    "torch_export",
    "linalg",
    "cf",
    "cf_stats",
    "handshake",
    "hs_ext",
    "hw0",
    "hw",
    "hw_clean",
    "fp_stub_gen",
    "sv",
    "fp_coverage",
    "il",
    "yosys_stat",
]

TIME_MARKER = "__TRIAGE_TIME__"
FAILURE_TOKENS = (
    "error",
    "exception",
    "traceback",
    "failed",
    "segmentation fault",
    "assert",
    "not implemented",
)


@dataclass
class ModelSpec:
    index: int
    model_id: str
    revision: str
    raw: dict[str, str]


@dataclass
class CommandResult:
    status: str
    return_code: int | None
    wall_time_sec: float
    max_rss_kib: int | None
    signature: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--models",
        required=True,
        help="Model list file (TSV/CSV with model_id,revision or plain text)",
    )
    parser.add_argument(
        "--out",
        required=True,
        help="Output directory for triage artifacts",
    )
    parser.add_argument(
        "--max-models",
        type=int,
        default=0,
        help="Max models to process (0 means all)",
    )
    parser.add_argument(
        "--start-index",
        type=int,
        default=1,
        help="1-based model start index within the list",
    )
    parser.add_argument(
        "--stop-stage",
        choices=STAGES,
        default="handshake",
        help="Last stage to run for each model",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=1800,
        help="Per-stage timeout in seconds",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1,
        help="Batch size used during torch export",
    )
    parser.add_argument(
        "--seq-len",
        type=int,
        default=1,
        help="Sequence length used during torch export",
    )
    parser.add_argument(
        "--dtype",
        choices=("float32", "float16", "bfloat16"),
        default="float32",
        help="Model dtype used during torch export",
    )
    parser.add_argument(
        "--trust-remote-code",
        action="store_true",
        help="Enable trust_remote_code during torch export",
    )
    parser.add_argument(
        "--local-files-only",
        action="store_true",
        help="Disable network use during torch export",
    )
    parser.add_argument(
        "--attn-implementation",
        default="eager",
        help='from_pretrained attn_implementation (use "auto" to skip)',
    )
    parser.add_argument(
        "--strict-export",
        action="store_true",
        help="Use strict=True for torch.export.export",
    )
    parser.add_argument(
        "--linalg-lowering",
        choices=("loops", "affine"),
        default="loops",
        help="Pipeline linalg lowering mode",
    )
    parser.add_argument(
        "--handshake-insert-buffers",
        choices=("1", "0"),
        default="1",
        help="Set HANDSHAKE_INSERT_BUFFERS for pipeline scripts",
    )
    parser.add_argument(
        "--yosys-light-mode",
        action="store_true",
        help="Set YOSYS_LIGHT_MODE=1 in sv_to_il/stat steps",
    )
    parser.add_argument(
        "--skip-fp-coverage",
        action="store_true",
        help="Skip fp primitive coverage stage",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        default=True,
        help="Skip models already present in summary.jsonl",
    )
    parser.add_argument(
        "--no-resume",
        action="store_false",
        dest="resume",
        help="Do not skip previously processed models",
    )
    parser.add_argument(
        "--cache-dir",
        help="HF cache directory (defaults to <out>/hf-cache)",
    )
    parser.add_argument(
        "--torch-mlir-opt",
        help="Path override for torch-mlir-opt",
    )
    parser.add_argument(
        "--mlir-opt",
        help="Path override for mlir-opt",
    )
    parser.add_argument(
        "--circt-opt",
        help="Path override for circt-opt",
    )
    parser.add_argument(
        "--yosys",
        help="Path override for yosys",
    )
    parser.add_argument(
        "--yosys-slang-so",
        help="Path override for yosys slang plugin .so",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print plan and exit without running stages",
    )
    return parser.parse_args()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_models(path: Path) -> list[ModelSpec]:
    lines = path.read_text(encoding="utf-8").splitlines()
    filtered = [ln for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]
    if not filtered:
        return []

    def from_plain() -> list[ModelSpec]:
        models: list[ModelSpec] = []
        for idx, line in enumerate(filtered, start=1):
            parts = line.split()
            model_id = parts[0]
            revision = parts[1] if len(parts) > 1 else "main"
            models.append(
                ModelSpec(
                    index=idx,
                    model_id=model_id,
                    revision=revision,
                    raw={},
                )
            )
        return models

    first = filtered[0]
    delimiter = "\t" if "\t" in first else ("," if "," in first else "")
    if not delimiter:
        return from_plain()

    header_parts = [p.strip() for p in first.split(delimiter)]
    if "model_id" not in header_parts:
        return from_plain()

    reader = csv.DictReader(filtered, delimiter=delimiter)
    models = []
    for idx, row in enumerate(reader, start=1):
        model_id = (row.get("model_id") or "").strip()
        if not model_id:
            continue
        revision = (row.get("revision") or "main").strip() or "main"
        models.append(
            ModelSpec(
                index=idx,
                model_id=model_id,
                revision=revision,
                raw={k: (v or "") for k, v in row.items()},
            )
        )
    return models


def sanitize_model_id(model_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", model_id).strip("_")


def tail_lines(path: Path, count: int = 60) -> list[str]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return lines[-count:]


def extract_time_marker(log_path: Path) -> tuple[float | None, int | None]:
    for line in reversed(tail_lines(log_path, 120)):
        if not line.startswith(TIME_MARKER):
            continue
        elapsed = None
        rss = None
        for token in line.split():
            if token.startswith("elapsed_sec="):
                try:
                    elapsed = float(token.split("=", 1)[1])
                except ValueError:
                    elapsed = None
            elif token.startswith("max_rss_kib="):
                try:
                    rss = int(token.split("=", 1)[1])
                except ValueError:
                    rss = None
        return elapsed, rss
    return None, None


def extract_signature(log_path: Path) -> str:
    lines = tail_lines(log_path, 120)
    if not lines:
        return ""
    for line in reversed(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith(TIME_MARKER):
            continue
        lower = stripped.lower()
        if any(tok in lower for tok in FAILURE_TOKENS):
            return stripped[:500]
    for line in reversed(lines):
        stripped = line.strip()
        if stripped and not stripped.startswith(TIME_MARKER):
            return stripped[:500]
    return ""


def run_command(
    *,
    command: list[str],
    env: dict[str, str],
    cwd: Path,
    log_path: Path,
    timeout_seconds: int,
) -> CommandResult:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    wall_start = time.monotonic()
    timed_out = False
    return_code: int | None = None

    with log_path.open("w", encoding="utf-8") as log:
        log.write(f"$ {shlex.join(command)}\n")
        log.flush()
        wrapped = [
            "/usr/bin/time",
            "-f",
            f"{TIME_MARKER} elapsed_sec=%e max_rss_kib=%M",
            *command,
        ]
        proc = subprocess.Popen(
            wrapped,
            cwd=str(cwd),
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        try:
            return_code = proc.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                return_code = proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                return_code = proc.wait()

    wall_time = time.monotonic() - wall_start
    elapsed_from_time, max_rss_kib = extract_time_marker(log_path)
    elapsed = elapsed_from_time if elapsed_from_time is not None else wall_time
    signature = extract_signature(log_path)
    if timed_out:
        return CommandResult(
            status="timeout",
            return_code=return_code,
            wall_time_sec=elapsed,
            max_rss_kib=max_rss_kib,
            signature=signature or f"timeout after {timeout_seconds}s",
        )
    if return_code == 0:
        return CommandResult(
            status="pass",
            return_code=0,
            wall_time_sec=elapsed,
            max_rss_kib=max_rss_kib,
            signature="",
        )
    return CommandResult(
        status="fail",
        return_code=return_code,
        wall_time_sec=elapsed,
        max_rss_kib=max_rss_kib,
        signature=signature,
    )


def require_tool(name: str, override: str | None = None) -> str:
    if override:
        path = Path(override)
        if not path.exists():
            raise RuntimeError(f"tool override not found for {name}: {override}")
        return str(path)
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"required tool not found in PATH: {name}")
    return found


def resolve_torch_mlir_opt(override: str | None = None) -> str:
    if override:
        path = Path(override)
        if not path.exists():
            raise RuntimeError(f"torch-mlir-opt override not found: {override}")
        return str(path)
    from_env = os.environ.get("TORCH_MLIR_OPT")
    if from_env and Path(from_env).exists():
        return from_env
    direct = shutil.which("torch-mlir-opt")
    if direct:
        return direct
    code = (
        "import pathlib, torch_mlir\n"
        "p = pathlib.Path(torch_mlir.__file__).resolve().parent / '_mlir_libs' / 'torch-mlir-opt'\n"
        "print(p if p.exists() else '')\n"
    )
    probe = subprocess.run(
        [sys.executable, "-c", code],
        check=False,
        capture_output=True,
        text=True,
    )
    candidate = probe.stdout.strip()
    if candidate and Path(candidate).exists():
        return candidate
    raise RuntimeError(
        "unable to locate torch-mlir-opt; run in nix develop or pass --torch-mlir-opt"
    )


def resolve_yosys_slang_so(
    *,
    override: str | None,
    yosys_bin: str,
) -> str | None:
    if override:
        if Path(override).exists():
            return override
        raise RuntimeError(f"yosys slang plugin not found: {override}")

    env_value = os.environ.get("YOSYS_SLANG_SO")
    if env_value and Path(env_value).exists():
        return env_value

    yosys_config = shutil.which("yosys-config")
    if not yosys_config:
        return None
    proc = subprocess.run(
        [yosys_config, "--datdir"],
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    datdir = proc.stdout.strip()
    if not datdir:
        return None
    candidate = Path(datdir) / "plugins" / "slang.so"
    if candidate.exists():
        return str(candidate)
    # Common alternate name on some builds.
    candidate_alt = Path(datdir) / "plugins" / "slang" / "slang.so"
    if candidate_alt.exists():
        return str(candidate_alt)
    return None


def model_key(model: ModelSpec) -> str:
    return f"{model.model_id}@{model.revision}"


def read_processed_keys(summary_jsonl: Path) -> set[str]:
    processed: set[str] = set()
    if not summary_jsonl.exists():
        return processed
    for line in summary_jsonl.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        key = payload.get("key")
        if isinstance(key, str) and key:
            processed.add(key)
    return processed


def write_summary_csv(summary_jsonl: Path, summary_csv: Path) -> None:
    rows: list[dict[str, Any]] = []
    if summary_jsonl.exists():
        for line in summary_jsonl.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            rows.append(json.loads(line))

    stage_status_cols = [f"stage_{name}" for name in STAGES]
    stage_time_cols = [f"time_{name}_sec" for name in STAGES]
    fieldnames = [
        "index",
        "model_id",
        "revision",
        "status",
        "first_failure_stage",
        "first_failure_signature",
        "stages_passed",
        "total_wall_time_sec",
        "result_json",
    ] + stage_status_cols + stage_time_cols

    summary_csv.parent.mkdir(parents=True, exist_ok=True)
    with summary_csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            out: dict[str, Any] = {
                "index": row.get("index"),
                "model_id": row.get("model_id"),
                "revision": row.get("revision"),
                "status": row.get("status"),
                "first_failure_stage": row.get("first_failure_stage", ""),
                "first_failure_signature": row.get("first_failure_signature", ""),
                "stages_passed": row.get("stages_passed", 0),
                "total_wall_time_sec": row.get("total_wall_time_sec", 0.0),
                "result_json": row.get("result_json", ""),
            }
            stage_map = {s["name"]: s for s in row.get("stages", [])}
            for stage_name in STAGES:
                stage = stage_map.get(stage_name, {})
                out[f"stage_{stage_name}"] = stage.get("status", "skipped")
                out[f"time_{stage_name}_sec"] = stage.get("wall_time_sec", 0.0)
            writer.writerow(out)


def run_model(
    *,
    model: ModelSpec,
    args: argparse.Namespace,
    repo_root: Path,
    out_root: Path,
    base_env: dict[str, str],
) -> dict[str, Any]:
    stop_idx = STAGES.index(args.stop_stage)
    selected_stages = STAGES[: stop_idx + 1]

    safe_name = sanitize_model_id(model.model_id)
    model_dir = out_root / "models" / f"{model.index:03d}-{safe_name}"
    logs_dir = model_dir / "logs"
    model_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    files = {
        "torch": model_dir / "00-torch.mlir",
        "linalg": model_dir / "01-linalg.mlir",
        "cf": model_dir / "02-cf.mlir",
        "cf_stats": model_dir / "03-cf.stats",
        "handshake": model_dir / "04-handshake.mlir",
        "hs_ext": model_dir / "05-hs-ext.mlir",
        "hw0": model_dir / "06-hw0.mlir",
        "hw": model_dir / "07-hw.mlir",
        "hw_clean": model_dir / "08-hw-clean.mlir",
        "sv": model_dir / "09-output.sv",
        "sv_split_dir": model_dir / "09-output.split",
        "sv_filelist": model_dir / "09-output.split.f",
        "fp_stub": model_dir / "09-fp-prims-auto.sv",
        "il": model_dir / "10-output.il",
        "yosys_stat": model_dir / "11-yosys-stat.json",
    }

    triage_scripts = repo_root / "scripts" / "triage"
    pipeline_scripts = repo_root / "scripts" / "pipeline"
    exporter = triage_scripts / "export_hf_causallm_to_torch_mlir.py"

    stage_defs: list[tuple[str, list[str], dict[str, str]]] = [
        (
            "torch_export",
            [
                sys.executable,
                str(exporter),
                "--model-id",
                model.model_id,
                "--revision",
                model.revision,
                "--output",
                str(files["torch"]),
                "--batch-size",
                str(args.batch_size),
                "--seq-len",
                str(args.seq_len),
                "--dtype",
                args.dtype,
                "--attn-implementation",
                args.attn_implementation,
            ]
            + (["--trust-remote-code"] if args.trust_remote_code else [])
            + (["--local-files-only"] if args.local_files_only else [])
            + (["--strict-export"] if args.strict_export else []),
            {},
        ),
        (
            "linalg",
            [
                "bash",
                str(pipeline_scripts / "torch_to_linalg.sh"),
                str(files["torch"]),
                str(files["linalg"]),
            ],
            {},
        ),
        (
            "cf",
            [
                "bash",
                str(pipeline_scripts / "linalg_to_cf.sh"),
                str(files["linalg"]),
                str(files["cf"]),
            ],
            {},
        ),
        (
            "cf_stats",
            [
                "bash",
                str(pipeline_scripts / "cf_stats.sh"),
                str(files["cf"]),
                str(files["cf_stats"]),
            ],
            {},
        ),
        (
            "handshake",
            [
                "bash",
                str(pipeline_scripts / "cf_to_handshake.sh"),
                str(files["cf"]),
                str(files["handshake"]),
            ],
            {},
        ),
        (
            "hs_ext",
            [
                "bash",
                str(pipeline_scripts / "handshake_to_hs_ext.sh"),
                str(files["handshake"]),
                str(files["hs_ext"]),
            ],
            {},
        ),
        (
            "hw0",
            [
                "bash",
                str(pipeline_scripts / "hs_ext_to_hw0.sh"),
                str(files["hs_ext"]),
                str(files["hw0"]),
            ],
            {},
        ),
        (
            "hw",
            [
                "bash",
                str(pipeline_scripts / "hw0_to_hw.sh"),
                str(files["hw0"]),
                str(files["hw"]),
            ],
            {},
        ),
        (
            "hw_clean",
            [
                "bash",
                str(pipeline_scripts / "hw_to_hw_clean.sh"),
                str(files["hw"]),
                str(files["hw_clean"]),
            ],
            {},
        ),
        (
            "fp_stub_gen",
            [
                sys.executable,
                str(pipeline_scripts / "gen_fp_stubs_from_mlir.py"),
                str(files["hw_clean"]),
                str(files["fp_stub"]),
            ],
            {},
        ),
        (
            "sv",
            [
                "bash",
                str(pipeline_scripts / "hw_clean_to_sv.sh"),
                str(files["hw_clean"]),
                str(files["sv"]),
            ],
            {
                "SV_SPLIT_DIR": str(files["sv_split_dir"]),
                "SV_SPLIT_FILELIST": str(files["sv_filelist"]),
                "FP_PRIMS_SV": str(files["fp_stub"]),
            },
        ),
        (
            "fp_coverage",
            [
                "bash",
                str(pipeline_scripts / "check_fp_primitive_coverage.sh"),
                str(files["sv_filelist"]),
                str(files["fp_stub"]),
            ],
            {},
        ),
        (
            "il",
            [
                "bash",
                str(pipeline_scripts / "sv_to_il.sh"),
                str(files["sv_filelist"]),
                str(files["il"]),
            ],
            {},
        ),
        (
            "yosys_stat",
            [
                "bash",
                str(pipeline_scripts / "sv_to_yosys_stat.sh"),
                str(files["sv_filelist"]),
                str(files["yosys_stat"]),
            ],
            {},
        ),
    ]

    stage_defs = [sd for sd in stage_defs if sd[0] in selected_stages]
    if args.skip_fp_coverage:
        stage_defs = [sd for sd in stage_defs if sd[0] != "fp_coverage"]

    cache_dir = Path(args.cache_dir) if args.cache_dir else out_root / "hf-cache"
    cache_dir.mkdir(parents=True, exist_ok=True)

    stages: list[dict[str, Any]] = []
    started_at = utc_now_iso()
    model_status = "pass"
    first_failure_stage = ""
    first_failure_signature = ""

    for stage_name, command, extra_env in stage_defs:
        env = dict(base_env)
        env.update(extra_env)
        env["HF_HOME"] = str(cache_dir)
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"

        log_path = logs_dir / f"{stage_name}.log"
        result = run_command(
            command=command,
            env=env,
            cwd=repo_root,
            log_path=log_path,
            timeout_seconds=args.timeout_seconds,
        )
        stage_payload: dict[str, Any] = {
            "name": stage_name,
            "status": result.status,
            "return_code": result.return_code,
            "wall_time_sec": round(result.wall_time_sec, 6),
            "max_rss_kib": result.max_rss_kib,
            "signature": result.signature,
            "log_path": str(log_path),
        }
        stages.append(stage_payload)
        if result.status != "pass":
            model_status = "fail"
            first_failure_stage = stage_name
            first_failure_signature = result.signature
            break

    executed = {s["name"] for s in stages}
    for stage_name in selected_stages:
        if args.skip_fp_coverage and stage_name == "fp_coverage":
            continue
        if stage_name in executed:
            continue
        stages.append(
            {
                "name": stage_name,
                "status": "skipped",
                "return_code": None,
                "wall_time_sec": 0.0,
                "max_rss_kib": None,
                "signature": "",
                "log_path": str(logs_dir / f"{stage_name}.log"),
            }
        )

    stage_by_name = {s["name"]: s for s in stages}
    ordered_stages = [stage_by_name[name] for name in selected_stages if name in stage_by_name]
    total_wall = sum(float(s.get("wall_time_sec", 0.0)) for s in ordered_stages)
    stages_passed = sum(1 for s in ordered_stages if s.get("status") == "pass")

    result_payload: dict[str, Any] = {
        "key": model_key(model),
        "index": model.index,
        "model_id": model.model_id,
        "revision": model.revision,
        "status": model_status,
        "first_failure_stage": first_failure_stage,
        "first_failure_signature": first_failure_signature,
        "stages_passed": stages_passed,
        "total_wall_time_sec": round(total_wall, 6),
        "started_at": started_at,
        "finished_at": utc_now_iso(),
        "model_dir": str(model_dir),
        "result_json": str(model_dir / "result.json"),
        "raw_model_row": model.raw,
        "stages": ordered_stages,
    }

    (model_dir / "result.json").write_text(
        json.dumps(result_payload, indent=2),
        encoding="utf-8",
    )
    return result_payload


def build_base_env(args: argparse.Namespace, stop_stage: str) -> dict[str, str]:
    env = dict(os.environ)
    env["LINALG_LOWERING"] = args.linalg_lowering
    env["HANDSHAKE_INSERT_BUFFERS"] = args.handshake_insert_buffers
    if args.yosys_light_mode:
        env["YOSYS_LIGHT_MODE"] = "1"
    if args.skip_fp_coverage:
        env["SKIP_FP_COVERAGE_CHECK"] = "1"

    stop_idx = STAGES.index(stop_stage)
    if stop_idx >= STAGES.index("linalg"):
        env["TORCH_MLIR_OPT"] = resolve_torch_mlir_opt(args.torch_mlir_opt)
        env["MLIR_OPT"] = require_tool("mlir-opt", args.mlir_opt)
        env["CIRCT_OPT"] = require_tool("circt-opt", args.circt_opt)
    if stop_idx >= STAGES.index("il"):
        yosys_bin = require_tool("yosys", args.yosys)
        env["YOSYS"] = yosys_bin
        slang = resolve_yosys_slang_so(
            override=args.yosys_slang_so,
            yosys_bin=yosys_bin,
        )
        if slang:
            env["YOSYS_SLANG_SO"] = slang
    return env


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    out_root = Path(args.out).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    summary_jsonl = out_root / "summary.jsonl"
    summary_csv = out_root / "summary.csv"

    models = read_models(Path(args.models))
    if not models:
        raise RuntimeError(f"no models found in {args.models}")
    models = [m for m in models if m.index >= args.start_index]
    if args.max_models > 0:
        models = models[: args.max_models]

    processed = read_processed_keys(summary_jsonl) if args.resume else set()
    pending = [m for m in models if model_key(m) not in processed]

    if args.dry_run:
        print(f"repo_root={repo_root}")
        print(f"models_total={len(models)} pending={len(pending)}")
        print(f"stop_stage={args.stop_stage}")
        for model in pending[: min(10, len(pending))]:
            print(f"- {model.index:03d} {model.model_id}@{model.revision}")
        return 0

    base_env = build_base_env(args, args.stop_stage)

    for model in pending:
        print(f"[{model.index}] {model.model_id}@{model.revision}")
        payload = run_model(
            model=model,
            args=args,
            repo_root=repo_root,
            out_root=out_root,
            base_env=base_env,
        )
        with summary_jsonl.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload) + "\n")
        write_summary_csv(summary_jsonl, summary_csv)
        print(
            f"  -> {payload['status']} "
            f"(failure_stage={payload['first_failure_stage'] or 'none'})"
        )

    print(f"summary_jsonl={summary_jsonl}")
    print(f"summary_csv={summary_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
