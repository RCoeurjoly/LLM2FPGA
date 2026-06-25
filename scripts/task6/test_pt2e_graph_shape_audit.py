#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "scripts" / "task6" / "pt2e_graph_shape_audit.py"


class GraphShapeAuditTest(unittest.TestCase):
    def test_float_matmul_after_dequant_is_nonstructural(self) -> None:
        from scripts.task6.pt2e_graph_shape_audit import audit_graph_text

        graph = textwrap.dedent(
            """
            torch.ops.quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.matmul.default
            torch.ops.quantized_decomposed.quantize_per_tensor.default
            torch.ops.aten.layer_norm.default
            torch.ops.aten.tanh.default
            """
        )

        report = audit_graph_text(graph, model_label="synthetic-qdfloat")

        self.assertEqual(report["status"], "fail")
        self.assertIn("float_matmul_after_dequant", report["failure_reasons"])
        self.assertIn("float_layer_norm", report["failure_reasons"])
        self.assertIn("float_gelu_or_tanh", report["failure_reasons"])
        self.assertEqual(report["op_counts"]["aten.matmul"], 1)
        self.assertEqual(
            report["op_counts"]["quantized_decomposed.dequantize_per_tensor"],
            1,
        )

    def test_integer_like_graph_passes_without_float_critical_ops(self) -> None:
        from scripts.task6.pt2e_graph_shape_audit import audit_graph_text

        graph = textwrap.dedent(
            """
            torch.ops.aten.mm.default
            torch.ops.aten.add.Tensor
            torch.ops.aten.clamp.default
            torch.ops.aten.to.dtype
            """
        )

        report = audit_graph_text(graph, model_label="synthetic-intlike")

        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["failure_reasons"], [])
        self.assertEqual(report["critical_float_ops"], [])

    def test_flags_float_linear_after_dequant_separately_from_matmul(self) -> None:
        from scripts.task6.pt2e_graph_shape_audit import audit_graph_text

        graph = textwrap.dedent(
            """
            %dq_x = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%x,), kwargs={})
            %dq_w = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%w,), kwargs={})
            %linear = call_function[target=torch.ops.aten.linear.default](args=(%dq_x, %dq_w, %bias), kwargs={})
            %q = call_function[target=torch.ops.quantized_decomposed.quantize_per_tensor.default](args=(%linear,), kwargs={})
            """
        )

        report = audit_graph_text(graph, model_label="linear-q dq")

        self.assertEqual(report["status"], "fail")
        self.assertIn("float_linear_after_dequant", report["failure_reasons"])
        self.assertNotIn("float_matmul_after_dequant", report["failure_reasons"])
        self.assertEqual(report["op_counts"]["aten.linear"], 1)

    def test_cli_writes_json_and_markdown(self) -> None:
        graph = (
            "torch.ops.quantized_decomposed.dequantize_per_tensor.default\n"
            "torch.ops.aten.matmul.default\n"
        )

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            graph_path = tmp / "graph.fx.txt"
            json_path = tmp / "report.json"
            md_path = tmp / "report.md"
            graph_path.write_text(graph, encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(CLI),
                    "--graph",
                    str(graph_path),
                    "--json-out",
                    str(json_path),
                    "--markdown-out",
                    str(md_path),
                    "--model-label",
                    "cli-smoke",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertEqual(report["model_label"], "cli-smoke")
            self.assertIn("float_matmul_after_dequant", report["failure_reasons"])
            self.assertIn("# PT2E Graph Shape Audit", md_path.read_text(encoding="utf-8"))

    def test_cli_gate_exits_nonzero_on_nonstructural_graph(self) -> None:
        graph = (
            "torch.ops.quantized_decomposed.dequantize_per_tensor.default\n"
            "torch.ops.aten.matmul.default\n"
        )

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            graph_path = tmp / "graph.fx.txt"
            json_path = tmp / "report.json"
            graph_path.write_text(graph, encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(CLI),
                    "--graph",
                    str(graph_path),
                    "--json-out",
                    str(json_path),
                    "--model-label",
                    "gate-smoke",
                    "--fail-on-nonstructural",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(completed.returncode, 2)
            self.assertIn("non-structural PT2E graph", completed.stderr)


if __name__ == "__main__":
    unittest.main()
