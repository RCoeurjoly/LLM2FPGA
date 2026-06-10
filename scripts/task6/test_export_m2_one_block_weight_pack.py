#!/usr/bin/env python3
"""Small tests for M2 one-block weight pack helpers."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


SCRIPT = Path(__file__).with_name("export_m2_one_block_weight_pack.py")
SPEC = importlib.util.spec_from_file_location("export_m2_one_block_weight_pack", SCRIPT)
assert SPEC is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["export_m2_one_block_weight_pack"] = MODULE
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class M2WeightPackHelperTest(unittest.TestCase):
    def test_selected_parameter_prefixes(self) -> None:
        prefixes = MODULE.selected_parameter_names(2)
        self.assertIn("transformer.wte.", prefixes)
        self.assertIn("transformer.wpe.", prefixes)
        self.assertIn("transformer.h.2.", prefixes)

    def test_safe_filename(self) -> None:
        self.assertEqual(
            MODULE.safe_filename("transformer.h.0.attn.weight"),
            "transformer__h__0__attn__weight.bin",
        )


if __name__ == "__main__":
    unittest.main()
