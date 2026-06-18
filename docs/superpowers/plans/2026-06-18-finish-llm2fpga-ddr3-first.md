# Finish LLM2FPGA DDR3-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the remaining NLnet scope by proving TinyStories-1M token-exact inference on the YPCB board through a DDR3-backed open-source FPGA flow, then scaling the same path to larger TinyStories variants.

**Architecture:** The mainline is manifest -> quantized contracts -> DDR3 row/weight movement -> staged kernel board gates -> full TinyStories-1M inference -> scaling gates. BRAM/on-chip designs stay as regression and diagnostic fixtures, not the primary completion route.

**Tech Stack:** Nix flakes, Just, Python gate/orchestration scripts, SystemVerilog RTL/testbenches, Yosys/OpenXC7/nextpnr-xilinx, YPCB-00338-1P1, PCIe, UberDDR3/LiteDRAM experiments, Org/JSON state docs.

---

## File Structure

- Modify: `docs/human-plan.org` - make this the short human-facing top plan, or replace it with the canonical path chosen in Task 1.
- Modify: `docs/task6-crisp-state.org` - human-readable state-of-the-art truth.
- Modify: `docs/task6-crisp-state.json` - machine-readable state-of-the-art truth.
- Modify: `docs/task6-resource-usage-reduction-notes.md` - append Task 6 detail notes only when detail exceeds the crisp state.
- Create: `docs/finish-llm2fpga.org` - top-level canonical org plan if `docs/human-plan.org` remains a scratch file.
- Create: `.agents/README.md` - short agent rules for commits, state updates, and verification.
- Modify: `flake.nix` - add small canonical aliases first; split only after aliases are covered.
- Create: `nix/current.nix` - eventual canonical package set for default, latest passing, bottleneck, and board gate dependencies.
- Create: `nix/task6-ddr3.nix` - eventual Task 6 DDR3 and inference package set.
- Create: `nix/previous-tasks.nix` - eventual aliases for Task 2/Task 3 historical deliverables.
- Modify: `justfile` - add short canonical recipes for latest passing, bottleneck, DDR3 gates, state validation, and cleanup checks.
- Modify or create: `scripts/task6/task6_state_validate.py` - validate crisp state JSON and org required fields.
- Modify or create: `scripts/task6/task6_repo_surface_check.py` - enforce file-size/root-surface guardrails with exclusions for historical/artifact directories.

Do not edit `docs/project-plan*` unless the user explicitly says reviewer approval was obtained.

## Milestone Definitions

- `G0-control`: state files, aliases, and commands make the project state unambiguous.
- `G1-latest-green`: `nix build` builds the latest passing milestone, and the matching board gate either passes or records a precise hardware failure signature.
- `G2-bottleneck`: `nix build .#bottleneck` builds the current unsolved DDR3/inference target, and its gate records the exact failing delta from `G1`.
- `D0-ddr3-boot`: DDR3 boot/calibration is stable on the current board session.
- `D1-rowstream-integrity`: TinyStories rowstream load/readback is byte-accurate at boundary rows, then by full/chunk hash.
- `D2-output-head`: DDR3-backed TinyStories output-head top1 remains green.
- `M1-transformer-boundary`: board runs the MLP/residual boundary with host-supplied activations/residuals.
- `M2-one-full-block-ddr3`: board runs one complete TinyStories block using DDR3-backed model movement where required.
- `M3-tinystories-1m-ddr3`: board returns token-exact greedy TinyStories-1M output for the fixed prompt/vector set.
- `S1-scaling`: repeat the manifest/contract/gate path for larger TinyStories sizes and record resource/performance scaling.

## Task 1: Canonical Human Plan and State Contract

**Files:**
- Modify: `docs/human-plan.org`
- Modify: `docs/task6-crisp-state.org`
- Modify: `docs/task6-crisp-state.json`
- Modify: `docs/task6-resource-usage-reduction-notes.md`
- Optionally create: `docs/finish-llm2fpga.org`

- [ ] **Step 1: Decide canonical human-plan path**

Use `docs/human-plan.org` as canonical if it is meant to be committed. Otherwise create `docs/finish-llm2fpga.org` and leave `docs/human-plan.org` as scratch until deleted or absorbed.

Run:

```bash
git status --short
sed -n '1,220p' docs/human-plan.org
```

Expected: `docs/human-plan.org` is untracked or modified, and its content is the hierarchy from this plan.

- [ ] **Step 2: Write the top-level org plan**

Content requirements:

```org
* LLM2FPGA Finish Plan
** Canonical state
- Human state: [[file:task6-crisp-state.org][docs/task6-crisp-state.org]]
- Machine state: [[file:task6-crisp-state.json][docs/task6-crisp-state.json]]
- Task 6 details: [[file:task6-resource-usage-reduction-notes.md][docs/task6-resource-usage-reduction-notes.md]]

** Priority
DDR3-first. The first full TinyStories-1M inference proof should use the DDR3-backed model/row movement path that can scale to larger TinyStories sizes. BRAM-only/on-chip targets are diagnostics and regressions.

** Remaining grant tasks
*** TODO Task 6: resource minimization and fitting inference
*** TODO Task 4: FPGA inference demonstration
*** TODO Task 5: scaling to larger TinyStories sizes

** Current control targets
*** TODO Latest passing milestone
- Command: =nix build=
- Board gate: =just task6-latest-passing-milestone-board-gate=

*** TODO Current bottleneck
- Command: =nix build .#bottleneck=
- Gate: =just task6-bottleneck-board-gate=

** DDR3-first inference ladder
*** TODO D0 DDR3 boot/calibration
*** TODO D1 TinyStories rowstream integrity
*** TODO D2 DDR3 output-head top1
*** TODO M1 transformer-boundary MLP/residual
*** TODO M2 one full block, DDR3-backed where required
*** TODO M3 TinyStories-1M token-exact greedy inference
*** TODO S1 larger TinyStories scaling
```

- [ ] **Step 3: Normalize `docs/task6-crisp-state.json` required fields**

Keep these exact top-level keys:

```json
{
  "last_updated": "2026-06-18T00:00:00+02:00",
  "milestone": "G0-control",
  "build_variant": "nix build -> .#latest-passing-milestone",
  "next_milestone": "G1-latest-green",
  "latest_green_artifact": "",
  "current_gap": "Canonical aliases and DDR3-first bottleneck gate are not yet fully defined.",
  "failure_signature": "",
  "next_action": "Add latest-passing and bottleneck aliases, then validate the latest passing board gate.",
  "status": "PLANNING"
}
```

Only add extra fields if they are useful for automation; do not remove the required fields.

- [ ] **Step 4: Mirror the JSON state in `docs/task6-crisp-state.org`**

Use the same required fields in a short org section. Keep long history in `docs/task6-resource-usage-reduction-notes.md`.

- [ ] **Step 5: Validate manually**

Run:

```bash
python3 -m json.tool docs/task6-crisp-state.json >/tmp/task6-crisp-state.pretty.json
rg "milestone|build_variant|next_milestone|latest_green_artifact|current_gap|failure_signature|next_action" docs/task6-crisp-state.org docs/task6-crisp-state.json
```

Expected: JSON parses and each required field appears in both files.

- [ ] **Step 6: Commit**

```bash
git add docs/human-plan.org docs/task6-crisp-state.org docs/task6-crisp-state.json docs/task6-resource-usage-reduction-notes.md
git commit -m "docs: define DDR3-first finish plan state"
```

If `docs/finish-llm2fpga.org` is used instead, add that file and either remove or intentionally leave `docs/human-plan.org` untracked.

## Task 2: Agent Instructions

**Files:**
- Create: `.agents/README.md`
- Modify: `AGENTS.md` only if a short pointer to `.agents/README.md` is needed.

- [ ] **Step 1: Create `.agents/README.md`**

Write:

```markdown
# Agent Rules

- Make short commits for each coherent piece of work.
- Before editing, check `git status --short` and do not overwrite unrelated user changes.
- Keep `docs/project-plan*` unchanged unless the user says reviewer approval was obtained.
- Keep detailed Task 6 notes in `docs/task6-resource-usage-reduction-notes.md`.
- Update `docs/task6-crisp-state.org` and `docs/task6-crisp-state.json` whenever milestone, bottleneck, failure signature, or next action changes.
- Treat DDR3-backed TinyStories-1M inference as the main completion route.
- Treat BRAM-only/on-chip targets as diagnostics or regressions unless the user changes priority.
- Every final work report must include verification commands run, or explicitly say what was not run.
```

- [ ] **Step 2: Check whether `AGENTS.md` needs a pointer**

Run:

```bash
sed -n '1,220p' AGENTS.md
```

If `.agents/README.md` is not discoverable enough, add one line:

```markdown
- Additional per-agent workflow rules live in [.agents/README.md](.agents/README.md).
```

- [ ] **Step 3: Commit**

```bash
git add .agents/README.md AGENTS.md
git commit -m "docs: add agent workflow rules"
```

## Task 3: Canonical Build Aliases

**Files:**
- Modify: `flake.nix`
- Modify: `justfile`

- [ ] **Step 1: Inspect the current package alias block**

Run:

```bash
sed -n '15500,15560p' flake.nix
sed -n '1,80p' justfile
```

Expected: `default = latestPassingMilestoneBitstream;` and `latest-passing-milestone = latestPassingMilestoneBitstream;` already exist.

- [ ] **Step 2: Add or confirm `bottleneck` alias**

Set `bottleneck` to the current DDR3-first failing target. Initial value should be the target that exercises the next unresolved DDR3 TinyStories inference gate, not a BRAM-only M2 proof.

Candidate if current failure remains loader readiness:

```nix
bottleneck = latestPassingMilestoneBitstream;
```

Replace with a more specific package once the next DDR3 inference build target is identified, for example:

```nix
bottleneck = task6YpcbPcieUberDdr3RowstreamLoaderOnlyTop1Pnr100Bitstream;
```

Do not choose a Nix store path. Use a derivation already defined in `flake.nix`.

- [ ] **Step 3: Add Just recipes**

Add these recipes near the existing latest-passing recipes:

```just
task6-bottleneck-bitstream:
    nix build .#bottleneck --no-link --print-out-paths

task6-bottleneck-board-gate bitstream='' model_path='' run_root='artifacts/task6/runs/task6-bottleneck' sample_count='8':
    if [ -n "{{model_path}}" ]; then if [ -n "{{bitstream}}" ]; then python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "{{bitstream}}" --model-path "{{model_path}}" --sample-count "{{sample_count}}" --json-only --run-root "{{run_root}}"; else python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "$(nix build .#bottleneck --no-link --print-out-paths)" --model-path "{{model_path}}" --sample-count "{{sample_count}}" --json-only --run-root "{{run_root}}"; fi; else if [ -n "{{bitstream}}" ]; then python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "{{bitstream}}" --skip-top1 --skip-inference --json-only --run-root "{{run_root}}"; else python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "$(nix build .#bottleneck --no-link --print-out-paths)" --skip-top1 --skip-inference --json-only --run-root "{{run_root}}"; fi; fi
```

- [ ] **Step 4: Verify aliases**

Run:

```bash
nix eval .#default.name
nix eval .#latest-passing-milestone.name
nix eval .#bottleneck.name
just --list | rg "task6-(latest-passing|bottleneck)"
```

Expected: all three Nix evals return derivation names and Just lists four recipes.

- [ ] **Step 5: Commit**

```bash
git add flake.nix justfile
git commit -m "nix: add canonical Task 6 build aliases"
```

## Task 4: State Validator

**Files:**
- Create: `scripts/task6/task6_state_validate.py`
- Modify: `justfile`

- [ ] **Step 1: Add validator script**

Create `scripts/task6/task6_state_validate.py`:

```python
#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REQUIRED = [
    "milestone",
    "build_variant",
    "next_milestone",
    "latest_green_artifact",
    "current_gap",
    "failure_signature",
    "next_action",
]


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    json_path = repo / "docs" / "task6-crisp-state.json"
    org_path = repo / "docs" / "task6-crisp-state.org"
    payload = json.loads(json_path.read_text())
    missing_json = [key for key in REQUIRED if key not in payload]
    org_text = org_path.read_text()
    missing_org = [key for key in REQUIRED if key not in org_text]
    if missing_json or missing_org:
        if missing_json:
            print(f"missing JSON fields: {', '.join(missing_json)}", file=sys.stderr)
        if missing_org:
            print(f"missing org fields: {', '.join(missing_org)}", file=sys.stderr)
        return 1
    print("task6 crisp state validates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Add Just recipe**

```just
task6-state-validate:
    python3 scripts/task6/task6_state_validate.py
```

- [ ] **Step 3: Run validator**

```bash
python3 -m py_compile scripts/task6/task6_state_validate.py
python3 scripts/task6/task6_state_validate.py
just task6-state-validate
```

Expected: py_compile succeeds and validator prints `task6 crisp state validates`.

- [ ] **Step 4: Commit**

```bash
git add scripts/task6/task6_state_validate.py justfile
git commit -m "task6: validate crisp state files"
```

## Task 5: Latest Green Board Gate

**Files:**
- Modify: `docs/task6-crisp-state.org`
- Modify: `docs/task6-crisp-state.json`
- Append: `docs/task6-resource-usage-reduction-notes.md`

- [ ] **Step 1: Build latest passing milestone**

Run:

```bash
nix build
nix build .#latest-passing-milestone --no-link --print-out-paths
```

Expected: both commands build the same or intentionally equivalent bitstream derivation.

- [ ] **Step 2: Run the latest-passing board gate**

Use a dated run root:

```bash
just task6-latest-passing-milestone-board-gate run_root="artifacts/task6/runs/$(date +%Y-%m-%dT%H-%M-%S%z)-latest-passing"
```

Expected if green: JSON artifact reports PASS. Expected if not green: JSON/log captures the exact failure signature.

- [ ] **Step 3: Update crisp state**

If green:

```json
"milestone": "G1-latest-green",
"latest_green_artifact": "artifacts/task6/runs/<run>/...",
"current_gap": "Bottleneck DDR3 inference target is next.",
"failure_signature": "",
"next_action": "Build and run .#bottleneck with explicit run_root."
```

If failing:

```json
"milestone": "G1-latest-green",
"latest_green_artifact": "",
"current_gap": "Latest passing board gate is not green.",
"failure_signature": "<exact first failing line or JSON status>",
"next_action": "<single next diagnostic action>"
```

- [ ] **Step 4: Commit**

```bash
git add docs/task6-crisp-state.org docs/task6-crisp-state.json docs/task6-resource-usage-reduction-notes.md
git commit -m "task6: record latest green gate status"
```

## Task 6: DDR3 Bottleneck Gate

**Files:**
- Modify: `docs/task6-crisp-state.org`
- Modify: `docs/task6-crisp-state.json`
- Append: `docs/task6-resource-usage-reduction-notes.md`

- [ ] **Step 1: Build bottleneck**

Run:

```bash
nix build .#bottleneck --no-link --print-out-paths
```

Expected: derivation builds, even if the later hardware gate fails.

- [ ] **Step 2: Run bottleneck board gate**

```bash
just task6-bottleneck-board-gate run_root="artifacts/task6/runs/$(date +%Y-%m-%dT%H-%M-%S%z)-bottleneck"
```

Expected if green: advance `next_milestone` to the next DDR3 ladder rung. Expected if failing: record exact failing stage.

- [ ] **Step 3: Classify the gap**

Use one of these gap labels in `docs/task6-crisp-state.json`:

```text
BLOCKED_DDR3_BOOT
BLOCKED_ROWSTREAM_LOAD
BLOCKED_ROWSTREAM_READBACK
BLOCKED_OUTPUT_HEAD_TOP1
BLOCKED_M1_TRANSFORMER_BOUNDARY
BLOCKED_M2_ONE_BLOCK
BLOCKED_M3_FULL_INFERENCE
```

- [ ] **Step 4: Commit**

```bash
git add docs/task6-crisp-state.org docs/task6-crisp-state.json docs/task6-resource-usage-reduction-notes.md
git commit -m "task6: record DDR3 bottleneck gate"
```

## Task 7: DDR3 Gate Ladder Recipes

**Files:**
- Modify: `justfile`
- Modify or create scripts only where a missing gate cannot already be expressed.

- [ ] **Step 1: Inventory existing gate scripts**

Run:

```bash
find scripts/task6 -maxdepth 1 -type f | sort | rg "ddr3|rowstream|tinystories|m2|m3|gate"
```

Expected: existing scripts include rowstream, TinyStories inference, M2, M3, and DDR3 support.

- [ ] **Step 2: Add recipe names that match the ladder**

Add aliases to existing scripts rather than duplicating logic:

```just
task6-ddr3-boot-gate:
    python3 scripts/task6/task6_ddr3_experiment_runner.py --gate boot

task6-ddr3-rowstream-boundary-gate:
    python3 scripts/task6/task6_pcie_rowstream_top1_gate.py --boundary-rows 0,1,31,32,50256

task6-ddr3-rowstream-top1-gate:
    python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --skip-inference --json-only

task6-ddr3-full-inference-gate:
    python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --json-only
```

If the exact flags are not supported, implement the smallest script changes to make these recipes real and covered by unit tests.

- [ ] **Step 3: Verify recipe parse**

```bash
just --list | rg "task6-ddr3"
```

Expected: four DDR3 ladder recipes are listed.

- [ ] **Step 4: Commit**

```bash
git add justfile scripts/task6
git commit -m "task6: add DDR3 gate ladder recipes"
```

## Task 8: Repo Surface Inventory

**Files:**
- Create: `docs/repo-surface-inventory.md`
- Create: `scripts/task6/task6_repo_surface_check.py`
- Modify: `justfile`

- [ ] **Step 1: Generate an inventory**

Run:

```bash
find . -maxdepth 2 -type f | sort > /tmp/llm2fpga-root-surface.txt
find rtl fpga sim scripts src TinyStories nix docs -maxdepth 2 -type f | sort > /tmp/llm2fpga-main-surface.txt
wc -l /tmp/llm2fpga-root-surface.txt /tmp/llm2fpga-main-surface.txt
```

- [ ] **Step 2: Write `docs/repo-surface-inventory.md`**

Use this structure:

```markdown
# Repo Surface Inventory

## Canonical Active Surface

- `flake.nix`: temporary root flake; should shrink through `nix/*.nix` modules.
- `justfile`: human command surface.
- `docs/task6-crisp-state.org`: human state.
- `docs/task6-crisp-state.json`: machine state.
- `docs/human-plan.org` or `docs/finish-llm2fpga.org`: top plan.
- `scripts/task6/`: Task 6 board, gate, quantization, and artifact scripts.
- `rtl/task6/`: reusable Task 6 kernels.
- `fpga/rtl/`: board-facing tops and PCIe/DDR3 integration.
- `sim/`: SystemVerilog testbenches and generated-vector helpers.
- `nix/`: reusable Nix modules.

## Historical Surface To Hide Behind Aliases

- `deliverables/`: reviewer artifacts; do not churn.
- `patches/circt-task3-rfp/`: Task 3 patch history.
- `patches/torch-mlir-task3-rfp/`: Task 3 patch history.
- Task 2/Task 3 RTL/Python that is not used by current aliases.

## Excluded From File-Size Checks

- `.git/`
- `artifacts/`
- `deliverables/`
- `patches/`
- generated `__pycache__/`
- Nix `result` symlinks
```

- [ ] **Step 3: Add surface check script**

Create a script that fails on oversized active files while excluding historical/artifact paths. Initial thresholds:

```python
#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
EXCLUDED_PREFIXES = (
    ".git/",
    "artifacts/",
    "deliverables/",
    "patches/",
)
EXCLUDED_NAMES = {"__pycache__", "result"}
MAX_LINES = {
    "flake.nix": 18000,
    "justfile": 800,
}
DEFAULT_MAX_LINES = 1200


def excluded(path: Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    if any(part in EXCLUDED_NAMES for part in path.parts):
        return True
    return rel.startswith(EXCLUDED_PREFIXES)


def line_count(path: Path) -> int:
    try:
        return len(path.read_text(errors="ignore").splitlines())
    except UnicodeDecodeError:
        return 0


def main() -> int:
    failures = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or excluded(path):
            continue
        rel = path.relative_to(ROOT).as_posix()
        limit = MAX_LINES.get(rel, DEFAULT_MAX_LINES)
        count = line_count(path)
        if count > limit:
            failures.append(f"{rel}: {count} lines > {limit}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("repo surface check passes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Add Just recipe**

```just
repo-surface-check:
    python3 scripts/task6/task6_repo_surface_check.py
```

- [ ] **Step 5: Verify**

```bash
python3 -m py_compile scripts/task6/task6_repo_surface_check.py
python3 scripts/task6/task6_repo_surface_check.py
```

Expected initially may be FAIL. If it fails, either add justified exclusions or create follow-up tasks for splits. Do not inflate thresholds to hide active complexity.

- [ ] **Step 6: Commit**

```bash
git add docs/repo-surface-inventory.md scripts/task6/task6_repo_surface_check.py justfile
git commit -m "repo: add surface inventory and guard"
```

## Task 9: Split Flake Surface Without Behavior Changes

**Files:**
- Modify: `flake.nix`
- Create: `nix/current.nix`
- Create: `nix/task6-ddr3.nix`
- Create: `nix/previous-tasks.nix`

- [ ] **Step 1: Add modules as pass-through attrset helpers**

Start with tiny files that do not move derivation definitions yet.

`nix/current.nix`:

```nix
{ latestPassingMilestoneBitstream, bottleneckBitstream ? latestPassingMilestoneBitstream }:
{
  default = latestPassingMilestoneBitstream;
  latest-passing-milestone = latestPassingMilestoneBitstream;
  bottleneck = bottleneckBitstream;
}
```

`nix/task6-ddr3.nix`:

```nix
attrs:
{
  inherit (attrs)
    task6-ypcb-pcie-uberddr3-rowstream-loader-only-top1-bitstream
    task6-ypcb-ddr3-inference-gate-runbook
    ;
}
```

Adjust names to existing package aliases exactly as they appear in `flake.nix`.

- [ ] **Step 2: Import one module at a time**

In `flake.nix`, replace only the duplicated alias block for default/latest/bottleneck first:

```nix
canonicalPackages = import ./nix/current.nix {
  inherit latestPassingMilestoneBitstream;
  bottleneckBitstream = latestPassingMilestoneBitstream;
};
```

Then merge:

```nix
packages = canonicalPackages // {
  # existing package aliases remain here
};
```

- [ ] **Step 3: Verify no package names disappear**

Run before and after each split:

```bash
nix flake show --json > /tmp/llm2fpga-flake-show-after.json
nix eval .#default.name
nix eval .#latest-passing-milestone.name
nix eval .#bottleneck.name
```

Expected: canonical aliases evaluate.

- [ ] **Step 4: Commit each split**

```bash
git add flake.nix nix/current.nix
git commit -m "nix: split canonical package aliases"
```

Repeat with Task 6 DDR3 aliases, then previous-task aliases. Do not move large derivation bodies until aliases and tests are stable.

## Task 10: Previous Task Quarantine

**Files:**
- Create directories as needed under `previous_tasks/`
- Modify: `docs/repo-surface-inventory.md`
- Modify: `flake.nix` or `nix/previous-tasks.nix`

- [ ] **Step 1: Identify previous-task files**

Run:

```bash
rg --files | rg "task[23]|matmul|tiny_stories_selftest|circt-task3|torch-mlir-task3|deliverables/[23]"
```

- [ ] **Step 2: Do not move reviewer deliverables**

Leave `deliverables/` stable. Record them as historical/reviewer-facing in `docs/repo-surface-inventory.md`.

- [ ] **Step 3: Move only non-reviewer active-surface files after aliases exist**

For each move, use `git mv` and preserve package aliases. Example:

```bash
mkdir -p previous_tasks/task2 previous_tasks/task3
git mv rtl/tiny_stories_selftest_top.sv previous_tasks/task3/tiny_stories_selftest_top.sv
```

Then update Nix references in the same commit.

- [ ] **Step 4: Verify moved references**

```bash
rg "tiny_stories_selftest_top|matmul_selftest" flake.nix nix fpga rtl sim src previous_tasks
nix eval .#latest-passing-milestone.name
```

- [ ] **Step 5: Commit in small batches**

```bash
git add previous_tasks flake.nix nix docs/repo-surface-inventory.md
git commit -m "repo: move Task 3 historical RTL behind aliases"
```

## Task 11: Short Checks

**Files:**
- Modify: `justfile`
- Create or modify scripts under `scripts/checks/` if needed.

- [ ] **Step 1: Add check recipes**

Add:

```just
check-python:
    python3 -m py_compile scripts/task6/*.py scripts/pipeline/*.py TinyStories/*.py src/*.py

check-nix:
    nix flake show --json >/tmp/llm2fpga-flake-show.json
    nix eval .#default.name
    nix eval .#latest-passing-milestone.name
    nix eval .#bottleneck.name

check-shell:
    bash -n scripts/pipeline/*.sh scripts/task6/*.sh

check-rtl-smoke:
    nix build .#task6-ddr3-rowstream-wb-top1-reader-64-sv-sim --no-link

check-doc-state:
    python3 scripts/task6/task6_state_validate.py

check-repo:
    just check-doc-state
    just check-python
    just check-shell
    just check-nix
    just repo-surface-check
```

Adjust `check-rtl-smoke` to an existing quick simulation package if that exact alias is absent.

- [ ] **Step 2: Run cheap checks**

```bash
just check-doc-state
just check-shell
just check-nix
```

Expected: all pass before making broad cleanup changes.

- [ ] **Step 3: Commit**

```bash
git add justfile
git commit -m "repo: add short canonical checks"
```

## Task 12: TinyStories-1M DDR3 Inference Execution

**Files:**
- Modify board/gate scripts only where a gate fails with an understood cause.
- Update `docs/task6-crisp-state.*` after every gate.
- Append details to `docs/task6-resource-usage-reduction-notes.md`.

- [ ] **Step 1: D0 DDR3 boot/calibration**

Run the canonical DDR3 boot recipe once it exists:

```bash
just task6-ddr3-boot-gate
```

Pass criteria: `calib_seen=true`, boot done, no loader error.

- [ ] **Step 2: D1 boundary row integrity**

```bash
just task6-ddr3-rowstream-boundary-gate
```

Pass criteria: rows `0,1,31,32,50256` byte-match source rowstream.

- [ ] **Step 3: D1 full or chunk rowstream integrity**

If full readback is feasible, run full SHA check. If not, run chunk hashes and record the weaker evidence explicitly.

- [ ] **Step 4: D2 output-head top1**

```bash
just task6-ddr3-rowstream-top1-gate
```

Pass criteria: hardware top1 matches fixed Q0.24 TinyStories reference for all selected samples.

- [ ] **Step 5: M1 transformer-boundary MLP/residual**

Run the existing MLP boundary gate with prompt-derived activation/residual vectors. Pass criteria: board residual output matches reference for selected decode steps.

- [ ] **Step 6: M2 one full block**

Run one full TinyStories block with DDR3-backed model movement where required. Pass criteria: block output and checkpoint hashes match fixed-point reference.

- [ ] **Step 7: M3 full TinyStories-1M**

Run full prompt greedy decode:

```bash
just task6-ddr3-full-inference-gate
```

Pass criteria:

- generated token IDs match reference exactly;
- board artifacts include command logs and JSON verdicts;
- resource comparison uses `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`;
- crisp state records `M3-tinystories-1m-ddr3` and a latest green artifact.

- [ ] **Step 8: Commit after each green gate**

```bash
git add docs/task6-crisp-state.org docs/task6-crisp-state.json docs/task6-resource-usage-reduction-notes.md artifacts/task6/runs
git commit -m "task6: record <gate-name> DDR3 gate"
```

Do not commit huge generated artifacts unless the repo already tracks that artifact class and the artifact is needed for review.

## Task 13: Scaling To Larger TinyStories Sizes

**Files:**
- Modify: Nix model manifests/outputs
- Modify: contract and weight-pack scripts only if shape assumptions break
- Update docs/state and final report artifacts

- [ ] **Step 1: Add model manifests**

Add manifest outputs for the next TinyStories sizes in increasing order. Each manifest must include checkpoint identity, tokenizer identity, parameter summary, and shape contract.

- [ ] **Step 2: Regenerate quantized weight packs**

For each larger model:

```bash
nix build .#<tinystories-size>-model-manifest --no-link --print-out-paths
nix build .#<tinystories-size>-weight-pack-int8 --no-link --print-out-paths
```

- [ ] **Step 3: Run software/fixed-point references**

Generate token references for the same prompt/decode policy used by TinyStories-1M.

- [ ] **Step 4: Run DDR3 rowstream integrity**

Do not run full inference until rowstream integrity passes for the larger model.

- [ ] **Step 5: Run inference gates**

Run the smallest larger TinyStories variant first. Record whether failures are capacity, timing, DDR3 bandwidth, shape contract, or numeric mismatch.

- [ ] **Step 6: Update scaling report**

Record resource usage, board runtime, DDR3 traffic, and token correctness against TinyStories-1M.

- [ ] **Step 7: Commit each model-size result**

```bash
git add docs/task6-crisp-state.org docs/task6-crisp-state.json docs/task6-resource-usage-reduction-notes.md
git commit -m "task5: record TinyStories <size> scaling result"
```

## Task 14: Final Deliverable Stabilization

**Files:**
- Create final report under an approved docs/deliverables path only after confirming reviewer-doc policy.
- Update `README.org` with short current build/gate pointers.
- Do not edit `docs/project-plan*` without explicit approval.

- [ ] **Step 1: Produce final evidence bundle**

Bundle:

- TinyStories-1M M3 inference artifact;
- resource comparison vs copied baseline bundle at `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`;
- DDR3 boot/load/readback evidence;
- output-head top1 evidence;
- transformer-stage evidence;
- scaling evidence for larger TinyStories sizes.

- [ ] **Step 2: Update README with only stable commands**

Add:

```org
* Current Build

- Latest passing milestone: =nix build=
- Current bottleneck: =nix build .#bottleneck=
- Project state: [[file:docs/task6-crisp-state.org][docs/task6-crisp-state.org]]
- Human finish plan: [[file:docs/human-plan.org][docs/human-plan.org]]
```

- [ ] **Step 3: Run final checks**

```bash
just check-repo
nix build
nix build .#bottleneck --no-link
```

Board checks must be run on hardware and recorded in artifacts.

- [ ] **Step 4: Commit final docs**

```bash
git add README.org docs artifacts/task6/runs
git commit -m "docs: record LLM2FPGA completion evidence"
```

## Self-Review

- Spec coverage: The plan covers clarity/control, latest green build, bottleneck build, old task quarantine, manageable repo surface, checks, agent instructions, canonical docs, state observability, DDR3-first TinyStories-1M inference, and scaling.
- Placeholder scan: No task uses `TBD` or an unspecified later implementation. Where an exact target depends on current flake names, the plan instructs the executor to inspect and choose an existing derivation, then verify with `nix eval`.
- Type/name consistency: Required state fields are consistent across JSON, org, validator, and task descriptions.
- Scope check: This is a large project plan. It is intentionally split into independently commit-sized tasks so execution can proceed with review checkpoints.
