#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare a hardware-observed matmul output against the fixed "
            "Task-2 golden reference."
        )
    )
    parser.add_argument(
        "--vectors",
        type=Path,
        default=Path(__file__).parent / "test_vectors.json",
        help="Path to test vector JSON (default: sim/test_vectors.json).",
    )
    parser.add_argument(
        "--got",
        type=str,
        help="Observed hardware output value (supports decimal or 0x... form).",
    )
    parser.add_argument(
        "--got-json",
        type=Path,
        help="JSON file containing observed output value.",
    )
    parser.add_argument(
        "--got-key",
        default="got",
        help="Key used with --got-json (default: got).",
    )
    parser.add_argument(
        "--print-expected",
        action="store_true",
        help="Only print the expected golden value and exit.",
    )
    return parser.parse_args()


def to_i32(value: int) -> int:
    value &= 0xFFFFFFFF
    if value >= 0x80000000:
        value -= 0x100000000
    return value


def load_vectors(path: Path) -> tuple[list[int], list[int]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("dtype") != "int32":
        raise ValueError(f"Expected dtype=int32, got {payload.get('dtype')!r}")
    if payload.get("shape") != [16]:
        raise ValueError(f"Expected shape [16], got {payload.get('shape')!r}")
    a = payload.get("a")
    b = payload.get("b")
    if not isinstance(a, list) or not isinstance(b, list):
        raise ValueError("Expected keys 'a' and 'b' to be lists")
    if len(a) != 16 or len(b) != 16:
        raise ValueError("Expected exactly 16 elements in each of 'a' and 'b'")
    return [int(x) for x in a], [int(x) for x in b]


def expected_from_int32_dot(a: list[int], b: list[int]) -> int:
    acc = 0
    for x, y in zip(a, b):
        prod = to_i32(to_i32(x) * to_i32(y))
        acc = to_i32(acc + prod)
    return acc


def expected_from_torch(a: list[int], b: list[int]) -> int | None:
    try:
        import torch  # type: ignore
    except Exception:
        return None

    # Import the local helper only when torch is available.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        from sim_utils import load_matmul_module  # type: ignore

        MatmulModule = load_matmul_module()
        module = MatmulModule().eval()
        ta = torch.tensor(a, dtype=torch.int32)
        tb = torch.tensor(b, dtype=torch.int32)
        with torch.no_grad():
            return int(module(ta, tb).item())
    except Exception:
        return None


def parse_got_value(args: argparse.Namespace) -> int | None:
    if args.got is not None:
        return int(args.got, 0)

    if args.got_json is not None:
        payload: dict[str, Any] = json.loads(args.got_json.read_text(encoding="utf-8"))
        if args.got_key not in payload:
            raise KeyError(f"Key {args.got_key!r} not found in {args.got_json}")
        return int(payload[args.got_key])

    return None


def main() -> int:
    args = parse_args()
    a, b = load_vectors(args.vectors)

    expected_int32 = expected_from_int32_dot(a, b)
    expected_torch = expected_from_torch(a, b)

    if expected_torch is not None and expected_torch != expected_int32:
        raise RuntimeError(
            "Torch and int32-dot golden mismatch: "
            f"torch={expected_torch}, int32={expected_int32}"
        )

    expected = expected_torch if expected_torch is not None else expected_int32
    source = "torch" if expected_torch is not None else "int32-dot-fallback"

    if args.print_expected:
        print(json.dumps({"expected": expected, "source": source}, indent=2))
        return 0

    got = parse_got_value(args)
    if got is None:
        raise ValueError("Provide --got or --got-json, or use --print-expected.")

    got = to_i32(got)
    status = "PASS" if got == expected else "FAIL"
    print(
        json.dumps(
            {"status": status, "expected": expected, "got": got, "source": source},
            indent=2,
        )
    )
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
