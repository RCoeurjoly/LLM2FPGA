# PT2E Graph Shape Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cheap pre-Torch-MLIR graph-shape audit/gate for the TinyStories representative-core PT2E W2A2 path so non-structural quantization is rejected before CF, Handshake, SV, or Yosys.

**Architecture:** Reuse the existing PT2E graph dump hook (`TINYSTORIES_DUMP_PT2E_QUANTIZED_GRAPH`) and add a small standalone analyzer under `scripts/task6/`. The analyzer reads the dumped FX text, classifies hardware-critical float/QDQ patterns, emits JSON/Markdown reports, and optionally exits nonzero when structural integer/fixed-point invariants are violated. Nix gets a lightweight derivation that runs only through the PT2E dump and analyzer, not through Torch-MLIR lowering.

**Tech Stack:** Python standard library, `unittest`, existing TinyStories adapter, Nix `runCommand`, existing `pythonWithTinyStories` environment.

---

## File Structure

- Create: `scripts/task6/pt2e_graph_shape_audit.py`
  - Responsibility: parse FX graph text, count known operations, classify critical subgraph families, emit JSON/Markdown, and implement `--fail-on-nonstructural`.
- Create: `scripts/task6/test_pt2e_graph_shape_audit.py`
  - Responsibility: unit-test the parser, report schema, CLI outputs, and failing gate behavior with small synthetic FX snippets.
- Modify: `flake.nix`
  - Responsibility: add a `tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit` derivation that dumps the PT2E graph and runs the analyzer.
- Modify: `docs/task6-resource-usage-reduction-notes.md`
  - Responsibility: add a short dated note pointing to the audit target and explaining that it is the next cheap gate before Torch-MLIR.
- Optional after first green run: add `docs/task6-pt2e-graph-shape-audit.md` only if the Nix artifact needs a stable human-readable copy in the repo. Do not create it if the generated Markdown report is enough.

## Task 1: Add Unit Tests For Graph Audit Classification

**Files:**
- Create: `scripts/task6/test_pt2e_graph_shape_audit.py`
- Create later in Task 2: `scripts/task6/pt2e_graph_shape_audit.py`

- [ ] **Step 1: Write failing tests for structural and non-structural cases**

Create `scripts/task6/test_pt2e_graph_shape_audit.py` with:

```python
#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "scripts" / "task6" / "pt2e_graph_shape_audit.py"


class GraphShapeAuditTest(unittest.TestCase):
    def test_float_matmul_after_dequant_is_nonstructural(self) -> None:
        from scripts.task6.pt2e_graph_shape_audit import audit_graph_text

        graph = textwrap.dedent(
            """
            torch.ops.quantized_decomposed.dequantize_per_tensor.default
            torch.ops.aten.matmul.default
            torch.ops.quantized_decomposed.quantize_per_tensor.default
            torch.ops.aten.layer_norm.default
            torch.ops.aten.tanh.default
            """
        )

        report = audit_graph_text(graph, model_label="synthetic-qdfloat")

        self.assertEqual(report["status"], "fail")
        self.assertIn("float_matmul_after_dequant", report["failure_reasons"])
        self.assertIn("float_layer_norm", report["failure_reasons"])
        self.assertIn("float_gelu_or_tanh", report["failure_reasons"])
        self.assertEqual(report["op_counts"]["aten.matmul"], 1)
        self.assertEqual(report["op_counts"]["quantized_decomposed.dequantize_per_tensor"], 1)

    def test_integer_like_graph_passes_without_float_critical_ops(self) -> None:
        from scripts.task6.pt2e_graph_shape_audit import audit_graph_text

        graph = textwrap.dedent(
            """
            torch.ops.aten.mm.default
            torch.ops.aten.add.Tensor
            torch.ops.aten.clamp.default
            torch.ops.aten.to.dtype
            """
        )

        report = audit_graph_text(graph, model_label="synthetic-intlike")

        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["failure_reasons"], [])
        self.assertEqual(report["critical_float_ops"], [])

    def test_cli_writes_json_and_markdown(self) -> None:
        graph = "torch.ops.quantized_decomposed.dequantize_per_tensor.default\\ntorch.ops.aten.matmul.default\\n"

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            graph_path = tmp / "graph.fx.txt"
            json_path = tmp / "report.json"
            md_path = tmp / "report.md"
            graph_path.write_text(graph, encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(CLI),
                    "--graph",
                    str(graph_path),
                    "--json-out",
                    str(json_path),
                    "--markdown-out",
                    str(md_path),
                    "--model-label",
                    "cli-smoke",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertEqual(report["model_label"], "cli-smoke")
            self.assertIn("float_matmul_after_dequant", report["failure_reasons"])
            self.assertIn("# PT2E Graph Shape Audit", md_path.read_text(encoding="utf-8"))

    def test_cli_gate_exits_nonzero_on_nonstructural_graph(self) -> None:
        graph = "torch.ops.quantized_decomposed.dequantize_per_tensor.default\\ntorch.ops.aten.matmul.default\\n"

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            graph_path = tmp / "graph.fx.txt"
            json_path = tmp / "report.json"
            graph_path.write_text(graph, encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(CLI),
                    "--graph",
                    str(graph_path),
                    "--json-out",
                    str(json_path),
                    "--model-label",
                    "gate-smoke",
                    "--fail-on-nonstructural",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(completed.returncode, 2)
            self.assertIn("non-structural PT2E graph", completed.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the new tests and verify they fail because the module does not exist**

Run:

```bash
python3 -m unittest scripts/task6/test_pt2e_graph_shape_audit.py
```

Expected: `ModuleNotFoundError` or CLI file-not-found failures for `scripts.task6.pt2e_graph_shape_audit`.

- [ ] **Step 3: Commit the failing tests**

Run:

```bash
git add scripts/task6/test_pt2e_graph_shape_audit.py
git commit -m "test: add PT2E graph shape audit expectations"
```

## Task 2: Implement The Graph Shape Audit CLI

**Files:**
- Create: `scripts/task6/pt2e_graph_shape_audit.py`
- Test: `scripts/task6/test_pt2e_graph_shape_audit.py`

- [ ] **Step 1: Write the analyzer and CLI**

Create `scripts/task6/pt2e_graph_shape_audit.py` with:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any


OP_PATTERNS = {
    "aten.matmul": re.compile(r"(?:torch\\.ops\\.)?aten\\.matmul(?:\\.default)?"),
    "aten.mm": re.compile(r"(?:torch\\.ops\\.)?aten\\.mm(?:\\.default)?"),
    "aten.layer_norm": re.compile(r"(?:torch\\.ops\\.)?aten\\.layer_norm(?:\\.default)?"),
    "aten.tanh": re.compile(r"(?:torch\\.ops\\.)?aten\\.tanh(?:\\.default)?"),
    "aten.pow": re.compile(r"(?:torch\\.ops\\.)?aten\\.pow(?:\\.|\\b)"),
    "aten.rsqrt": re.compile(r"(?:torch\\.ops\\.)?aten\\.rsqrt(?:\\.default)?"),
    "aten.softmax": re.compile(r"(?:torch\\.ops\\.)?aten\\.softmax(?:\\.|\\b)"),
    "aten.to.dtype": re.compile(r"(?:torch\\.ops\\.)?aten\\.to\\.dtype"),
    "aten.clamp": re.compile(r"(?:torch\\.ops\\.)?aten\\.clamp(?:\\.|\\b)"),
    "quantized_decomposed.quantize_per_tensor": re.compile(
        r"(?:torch\\.ops\\.)?quantized_decomposed\\.quantize_per_tensor"
    ),
    "quantized_decomposed.dequantize_per_tensor": re.compile(
        r"(?:torch\\.ops\\.)?quantized_decomposed\\.dequantize_per_tensor"
    ),
    "torch.aten.quantize_per_tensor": re.compile(r"torch\\.aten\\.quantize_per_tensor"),
    "torch.aten.dequantize": re.compile(r"torch\\.aten\\.dequantize"),
}


def count_ops(graph_text: str) -> dict[str, int]:
    return {name: len(pattern.findall(graph_text)) for name, pattern in OP_PATTERNS.items()}


def _has_dequant_before_matmul(lines: list[str]) -> bool:
    seen_dequant = False
    for line in lines:
        if "dequantize" in line:
            seen_dequant = True
        if "aten.matmul" in line and seen_dequant:
            return True
    return False


def audit_graph_text(graph_text: str, *, model_label: str) -> dict[str, Any]:
    lines = [line.strip() for line in graph_text.splitlines() if line.strip()]
    op_counts = count_ops(graph_text)
    critical_float_ops: list[dict[str, Any]] = []
    failure_reasons: list[str] = []

    if _has_dequant_before_matmul(lines):
        failure_reasons.append("float_matmul_after_dequant")
        critical_float_ops.append(
            {
                "family": "matmul",
                "reason": "aten.matmul appears after a dequantize marker",
                "count": op_counts["aten.matmul"],
            }
        )

    if op_counts["aten.layer_norm"]:
        failure_reasons.append("float_layer_norm")
        critical_float_ops.append(
            {
                "family": "layer_norm",
                "reason": "aten.layer_norm remains in the post-PT2E graph",
                "count": op_counts["aten.layer_norm"],
            }
        )

    if op_counts["aten.tanh"] or op_counts["aten.pow"]:
        failure_reasons.append("float_gelu_or_tanh")
        critical_float_ops.append(
            {
                "family": "gelu_or_tanh",
                "reason": "tanh/pow GELU-style math remains in the post-PT2E graph",
                "count": op_counts["aten.tanh"] + op_counts["aten.pow"],
            }
        )

    if op_counts["aten.rsqrt"]:
        failure_reasons.append("float_rsqrt")
        critical_float_ops.append(
            {
                "family": "rsqrt",
                "reason": "rsqrt remains in the post-PT2E graph",
                "count": op_counts["aten.rsqrt"],
            }
        )

    status = "fail" if failure_reasons else "pass"
    return {
        "schema_version": 1,
        "model_label": model_label,
        "status": status,
        "failure_reasons": failure_reasons,
        "op_counts": op_counts,
        "critical_float_ops": critical_float_ops,
        "line_count": len(lines),
        "recommendation": recommendation_for_status(status, failure_reasons),
    }


def recommendation_for_status(status: str, failure_reasons: list[str]) -> str:
    if status == "pass":
        return "Proceed to Torch-MLIR size gates; this audit found no critical float/QDQ blockers."
    reasons = ", ".join(failure_reasons)
    return (
        "Do not treat this graph as structurally integer/fixed-point before Torch-MLIR. "
        f"Fix or isolate: {reasons}."
    )


def write_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# PT2E Graph Shape Audit",
        "",
        f"- model: `{report['model_label']}`",
        f"- status: `{report['status']}`",
        f"- line_count: `{report['line_count']}`",
        f"- recommendation: {report['recommendation']}",
        "",
        "## Failure Reasons",
        "",
    ]
    reasons = report["failure_reasons"]
    if reasons:
        lines.extend(f"- `{reason}`" for reason in reasons)
    else:
        lines.append("- none")
    lines.extend(["", "## Operation Counts", ""])
    for name, count in sorted(report["op_counts"].items()):
        lines.append(f"- `{name}`: `{count}`")
    lines.extend(["", "## Critical Float Ops", ""])
    critical = report["critical_float_ops"]
    if critical:
        for item in critical:
            lines.append(f"- `{item['family']}`: {item['reason']} (`count={item['count']}`)")
    else:
        lines.append("- none")
    lines.append("")
    return "\\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--graph", required=True, type=Path)
    parser.add_argument("--json-out", required=True, type=Path)
    parser.add_argument("--markdown-out", type=Path)
    parser.add_argument("--model-label", required=True)
    parser.add_argument("--fail-on-nonstructural", action="store_true")
    args = parser.parse_args()

    graph_text = args.graph.read_text(encoding="utf-8")
    report = audit_graph_text(graph_text, model_label=args.model_label)
    args.json_out.parent.mkdir(parents=True, exist_ok=True)
    args.json_out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\\n", encoding="utf-8")
    if args.markdown_out is not None:
        args.markdown_out.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_out.write_text(write_markdown(report), encoding="utf-8")
    if args.fail_on_nonstructural and report["status"] != "pass":
        print(f"non-structural PT2E graph: {', '.join(report['failure_reasons'])}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Run the unit tests and verify they pass**

Run:

```bash
python3 -m unittest scripts/task6/test_pt2e_graph_shape_audit.py
```

Expected: all tests pass.

- [ ] **Step 3: Run a manual CLI smoke test**

Run:

```bash
tmp="$(mktemp -d)"
printf '%s\n' \
  'torch.ops.quantized_decomposed.dequantize_per_tensor.default' \
  'torch.ops.aten.matmul.default' > "$tmp/graph.fx.txt"
python3 scripts/task6/pt2e_graph_shape_audit.py \
  --graph "$tmp/graph.fx.txt" \
  --json-out "$tmp/report.json" \
  --markdown-out "$tmp/report.md" \
  --model-label manual-smoke \
  --fail-on-nonstructural
```

Expected: exit code `2` and stderr contains `non-structural PT2E graph: float_matmul_after_dequant`.

- [ ] **Step 4: Commit the implementation**

Run:

```bash
git add scripts/task6/pt2e_graph_shape_audit.py scripts/task6/test_pt2e_graph_shape_audit.py
git commit -m "feat: add PT2E graph shape audit"
```

## Task 3: Add A Lightweight Nix Audit Target

**Files:**
- Modify: `flake.nix`
- Test: `nix build .#tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit --no-link -L`

- [ ] **Step 1: Add the derivation next to the existing ExecuTorch manifest derivation**

In `flake.nix`, near `tinyStoriesRepresentativeCoreW2A2ExecuTorchFpgaBackendManifest`, add:

```nix
        tinyStoriesRepresentativeCoreW2A2GraphShapeAudit =
          pkgs.runCommand
          "tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit"
          {
            buildInputs = [ pythonWithTinyStories ];
          } ''
            set -euo pipefail
            mkdir -p "$out"
            export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlir}/${python.sitePackages}:${torchMlir}/${python.sitePackages}/torch_mlir:${./.}:''${PYTHONPATH:-}"
            export TINYSTORIES_CORE_VOCAB_SIZE=32
            export TINYSTORIES_CORE_NUM_LAYERS=2
            export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=4
            export TINYSTORIES_CORE_WINDOW_SIZE=2
            export TINYSTORIES_CORE_HIDDEN_SIZE=2
            export TINYSTORIES_CORE_NUM_HEADS=1
            export TINYSTORIES_PYTORCHAO_ACTIVATION_BITS=2
            export TINYSTORIES_PYTORCHAO_WEIGHT_BITS=2
            export TINYSTORIES_DUMP_PT2E_QUANTIZED_GRAPH="$out/quantized.fx.txt"

            python ${./scripts/compile-pytorch.py} \
              --adapter ${./TinyStories/model_adapter_representative_core_pt2e_static_quant.py} \
              --model-path ${tinyStories1m.snapshot} \
              --out "$TMPDIR/torch.mlir" >/dev/null

            python ${./scripts/task6/pt2e_graph_shape_audit.py} \
              --graph "$out/quantized.fx.txt" \
              --json-out "$out/report.json" \
              --markdown-out "$out/report.md" \
              --model-label tiny-stories-1m-representative-core-pt2e-static-w2a2
          '';
```

- [ ] **Step 2: Export the derivation as a package**

In the `packages` attribute set where other Task 6 packages are exposed, add:

```nix
          tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit =
            tinyStoriesRepresentativeCoreW2A2GraphShapeAudit;
```

If the package export area is not obvious, run:

```bash
rg -n "executorch-fpga-backend-manifest|task6-executorch-official-backend-survey|packages =" flake.nix
```

Expected: locate the package mapping that already exposes `tinyStoriesRepresentativeCoreW2A2ExecuTorchFpgaBackendManifest` or nearby Task 6 derivations.

- [ ] **Step 3: Run a syntax check**

Run:

```bash
nix-instantiate --parse flake.nix >/dev/null
```

Expected: command exits `0`.

- [ ] **Step 4: Build the audit target**

Run:

```bash
nix build .#tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit --no-link -L
```

Expected: build succeeds and prints a store path. The output directory contains `quantized.fx.txt`, `report.json`, and `report.md`.

- [ ] **Step 5: Inspect the generated report**

Run:

```bash
out="$(nix build .#tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit --no-link --print-out-paths)"
python3 -m json.tool "$out/report.json" | sed -n '1,160p'
sed -n '1,120p' "$out/report.md"
```

Expected: `report.json` has `schema_version=1`, `model_label=tiny-stories-1m-representative-core-pt2e-static-w2a2`, and either `status=fail` with concrete failure reasons or `status=pass` if the graph changed unexpectedly.

- [ ] **Step 6: Commit the Nix target**

Run:

```bash
git add flake.nix
git commit -m "nix: add W2A2 PT2E graph shape audit"
```

## Task 4: Record The Audit Path In Task 6 Notes

**Files:**
- Modify: `docs/task6-resource-usage-reduction-notes.md`

- [ ] **Step 1: Add a short dated note near the top**

Add this section after the `# Task 6 Resource Usage Reduction Notes` introduction and before older dated entries:

```markdown
## 2026-06-25 - PT2E graph-shape audit gate

Added the lightweight audit target
`tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit`.
It stops before Torch-MLIR lowering, preserves the post-`convert_pt2e`
`quantized.fx.txt` dump, and emits `report.json` plus `report.md` with
operation counts and structural integer/fixed-point gate findings.

This target is the first feedback-loop step for the graph-shaping recommendation
in `docs/task6-torch-mlir-import-and-graph-shaping.md`: do not spend CF,
Handshake, SV, or Yosys cycles until the post-PT2E graph shows the desired
integer/fixed-point structure.
```

- [ ] **Step 2: Run a documentation grep check**

Run:

```bash
rg -n "PT2E graph-shape audit|graph-shaping recommendation|tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit" docs/task6-resource-usage-reduction-notes.md docs/task6-torch-mlir-import-and-graph-shaping.md
```

Expected: output includes the new note and the already committed pipeline-understanding note.

- [ ] **Step 3: Commit the note update**

Run:

```bash
git add docs/task6-resource-usage-reduction-notes.md
git commit -m "docs: record PT2E graph shape audit gate"
```

## Task 5: Final Verification And Decision Point

**Files:**
- No new files.
- Verify: tests, Nix parse, audit target build.

- [ ] **Step 1: Run all focused tests**

Run:

```bash
python3 -m unittest scripts/task6/test_pt2e_graph_shape_audit.py
python3 -m unittest scripts/task6/test_llm2fpga_executorch_backend.py
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected: all focused tests pass.

- [ ] **Step 2: Run Nix parse**

Run:

```bash
nix-instantiate --parse flake.nix >/dev/null
```

Expected: command exits `0`.

- [ ] **Step 3: Build and inspect the audit target**

Run:

```bash
out="$(nix build .#tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit --no-link --print-out-paths -L)"
test -f "$out/quantized.fx.txt"
test -f "$out/report.json"
test -f "$out/report.md"
python3 -m json.tool "$out/report.json" >/dev/null
```

Expected: all commands exit `0`.

- [ ] **Step 4: Decide the next implementation branch**

Read `"$out/report.md"` and choose one next implementation:

```text
If the top failure is float_matmul_after_dequant:
  plan a maintained-tool survey for PT2E quantizer/decomposition options around linear/GEMV or MLP.

If the top failure is float_layer_norm:
  plan a fixed-point LayerNorm approximation/import experiment.

If the top failure is float_gelu_or_tanh:
  plan a GELU replacement experiment using a LUT or piecewise-linear module before export.

If no failures appear:
  plan Torch-MLIR/Linalg/CF size gates because the graph shape changed and needs downstream measurement.
```

- [ ] **Step 5: Commit final verification notes only if a repo note changed**

If no files changed, do not commit. If `docs/task6-resource-usage-reduction-notes.md` was updated with the concrete report result, run:

```bash
git add docs/task6-resource-usage-reduction-notes.md
git commit -m "docs: summarize PT2E graph shape audit result"
```

## Self-Review

- Spec coverage: implements the approved recommendation to prove graph structure before Torch-MLIR, uses maintained PyTorch-family tools first, and creates a cheap representative-core feedback loop.
- Scope check: this plan deliberately does not implement fixed-point GELU, LayerNorm, attention, or a custom ExecuTorch backend. It creates the gate that chooses which of those is worth planning next.
- Test coverage: includes parser/schema tests, CLI behavior tests, existing backend tests, Nix parse, and Nix build of the audit artifact.
- Risk: the first audit is text-based and heuristic. That is acceptable for a cheap gate, but if the report drives a major architecture decision, follow up with structured FX node inspection inside the same Python environment.
