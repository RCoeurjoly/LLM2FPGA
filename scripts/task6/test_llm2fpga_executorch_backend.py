#!/usr/bin/env python3
"""Tests for the LLM2FPGA ExecuTorch-style backend manifest path."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "src" / "llm2fpga_executorch_backend" / "cli.py"


class ManifestValidationTest(unittest.TestCase):
    def test_complete_manifest_validates(self) -> None:
        from src.llm2fpga_executorch_backend.manifest import validate_manifest

        manifest = {
            "schema_version": 1,
            "backend_id": "llm2fpga.executorch",
            "model_label": "tiny-stories-1m-representative-core-pt2e-static-w2a2-nolsq",
            "representative_core_dimensions": {
                "vocab_size": 32,
                "num_layers": 2,
                "hidden_size": 2,
                "num_heads": 1,
                "max_position_embeddings": 4,
                "window_size": 2,
            },
            "ops": [
                {
                    "id": "op0",
                    "family": "fpga.quantized_matmul",
                    "source_ops": ["aten.matmul.default"],
                    "kernel_id": "qmatmul.v1",
                }
            ],
            "quant_params": {"activation_bits": 2, "weight_bits": 2},
            "tensor_metadata": [],
            "tiling_hints": {"target": "representative-core-min"},
            "kernel_ids": {
                "fpga.quantized_matmul": "qmatmul.v1",
                "fpga.layer_norm": "layer_norm.v1",
                "fpga.softmax_or_attention": "attention.v1",
                "fpga.gelu": "gelu.v1",
            },
            "unmatched_core_ops": [],
        }

        validate_manifest(manifest)

    def test_missing_required_field_is_rejected(self) -> None:
        from src.llm2fpga_executorch_backend.manifest import ManifestError, validate_manifest

        with self.assertRaisesRegex(ManifestError, "model_label"):
            validate_manifest(
                {
                    "schema_version": 1,
                    "backend_id": "llm2fpga.executorch",
                    "representative_core_dimensions": {},
                    "ops": [],
                    "quant_params": {},
                    "tensor_metadata": [],
                    "tiling_hints": {},
                    "kernel_ids": {},
                    "unmatched_core_ops": [],
                }
            )

    def test_unknown_op_family_is_rejected(self) -> None:
        from src.llm2fpga_executorch_backend.manifest import ManifestError, validate_manifest

        with self.assertRaisesRegex(ManifestError, "fpga.unknown"):
            validate_manifest(
                {
                    "schema_version": 1,
                    "backend_id": "llm2fpga.executorch",
                    "model_label": "bad",
                    "representative_core_dimensions": {},
                    "ops": [{"id": "op0", "family": "fpga.unknown"}],
                    "quant_params": {},
                    "tensor_metadata": [],
                    "tiling_hints": {},
                    "kernel_ids": {},
                    "unmatched_core_ops": [],
                }
            )


class PatternCaptureTest(unittest.TestCase):
    def test_cli_captures_all_required_representative_core_families(self) -> None:
        graph = textwrap.dedent(
            """
            quantized_decomposed.dequantize_per_tensor.default
            aten.matmul.default
            quantized_decomposed.quantize_per_tensor.default
            quantized_decomposed.dequantize_per_tensor.default
            aten.layer_norm.default
            quantized_decomposed.quantize_per_tensor.default
            aten.mul.Tensor
            aten.tanh.default
            quantized_decomposed.quantize_per_tensor.default
            aten.softmax.int
            aten.matmul.default
            quantized_decomposed.quantize_per_tensor.default
            """
        ).strip()

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            graph_path = tmp / "quantized.fx.txt"
            graph_path.write_text(graph, encoding="utf-8")
            out_dir = tmp / "out"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(CLI),
                    "--graph",
                    str(graph_path),
                    "--out-dir",
                    str(out_dir),
                    "--model-label",
                    "tiny-stories-1m-representative-core-pt2e-static-w2a2-nolsq",
                    "--require-representative-core",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            manifest = json.loads((out_dir / "manifest.json").read_text(encoding="utf-8"))
            families = {op["family"] for op in manifest["ops"]}
            self.assertEqual(
                families,
                {
                    "fpga.quantized_matmul",
                    "fpga.layer_norm",
                    "fpga.softmax_or_attention",
                    "fpga.gelu",
                },
            )
            self.assertEqual(manifest["unmatched_core_ops"], [])

    def test_cli_fails_before_handshake_when_core_ops_are_unmatched(self) -> None:
        graph = "aten.matmul.default\naten.layer_norm.default\n"

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            graph_path = tmp / "bad.fx.txt"
            graph_path.write_text(graph, encoding="utf-8")
            out_dir = tmp / "out"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(CLI),
                    "--graph",
                    str(graph_path),
                    "--out-dir",
                    str(out_dir),
                    "--model-label",
                    "bad-core",
                    "--require-representative-core",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertNotEqual(completed.returncode, 0)
            unmatched = json.loads((out_dir / "unmatched_core_ops.json").read_text(encoding="utf-8"))
            names = {item["op"] for item in unmatched["unmatched_core_ops"]}
            self.assertIn("aten.matmul", names)
            self.assertIn("aten.layer_norm", names)

    def test_attention_capture_covers_score_and_value_matmuls(self) -> None:
        from src.llm2fpga_executorch_backend.patterns import capture_backend_ops

        graph = textwrap.dedent(
            """
            torch.ops.quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.matmul.default
            torch.ops.aten.where.self
            torch.ops.aten.slice.Tensor
            torch.ops.aten.add.Tensor
            torch.ops.aten.clone.default
            torch.ops.quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.softmax.int
            torch.ops.aten.matmul.default
            torch.ops.quantized_decomposed.quantize_per_tensor.default
            """
        ).strip()

        ops, unmatched = capture_backend_ops(graph)

        self.assertIn("fpga.softmax_or_attention", {op["family"] for op in ops})
        self.assertEqual(unmatched, [])

    def test_attention_capture_accepts_value_matmul_without_post_quant_marker(self) -> None:
        from src.llm2fpga_executorch_backend.patterns import capture_backend_ops

        graph = textwrap.dedent(
            """
            torch.ops.quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.matmul.default
            torch.ops.aten.where.self
            torch.ops.aten.slice.Tensor
            torch.ops.quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.softmax.int
            torch.ops.aten.dropout.default
            torch.ops.quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.matmul.default
            torch.ops.aten.view.default
            """
        ).strip()

        ops, unmatched = capture_backend_ops(graph)

        self.assertIn("fpga.softmax_or_attention", {op["family"] for op in ops})
        self.assertEqual(unmatched, [])


class TorchMlirSurrogateTest(unittest.TestCase):
    def test_backend_manifest_defines_compact_surrogate_value(self) -> None:
        from src.llm2fpga_executorch_backend.torch_mlir_surrogate import (
            backend_surrogate_value,
        )

        value = backend_surrogate_value(
            {
                "ops": [
                    {"family": "fpga.quantized_matmul"},
                    {"family": "fpga.layer_norm"},
                    {"family": "fpga.softmax_or_attention"},
                ],
                "unmatched_core_ops": [],
            }
        )

        self.assertEqual(value, 3)


if __name__ == "__main__":
    unittest.main()
