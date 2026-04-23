#!/usr/bin/env python3
"""Run one Task 6 ladder stage and emit a compact artifact bundle."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import json
import re
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNS_ROOT = ROOT / "artifacts" / "task6-streamtensor-lite" / "runs"
LUT_CEILING = 29_860
FF_CEILING = 59_720


@dataclass(frozen=True)
class CommandSpec:
    label: str
    log_name: str
    argv: tuple[str, ...]


@dataclass(frozen=True)
class StageSpec:
    stage: str
    title: str
    model_target: str
    status: str
    large_weights_as_rtl_constants: bool | None
    next_action: str
    blocked_reason: str | None = None
    commands: tuple[CommandSpec, ...] = ()


def timed_nix_build(target: str) -> tuple[str, ...]:
    return (
        "/usr/bin/time",
        "-f",
        "ELAPSED=%e RSS_KB=%M",
        "nix",
        "build",
        f".#{target}",
        "--no-link",
        "--print-out-paths",
        "-L",
    )


STAGES: dict[str, StageSpec] = {
    "l0": StageSpec(
        stage="L0",
        title="Synthetic 64x64 GEMV smoke",
        model_target="task6-l0-gemv64 external-weight kernel",
        status="running",
        large_weights_as_rtl_constants=False,
        next_action="Use only for kernel plumbing and DSP validation; do not treat it as a scorecard-cleared reference while LUT stays above the ceiling.",
        commands=(
            CommandSpec(
                label="yosys-stat",
                log_name="yosys-stat.log",
                argv=timed_nix_build("task6-l0-gemv64-yosys-stat"),
            ),
            CommandSpec(
                label="sv-sim",
                log_name="sv-sim.log",
                argv=timed_nix_build("task6-l0-gemv64-sv-sim"),
            ),
            CommandSpec(
                label="utilization",
                log_name="utilization.log",
                argv=timed_nix_build("task6-l0-gemv64-utilization"),
            ),
        ),
    ),
    "l1": StageSpec(
        stage="L1",
        title="TinyStories single linear op",
        model_target="block-0 mlp.c_fc extracted from tiny-stories-1m-representative-core-v64-h4",
        status="frozen reference",
        large_weights_as_rtl_constants=False,
        next_action="Keep this as the L1 gold reference and do not reopen local hotspot surgery unless L2 forces a boundary rethink.",
        commands=(
            CommandSpec(
                label="yosys-stat",
                log_name="yosys-stat.log",
                argv=timed_nix_build(
                    "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-yosys-stat"
                ),
            ),
            CommandSpec(
                label="sv-sim",
                log_name="sv-sim.log",
                argv=timed_nix_build(
                    "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim"
                ),
            ),
            CommandSpec(
                label="utilization",
                log_name="utilization.log",
                argv=timed_nix_build(
                    "task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization"
                ),
            ),
        ),
    ),
    "l2": StageSpec(
        stage="L2",
        title="Reduced-vocab single-block replay",
        model_target="tiny-stories-v1k-h64-l1 tiled 4 x 64 wrapper around one reused 64 -> 64 kernel",
        status="running",
        large_weights_as_rtl_constants=False,
        next_action="Keep tiled L2 as the only active mainline; L3 remains blocked until this rung clears the LUT ceiling or a new structural hypothesis replaces it.",
        commands=(
            CommandSpec(
                label="yosys-stat",
                log_name="yosys-stat.log",
                argv=timed_nix_build(
                    "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-yosys-stat"
                ),
            ),
            CommandSpec(
                label="sv-sim",
                log_name="sv-sim.log",
                argv=timed_nix_build(
                    "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-sv-sim"
                ),
            ),
            CommandSpec(
                label="utilization",
                log_name="utilization.log",
                argv=timed_nix_build(
                    "task6-l2-c-fc-redirect-tile4x64-postbranch-outbuf-fifo2-abc9-utilization"
                ),
            ),
        ),
    ),
    "l3": StageSpec(
        stage="L3",
        title="Reduced-vocab replay",
        model_target="planned tiny-stories-v4k-h64-l1",
        status="blocked",
        large_weights_as_rtl_constants=None,
        blocked_reason="Promotion is closed because the current L2 reference still sits at 31,907 LUT, above the 29,860 LUT ceiling.",
        next_action="Do not start L3 until L2 clears the first-proof scorecard or a new structural hypothesis changes the lane.",
    ),
    "l4": StageSpec(
        stage="L4",
        title="Representative-core replay",
        model_target="existing tiny-stories-1m-representative-core-v64-h4",
        status="blocked",
        large_weights_as_rtl_constants=None,
        blocked_reason="Replay is reserve-only until L3 demonstrates a believable structural win.",
        next_action="Keep L4 parked behind L3.",
    ),
    "x1": StageSpec(
        stage="X1",
        title="Deferred fidelity step",
        model_target="planned tiny-stories-v10k-h64-l1",
        status="blocked",
        large_weights_as_rtl_constants=None,
        blocked_reason="The deferred extension ladder is not allowed to become the default loop while the primary ladder remains unresolved.",
        next_action="Keep X1 deferred until the primary L0-L4 ladder is exhausted on stronger evidence.",
    ),
    "x2": StageSpec(
        stage="X2",
        title="Deferred reuse step",
        model_target="planned tiny-stories-v10k-h64-l2",
        status="blocked",
        large_weights_as_rtl_constants=None,
        blocked_reason="X2 depends on X1 first proving the higher-vocab rung is worth replaying.",
        next_action="Do not start X2 before X1.",
    ),
    "x3": StageSpec(
        stage="X3",
        title="Final whole-model comparison replay",
        model_target="existing tiny-stories-1m-baseline-float",
        status="blocked",
        large_weights_as_rtl_constants=None,
        blocked_reason="The whole-model lane stays comparison-only and remains blocked until L4 is believable downstream.",
        next_action="Keep X3 as a final comparison artifact, not an active iteration surface.",
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True, choices=sorted(STAGES))
    return parser.parse_args()


def iso_timestamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def allocate_run_dir() -> Path:
    base = iso_timestamp()
    index = 0
    while True:
        suffix = "" if index == 0 else f"-{index:02d}"
        candidate = RUNS_ROOT / f"{base}{suffix}"
        try:
            candidate.mkdir(parents=True, exist_ok=False)
            return candidate
        except FileExistsError:
            index += 1


def run_command(spec: CommandSpec, output_dir: Path) -> dict[str, Any]:
    log_path = output_dir / spec.log_name
    with log_path.open("w", encoding="utf-8") as log_file:
        proc = subprocess.run(
            list(spec.argv),
            cwd=ROOT,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    text = log_path.read_text(encoding="utf-8")
    elapsed_matches = re.findall(r"ELAPSED=([0-9.]+)", text)
    rss_matches = re.findall(r"RSS_KB=(\d+)", text)
    store_paths = re.findall(r"(?m)^/nix/store/\S+$", text)
    return {
        "label": spec.label,
        "argv": list(spec.argv),
        "log_name": spec.log_name,
        "returncode": proc.returncode,
        "elapsed_s": float(elapsed_matches[-1]) if elapsed_matches else None,
        "rss_kb": int(rss_matches[-1]) if rss_matches else None,
        "store_path": store_paths[-1] if store_paths else None,
        "log_text": text,
    }


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def summarize_yosys(result: dict[str, Any]) -> dict[str, Any]:
    if result["store_path"] is None:
        return {}
    payload = load_json(Path(result["store_path"]))
    reviewer = payload.get("reviewer_summary") or {}
    design = reviewer.get("design") or {}
    sv_bundle = reviewer.get("sv_bundle") or {}
    memories = reviewer.get("memory_modules") or {}
    return {
        "store_path": result["store_path"],
        "elapsed_s": result["elapsed_s"],
        "rss_kb": result["rss_kb"],
        "summary_lines": payload.get("reviewer_summary_lines") or [],
        "design_cells": design.get("num_cells"),
        "sv_file_count": sv_bundle.get("file_count"),
        "main_sv_lines": sv_bundle.get("main_sv_lines"),
        "total_memory_bits": memories.get("total_memory_bits"),
    }


def summarize_utilization(result: dict[str, Any]) -> dict[str, Any]:
    if result["store_path"] is None:
        return {}
    payload = load_json(Path(result["store_path"]) / "summary.json")
    resources = payload.get("resources") or {}
    return {
        "store_path": result["store_path"],
        "elapsed_s": result["elapsed_s"],
        "rss_kb": result["rss_kb"],
        "lut": resources.get("clb_luts", {}).get("used"),
        "ff": resources.get("clb_ffs", {}).get("used"),
        "dsp": resources.get("dsp", {}).get("used"),
        "bram36": resources.get("bram36", {}).get("used"),
    }


def summarize_sim(result: dict[str, Any]) -> dict[str, Any]:
    pass_line = None
    fail_line = None
    payload: dict[str, Any] = {}
    if result["store_path"] is not None:
        payload = load_json(Path(result["store_path"]))
        status = payload.get("status")
        stores = payload.get("stores")
        outputs = payload.get("outputs")
        if status == "PASS":
            pass_line = f"PASS: stores {stores} outputs {outputs}"
        elif status is not None:
            fail_line = f"{status}: stores {stores} outputs {outputs}"
    if pass_line is None and fail_line is None:
        for line in result["log_text"].splitlines():
            stripped = line.strip()
            if stripped.startswith("PASS:"):
                pass_line = stripped
            if stripped.startswith("FAIL:") or "Timeout waiting" in stripped:
                fail_line = stripped
    return {
        "store_path": result["store_path"],
        "elapsed_s": result["elapsed_s"],
        "rss_kb": result["rss_kb"],
        "pass_line": pass_line,
        "fail_line": fail_line,
        "status": payload.get("status"),
        "stores": payload.get("stores"),
        "outputs": payload.get("outputs"),
    }


def format_int(value: Any) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return f"{value:,}"
    return str(value)


def format_seconds(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.2f} s"


def verdict_for(stage: StageSpec, util: dict[str, Any], sim: dict[str, Any]) -> str:
    if stage.blocked_reason is not None:
        return "blocked"
    if sim.get("pass_line") is None:
        return "fail-sim"
    if util.get("dsp") in (None, 0):
        return "fail-dsp"
    if util.get("lut") is not None and util["lut"] > LUT_CEILING:
        return "fail-lut"
    if util.get("ff") is not None and util["ff"] > FF_CEILING:
        return "fail-ff"
    return "pass"


def write_summary(
    stage: StageSpec,
    summary_path: Path,
    command_results: list[dict[str, Any]],
    yosys: dict[str, Any],
    sim: dict[str, Any],
    util: dict[str, Any],
    verdict: str,
) -> None:
    lines = [f"# {stage.stage} Stage-Local Runner", "", "## Stage", ""]
    lines.append(f"- rung: `{stage.stage}`")
    lines.append(f"- title: {stage.title}")
    lines.append(f"- model target: `{stage.model_target}`")
    lines.append(f"- status: `{stage.status}`")
    lines.append("")
    lines.append("## Commands")
    lines.append("")
    if command_results:
        for result in command_results:
            lines.append(f"- `{' '.join(result['argv'])}`")
    else:
        lines.append("- none")
    lines.append("")
    lines.append("## Logs")
    lines.append("")
    if command_results:
        for result in command_results:
            lines.append(f"- `{result['log_name']}`")
    else:
        lines.append("- none")
    lines.append("")
    lines.append("## Structural Summary")
    lines.append("")
    if yosys.get("summary_lines"):
        for row in yosys["summary_lines"]:
            lines.append(f"- {row}")
    elif stage.blocked_reason is not None:
        lines.append(f"- {stage.blocked_reason}")
    else:
        lines.append("- unavailable")
    lines.append("")
    lines.append("## Metrics")
    lines.append("")
    if stage.blocked_reason is None:
        lines.append("- measurement mode: `cache-hit status replay`")
        lines.append(
            "- timing note: replay timings are status-surface timings and are not comparable to frontier experiment timings in the main ledger"
        )
        lines.append(
            f"- Yosys stat replay wall-clock: {format_seconds(yosys.get('elapsed_s'))}"
        )
        lines.append(
            f"- Yosys stat replay peak RSS: {format_int(yosys.get('rss_kb'))} KB"
        )
        lines.append(
            f"- Verilator replay wall-clock: {format_seconds(sim.get('elapsed_s'))}"
        )
        lines.append(
            f"- Verilator replay peak RSS: {format_int(sim.get('rss_kb'))} KB"
        )
        lines.append(f"- Verilator result: `{sim.get('pass_line') or sim.get('fail_line') or 'n/a'}`")
        if sim.get("store_path"):
            lines.append(f"- sv-sim output: `{sim['store_path']}`")
        lines.append(
            f"- utilization replay wall-clock: {format_seconds(util.get('elapsed_s'))}"
        )
        lines.append(
            f"- utilization replay peak RSS: {format_int(util.get('rss_kb'))} KB"
        )
        lines.append(f"- CLB LUTs: {format_int(util.get('lut'))}")
        lines.append(f"- CLB FFs: {format_int(util.get('ff'))}")
        lines.append(f"- DSP48E1: {format_int(util.get('dsp'))}")
        lines.append(f"- BRAM36: {format_int(util.get('bram36'))}")
        lines.append(
            "- large weights emitted as RTL constants: "
            + ("yes" if stage.large_weights_as_rtl_constants else "no")
        )
        lines.append(
            f"- LUT ceiling check: {'pass' if util.get('lut') is not None and util['lut'] <= LUT_CEILING else 'fail'} (`{LUT_CEILING:,}`)"
        )
        lines.append(
            f"- FF ceiling check: {'pass' if util.get('ff') is not None and util['ff'] <= FF_CEILING else 'fail'} (`{FF_CEILING:,}`)"
        )
        if util.get("store_path"):
            lines.append(f"- utilization output: `{util['store_path']}`")
        if yosys.get("store_path"):
            lines.append(f"- yosys-stat output: `{yosys['store_path']}`")
    else:
        lines.append("- command execution: skipped")
        lines.append("- blocked reason:")
        lines.append(f"  - {stage.blocked_reason}")
    lines.append("")
    lines.append("## Verdict")
    lines.append("")
    lines.append(f"- `{verdict}`")
    lines.append("")
    lines.append("## Next Action")
    lines.append("")
    lines.append(f"- {stage.next_action}")
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_readme(run_dir: Path, stage: StageSpec, leaf_dir: Path) -> None:
    relative_summary = f"./{leaf_dir.name}/summary.md"
    readme = "\n".join(
        [
            f"# Task 6 Stage-Local Runner - {stage.stage}",
            "",
            "## Contents",
            "",
            f"- [{leaf_dir.name}/summary.md]({relative_summary})",
            "",
        ]
    )
    (run_dir / "README.md").write_text(readme, encoding="utf-8")


def main() -> None:
    args = parse_args()
    stage = STAGES[args.stage]
    run_dir = allocate_run_dir()
    leaf_dir = run_dir / f"stage-local-{args.stage}"
    leaf_dir.mkdir(parents=True, exist_ok=False)

    command_results: list[dict[str, Any]] = []
    yosys: dict[str, Any] = {}
    sim: dict[str, Any] = {}
    util: dict[str, Any] = {}

    if stage.blocked_reason is None:
        for spec in stage.commands:
            result = run_command(spec, leaf_dir)
            command_results.append(result)
            if result["returncode"] != 0:
                raise SystemExit(
                    f"{stage.stage} stage-local runner command failed: {spec.label}"
                )
            if spec.label == "yosys-stat":
                yosys = summarize_yosys(result)
            elif spec.label == "sv-sim":
                sim = summarize_sim(result)
            elif spec.label == "utilization":
                util = summarize_utilization(result)

    verdict = verdict_for(stage, util, sim)
    write_summary(stage, leaf_dir / "summary.md", command_results, yosys, sim, util, verdict)
    write_readme(run_dir, stage, leaf_dir)
    print(f"{stage.stage} -> {leaf_dir}")


if __name__ == "__main__":
    main()
