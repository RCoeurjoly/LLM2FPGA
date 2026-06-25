# ExecuTorch Backend Quantizer Graph-Shape Survey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cheap, maintained-tool survey that checks whether ExecuTorch backend quantizers can shape a PT2E graph into a more integer/fixed-point structure before Torch-MLIR import.

**Architecture:** Keep the current import-only backend survey intact, then add quantizer-specific inventory and a separate tiny PT2E graph-shape probe. The first layer answers "which maintained backend quantizers exist in this environment?"; the second layer answers "does an importable quantizer make a tiny linear/GEMV graph structurally better after `convert_pt2e`?" without requiring vendor SDKs or hardware.

**Tech Stack:** Python `unittest`, `torch.export`, PT2E `prepare_pt2e`/`convert_pt2e`, ExecuTorch backend quantizer entrypoints where importable, existing `scripts/task6/pt2e_graph_shape_audit.py`, Nix package targets in `flake.nix`.

---

## File Map

- Modify: `scripts/task6/executorch_backend_survey.py`
  - Add backend quantizer candidate metadata.
  - Report quantizer importability separately from partitioner/import status.
  - Preserve the existing JSON keys so current consumers do not break.
- Modify: `scripts/task6/test_executorch_backend_survey.py`
  - Add unit tests for quantizer candidate metadata, import success, import failure, and CLI JSON shape.
- Modify: `scripts/task6/pt2e_graph_shape_audit.py`
  - Add `aten.linear` counting.
  - Add `float_linear_after_dequant` detection distinct from `float_matmul_after_dequant`.
- Modify: `scripts/task6/test_pt2e_graph_shape_audit.py`
  - Add a focused test for `dequantize_per_tensor -> aten.linear.default -> quantize_per_tensor`.
- Create: `scripts/task6/backend_quantizer_graph_shape_probe.py`
  - Build a tiny deterministic `nn.Linear`/GEMV module.
  - Instantiate one known backend quantizer when importable.
  - Run `torch.export -> prepare_pt2e -> calibrate -> convert_pt2e`.
  - Dump the post-convert FX graph and run the existing graph-shape audit.
  - Degrade to a structured `skip` report when dependencies or quantizer construction are unavailable.
- Create: `scripts/task6/test_backend_quantizer_graph_shape_probe.py`
  - Unit-test report schema and skip behavior with mocks.
  - Unit-test that an existing graph dump can be audited without a real ExecuTorch install.
- Modify: `flake.nix`
  - Add a Nix target for quantizer inventory.
  - Add a Nix target for the tiny graph-shape probe, gated to skip gracefully if no usable backend quantizer imports.
- Modify: `docs/task6-pt2e-linear-gemv-graph-shaping-survey.md`
  - Add ExecuTorch backend quantizers as the new first maintained experiment.
- Modify: `docs/task6-resource-usage-reduction-notes.md`
  - Add a short dated note pointing to the new survey target and explaining expected outcomes.

## Task 1: Add Quantizer Inventory Metadata

**Files:**
- Modify: `scripts/task6/executorch_backend_survey.py`
- Modify: `scripts/task6/test_executorch_backend_survey.py`

- [ ] **Step 1: Write failing tests for quantizer candidates**

Add these imports in `scripts/task6/test_executorch_backend_survey.py`:

```python
from scripts.task6.executorch_backend_survey import (
    BACKEND_CANDIDATES,
    classify_backend,
    classify_graph_transparency,
    attempt_backend_imports,
    backend_quantizer_entrypoints,
    inventory_backends,
    main,
    make_report_entry,
    validate_report_entry,
)
```

Add these tests to `BackendSurveySchemaTest`:

```python
    def test_xnnpack_quantizer_candidates_include_pt2e_entrypoints(self) -> None:
        entrypoints = backend_quantizer_entrypoints("xnnpack")

        self.assertIn(
            "torch.ao.quantization.quantizer.xnnpack_quantizer.XNNPACKQuantizer",
            entrypoints,
        )
        self.assertIn(
            "executorch.backends.xnnpack.quantizer.xnnpack_quantizer.XNNPACKQuantizer",
            entrypoints,
        )

    def test_nxp_quantizer_candidate_matches_official_docs(self) -> None:
        entrypoints = backend_quantizer_entrypoints("nxp")

        self.assertIn(
            "executorch.backends.nxp.quantizer.neutron_quantizer.NeutronQuantizer",
            entrypoints,
        )

    def test_report_entry_contains_quantizer_inventory_keys(self) -> None:
        entry = make_report_entry("nxp", status="skip", skip_reason="executorch_backend_not_importable")
        validate_report_entry(entry)

        self.assertIn("quantizer_entrypoints", entry)
        self.assertIn("available_quantizers", entry)
        self.assertIn("quantizer_import_errors", entry)
        self.assertEqual(entry["available_quantizers"], [])
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected: FAIL with `ImportError: cannot import name 'backend_quantizer_entrypoints'`.

- [ ] **Step 3: Implement quantizer metadata**

In `scripts/task6/executorch_backend_survey.py`, add these report keys:

```python
    "quantizer_entrypoints",
    "available_quantizers",
    "quantizer_import_errors",
```

Add this helper below `backend_entrypoints`:

```python
def backend_quantizer_entrypoints(backend: str) -> list[str]:
    mapping = {
        "xnnpack": [
            "torch.ao.quantization.quantizer.xnnpack_quantizer.XNNPACKQuantizer",
            "executorch.backends.xnnpack.quantizer.xnnpack_quantizer.XNNPACKQuantizer",
        ],
        "cadence": [
            "executorch.backends.cadence.aot.quantizer.quantizer.CadenceQuantizer",
            "executorch.backends.cadence.quantizer.quantizer.CadenceQuantizer",
        ],
        "arm": [
            "executorch.backends.arm.quantizer.arm_quantizer.ArmQuantizer",
            "executorch.backends.arm.quantizer.ethosu_quantizer.EthosUQuantizer",
        ],
        "cortex_m": [
            "executorch.backends.cortex_m.quantizer.cortex_m_quantizer.CortexMQuantizer",
        ],
        "nxp": [
            "executorch.backends.nxp.quantizer.neutron_quantizer.NeutronQuantizer",
        ],
        "qualcomm": [
            "executorch.backends.qualcomm.quantizer.quantizer.Quantizer",
            "executorch.backends.qualcomm.quantizer.qnn_quantizer.QnnQuantizer",
        ],
        "example": [
            "executorch.backends.example.example_quantizer.ExampleQuantizer",
        ],
        "test": [
            "executorch.backends.test.test_quantizer.TestQuantizer",
        ],
    }
    return mapping.get(backend, [])
```

Add this helper below `module_import_status`:

```python
def object_import_status(dotted_name: str) -> tuple[bool, str | None]:
    module_name, _, object_name = dotted_name.rpartition(".")
    if not module_name or not object_name:
        return False, "ValueError: dotted object path must include module and object name"
    try:
        module = importlib.import_module(module_name)
        getattr(module, object_name)
    except Exception as exc:
        return False, f"{type(exc).__name__}: {exc}"
    return True, None
```

Add this helper below `attempt_backend_imports`:

```python
def attempt_quantizer_imports(dotted_names: list[str]) -> dict[str, Any]:
    available_quantizers = []
    import_errors = {}
    for name in dotted_names:
        available, error = object_import_status(name)
        if available:
            available_quantizers.append(name)
        elif error is not None:
            import_errors[name] = error
    return {
        "available": bool(available_quantizers),
        "available_quantizers": available_quantizers,
        "import_errors": import_errors,
    }
```

In `make_report_entry`, add these fields:

```python
        "quantizer_entrypoints": backend_quantizer_entrypoints(backend),
        "available_quantizers": [],
        "quantizer_import_errors": {},
```

In `probe_xnnpack_lowering` and `probe_backend_by_import_only`, after creating `entry`, add:

```python
    quantizer_imports = attempt_quantizer_imports(entry["quantizer_entrypoints"])
    entry["available_quantizers"] = quantizer_imports["available_quantizers"]
    entry["quantizer_import_errors"] = quantizer_imports["import_errors"]
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected: PASS.

- [ ] **Step 5: Commit**

Because this workspace has unrelated dirty changes, inspect before committing:

```bash
git diff -- scripts/task6/executorch_backend_survey.py scripts/task6/test_executorch_backend_survey.py
git status --short
```

If only intended hunks are present for these files, commit path-limited:

```bash
git add scripts/task6/executorch_backend_survey.py scripts/task6/test_executorch_backend_survey.py
git commit -m "feat: inventory executorch backend quantizers"
```

## Task 2: Teach the Graph Audit About Float Linear After Dequant

**Files:**
- Modify: `scripts/task6/pt2e_graph_shape_audit.py`
- Modify: `scripts/task6/test_pt2e_graph_shape_audit.py`

- [ ] **Step 1: Write failing audit test**

Add this test to `scripts/task6/test_pt2e_graph_shape_audit.py`:

```python
    def test_flags_float_linear_after_dequant_separately_from_matmul(self) -> None:
        from scripts.task6.pt2e_graph_shape_audit import audit_graph_text

        graph = """
        %dq_x = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%x,), kwargs={})
        %dq_w = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%w,), kwargs={})
        %linear = call_function[target=torch.ops.aten.linear.default](args=(%dq_x, %dq_w, %bias), kwargs={})
        %q = call_function[target=torch.ops.quantized_decomposed.quantize_per_tensor.default](args=(%linear,), kwargs={})
        """

        report = audit_graph_text(graph, model_label="linear-q dq")

        self.assertEqual(report["status"], "fail")
        self.assertIn("float_linear_after_dequant", report["failure_reasons"])
        self.assertNotIn("float_matmul_after_dequant", report["failure_reasons"])
        self.assertEqual(report["op_counts"]["aten.linear"], 1)
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
python3 -m unittest scripts/task6/test_pt2e_graph_shape_audit.py
```

Expected: FAIL with missing `aten.linear` count or missing `float_linear_after_dequant`.

- [ ] **Step 3: Implement linear detection**

In `scripts/task6/pt2e_graph_shape_audit.py`, add this entry to `OP_PATTERNS`:

```python
    "aten.linear": re.compile(r"(?:torch\.ops\.)?aten\.linear(?:\.default)?"),
```

Rename `_has_dequant_before_matmul` to `_has_dequant_before_op`:

```python
def _has_dequant_before_op(lines: list[str], op_marker: str) -> bool:
    seen_dequant = False
    for line in lines:
        if "dequantize" in line:
            seen_dequant = True
        if op_marker in line and seen_dequant:
            return True
    return False
```

Replace the matmul check with:

```python
    if _has_dequant_before_op(lines, "aten.matmul"):
        failure_reasons.append("float_matmul_after_dequant")
        critical_float_ops.append(
            {
                "family": "matmul",
                "reason": "aten.matmul appears after a dequantize marker",
                "count": op_counts["aten.matmul"],
            }
        )

    if _has_dequant_before_op(lines, "aten.linear"):
        failure_reasons.append("float_linear_after_dequant")
        critical_float_ops.append(
            {
                "family": "linear",
                "reason": "aten.linear appears after a dequantize marker",
                "count": op_counts["aten.linear"],
            }
        )
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
python3 -m unittest scripts/task6/test_pt2e_graph_shape_audit.py
```

Expected: PASS.

- [ ] **Step 5: Rebuild the existing graph audit**

Run:

```bash
nix build .#tiny-stories-1m-representative-core-pt2e-static-w2a2-graph-shape-audit --no-link --print-out-paths -L
```

Expected: build succeeds. The report should still fail, now with both attention and linear structural reasons visible if the post-PT2E graph contains dequantized `aten.linear`.

- [ ] **Step 6: Commit**

```bash
git add scripts/task6/pt2e_graph_shape_audit.py scripts/task6/test_pt2e_graph_shape_audit.py
git commit -m "feat: flag float linear after dequant"
```

## Task 3: Add the Tiny Backend Quantizer Graph-Shape Probe

**Files:**
- Create: `scripts/task6/backend_quantizer_graph_shape_probe.py`
- Create: `scripts/task6/test_backend_quantizer_graph_shape_probe.py`

- [ ] **Step 1: Write tests for skip/report behavior**

Create `scripts/task6/test_backend_quantizer_graph_shape_probe.py`:

```python
#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.task6.backend_quantizer_graph_shape_probe import (
    audit_existing_graph,
    make_skip_report,
    main,
)


def main_with_args(argv: list[str]) -> int:
    import sys

    with mock.patch.object(sys, "argv", ["backend_quantizer_graph_shape_probe.py", *argv]):
        return main()


class BackendQuantizerGraphShapeProbeTest(unittest.TestCase):
    def test_make_skip_report_has_stable_schema(self) -> None:
        report = make_skip_report(
            backend="nxp",
            quantizer="executorch.backends.nxp.quantizer.neutron_quantizer.NeutronQuantizer",
            reason="quantizer_not_importable",
            detail="ModuleNotFoundError: No module named 'executorch'",
        )

        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["status"], "skip")
        self.assertEqual(report["backend"], "nxp")
        self.assertEqual(report["skip_reason"], "quantizer_not_importable")
        self.assertIn("No module named 'executorch'", report["detail"])

    def test_audit_existing_graph_flags_dequant_linear(self) -> None:
        graph = """
        %dq_x = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%x,), kwargs={})
        %linear = call_function[target=torch.ops.aten.linear.default](args=(%dq_x, %w, %b), kwargs={})
        """

        report = audit_existing_graph(graph, backend="mock", quantizer="mock.Quantizer")

        self.assertEqual(report["status"], "fail")
        self.assertEqual(report["backend"], "mock")
        self.assertIn("float_linear_after_dequant", report["graph_shape_report"]["failure_reasons"])

    def test_cli_can_audit_existing_graph_without_torch(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            graph = tmp / "graph.fx.txt"
            graph.write_text(
                "%dq = call_function[target=torch.ops.quantized_decomposed.dequantize_per_tensor.default](args=(%x,), kwargs={})\n"
                "%linear = call_function[target=torch.ops.aten.linear.default](args=(%dq, %w, %b), kwargs={})\n",
                encoding="utf-8",
            )
            out = tmp / "report.json"

            rc = main_with_args(
                [
                    "--backend",
                    "mock",
                    "--quantizer",
                    "mock.Quantizer",
                    "--existing-graph",
                    str(graph),
                    "--out",
                    str(out),
                ]
            )

            self.assertEqual(rc, 0)
            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(payload["status"], "fail")
            self.assertEqual(payload["graph_shape_report"]["op_counts"]["aten.linear"], 1)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
python3 -m unittest scripts/task6/test_backend_quantizer_graph_shape_probe.py
```

Expected: FAIL because `scripts.task6.backend_quantizer_graph_shape_probe` does not exist.

- [ ] **Step 3: Implement the probe CLI**

Create `scripts/task6/backend_quantizer_graph_shape_probe.py`:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib
import json
from pathlib import Path
from typing import Any

from scripts.task6.executorch_backend_survey import backend_quantizer_entrypoints
from scripts.task6.pt2e_graph_shape_audit import audit_graph_text


def make_skip_report(*, backend: str, quantizer: str, reason: str, detail: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "backend": backend,
        "quantizer": quantizer,
        "status": "skip",
        "skip_reason": reason,
        "detail": detail,
        "graph_shape_report": None,
    }


def audit_existing_graph(graph_text: str, *, backend: str, quantizer: str) -> dict[str, Any]:
    graph_report = audit_graph_text(graph_text, model_label=f"{backend}:{quantizer}")
    return {
        "schema_version": 1,
        "backend": backend,
        "quantizer": quantizer,
        "status": graph_report["status"],
        "skip_reason": None,
        "detail": "audited existing graph text",
        "graph_shape_report": graph_report,
    }


def import_object(dotted_name: str) -> object:
    module_name, _, object_name = dotted_name.rpartition(".")
    if not module_name or not object_name:
        raise ValueError("quantizer path must be a dotted object path")
    module = importlib.import_module(module_name)
    return getattr(module, object_name)


def choose_quantizer(backend: str, explicit_quantizer: str | None) -> str | None:
    if explicit_quantizer is not None:
        return explicit_quantizer
    candidates = backend_quantizer_entrypoints(backend)
    return candidates[0] if candidates else None


def run_tiny_pt2e_probe(*, backend: str, quantizer: str) -> dict[str, Any]:
    try:
        import torch
        from torch import nn
        from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="torch_pt2e_not_importable",
            detail=f"{type(exc).__name__}: {exc}",
        )

    try:
        quantizer_cls = import_object(quantizer)
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="quantizer_not_importable",
            detail=f"{type(exc).__name__}: {exc}",
        )

    class TinyLinear(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.linear = nn.Linear(4, 3)

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            return self.linear(x)

    torch.manual_seed(0)
    model = TinyLinear().eval()
    example_inputs = (torch.randn(2, 4),)

    try:
        quantizer_obj = quantizer_cls()
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="quantizer_constructor_failed",
            detail=f"{type(exc).__name__}: {exc}",
        )

    try:
        exported = torch.export.export(model, example_inputs).module()
        prepared = prepare_pt2e(exported, quantizer_obj)
        prepared(*example_inputs)
        converted = convert_pt2e(prepared)
    except Exception as exc:
        return make_skip_report(
            backend=backend,
            quantizer=quantizer,
            reason="pt2e_probe_failed",
            detail=f"{type(exc).__name__}: {exc}",
        )

    return audit_existing_graph(str(converted.graph), backend=backend, quantizer=quantizer)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", required=True)
    parser.add_argument("--quantizer")
    parser.add_argument("--existing-graph", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    quantizer = choose_quantizer(args.backend, args.quantizer)
    if quantizer is None:
        report = make_skip_report(
            backend=args.backend,
            quantizer="",
            reason="no_quantizer_candidates",
            detail=f"no quantizer candidates configured for backend {args.backend!r}",
        )
    elif args.existing_graph is not None:
        report = audit_existing_graph(
            args.existing_graph.read_text(encoding="utf-8"),
            backend=args.backend,
            quantizer=quantizer,
        )
    else:
        report = run_tiny_pt2e_probe(backend=args.backend, quantizer=quantizer)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
python3 -m unittest scripts/task6/test_backend_quantizer_graph_shape_probe.py
```

Expected: PASS.

- [ ] **Step 5: Run all Task 6 survey/audit tests**

Run:

```bash
python3 -m unittest \
  scripts/task6/test_executorch_backend_survey.py \
  scripts/task6/test_pt2e_graph_shape_audit.py \
  scripts/task6/test_backend_quantizer_graph_shape_probe.py
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/task6/backend_quantizer_graph_shape_probe.py scripts/task6/test_backend_quantizer_graph_shape_probe.py
git commit -m "feat: probe backend quantizer graph shape"
```

## Task 4: Add Nix Targets for Reproducible Survey Outputs

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add quantizer inventory output to existing survey target**

In `flake.nix`, keep `task6ExecuTorchOfficialBackendSurvey` as the package name and rely on the updated Python script to add quantizer fields to `survey.json`.

Run:

```bash
nix build .#task6-executorch-official-backend-survey --no-link --print-out-paths -L
```

Expected: build succeeds and the resulting `survey.json` contains `quantizer_entrypoints`, `available_quantizers`, and `quantizer_import_errors` for each backend.

- [ ] **Step 2: Add a tiny graph-shape probe target**

Near `task6ExecuTorchOfficialBackendSurvey`, add:

```nix
        task6ExecuTorchBackendQuantizerGraphShapeProbe = pkgs.runCommand
          "task6-executorch-backend-quantizer-graph-shape-probe"
          {
            buildInputs = [ executorch2605SurveyPython ];
          } ''
            mkdir -p "$out"
            export PYTHONPATH="${./.}:''${PYTHONPATH:-}"
            ${executorch2605SurveyPython}/bin/python ${./scripts/task6/backend_quantizer_graph_shape_probe.py} \
              --backend xnnpack \
              --out "$out/xnnpack-report.json"
          '';
```

In `packages`, expose:

```nix
          task6-executorch-backend-quantizer-graph-shape-probe =
            task6ExecuTorchBackendQuantizerGraphShapeProbe;
```

- [ ] **Step 3: Parse the flake**

Run:

```bash
nix-instantiate --parse flake.nix >/dev/null
```

Expected: exit code 0.

- [ ] **Step 4: Build the new target**

Run:

```bash
nix build .#task6-executorch-backend-quantizer-graph-shape-probe --no-link --print-out-paths -L
```

Expected: build succeeds. If the quantizer cannot run in the pinned environment, `xnnpack-report.json` should be a structured `skip`, not a build failure.

- [ ] **Step 5: Commit**

Because `flake.nix` is already mixed with unrelated Task 6 work in this workspace, inspect carefully:

```bash
git diff -- flake.nix
git status --short
```

If the diff contains unrelated hunks, do not commit `flake.nix` until the user confirms the combined scope. If clean, commit:

```bash
git add flake.nix
git commit -m "nix: add backend quantizer graph-shape probe"
```

## Task 5: Update Task 6 Documentation and Recommendation

**Files:**
- Modify: `docs/task6-pt2e-linear-gemv-graph-shaping-survey.md`
- Modify: `docs/task6-resource-usage-reduction-notes.md`

- [ ] **Step 1: Update the graph-shaping survey recommendation**

In `docs/task6-pt2e-linear-gemv-graph-shaping-survey.md`, insert this section before the current "Option 1: PT2E Custom Quantizer Annotation" and renumber later options if desired:

```markdown
## Option 0: Maintained ExecuTorch Backend Quantizers

This is now the first experiment to run before writing a Task 6-specific
quantizer. ExecuTorch backends such as NXP document a backend-owned PT2E
quantizer flow:

```text
torch.export -> backend quantizer -> prepare_pt2e -> calibrate
-> convert_pt2e -> export/lower with the normal flow
```

The key point for Task 6 is that `convert_pt2e` returns a regular PyTorch
model. That means we can use the backend quantizer as a graph-shaping tool,
then export or import the resulting model through our existing Torch-MLIR path
without committing to ExecuTorch delegation.

For Task 6, the maintained-backend experiment is:

1. inventory importable backend quantizers in the pinned Nix environment;
2. run each importable quantizer on a tiny linear/GEMV slice;
3. dump the post-`convert_pt2e` FX graph;
4. run `pt2e_graph_shape_audit.py`;
5. accept the path only if the graph reduces or removes
   `float_linear_after_dequant` and exposes integer/fixed-point compute before
   Torch-MLIR.

Expected risk: backend quantizers often target backend partitioners and runtime
delegates. They may annotate more patterns but still emit QDQ around float ATen
ops unless the backend lowering consumes those annotations.

Verdict: **best first integration experiment**, because it uses maintained
backend-owned quantization policy and answers our structural question before
any custom graph compiler work.
```

Add this source anchor:

```markdown
- ExecuTorch NXP backend quantization guide:
  `https://docs.pytorch.org/executorch/stable/backends/nxp/nxp-quantization.html`.
```

- [ ] **Step 2: Add a short Task 6 note**

Near the top of `docs/task6-resource-usage-reduction-notes.md`, add:

```markdown
## 2026-06-25 - ExecuTorch backend quantizer graph-shape probe

Added a plan to test maintained ExecuTorch backend quantizers as PT2E
graph-shaping tools before Torch-MLIR import. The important distinction is that
we are not feeding an opaque ExecuTorch delegate into Torch-MLIR. We are testing
whether a backend quantizer can produce a better regular post-`convert_pt2e`
PyTorch graph, then applying the existing graph-shape audit.

The first success criterion is structural, not accuracy: the tiny linear/GEMV
probe should reduce or eliminate `float_linear_after_dequant` and expose
integer/fixed-point compute before Torch-MLIR.
```

- [ ] **Step 3: Commit docs**

```bash
git add docs/task6-pt2e-linear-gemv-graph-shaping-survey.md docs/task6-resource-usage-reduction-notes.md
git commit -m "docs: recommend backend quantizer graph-shape probe"
```

## Task 6: Final Verification and Outcome Capture

**Files:**
- No new source edits unless verification exposes a specific bug.

- [ ] **Step 1: Run Python tests**

Run:

```bash
python3 -m unittest \
  scripts/task6/test_executorch_backend_survey.py \
  scripts/task6/test_pt2e_graph_shape_audit.py \
  scripts/task6/test_backend_quantizer_graph_shape_probe.py \
  scripts/task6/test_llm2fpga_executorch_backend.py
```

Expected: PASS.

- [ ] **Step 2: Parse the flake**

Run:

```bash
nix-instantiate --parse flake.nix >/dev/null
```

Expected: exit code 0.

- [ ] **Step 3: Build inventory target**

Run:

```bash
nix build .#task6-executorch-official-backend-survey --no-link --print-out-paths -L
```

Expected: build succeeds.

- [ ] **Step 4: Build graph-shape probe target**

Run:

```bash
nix build .#task6-executorch-backend-quantizer-graph-shape-probe --no-link --print-out-paths -L
```

Expected: build succeeds. The JSON status may be `skip`, `fail`, or `pass`; only a Python crash or missing structured report is a failure.

- [ ] **Step 5: Capture the outcome**

Open the generated JSON report and add one short outcome paragraph to `docs/task6-resource-usage-reduction-notes.md`:

```markdown
Result: the first backend quantizer graph-shape probe reported `<status>` for
`<backend>/<quantizer>`. If skipped, the blocking reason was `<skip_reason>`.
If run, the post-`convert_pt2e` graph-shape failures were `<failure_reasons>`.
This tells us whether maintained backend quantizers are enough to pursue before
writing a Task 6-specific quantizer.
```

Replace the angle-bracket fields with exact values from the generated JSON.

- [ ] **Step 6: Commit outcome note if changed**

```bash
git add docs/task6-resource-usage-reduction-notes.md
git commit -m "docs: record backend quantizer probe outcome"
```

## Self-Review

Spec coverage:

- The plan explores maintained backend quantizers, including the NXP-style `convert_pt2e` regular-PyTorch path.
- It keeps Torch-MLIR import separate from ExecuTorch delegate lowering.
- It extends the existing graph-shape gate to distinguish linear/GEMV from attention matmul.
- It uses small, cheap probes before whole representative-core work.
- It records recommendations in Task 6-specific docs, not reviewer-controlled project-plan files.

Placeholder scan:

- No placeholder markers or unspecified "add tests" steps remain.
- The only angle-bracket text is explicitly in the final outcome template with instructions to replace it using generated JSON values.

Type consistency:

- `backend_quantizer_entrypoints`, `attempt_quantizer_imports`, and `object_import_status` are defined before tests use them.
- Probe JSON uses stable fields: `schema_version`, `backend`, `quantizer`, `status`, `skip_reason`, `detail`, `graph_shape_report`.
- The audit extension uses `aten.linear` and `float_linear_after_dequant` consistently.
