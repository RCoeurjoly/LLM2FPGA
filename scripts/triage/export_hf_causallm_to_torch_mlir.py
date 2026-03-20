#!/usr/bin/env python3
"""Export a Hugging Face causal LM to Torch-MLIR."""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
from torch_mlir.fx import export_and_import
from transformers import AutoModelForCausalLM


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    model = parser.add_mutually_exclusive_group(required=True)
    model.add_argument("--model-id", help="Hugging Face model id")
    model.add_argument(
        "--model-path",
        help="Local path to a pinned model snapshot",
    )
    parser.add_argument(
        "--revision",
        default="main",
        help="Pinned model revision/commit",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output path for exported torch-MLIR",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1,
        help="Dummy batch size used for export",
    )
    parser.add_argument(
        "--seq-len",
        type=int,
        default=1,
        help="Dummy sequence length used for export",
    )
    parser.add_argument(
        "--dtype",
        choices=("float32", "float16", "bfloat16"),
        default="float32",
        help="Requested model dtype",
    )
    parser.add_argument(
        "--attn-implementation",
        default="eager",
        help='Value for from_pretrained(attn_implementation=...). Use "auto" to skip.',
    )
    parser.add_argument(
        "--trust-remote-code",
        action="store_true",
        help="Enable trust_remote_code for custom model classes",
    )
    parser.add_argument(
        "--local-files-only",
        action="store_true",
        help="Disable network usage in from_pretrained",
    )
    parser.add_argument(
        "--strict-export",
        action="store_true",
        help="Use strict=True in torch.export.export",
    )
    return parser.parse_args()


def dtype_from_arg(name: str) -> torch.dtype:
    if name == "float16":
        return torch.float16
    if name == "bfloat16":
        return torch.bfloat16
    return torch.float32


def main() -> int:
    args = parse_args()
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    model_kwargs = {
        "use_cache": False,
        "trust_remote_code": args.trust_remote_code,
        "local_files_only": args.local_files_only,
        "torch_dtype": dtype_from_arg(args.dtype),
    }
    model_ref = args.model_id
    if args.model_path:
        model_ref = args.model_path
    else:
        model_kwargs["revision"] = args.revision
    if args.attn_implementation != "auto":
        model_kwargs["attn_implementation"] = args.attn_implementation

    model = AutoModelForCausalLM.from_pretrained(model_ref, **model_kwargs).eval()

    class CausalLmWrapper(torch.nn.Module):
        def __init__(self, core: torch.nn.Module):
            super().__init__()
            self.core = core

        def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
            return self.core(input_ids).logits

    wrapper = CausalLmWrapper(model).eval()
    input_ids = torch.zeros((args.batch_size, args.seq_len), dtype=torch.long)

    with torch.no_grad():
        exported = torch.export.export(
            wrapper,
            (input_ids,),
            strict=args.strict_export,
        )
        mlir_module = export_and_import(exported)

    out_path.write_text(str(mlir_module), encoding="utf-8")
    print(out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
