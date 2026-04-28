from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Iterable

IN_DIM = 64
OUT_DIM = 64
WEIGHT_WORDS = IN_DIM * OUT_DIM


def activation_value(index: int) -> int:
    return ((index * 7 + 3) % 31) - 15


def weight_value(out_index: int, in_index: int) -> int:
    return ((out_index * 11 + in_index * 5 + 1) % 47) - 23


def expected_value(out_index: int) -> int:
    return sum(
        activation_value(in_index) * weight_value(out_index, in_index)
        for in_index in range(IN_DIM)
    )


def sha256_ints(values: Iterable[int], byte_width: int) -> str:
    digest = hashlib.sha256()
    for value in values:
        digest.update(int(value).to_bytes(byte_width, byteorder="little", signed=True))
    return digest.hexdigest()


def summarize_yosys_stat(path: Path, top_name: str) -> dict[str, object]:
    stat = json.loads(path.read_text(encoding="utf-8"))
    design = stat.get("design", {})
    cells_by_type = design.get("num_cells_by_type", {})
    lut_cells = sum(int(cells_by_type.get(f"LUT{index}", 0)) for index in range(1, 7))
    dsp_cells = sum(
        int(cells_by_type.get(cell_type, 0))
        for cell_type in ("DSP48", "DSP48A", "DSP48A1", "DSP48E1", "DSP48E2")
    )
    ff_cells = sum(
        int(cells_by_type.get(cell_type, 0))
        for cell_type in ("FDRE", "FDSE", "FDCE", "FDPE", "FDRSE", "FDCPE")
    )
    return {
        "path": str(path),
        "creator": stat.get("creator", ""),
        "top": top_name,
        "num_cells": int(design.get("num_cells", 0)),
        "num_wires": int(design.get("num_wires", 0)),
        "num_wire_bits": int(design.get("num_wire_bits", 0)),
        "cells_by_type": cells_by_type,
        "dsp_cells": dsp_cells,
        "lut_cells": lut_cells,
        "ff_cells": ff_cells,
        "dsp_gate_pass": dsp_cells > 0,
    }


def summarize_mapped_utilization(path: Path) -> dict[str, object]:
    summary = json.loads(path.read_text(encoding="utf-8"))
    resources = summary.get("resources", {})
    return {
        "path": str(path),
        "design_json": summary.get("design_json", ""),
        "top": summary.get("top", ""),
        "resources": {
            name: resources.get(name, {})
            for name in (
                "slices_lower_bound",
                "clb_luts",
                "clb_ffs",
                "dsp",
                "bram36",
                "bram36_equiv",
                "bram_kb",
            )
        },
        "top_leaf_cell_types": summary.get("top_leaf_cell_types", []),
    }


def build_payload(
    artifact_name: str,
    kernel_source: Path,
    extra_kernel_sources: list[Path],
    testbench_source: Path,
    top_name: str,
    lane_count: int,
    packed_weight_words: int,
    local_packed_weight_memory: bool,
    packed_weight_read_latency_cycles: int,
    nix_target_prefix: str,
    sim_result_json: Path | None,
    yosys_stat_json: Path | None,
    mapped_utilization_summary_json: Path | None,
) -> dict[str, object]:
    activations = [activation_value(index) for index in range(IN_DIM)]
    weights = [
        weight_value(out_index, in_index)
        for out_index in range(OUT_DIM)
        for in_index in range(IN_DIM)
    ]
    expected = [expected_value(out_index) for out_index in range(OUT_DIM)]
    tools = {
        "verilator": shutil.which("verilator"),
        "yosys": shutil.which("yosys"),
        "iverilog": shutil.which("iverilog"),
    }
    can_execute_sim = tools["verilator"] is not None or tools["iverilog"] is not None
    can_score_synthesis = tools["yosys"] is not None
    sim_result = None
    if sim_result_json is not None:
        sim_result = json.loads(sim_result_json.read_text(encoding="utf-8"))
    yosys_result = None
    if yosys_stat_json is not None:
        yosys_result = summarize_yosys_stat(yosys_stat_json, top_name)
    mapped_result = None
    if mapped_utilization_summary_json is not None:
        mapped_result = summarize_mapped_utilization(mapped_utilization_summary_json)

    if (
        sim_result is not None
        and sim_result.get("status") == "PASS"
        and yosys_result is not None
        and yosys_result.get("dsp_gate_pass")
        and mapped_result is not None
    ):
        status = "sim_pass_yosys_dsp_pass_mapped"
        blocked_reason = ""
    elif (
        sim_result is not None
        and sim_result.get("status") == "PASS"
        and yosys_result is not None
        and yosys_result.get("dsp_gate_pass")
    ):
        status = "sim_pass_yosys_dsp_pass"
        blocked_reason = ""
    elif sim_result is not None and sim_result.get("status") == "PASS":
        status = "sim_pass"
        blocked_reason = ""
    elif can_execute_sim:
        status = "prepared_sim_tool_available"
        blocked_reason = ""
    else:
        status = "prepared_not_executed"
        blocked_reason = "verilator and iverilog are not available on PATH"

    contract = {
        "in_dim": IN_DIM,
        "out_dim": OUT_DIM,
        "activation_dtype": "int8",
        "weight_dtype": "int8",
        "accumulator_dtype": "int32",
        "weight_words": WEIGHT_WORDS,
        "macs": IN_DIM * OUT_DIM,
        "interface": "combinational address/data memories plus ready/valid output",
    }
    if lane_count > 1:
        contract.update(
            {
                "parallel_output_lanes": lane_count,
                "mac_lanes_per_cycle": lane_count,
                "output_tile_count": OUT_DIM // lane_count,
            }
        )
    if packed_weight_words > 0:
        contract.update(
            {
                "packed_weight_words": packed_weight_words,
                "packed_weight_word_bits": lane_count * 8,
                "weight_interface": "one packed weight word per activation step",
            }
        )
    if local_packed_weight_memory:
        contract.update(
            {
                "local_packed_weight_memory": True,
                "packed_weight_read_latency_cycles": packed_weight_read_latency_cycles,
                "weight_interface": "loadable synchronous local packed-weight memory",
            }
        )

    object_dir_stem = top_name.removesuffix("_kernel")
    testbench_top = f"{object_dir_stem}_tb"
    rtl_sources = [*extra_kernel_sources, kernel_source]
    rtl_sources_text = " ".join(str(source) for source in rtl_sources)
    rtl = {
        "kernel_source": str(kernel_source),
        "testbench_source": str(testbench_source),
        "contract": contract,
    }
    if extra_kernel_sources:
        rtl["extra_kernel_sources"] = [
            str(extra_kernel_source) for extra_kernel_source in extra_kernel_sources
        ]

    return {
        "artifact": artifact_name,
        "status": status,
        "blocked_reason": blocked_reason,
        "rtl": rtl,
        "tools": {
            "verilator_on_path": tools["verilator"] is not None,
            "yosys_on_path": tools["yosys"] is not None,
            "iverilog_on_path": tools["iverilog"] is not None,
            "verilator_path": tools["verilator"] or "",
            "yosys_path": tools["yosys"] or "",
            "iverilog_path": tools["iverilog"] or "",
        },
        "execution": {
            "sim_executed": sim_result is not None,
            "synthesis_executed": yosys_result is not None,
            "sim_result": sim_result or {},
            "yosys_result": yosys_result or {},
            "mapped_utilization_result": mapped_result or {},
            "can_execute_sim_from_path": can_execute_sim,
            "can_score_synthesis_from_path": can_score_synthesis,
            "nix_sim_target": f".#{nix_target_prefix}-sv-sim",
            "nix_yosys_target": f".#{nix_target_prefix}-yosys-stat",
            "nix_mapped_utilization_target": f".#{nix_target_prefix}-utilization",
            "verilator_command_template": (
                "verilator --binary --timing --language 1800-2017 -Wno-fatal "
                f"-top {testbench_top} -Mdir /tmp/{object_dir_stem}_obj "
                f"-o sim_main {rtl_sources_text} {testbench_source}"
            ),
            "sim_binary_template": f"/tmp/{object_dir_stem}_obj/sim_main",
        },
        "vectors": {
            "activation_count": len(activations),
            "weight_count": len(weights),
            "expected_count": len(expected),
            "activation_sha256_i8_le": sha256_ints(activations, 1),
            "weight_sha256_i8_le": sha256_ints(weights, 1),
            "expected_sha256_i32_le": sha256_ints(expected, 4),
            "activation_preview": activations[:8],
            "weight_row0_preview": weights[:8],
            "expected_preview": expected[:8],
            "expected_min": min(expected),
            "expected_max": max(expected),
        },
        "acceptance_gates": {
            "functional": "Verilator or Icarus PASS line from the self-checking testbench",
            "synthesis": "Yosys stat with DSP > 0",
            "resource": "mapped LUT below the current float L0/L2 kernel class or a documented dequantization boundary change",
        },
        "interpretation": build_interpretation(
            sim_result,
            yosys_result,
            mapped_result,
            lane_count,
            packed_weight_words,
            local_packed_weight_memory,
            packed_weight_read_latency_cycles,
        ),
    }


def build_interpretation(
    sim_result: dict[str, object] | None,
    yosys_result: dict[str, object] | None,
    mapped_result: dict[str, object] | None,
    lane_count: int,
    packed_weight_words: int,
    local_packed_weight_memory: bool,
    packed_weight_read_latency_cycles: int,
) -> list[str]:
    lines = [
        "This is a bounded H2 fixed-point kernel proof, not a replay of the earlier f32-activation contract.",
        "It avoids the old torch-mlir int8 byte/char lowering route that blocked the prior L0 int8 probe.",
    ]
    if lane_count > 1:
        lines.append(
            f"It scales the standalone proof to {lane_count} parallel int8 MAC lanes sharing one controller."
        )
    if packed_weight_words > 0:
        lines.append(
            f"It uses {packed_weight_words} packed weight words so each cycle fetches one {lane_count}-lane weight vector."
        )
    if local_packed_weight_memory:
        lines.append(
            "It adds a loadable local packed-weight memory with "
            f"{packed_weight_read_latency_cycles} cycle read latency."
        )
    if sim_result is not None and sim_result.get("status") == "PASS":
        lines.append("Nix-provided Verilator simulation passed the deterministic self-checking testbench.")
    else:
        lines.append("The deterministic self-checking testbench is prepared but has not produced a PASS artifact.")
    if yosys_result is not None and yosys_result.get("dsp_gate_pass"):
        lines.append("Light Yosys synth_xilinx maps the bounded MAC datapath to at least one DSP cell.")
    elif yosys_result is not None:
        lines.append("Light Yosys synth_xilinx ran, but the DSP gate did not pass.")
    else:
        lines.append("Yosys/DSP scoring is still pending.")
    if mapped_result is not None:
        resources = mapped_result.get("resources", {})
        luts = (resources.get("clb_luts") or {}).get("used")
        ffs = (resources.get("clb_ffs") or {}).get("used")
        dsp = (resources.get("dsp") or {}).get("used")
        lines.append(
            f"Mapped JSON utilization reports {luts} CLB LUTs, {ffs} CLB FFs, and {dsp} DSP."
        )
    else:
        lines.append("Mapped JSON utilization scoring is still pending.")
    return lines


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit deterministic metadata for the Task 6 int8 GEMV RTL proof."
    )
    parser.add_argument(
        "--kernel-source",
        type=Path,
        default=Path("rtl/task6/task6_int8_gemv64_kernel.sv"),
    )
    parser.add_argument(
        "--extra-kernel-source",
        action="append",
        type=Path,
        default=[],
        help="Additional RTL source to compile before --kernel-source.",
    )
    parser.add_argument(
        "--testbench-source",
        type=Path,
        default=Path("sim/task6_int8_gemv64_tb_main.sv"),
    )
    parser.add_argument(
        "--artifact-name",
        default="h2-int8-gemv64-rtl-proof",
    )
    parser.add_argument(
        "--top-name",
        default="task6_int8_gemv64_kernel",
    )
    parser.add_argument(
        "--lane-count",
        type=int,
        default=1,
    )
    parser.add_argument(
        "--packed-weight-words",
        type=int,
        default=0,
    )
    parser.add_argument(
        "--local-packed-weight-memory",
        action="store_true",
    )
    parser.add_argument(
        "--packed-weight-read-latency-cycles",
        type=int,
        default=0,
    )
    parser.add_argument(
        "--nix-target-prefix",
        default="task6-int8-gemv64",
    )
    parser.add_argument("--out-json", type=Path)
    parser.add_argument(
        "--sim-result-json",
        type=Path,
        help="Optional JSON emitted by .#task6-int8-gemv64-sv-sim.",
    )
    parser.add_argument(
        "--yosys-stat-json",
        type=Path,
        help="Optional JSON emitted by .#task6-int8-gemv64-yosys-stat.",
    )
    parser.add_argument(
        "--mapped-utilization-summary-json",
        type=Path,
        help="Optional summary.json emitted by .#task6-int8-gemv64-utilization.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    payload = build_payload(
        args.artifact_name,
        args.kernel_source,
        args.extra_kernel_source,
        args.testbench_source,
        args.top_name,
        args.lane_count,
        args.packed_weight_words,
        args.local_packed_weight_memory,
        args.packed_weight_read_latency_cycles,
        args.nix_target_prefix,
        args.sim_result_json,
        args.yosys_stat_json,
        args.mapped_utilization_summary_json,
    )
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.out_json is None:
        print(text, end="")
    else:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
