#!/usr/bin/env python3
"""Unit tests for the PyTorch model manifest compiler."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


SCRIPT = Path(__file__).with_name("llm2fpga_model_manifest.py")


class ModelManifestCliTest(unittest.TestCase):
    def test_fake_gpt_adapter_emits_scaling_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            adapter = tmp / "fake_adapter.py"
            adapter.write_text(
                textwrap.dedent(
                    """
                    class Config:
                        def to_dict(self):
                            return {
                                "vocab_size": 128,
                                "n_embd": 16,
                                "n_layer": 1,
                                "n_head": 2,
                                "n_positions": 32,
                            }

                    class FakeTensor:
                        dtype = "float32"

                        def __init__(self, shape):
                            self.shape = shape

                        def detach(self):
                            return self

                        def cpu(self):
                            return self

                        def contiguous(self):
                            return self

                        def numel(self):
                            total = 1
                            for dim in self.shape:
                                total *= dim
                            return total

                        def element_size(self):
                            return 4

                    class FakeModule:
                        def __init__(self, name="", params=None, children=None):
                            self.name = name
                            self.params = params or []
                            self.children = children or []

                        def eval(self):
                            return self

                        def named_parameters(self, recurse=True):
                            for name, param in self.params:
                                yield name, param
                            if recurse:
                                for child_name, child in self.children:
                                    for name, param in child.named_parameters(recurse=True):
                                        yield f"{child_name}.{name}", param

                        def named_modules(self):
                            yield "", self
                            for child_name, child in self.children:
                                yield child_name, child
                                for nested_name, nested in child.named_modules():
                                    if nested_name:
                                        yield f"{child_name}.{nested_name}", nested

                    class FakeGPT(FakeModule):
                        def __init__(self):
                            self.config = Config()
                            super().__init__(
                                children=[
                                    ("transformer.wte", FakeModule(params=[("weight", FakeTensor((128, 16)))])),
                                    ("transformer.h.0.ln_1", FakeModule(params=[("weight", FakeTensor((16,)))])),
                                    ("transformer.h.0.mlp.c_fc", FakeModule(params=[("weight", FakeTensor((64, 16))), ("bias", FakeTensor((64,)))])),
                                    ("transformer.h.0.mlp.c_proj", FakeModule(params=[("weight", FakeTensor((16, 64))), ("bias", FakeTensor((16,)))])),
                                    ("lm_head", FakeModule(params=[("weight", FakeTensor((128, 16)))])),
                                ]
                            )

                    def build_model(model_path):
                        return FakeGPT()
                    """
                ),
                encoding="utf-8",
            )
            out_json = tmp / "manifest.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--model-path",
                    str(tmp / "model"),
                    "--adapter-path",
                    str(adapter),
                    "--model-label",
                    "fake-gpt",
                    "--out-json",
                    str(out_json),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

            manifest = json.loads(out_json.read_text(encoding="utf-8"))
            self.assertEqual(manifest["artifact_name"], "llm2fpga-pytorch-model-manifest")
            self.assertEqual(manifest["family_check"]["status"], "supported")
            self.assertEqual(manifest["dimensions"]["vocab_size"], 128)
            self.assertEqual(manifest["dimensions"]["hidden_size"], 16)
            self.assertEqual(manifest["dimensions"]["num_layers"], 1)
            self.assertGreater(manifest["dimensions"]["parameter_count"], 0)
            self.assertIn("DDR3 model/row movement", manifest["target_board_contract"]["fpga"])
            self.assertIn("quantized-weight-pack", manifest["next_artifact_stages"])

    def test_missing_adapter_build_model_fails_clearly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            adapter = tmp / "bad_adapter.py"
            adapter.write_text("VALUE = 1\n", encoding="utf-8")
            out_json = tmp / "manifest.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--model-path",
                    str(tmp / "model"),
                    "--adapter-path",
                    str(adapter),
                    "--model-label",
                    "bad",
                    "--out-json",
                    str(out_json),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("build_model", completed.stderr)


if __name__ == "__main__":
    unittest.main()
