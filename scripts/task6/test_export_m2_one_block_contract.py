#!/usr/bin/env python3
"""Small tests for M2 one-block contract helpers."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


SCRIPT = Path(__file__).with_name("export_m2_one_block_contract.py")
SPEC = importlib.util.spec_from_file_location("export_m2_one_block_contract", SCRIPT)
assert SPEC is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules["export_m2_one_block_contract"] = MODULE
assert SPEC.loader is not None
try:
    SPEC.loader.exec_module(MODULE)
except ModuleNotFoundError as exc:
    if exc.name not in {"torch", "transformers"}:
        raise
    MODULE = None


@unittest.skipIf(MODULE is None, "torch/transformers unavailable in base Python")
class M2ContractHelperTest(unittest.TestCase):
    def test_context_steps_prefers_q024_context(self) -> None:
        reference = {
            "artifact_name": "test",
            "steps": [
                {
                    "step": 3,
                    "q024_context_token_ids": [1, 2, 3],
                    "f32_context_token_ids": [9],
                    "q024_topk_token_ids": [4],
                }
            ],
        }
        steps = MODULE.context_steps(reference, None)
        self.assertEqual(steps[0]["step"], 3)
        self.assertEqual(steps[0]["context_token_ids"], [1, 2, 3])
        self.assertEqual(steps[0]["expected_next_token"], 4)

    def test_context_steps_rejects_empty_reference(self) -> None:
        with self.assertRaises(SystemExit):
            MODULE.context_steps({"steps": []}, None)


if __name__ == "__main__":
    unittest.main()
