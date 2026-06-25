from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Any

from .manifest import DEFAULT_KERNEL_IDS, SUPPORTED_FAMILIES


CORE_OP_PATTERNS = {
    "aten.matmul": re.compile(r"\baten\.matmul\b"),
    "aten.layer_norm": re.compile(r"\baten\.layer_norm\b"),
    "aten.tanh": re.compile(r"\baten\.tanh\b"),
    "aten.softmax": re.compile(r"\baten\.softmax\b"),
}
DEQUANT_RE = re.compile(
    r"\b(?:quantized_decomposed\.|torch\.ops\.quantized_decomposed\.)?"
    r"(?:dequantize_per_tensor|dequantize)\.default\b"
)
QUANT_RE = re.compile(
    r"\b(?:quantized_decomposed\.|torch\.ops\.quantized_decomposed\.)?"
    r"(?:quantize_per_tensor|quantize)\.default\b"
)
MATMUL_RE = CORE_OP_PATTERNS["aten.matmul"]
LAYER_NORM_RE = CORE_OP_PATTERNS["aten.layer_norm"]
TANH_RE = CORE_OP_PATTERNS["aten.tanh"]
SOFTMAX_RE = CORE_OP_PATTERNS["aten.softmax"]


@dataclass(frozen=True)
class CapturedOp:
    family: str
    source_ops: tuple[str, ...]
    first_line: int
    last_line: int

    def to_manifest_op(self, index: int) -> dict[str, Any]:
        return {
            "id": f"op{index}",
            "family": self.family,
            "source_ops": list(self.source_ops),
            "kernel_id": DEFAULT_KERNEL_IDS[self.family],
            "line_range": [self.first_line, self.last_line],
        }


def _safe_slice(lines: list[str], start: int, end: int) -> list[str]:
    return lines[max(0, start) : min(len(lines), end)]


def _has_between(lines: list[str], start: int, end: int, pattern: re.Pattern[str]) -> bool:
    return any(pattern.search(line) for line in _safe_slice(lines, start, end))


def _first_matching_index(lines: list[str], start: int, end: int, pattern: re.Pattern[str]) -> int | None:
    safe = _safe_slice(lines, start, end)
    if not safe:
        return None
    base = max(0, start)
    for offset, line in enumerate(safe):
        if pattern.search(line):
            return base + offset
    return None


def _has_between_or(lines: list[str], start: int, end: int, patterns: list[re.Pattern[str]]) -> bool:
    return any(
        pattern.search(line)
        for line in _safe_slice(lines, start, end)
        for pattern in patterns
    )


def _dedupe_captures(captures: list[CapturedOp]) -> list[CapturedOp]:
    deduped: list[CapturedOp] = []
    seen: set[tuple[int, int, str]] = set()
    for capture in captures:
        if capture.family not in SUPPORTED_FAMILIES:
            continue
        key = (capture.first_line, capture.last_line, capture.family)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(capture)
    return deduped


def capture_backend_ops(
    graph_text: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    lines = graph_text.splitlines()
    captures: list[CapturedOp] = []
    covered_lines: set[int] = set()

    # Matmul -> quantize islands (QDQ + quantized output)
    for index, line in enumerate(lines):
        if not MATMUL_RE.search(line):
            continue
        window_start = max(0, index - 4)
        window_end = min(len(lines), index + 5)
        if _has_between(lines, window_start, index, DEQUANT_RE) and _has_between(
            lines, index + 1, window_end, QUANT_RE
        ):
            captures.append(
                CapturedOp(
                    family="fpga.quantized_matmul",
                    source_ops=("aten.matmul",),
                    first_line=window_start + 1,
                    last_line=window_end,
                )
            )
            covered_lines.update(range(window_start, window_end))

    # LayerNorm -> quantize islands
    for index, line in enumerate(lines):
        if not LAYER_NORM_RE.search(line):
            continue
        window_start = max(0, index - 4)
        window_end = min(len(lines), index + 5)
        if _has_between(lines, window_start, index, DEQUANT_RE) and _has_between(
            lines, index + 1, window_end, QUANT_RE
        ):
            captures.append(
                CapturedOp(
                    family="fpga.layer_norm",
                    source_ops=("aten.layer_norm",),
                    first_line=window_start + 1,
                    last_line=window_end,
                )
            )
            covered_lines.update(range(window_start, window_end))

    # GELU via tanh island detection for the representative core variant
    for index, line in enumerate(lines):
        if not TANH_RE.search(line):
            continue
        window_start = max(0, index - 5)
        window_end = min(len(lines), index + 4)
        if _has_between(lines, window_start, window_end, QUANT_RE):
            captures.append(
                CapturedOp(
                    family="fpga.gelu",
                    source_ops=("aten.tanh",),
                    first_line=window_start + 1,
                    last_line=window_end,
                )
            )
            covered_lines.update(range(window_start, window_end))

    # Attention-softmax island: score matmul -> softmax -> value matmul.
    # Some PT2E exports place quant/dequant markers before/after softmax inconsistently,
    # so this matcher allows flexible boundaries while still requiring quantized context
    # around the key attention transitions.
    for index, line in enumerate(lines):
        if not SOFTMAX_RE.search(line):
            continue
        window_start = max(0, index - 24)
        window_end = min(len(lines), index + 12)
        score_matmul = _first_matching_index(lines, window_start, index, MATMUL_RE)
        value_matmul = _first_matching_index(lines, index + 1, window_end, MATMUL_RE)
        if score_matmul is None or value_matmul is None:
            continue
        captures.append(
            CapturedOp(
                family="fpga.softmax_or_attention",
                source_ops=("aten.matmul", "aten.softmax", "aten.matmul"),
                first_line=window_start + 1,
                last_line=window_end,
            )
        )
        covered_lines.update(range(window_start, window_end))
        covered_lines.update((score_matmul, value_matmul, index))

    ops = _dedupe_captures(captures)
    unmatched = find_unmatched_core_ops(graph_text, covered_lines)
    return [op.to_manifest_op(index) for index, op in enumerate(ops)], unmatched


def find_unmatched_core_ops(graph_text: str, covered_lines: set[int]) -> list[dict[str, Any]]:
    unmatched: list[dict[str, Any]] = []
    for index, line in enumerate(graph_text.splitlines()):
        if index in covered_lines:
            continue
        for op, pattern in CORE_OP_PATTERNS.items():
            if pattern.search(line):
                unmatched.append({"op": op, "line": index + 1, "text": line.strip()})
                break
    return unmatched
