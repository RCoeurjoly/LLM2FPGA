#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.task6.executorch_backend_survey import (
    BACKEND_CANDIDATES,
    classify_backend,
    classify_graph_transparency,
    attempt_backend_imports,
    inventory_backends,
    main,
    make_report_entry,
    validate_report_entry,
)


def main_with_args(argv: list[str]) -> int:
    import sys

    with mock.patch.object(sys, "argv", ["executorch_backend_survey.py", *argv]):
        return main()


class BackendSurveySchemaTest(unittest.TestCase):
    def test_candidate_order_starts_with_locally_useful_backends(self) -> None:
        self.assertEqual(BACKEND_CANDIDATES[:4], ["xnnpack", "example", "test", "vulkan"])

    def test_xnnpack_classification_is_local_first(self) -> None:
        info = classify_backend("xnnpack")
        self.assertEqual(info["backend"], "xnnpack")
        self.assertFalse(info["requires_hardware"])
        self.assertIn("executorch.backends.xnnpack", info["python_entrypoints"][0])

    def test_vendor_backend_classification_is_sdk_gated(self) -> None:
        info = classify_backend("qualcomm")
        self.assertEqual(info["backend"], "qualcomm")
        self.assertTrue(info["requires_sdk"])

    def test_report_entry_contains_required_keys(self) -> None:
        entry = make_report_entry("xnnpack", status="skip", skip_reason="executorch_not_importable")
        validate_report_entry(entry)
        self.assertEqual(entry["status"], "skip")
        self.assertEqual(entry["torch_mlir_status"], "skip")
        self.assertEqual(entry["graph_transparency"], "unknown")

    def test_delegate_call_marks_graph_opaque(self) -> None:
        transparency = classify_graph_transparency("executorch_call_delegate(lowered_module_0, arg0)")

        self.assertEqual(transparency, "opaque")

    def test_aten_graph_marks_graph_transparent(self) -> None:
        graph = "%mm = call_function[target=torch.ops.aten.mm.default](args=(%x, %w), kwargs={})"

        self.assertEqual(classify_graph_transparency(graph), "transparent")

    def test_inventory_backends_skips_when_module_is_unavailable(self) -> None:
        with mock.patch("scripts.task6.executorch_backend_survey.module_available", return_value=False):
            entries = inventory_backends(["xnnpack"])

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["backend"], "xnnpack")
        self.assertEqual(entries[0]["status"], "skip")
        self.assertEqual(entries[0]["skip_reason"], "executorch_xnnpack_not_importable")

    def test_inventory_backends_skips_when_module_lookup_raises_missing_parent(self) -> None:
        def raise_missing_parent(module_name: str) -> bool:
            raise ModuleNotFoundError("No module named 'executorch'")

        with mock.patch("importlib.import_module", side_effect=raise_missing_parent):
            entries = inventory_backends(["xnnpack"])

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["backend"], "xnnpack")
        self.assertEqual(entries[0]["status"], "skip")
        self.assertEqual(entries[0]["skip_reason"], "executorch_xnnpack_not_importable")

    def test_inventory_backends_skips_when_module_import_raises_runtime_error(self) -> None:
        def raise_runtime_error(module_name: str) -> bool:
            raise RuntimeError("backend import failed during initialization")

        with mock.patch("importlib.import_module", side_effect=raise_runtime_error):
            entries = inventory_backends(["example"])

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["backend"], "example")
        self.assertEqual(entries[0]["status"], "skip")
        self.assertEqual(entries[0]["skip_reason"], "executorch_backend_not_importable")

    def test_inventory_backends_uses_xnnpack_probe_when_partitioner_is_available(self) -> None:
        with mock.patch("scripts.task6.executorch_backend_survey.module_available", return_value=True):
            entries = inventory_backends(["xnnpack"])

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["backend"], "xnnpack")
        self.assertEqual(entries[0]["status"], "skip")
        self.assertEqual(entries[0]["skip_reason"], "xnnpack_probe_requires_executorch_runtime_wiring")
        self.assertEqual(entries[0]["graph_transparency"], "unknown")

    def test_attempt_backend_imports_reports_missing_modules_as_unavailable(self) -> None:
        result = attempt_backend_imports(["definitely_missing_backend_module_xyz"])
        self.assertFalse(result["available"])
        self.assertEqual(result["available_modules"], [])

    def test_attempt_backend_imports_reports_available_modules(self) -> None:
        result = attempt_backend_imports(["json"])
        self.assertTrue(result["available"])
        self.assertEqual(result["available_modules"], ["json"])

    def test_inventory_backends_reports_generic_backend_import_only_probe(self) -> None:
        def module_available(module_name: str) -> bool:
            return module_name == "executorch.backends.example"

        with mock.patch("scripts.task6.executorch_backend_survey.module_available", side_effect=module_available):
            entries = inventory_backends(["example"])

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["backend"], "example")
        self.assertEqual(entries[0]["status"], "skip")
        self.assertEqual(entries[0]["skip_reason"], "backend_lowering_probe_not_connected")
        self.assertEqual(entries[0]["python_entrypoints"], ["executorch.backends.example"])


class BackendSurveyCliTest(unittest.TestCase):
    def test_cli_writes_inventory_report_for_selected_backend(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out = Path(tmpdir) / "survey.json"
            with mock.patch("scripts.task6.executorch_backend_survey.module_available", return_value=False):
                rc = main_with_args(["--backend", "xnnpack", "--out", str(out)])
            self.assertEqual(rc, 0)
            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(len(payload["backends"]), 1)
            self.assertEqual(payload["backends"][0]["backend"], "xnnpack")
            self.assertEqual(payload["backends"][0]["status"], "skip")
            self.assertEqual(payload["backends"][0]["skip_reason"], "executorch_xnnpack_not_importable")


if __name__ == "__main__":
    unittest.main()
