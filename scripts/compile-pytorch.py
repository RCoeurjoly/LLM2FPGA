#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import sys
from types import ModuleType

from torch_mlir.fx import export_and_import
import torch


def load_adapter(path: Path) -> ModuleType:
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location(path.stem, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load adapter module from {path}")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    finally:
        try:
            sys.path.remove(str(path.parent))
        except ValueError:
            pass
    return module


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compile a PyTorch model adapter into torch-mlir text."
    )
    parser.add_argument("--adapter", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--model-path")
    parser.add_argument(
        "--output-type",
        choices=("raw", "torch"),
        default="torch",
        help="torch-mlir import stage to emit",
    )
    args = parser.parse_args()

    adapter = load_adapter(args.adapter)

    build_mlir_module = getattr(adapter, "build_mlir_module", None)
    if build_mlir_module is not None:
        module_or_text = build_mlir_module(args.model_path, args.output_type)
        mlir_text = str(module_or_text)
        args.out.write_text(mlir_text, encoding="utf-8")
        print(mlir_text)
        return

    export_program = getattr(adapter, "export_program", None)
    if export_program is not None:
        exported = export_program(args.model_path)
    else:
        build_model = getattr(adapter, "build_model", None)
        example_inputs = getattr(adapter, "example_inputs", None)
        if build_model is None or example_inputs is None:
            raise SystemExit(
                f"{args.adapter} must define export_program(model_path) or "
                "build_model(model_path) plus example_inputs()"
            )

        model = build_model(args.model_path).eval()
        exported = torch.export.export(
            model,
            tuple(example_inputs()),
            strict=getattr(adapter, "EXPORT_STRICT", True),
        )
    module = export_and_import(exported, output_type=args.output_type)
    mlir_text = str(module)
    args.out.write_text(mlir_text, encoding="utf-8")
    print(mlir_text)


if __name__ == "__main__":
    main()
