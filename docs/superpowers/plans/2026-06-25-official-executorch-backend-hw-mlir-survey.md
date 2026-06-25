# Official ExecuTorch Backend HW MLIR Survey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local experiment harness that runs TinyStories representative-core PT2E W2A2 through official ExecuTorch backend paths where possible and reports whether each path can produce useful HW MLIR for the existing LLM2FPGA pipeline.

**Architecture:** Add a small, report-driven survey harness under `scripts/task6/` and Nix packages under `nix/models.nix`/`flake.nix` only after the script can run locally. The harness separates backend inventory, backend lowering attempts, Torch-MLIR import attempts, and existing pipeline stage attempts so failures are concrete and comparable.

**Tech Stack:** Python 3, PyTorch/PT2E, ExecuTorch Python APIs when available, Torch-MLIR, existing LLM2FPGA Nix pipeline, JSON reports, unittest.

---

## File structure

- Create `scripts/task6/executorch_backend_survey.py`: CLI runner that inventories configured official backends, attempts lowering/import/stage probes, and writes `survey.json`.
- Create `scripts/task6/test_executorch_backend_survey.py`: pure-Python unit tests for classification, report schema, and failure handling.
- Create `docs/task6-executorch-official-backend-survey.md`: human-readable results note updated by the harness output.
- Modify `flake.nix`: add a package for the survey report after the script works locally.
- Modify `nix/models.nix`: add backend-specific pipeline targets only for backends that produce transparent Torch-MLIR-compatible graphs.
- Do not edit `docs/project-plan*`.
- Do not replace the current FPGA backend target until the survey identifies a better official-backend path.

## Task 1: Add report schema and backend classification tests

**Files:**
- Create: `scripts/task6/test_executorch_backend_survey.py`
- Create: `scripts/task6/executorch_backend_survey.py`

- [ ] **Step 1: Write the failing schema tests**

Create `scripts/task6/test_executorch_backend_survey.py` with:

```python
#!/usr/bin/env python3
from __future__ import annotations

import unittest

from scripts.task6.executorch_backend_survey import (
    BACKEND_CANDIDATES,
    classify_backend,
    make_report_entry,
    validate_report_entry,
)


class BackendSurveySchemaTest(unittest.TestCase):
    def test_candidate_order_starts_with_locally_useful_backends(self) -> None:
        self.assertEqual(BACKEND_CANDIDATES[:4], ["xnnpack", "example", "test", "vulkan"])

    def test_xnnpack_classification_is_local_first(self) -> None:
        info = classify_backend("xnnpack")
        self.assertEqual(info["backend"], "xnnpack")
        self.assertFalse(info["requires_hardware"])
        self.assertIn("executorch.backends.xnnpack", info["python_entrypoints"][0])

    def test_vendor_backend_classification_is_sdk_gated(self) -> None:
        info = classify_backend("qualcomm")
        self.assertEqual(info["backend"], "qualcomm")
        self.assertTrue(info["requires_sdk"])

    def test_report_entry_contains_required_keys(self) -> None:
        entry = make_report_entry("xnnpack", status="skip", skip_reason="executorch_not_importable")
        validate_report_entry(entry)
        self.assertEqual(entry["status"], "skip")
        self.assertEqual(entry["torch_mlir_status"], "skip")
        self.assertEqual(entry["graph_transparency"], "unknown")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and confirm it fails because the module does not exist**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected result:

```text
ModuleNotFoundError: No module named 'scripts.task6.executorch_backend_survey'
```

- [ ] **Step 3: Add the minimal survey schema implementation**

Create `scripts/task6/executorch_backend_survey.py` with:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any


BACKEND_CANDIDATES = [
    "xnnpack",
    "example",
    "test",
    "vulkan",
    "cadence",
    "arm",
    "cortex_m",
    "openvino",
    "aoti",
    "cuda",
    "webgpu",
    "mlx",
    "apple",
    "mediatek",
    "nxp",
    "qualcomm",
    "samsung",
]

SDK_GATED_BACKENDS = {"apple", "mediatek", "nxp", "qualcomm", "samsung"}
HARDWARE_GATED_BACKENDS = {"apple", "mediatek", "nxp", "qualcomm", "samsung"}

REQUIRED_REPORT_KEYS = {
    "backend",
    "status",
    "skip_reason",
    "requires_sdk",
    "requires_hardware",
    "python_entrypoints",
    "partitioned_ops",
    "unpartitioned_ops",
    "delegate_blob_count",
    "delegate_blob_bytes",
    "graph_transparency",
    "torch_mlir_status",
    "linalg_status",
    "cf_status",
    "hw_status",
    "torch_mlir_bytes",
    "hw_mlir_bytes",
    "hw_mlir_lines",
    "failure_signature",
}


def classify_backend(backend: str) -> dict[str, Any]:
    return {
        "backend": backend,
        "requires_sdk": backend in SDK_GATED_BACKENDS,
        "requires_hardware": backend in HARDWARE_GATED_BACKENDS,
        "python_entrypoints": backend_entrypoints(backend),
    }


def backend_entrypoints(backend: str) -> list[str]:
    mapping = {
        "xnnpack": [
            "executorch.backends.xnnpack.partition.xnnpack_partitioner",
            "executorch.backends.xnnpack.xnnpack_preprocess",
        ],
        "example": ["executorch.backends.example"],
        "test": ["executorch.backends.test"],
        "vulkan": ["executorch.backends.vulkan"],
        "cadence": ["executorch.backends.cadence"],
        "arm": ["executorch.backends.arm"],
        "cortex_m": ["executorch.backends.cortex_m"],
        "openvino": ["executorch.backends.openvino"],
        "aoti": ["executorch.backends.aoti"],
        "cuda": ["executorch.backends.cuda"],
        "webgpu": ["executorch.backends.webgpu"],
        "mlx": ["executorch.backends.mlx"],
        "apple": ["executorch.backends.apple"],
        "mediatek": ["executorch.backends.mediatek"],
        "nxp": ["executorch.backends.nxp"],
        "qualcomm": ["executorch.backends.qualcomm"],
        "samsung": ["executorch.backends.samsung"],
    }
    return mapping.get(backend, [f"executorch.backends.{backend}"])


def module_available(module_name: str) -> bool:
    return importlib.util.find_spec(module_name) is not None


def make_report_entry(backend: str, *, status: str, skip_reason: str | None = None) -> dict[str, Any]:
    info = classify_backend(backend)
    entry = {
        "backend": backend,
        "status": status,
        "skip_reason": skip_reason,
        "requires_sdk": info["requires_sdk"],
        "requires_hardware": info["requires_hardware"],
        "python_entrypoints": info["python_entrypoints"],
        "partitioned_ops": [],
        "unpartitioned_ops": [],
        "delegate_blob_count": None,
        "delegate_blob_bytes": None,
        "graph_transparency": "unknown",
        "torch_mlir_status": "skip",
        "linalg_status": "skip",
        "cf_status": "skip",
        "hw_status": "skip",
        "torch_mlir_bytes": None,
        "hw_mlir_bytes": None,
        "hw_mlir_lines": None,
        "failure_signature": skip_reason,
    }
    validate_report_entry(entry)
    return entry


def validate_report_entry(entry: dict[str, Any]) -> None:
    missing = REQUIRED_REPORT_KEYS - set(entry)
    if missing:
        raise ValueError(f"report entry missing keys: {sorted(missing)}")
    if entry["status"] not in {"pass", "skip", "fail"}:
        raise ValueError(f"invalid status: {entry['status']!r}")
    if entry["graph_transparency"] not in {"transparent", "mixed", "opaque", "unknown"}:
        raise ValueError(f"invalid graph_transparency: {entry['graph_transparency']!r}")


def inventory_backends(backends: list[str]) -> list[dict[str, Any]]:
    entries = []
    for backend in backends:
        info = classify_backend(backend)
        available = any(module_available(name) for name in info["python_entrypoints"])
        if not available:
            entries.append(make_report_entry(backend, status="skip", skip_reason="executorch_backend_not_importable"))
            continue
        entries.append(make_report_entry(backend, status="skip", skip_reason="lowering_probe_not_implemented"))
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--backend", action="append", choices=BACKEND_CANDIDATES)
    args = parser.parse_args()

    backends = args.backend or BACKEND_CANDIDATES
    payload = {"backends": inventory_backends(backends)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the schema tests and confirm they pass**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected result:

```text
Ran 4 tests
OK
```

- [ ] **Step 5: Commit the schema harness**

Run:

```bash
git add scripts/task6/executorch_backend_survey.py scripts/task6/test_executorch_backend_survey.py
git commit -m "task6: add executorch backend survey schema"
```

## Task 2: Add backend import inventory report

**Files:**
- Modify: `scripts/task6/test_executorch_backend_survey.py`
- Modify: `scripts/task6/executorch_backend_survey.py`
- Create: `docs/task6-executorch-official-backend-survey.md`

- [ ] **Step 1: Add a test for JSON inventory output**

Append this test class to `scripts/task6/test_executorch_backend_survey.py`:

```python
import json
import tempfile
from pathlib import Path

from scripts.task6.executorch_backend_survey import main


class BackendSurveyCliTest(unittest.TestCase):
    def test_cli_writes_inventory_report_for_selected_backend(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out = Path(tmpdir) / "survey.json"
            rc = main_with_args(["--backend", "xnnpack", "--out", str(out)])
            self.assertEqual(rc, 0)
            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(len(payload["backends"]), 1)
            self.assertEqual(payload["backends"][0]["backend"], "xnnpack")
```

Also add this helper near the imports:

```python
def main_with_args(argv: list[str]) -> int:
    import sys
    from unittest import mock

    with mock.patch.object(sys, "argv", ["executorch_backend_survey.py", *argv]):
        return main()
```

- [ ] **Step 2: Run the test and confirm it fails because `main` exits through argparse correctly but helper is not present until added**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected before helper/import corrections:

```text
NameError or ImportError related to main_with_args/main
```

- [ ] **Step 3: Add the helper/imports exactly as shown in Step 1**

Edit `scripts/task6/test_executorch_backend_survey.py` to include the helper and imports.

- [ ] **Step 4: Run the CLI manually**

Run:

```bash
python3 scripts/task6/executorch_backend_survey.py --backend xnnpack --out /tmp/executorch-backend-survey-xnnpack.json
cat /tmp/executorch-backend-survey-xnnpack.json
```

Expected result includes:

```json
{
  "backends": [
    {
      "backend": "xnnpack"
    }
  ]
}
```

The actual object contains all schema fields.

- [ ] **Step 5: Add initial human-readable survey note**

Create `docs/task6-executorch-official-backend-survey.md` with:

```markdown
# Task 6 Official ExecuTorch Backend Survey

This note tracks the official ExecuTorch backend survey for TinyStories representative-core PT2E static W2A2.

## Purpose

Use official ExecuTorch backends as semantic graph-shaping frontends before writing custom FPGA backend semantics.

## Current acceptance rule

A backend is not accepted because Yosys runs. A backend is promising only when it uses official ExecuTorch lowering APIs and produces a graph or artifact that can be connected to reference-output comparison.

## Initial candidate order

1. xnnpack
2. example
3. test
4. vulkan
5. cadence
6. arm
7. cortex_m
8. openvino
9. aoti
10. cuda
11. webgpu
12. mlx
13. apple
14. mediatek
15. nxp
16. qualcomm
17. samsung
```

- [ ] **Step 6: Run tests**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected result:

```text
OK
```

- [ ] **Step 7: Commit inventory reporting**

Run:

```bash
git add scripts/task6/executorch_backend_survey.py scripts/task6/test_executorch_backend_survey.py docs/task6-executorch-official-backend-survey.md
git commit -m "task6: inventory official executorch backends"
```

## Task 3: Probe XNNPACK official lowering without HW MLIR first

**Files:**
- Modify: `scripts/task6/executorch_backend_survey.py`
- Modify: `scripts/task6/test_executorch_backend_survey.py`

- [ ] **Step 1: Add a unit test for opaque delegate classification**

Add to `BackendSurveySchemaTest`:

```python
    def test_delegate_call_marks_graph_opaque(self) -> None:
        from scripts.task6.executorch_backend_survey import classify_graph_transparency

        text = "executorch_call_delegate(lowered_module_0, arg0)"
        self.assertEqual(classify_graph_transparency(text), "opaque")

    def test_aten_graph_marks_graph_transparent(self) -> None:
        from scripts.task6.executorch_backend_survey import classify_graph_transparency

        text = "%mm = call_function[target=torch.ops.aten.mm.default](args=(%x, %w), kwargs={})"
        self.assertEqual(classify_graph_transparency(text), "transparent")
```

- [ ] **Step 2: Run the tests and confirm missing function failure**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected result:

```text
ImportError: cannot import name 'classify_graph_transparency'
```

- [ ] **Step 3: Implement graph transparency classification**

Add to `scripts/task6/executorch_backend_survey.py`:

```python
def classify_graph_transparency(graph_text: str) -> str:
    lowered = graph_text.lower()
    if "executorch_call_delegate" in lowered or "delegate" in lowered and "blob" in lowered:
        return "opaque"
    if "torch.ops.aten" in graph_text or "call_function" in graph_text:
        return "transparent"
    if "delegate" in lowered:
        return "mixed"
    return "unknown"
```

- [ ] **Step 4: Add XNNPACK probe function skeleton that fails safely when ExecuTorch is unavailable**

Add to `scripts/task6/executorch_backend_survey.py`:

```python
def probe_xnnpack_lowering() -> dict[str, Any]:
    if not module_available("executorch.backends.xnnpack.partition.xnnpack_partitioner"):
        return make_report_entry("xnnpack", status="skip", skip_reason="executorch_xnnpack_not_importable")
    entry = make_report_entry("xnnpack", status="skip", skip_reason="xnnpack_probe_requires_executorch_runtime_wiring")
    entry["graph_transparency"] = "unknown"
    validate_report_entry(entry)
    return entry
```

- [ ] **Step 5: Route XNNPACK inventory through the probe**

In `inventory_backends`, before generic availability handling, add:

```python
        if backend == "xnnpack":
            entries.append(probe_xnnpack_lowering())
            continue
```

- [ ] **Step 6: Run tests**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected result:

```text
OK
```

- [ ] **Step 7: Commit XNNPACK probe scaffold**

Run:

```bash
git add scripts/task6/executorch_backend_survey.py scripts/task6/test_executorch_backend_survey.py
git commit -m "task6: scaffold xnnpack executorch probe"
```

## Task 4: Add Nix survey package

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add a package that runs inventory only**

In `flake.nix`, near Task 6 package definitions, add a `pkgs.runCommand` package named `task6-executorch-official-backend-survey`:

```nix
task6ExecuTorchOfficialBackendSurvey = pkgs.runCommand
  "task6-executorch-official-backend-survey"
  {
    buildInputs = [ pythonWithTinyStories ];
  } ''
    mkdir -p "$out"
    export PYTHONPATH="${./.}:''${PYTHONPATH:-}"
    python ${./scripts/task6/executorch_backend_survey.py} \
      --out "$out/survey.json"
  '';
```

Expose it in the package set as:

```nix
task6-executorch-official-backend-survey = task6ExecuTorchOfficialBackendSurvey;
```

- [ ] **Step 2: Build the survey package**

Run:

```bash
nix build .#task6-executorch-official-backend-survey -L
```

Expected result:

```text
result/survey.json exists
```

- [ ] **Step 3: Inspect the report**

Run:

```bash
cat result/survey.json
```

Expected result: JSON with entries for all candidates and explicit skip/fail/pass statuses.

- [ ] **Step 4: Commit Nix survey package**

Run:

```bash
git add flake.nix
git commit -m "task6: add official executorch backend survey package"
```

## Task 5: Add real official-backend lowering probes one backend at a time

**Files:**
- Modify: `scripts/task6/executorch_backend_survey.py`
- Modify: `scripts/task6/test_executorch_backend_survey.py`
- Modify: `docs/task6-executorch-official-backend-survey.md`

- [ ] **Step 1: Add `attempt_backend_imports` tests**

Add tests:

```python
    def test_attempt_backend_imports_reports_missing_modules(self) -> None:
        from scripts.task6.executorch_backend_survey import attempt_backend_imports

        result = attempt_backend_imports(["definitely_missing_executorch_backend_module"])
        self.assertFalse(result["available"])
        self.assertEqual(result["available_modules"], [])

    def test_attempt_backend_imports_reports_available_stdlib_module(self) -> None:
        from scripts.task6.executorch_backend_survey import attempt_backend_imports

        result = attempt_backend_imports(["json"])
        self.assertTrue(result["available"])
        self.assertEqual(result["available_modules"], ["json"])
```

- [ ] **Step 2: Implement `attempt_backend_imports`**

Add:

```python
def attempt_backend_imports(module_names: list[str]) -> dict[str, Any]:
    available = [name for name in module_names if module_available(name)]
    return {"available": bool(available), "available_modules": available}
```

- [ ] **Step 3: For each backend, add only one real probe when its official Python API is importable**

Use this pattern for each backend-specific probe:

```python
def probe_backend_by_import_only(backend: str) -> dict[str, Any]:
    info = classify_backend(backend)
    imports = attempt_backend_imports(info["python_entrypoints"])
    if not imports["available"]:
        return make_report_entry(backend, status="skip", skip_reason="executorch_backend_not_importable")
    entry = make_report_entry(backend, status="skip", skip_reason="backend_lowering_probe_not_connected")
    entry["python_entrypoints"] = imports["available_modules"]
    validate_report_entry(entry)
    return entry
```

- [ ] **Step 4: Run import inventory through Nix**

Run:

```bash
nix build .#task6-executorch-official-backend-survey -L
cat result/survey.json
```

Expected result: each backend has a concrete importability status.

- [ ] **Step 5: Update the survey note with importability findings**

Append a section to `docs/task6-executorch-official-backend-survey.md`:

```markdown
## Importability findings

The current survey package records which official backend Python entrypoints are importable in the local Nix environment. Backends that are not importable are skipped before any lowering attempt. Backends that require proprietary SDKs remain inventory-only unless a pure local preprocessing API is available.
```

- [ ] **Step 6: Commit import probes**

Run:

```bash
git add scripts/task6/executorch_backend_survey.py scripts/task6/test_executorch_backend_survey.py docs/task6-executorch-official-backend-survey.md
git commit -m "task6: probe official executorch backend imports"
```

## Task 6: Add Torch-MLIR/HW MLIR attempt only for transparent lowered graphs

**Files:**
- Modify: `scripts/task6/executorch_backend_survey.py`
- Modify: `scripts/task6/test_executorch_backend_survey.py`

- [ ] **Step 1: Add test for stage-skip behavior on opaque graphs**

Add:

```python
    def test_opaque_graph_skips_mlir_stages(self) -> None:
        from scripts.task6.executorch_backend_survey import apply_transparency_to_stage_status

        entry = make_report_entry("xnnpack", status="pass")
        entry["graph_transparency"] = "opaque"
        apply_transparency_to_stage_status(entry)
        self.assertEqual(entry["torch_mlir_status"], "skip")
        self.assertEqual(entry["failure_signature"], "opaque_delegate_graph")
```

- [ ] **Step 2: Implement `apply_transparency_to_stage_status`**

Add:

```python
def apply_transparency_to_stage_status(entry: dict[str, Any]) -> None:
    if entry["graph_transparency"] == "opaque":
        entry["torch_mlir_status"] = "skip"
        entry["linalg_status"] = "skip"
        entry["cf_status"] = "skip"
        entry["hw_status"] = "skip"
        entry["failure_signature"] = "opaque_delegate_graph"
    validate_report_entry(entry)
```

- [ ] **Step 3: Add file-stat helper tests**

Add:

```python
    def test_collect_file_stats_counts_bytes_and_lines(self) -> None:
        from scripts.task6.executorch_backend_survey import collect_file_stats
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "x.mlir"
            path.write_text("a\nb\n", encoding="utf-8")
            self.assertEqual(collect_file_stats(path), {"bytes": 4, "lines": 2})
```

- [ ] **Step 4: Implement file-stat helper**

Add:

```python
def collect_file_stats(path: Path) -> dict[str, int]:
    data = path.read_bytes()
    return {"bytes": len(data), "lines": data.count(b"\n")}
```

- [ ] **Step 5: Do not call Nix from Python yet**

Record the stage status as `skip` unless a transparent exported graph file exists. This prevents the survey harness from accidentally launching expensive builds before graph transparency is known.

- [ ] **Step 6: Run tests**

Run:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
```

Expected result:

```text
OK
```

- [ ] **Step 7: Commit transparent-graph stage guard**

Run:

```bash
git add scripts/task6/executorch_backend_survey.py scripts/task6/test_executorch_backend_survey.py
git commit -m "task6: guard mlir lowering on graph transparency"
```

## Task 7: Decide whether to retire the local FPGA backend surrogate

**Files:**
- Modify: `docs/task6-executorch-official-backend-survey.md`
- Modify later only if approved: `TinyStories/model_adapter_representative_core_pt2e_static_quant_fpga_backend.py`, `src/llm2fpga_executorch_backend/torch_mlir_surrogate.py`, `nix/models.nix`

- [ ] **Step 1: Add a decision section to the survey note**

Append:

```markdown
## Decision gate for local FPGA backend surrogate

The local FPGA backend surrogate remains a wiring diagnostic only. It must not be treated as semantic proof. After the official-backend survey identifies a transparent and useful official backend path, either replace the surrogate target with that path or rename the surrogate target so it cannot be confused with a semantic backend.
```

- [ ] **Step 2: Do not delete the surrogate yet**

Keep the current target until at least one official backend path has produced a concrete report. Deleting it early removes the known-good small Yosys smoke path.

- [ ] **Step 3: Commit the decision note**

Run:

```bash
git add docs/task6-executorch-official-backend-survey.md
git commit -m "task6: document fpga backend surrogate decision gate"
```

## Final verification

Run these commands after all tasks complete:

```bash
python3 -m unittest scripts/task6/test_executorch_backend_survey.py
nix build .#task6-executorch-official-backend-survey -L
cat result/survey.json
```

Expected final state:

- Unit tests pass.
- Nix survey package builds.
- `survey.json` exists and has one report entry per official backend candidate.
- Each backend has explicit importability, skip/fail/pass status, and graph transparency status.
- No backend is accepted solely because HW MLIR or Yosys exists.

