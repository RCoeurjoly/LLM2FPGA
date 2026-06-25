#!/usr/bin/env python3
from __future__ import annotations

import json
import types
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.task6.backend_quantizer_graph_shape_probe import (
    audit_existing_graph,
    configure_quantizer_if_supported,
    load_pt2e_quantize_api,
    make_skip_report,
    main,
    run_probe_matrix,
)


def main_with_args(argv: list[str]) -> int:
    import sys

    with mock.patch.object(sys, "argv", ["backend_quantizer_graph_shape_probe.py", *argv]):
        return main()


class BackendQuantizerGraphShapeProbeTest(unittest.TestCase):
    def test_make_skip_report_has_stable_schema(self) -> None:
        report = make_skip_report(
            backend="nxp",
            quantizer="executorch.backends.nxp.quantizer.neutron_quantizer.NeutronQuantizer",
            reason="quantizer_not_importable",
            detail="ModuleNotFoundError: No module named 'executorch'",
        )

        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["status"], "skip")
        self.assertEqual(report["backend"], "nxp")
        self.assertEqual(report["skip_reason"], "quantizer_not_importable")
        self.assertIn("No module named 'executorch'", report["detail"])

    def test_audit_existing_graph_flags_dequant_linear(self) -> None:
        graph = """
        %dq_x = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%x,), kwargs={})
        %linear = call_function[target=torch.ops.aten.linear.default](args=(%dq_x, %w, %b), kwargs={})
        """

        report = audit_existing_graph(graph, backend="mock", quantizer="mock.Quantizer")

        self.assertEqual(report["status"], "fail")
        self.assertEqual(report["backend"], "mock")
        self.assertIn("float_linear_after_dequant", report["graph_shape_report"]["failure_reasons"])

    def test_cli_can_audit_existing_graph_without_torch(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            graph = tmp / "graph.fx.txt"
            graph.write_text(
                "%dq = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%x,), kwargs={})\n"
                "%linear = call_function[target=torch.ops.aten.linear.default](args=(%dq, %w, %b), kwargs={})\n",
                encoding="utf-8",
            )
            out = tmp / "report.json"

            rc = main_with_args(
                [
                    "--backend",
                    "mock",
                    "--quantizer",
                    "mock.Quantizer",
                    "--existing-graph",
                    str(graph),
                    "--out",
                    str(out),
                ]
            )

            self.assertEqual(rc, 0)
            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "fail")
            self.assertEqual(payload["graph_shape_report"]["op_counts"]["aten.linear"], 1)

    def test_load_pt2e_quantize_api_falls_back_to_torchao(self) -> None:
        torchao_module = types.SimpleNamespace(prepare_pt2e="prepare", convert_pt2e="convert")

        def import_module(name: str) -> object:
            if name == "torch.ao.quantization.quantize_pt2e":
                raise ModuleNotFoundError("No module named 'torch.ao.quantization.quantize_pt2e'")
            if name == "torchao.quantization.pt2e.quantize_pt2e":
                return torchao_module
            raise AssertionError(f"unexpected import: {name}")

        with mock.patch("scripts.task6.backend_quantizer_graph_shape_probe.importlib.import_module", side_effect=import_module):
            prepare_pt2e, convert_pt2e = load_pt2e_quantize_api()

        self.assertEqual(prepare_pt2e, "prepare")
        self.assertEqual(convert_pt2e, "convert")

    def test_configure_quantizer_uses_symmetric_config_when_available(self) -> None:
        class FakeQuantizer:
            def __init__(self) -> None:
                self.config = None

            def set_global(self, config: object) -> "FakeQuantizer":
                self.config = config
                return self

        module = types.SimpleNamespace(get_symmetric_quantization_config=lambda: "symmetric-config")
        quantizer = FakeQuantizer()

        with mock.patch("scripts.task6.backend_quantizer_graph_shape_probe.importlib.import_module", return_value=module):
            configured = configure_quantizer_if_supported(quantizer, "fake.backend.FakeQuantizer")

        self.assertIs(configured, quantizer)
        self.assertEqual(quantizer.config, "symmetric-config")

    def test_run_probe_matrix_runs_each_backend_quantizer_candidate(self) -> None:
        def fake_entrypoints(backend: str) -> list[str]:
            return {
                "xnnpack": ["xnnpack.Quantizer"],
                "example": ["example.QuantizerA", "example.QuantizerB"],
                "vulkan": [],
            }[backend]

        def fake_probe(*, backend: str, quantizer: str) -> dict[str, object]:
            return {
                "schema_version": 1,
                "backend": backend,
                "quantizer": quantizer,
                "status": "skip",
                "skip_reason": "mock",
                "detail": "mock",
                "graph_shape_report": None,
            }

        with (
            mock.patch(
                "scripts.task6.backend_quantizer_graph_shape_probe.backend_quantizer_entrypoints",
                side_effect=fake_entrypoints,
            ),
            mock.patch(
                "scripts.task6.backend_quantizer_graph_shape_probe.run_tiny_pt2e_probe",
                side_effect=fake_probe,
            ),
        ):
            report = run_probe_matrix(["xnnpack", "example", "vulkan"])

        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["status_counts"], {"skip": 3})
        self.assertEqual(
            [(item["backend"], item["quantizer"]) for item in report["probes"]],
            [
                ("xnnpack", "xnnpack.Quantizer"),
                ("example", "example.QuantizerA"),
                ("example", "example.QuantizerB"),
            ],
        )

    def test_cli_writes_aggregate_report_for_all_backends(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out = Path(tmpdir) / "matrix.json"

            with mock.patch(
                "scripts.task6.backend_quantizer_graph_shape_probe.run_probe_matrix",
                return_value={"schema_version": 1, "status_counts": {}, "probes": []},
            ):
                rc = main_with_args(["--all-backends", "--out", str(out)])

            self.assertEqual(rc, 0)
            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(payload["probes"], [])


if __name__ == "__main__":
    unittest.main()
