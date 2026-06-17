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
        q, scales = MODULE.quantize_rowwise_symmetric(values, 2, 3, 8)
        self.assertEqual(q[:3], [0, 127, -127])
        self.assertEqual(q[3:], [0, 0, 127])
        self.assertAlmostEqual(scales[0], 1.0 / 127.0)
        self.assertAlmostEqual(scales[1], 2.0 / 127.0)

    def test_quantize_rowwise_symmetric_int4_row_shapes(self) -> None:
        values = array("f", [1.0, -1.0, 0.0, 2.0])
        q, scales = MODULE.quantize_rowwise_symmetric(values, 2, 2, 4)
        self.assertEqual(q, [7, -7, 0, 7])
        self.assertEqual(scales, [1.0 / 7.0, 2.0 / 7.0])

    def test_pack_int4_nibble_order(self) -> None:
        packed = MODULE.pack_int4([0, 7, -1, -8, 2, -2])
        self.assertEqual(packed, [0x70, 0x8F, 0x02])

    def test_pack_ternary2_code_density(self) -> None:
        packed = MODULE.pack_ternary2([1, -1, 0, 1, -1, 0])
        self.assertEqual(packed, [0x49, 0x02])

    def test_quantize_rowwise_ternary_default(self) -> None:
        values = array("f", [0.5, -0.5, 0.1, -0.1, 0.0, 0.05])
        q, scales, thresholds = MODULE.quantize_rowwise_ternary(
            values,
            2,
            3,
            threshold_factor=0.25,
            scale_mode="least_squares",
        )
        self.assertEqual(q, [1, -1, 1, -1, 0, 1])
        self.assertEqual(thresholds[0], 0.09166666666666667)
        self.assertEqual(thresholds[1], 0.012500000000000002)
        self.assertAlmostEqual(scales[0], 1.1 / 3.0)
        self.assertAlmostEqual(scales[1], 0.15 / 2.0)

    def test_safe_filename(self) -> None:
        self.assertEqual(
            MODULE.safe_filename("transformer.h.0.weight", "__rowwise_i8.bin"),
            "transformer__h__0__weight__rowwise_i8.bin",
        )


if __name__ == "__main__":
    unittest.main()
