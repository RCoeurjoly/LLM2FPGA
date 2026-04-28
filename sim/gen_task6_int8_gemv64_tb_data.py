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


def summarize_yosys_stat(path: Path) -> dict[str, object]:
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
        "top": "task6_int8_gemv64_kernel",
        "num_cells": int(design.get("num_cells", 0)),
        "num_wires": int(design.get("num_wires", 0)),
        "num_wire_bits": int(design.get("num_wire_bits", 0)),
        "cells_by_type": cells_by_type,
        "dsp_cells": dsp_cells,
        "lut_cells": lut_cells,
        "ff_cells": ff_cells,
        "dsp_gate_pass": dsp_cells > 0,
    }


def build_payload(
    kernel_source: Path,
    testbench_source: Path,
    sim_result_json: Path | None,
    yosys_stat_json: Path | None,
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
        yosys_result = summarize_yosys_stat(yosys_stat_json)

    if (
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

    return {
        "artifact": "h2-int8-gemv64-rtl-proof",
        "status": status,
        "blocked_reason": blocked_reason,
        "rtl": {
            "kernel_source": str(kernel_source),
            "testbench_source": str(testbench_source),
            "contract": {
                "in_dim": IN_DIM,
                "out_dim": OUT_DIM,
                "activation_dtype": "int8",
                "weight_dtype": "int8",
                "accumulator_dtype": "int32",
                "weight_words": WEIGHT_WORDS,
                "macs": IN_DIM * OUT_DIM,
                "interface": "combinational address/data memories plus ready/valid output",
            },
        },
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
            "can_execute_sim_from_path": can_execute_sim,
            "can_score_synthesis_from_path": can_score_synthesis,
            "nix_sim_target": ".#task6-int8-gemv64-sv-sim",
            "nix_yosys_target": ".#task6-int8-gemv64-yosys-stat",
            "verilator_command_template": (
                "verilator --binary --timing --language 1800-2017 -Wno-fatal "
                "-top task6_int8_gemv64_tb -Mdir /tmp/task6_int8_gemv64_obj "
                "-o sim_main rtl/task6/task6_int8_gemv64_kernel.sv "
                "sim/task6_int8_gemv64_tb_main.sv"
            ),
            "sim_binary_template": "/tmp/task6_int8_gemv64_obj/sim_main",
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
        "interpretation": build_interpretation(sim_result, yosys_result),
    }


def build_interpretation(
    sim_result: dict[str, object] | None,
    yosys_result: dict[str, object] | None,
) -> list[str]:
    lines = [
        "This is a bounded H2 fixed-point kernel proof, not a replay of the earlier f32-activation contract.",
        "It avoids the old torch-mlir int8 byte/char lowering route that blocked the prior L0 int8 probe.",
    ]
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
        "--testbench-source",
        type=Path,
        default=Path("sim/task6_int8_gemv64_tb_main.sv"),
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    payload = build_payload(
        args.kernel_source,
        args.testbench_source,
        args.sim_result_json,
        args.yosys_stat_json,
    )
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.out_json is None:
        print(text, end="")
    else:
        args.out_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_json.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
