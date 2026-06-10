#!/usr/bin/env python3
"""Unit tests for M2 one-block weight quantization helpers."""

from __future__ import annotations

from array import array
import importlib.util
from pathlib import Path
import sys
import unittest


SCRIPT = Path(__file__).with_name("quantize_m2_one_block_weight_pack.py")
SPEC = importlib.util.spec_from_file_location("quantize_m2_one_block_weight_pack", SCRIPT)
assert SPEC is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["quantize_m2_one_block_weight_pack"] = MODULE
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class QuantizeM2WeightPackTest(unittest.TestCase):
    def test_rowwise_quantization_uses_independent_scales(self) -> None:
        values = array("f", [0.0, 1.0, -1.0, 0.0, 0.0, 2.0])
        q, scales = MODULE.quantize_rowwise(values, 2, 3)
        self.assertEqual(q[:3], [0, 127, -127])
        self.assertEqual(q[3:], [0, 0, 127])
        self.assertAlmostEqual(scales[0], 1.0 / 127.0)
        self.assertAlmostEqual(scales[1], 2.0 / 127.0)

    def test_safe_filename(self) -> None:
        self.assertEqual(
            MODULE.safe_filename("transformer.h.0.weight", "__rowwise_i8.bin"),
            "transformer__h__0__weight__rowwise_i8.bin",
        )


if __name__ == "__main__":
    unittest.main()
