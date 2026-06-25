#!/usr/bin/env python3
from __future__ import annotations

import unittest

from audit import audit_graph_text


class AuditGraphTextTest(unittest.TestCase):
    def test_flags_qdq_wrapped_float_linear(self) -> None:
        report = audit_graph_text(
            """
            quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.linear.default
            quantized_decomposed.quantize_per_tensor.default
            """
        )

        self.assertEqual(report["status"], "fail")
        self.assertIn("float_linear_after_dequant", report["failure_reasons"])
        self.assertEqual(report["op_counts"]["aten.linear"], 1)

    def test_flags_bare_float_linear(self) -> None:
        report = audit_graph_text("torch.ops.aten.linear.default")

        self.assertEqual(report["status"], "fail")
        self.assertIn("float_linear_unquantized", report["failure_reasons"])

    def test_allows_graph_without_float_linear_or_matmul(self) -> None:
        report = audit_graph_text("torch.ops.quantized_decomposed.choose_qparams.tensor")

        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["failure_reasons"], [])


if __name__ == "__main__":
    unittest.main()
