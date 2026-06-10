#!/usr/bin/env python3
"""Unit tests for M2 ln1/qkv lowering score helpers."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


SCRIPT = Path(__file__).with_name("score_m2_ln1_qkv_lowering.py")
SPEC = importlib.util.spec_from_file_location("score_m2_ln1_qkv_lowering", SCRIPT)
assert SPEC is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["score_m2_ln1_qkv_lowering"] = MODULE
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ScoreM2Ln1QkvTest(unittest.TestCase):
    def test_layernorm_zero_mean_unit_scale(self) -> None:
        rows = [[1.0, 2.0, 3.0, 4.0]]
        out = MODULE.layernorm_rows(rows, [1.0] * 4, [0.0] * 4)[0]
        self.assertAlmostEqual(sum(out), 0.0, places=6)

    def test_quantize_row_i8(self) -> None:
        q, scale = MODULE.quantize_row_i8([-2.0, 0.0, 1.0])
        self.assertEqual(q, [-127, 0, 64])
        self.assertAlmostEqual(scale, 2.0 / 127.0)

    def test_metrics_zero_error(self) -> None:
        result = MODULE.metrics([1.0, 2.0], [1.0, 2.0])
        self.assertEqual(result["rmse"], 0.0)
        self.assertEqual(result["normalized_rmse"], 0.0)


if __name__ == "__main__":
    unittest.main()
