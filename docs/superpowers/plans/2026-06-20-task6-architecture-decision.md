# Task 6 Architecture Decision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce evidence-backed Task 6 architecture guidance that prevents further implicit drift into manual per-model RTL.

**Architecture:** Treat `docs/task6-architecture-decision.md` as the controlling decision artifact. Evaluate exactly two valid architecture routes: automatic compiler-to-RTL and common-kernel v2. Use `tiny-stories-1m-representative-core` as the first fast-loop POC target, then record whether it is representative enough or should be promoted to a larger sweep rung.

**Tech Stack:** Nix flake targets, Torch-MLIR/CIRCT pipeline artifacts, Yosys resource reports, Task 6 Python scoring scripts, Markdown decision docs, existing Task 6 artifacts.

---

## File Structure

- Modify: `docs/task6-architecture-decision.md`
  - Owns the current decision record, evidence summary, scorecard, POC outcomes, and final recommendation.
- Modify: `docs/task6-resource-usage-reduction-notes.md`
  - Receives concise dated progress notes and links to durable artifacts.
- Create: `artifacts/task6/architecture-decision/`
  - Stores generated POC summaries, scorecards, command logs, and copied lightweight JSON outputs.
- Do not modify: `docs/project-plan*`
  - These files are reviewer-controlled.

## Task 1: Preserve The Current Architecture Decision Baseline

**Files:**
- Modify: `docs/task6-architecture-decision.md`
- Modify: `docs/task6-resource-usage-reduction-notes.md`

- [ ] **Step 1: Inspect current decision state**

Run:

```bash
sed -n '1,260p' docs/task6-architecture-decision.md
sed -n '1,80p' docs/task6-resource-usage-reduction-notes.md
git status --short
```

Expected:

- `docs/task6-architecture-decision.md` exists.
- `docs/task6-resource-usage-reduction-notes.md` has a dated architecture entry.
- No `docs/project-plan*` files are modified.

- [ ] **Step 2: Create artifact directory**

Run:

```bash
mkdir -p artifacts/task6/architecture-decision
```

Expected:

- `artifacts/task6/architecture-decision/` exists.

- [ ] **Step 3: Record the starting state**

Create `artifacts/task6/architecture-decision/2026-06-20-starting-state.md` with:

```markdown
# Task 6 Architecture Decision Starting State

Date: 2026-06-20

## Constraint

Task 6 must not rely on manual custom RTL per model.

## Candidate Architectures

1. Automatic compiler-to-RTL with int8 quantization and DDR3/external memory.
2. Common-kernel v2: reusable FPGA kernels driven by generated manifests, weights, schedules, DDR3 layouts, configs, and oracles.

## Fast POC Target

Use `tiny-stories-1m-representative-core` first. Promote to a larger registered sweep point only if the minimum core loses relevant operator, dialect, memory-shape, or scale evidence.

## Existing Anchors

- Architecture decision: `docs/task6-architecture-decision.md`
- Task 6 notes: `docs/task6-resource-usage-reduction-notes.md`
- Baseline bundle: `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`
```

- [ ] **Step 4: Commit baseline plan state**

Run:

```bash
git add docs/task6-architecture-decision.md docs/task6-resource-usage-reduction-notes.md docs/superpowers/plans/2026-06-20-task6-architecture-decision.md artifacts/task6/architecture-decision/2026-06-20-starting-state.md
git commit -m "Record Task 6 architecture decision plan"
```

Expected:

- Commit succeeds.
- `git status --short` does not show the files listed in the `git add` command.

## Task 2: Run The Bounded Architecture Survey

**Files:**
- Modify: `docs/task6-architecture-decision.md`
- Create: `artifacts/task6/architecture-decision/paper-architecture-survey.md`

- [ ] **Step 1: Read existing survey sources**

Run:

```bash
sed -n '1,90p' deliverables/1a-survey.org
sed -n '1,90p' deliverables/1a-openflow-kintex480t-survey.md
sed -n '1,90p' deliverables/1c-selected_route.org
sed -n '1,220p' docs/task6-third-party-kernel-survey.org
```

Expected:

- You have the paper list, selected Task 1 route, Kintex-480T reclassification, and kernel survey context in view.

- [ ] **Step 2: Read the saved inference-limits analysis**

Run:

```bash
test -f "/home/roland/Downloads/LLM Inference Limits.html"
rg -n "10K compact|BRAM-resident|bytes/token|ternary|int8|DDR3|throughput|latency|fits" "/home/roland/Downloads/LLM Inference Limits.html"
```

Expected:

- The file exists.
- The `rg` output identifies the compact TinyStories and storage/envelope discussion.

- [ ] **Step 3: Write the survey artifact**

Create `artifacts/task6/architecture-decision/paper-architecture-survey.md` with these exact sections:

```markdown
# Paper Architecture Survey For Task 6

## Purpose

This is a bounded architecture survey. It does not reopen Task 1. It extracts patterns that affect the Task 6 choice between automatic compiler-to-RTL and common-kernel v2.

## Architecture Patterns

| Pattern | Examples | What To Reuse | Task 6 Risk |
| --- | --- | --- | --- |
| Full compiler/dataflow pipeline | Torch-MLIR/CIRCT demo, StreamTensor | PyTorch input, automatic schedule/memory generation | Current full-model lowering explodes resources or hits CIRCT/Handshake risk |
| Reusable kernel/overlay | MASE, XtraMAC, ITA-style kernels | Fixed RTL with model data/config | Requires a precise generated artifact contract |
| HLS end-to-end systems | TeLLMe, HLSTransform, LoopLynx | System organization and low-bit dataflow ideas | Mostly proprietary Vitis/Vivado or unavailable code |
| External-memory streaming | FlightLLM, MEADOW, Spatial/Allo-style work, StreamTensor | DDR/HBM-backed weights with tiled compute | Must prove DDR3 bytes/token and avoid handshake shell blowups |
| Low-bit/table/ternary systems | TerEffic, MatMul-free LM, TeLLMe v2, LUT-LLM | Memory compression and low-bit compute ideas | Current repo evidence promotes int8 first and rejects int4/int3/ternary for near-term output-head RTL |
| KV/prefill/memory-pipeline systems | FAST-Prefill, SkipOPU, disaggregated memory work | Prefill/decode/KV-cache metrics | Mostly reference-only for this board |

## Takeaways

1. Fully automatic compiler-to-RTL remains valid only if it avoids giant all-fabric RTL and proves externalized memory.
2. The strongest practical pattern is compiler-managed data and schedules feeding reusable quantized kernels.
3. Most high-performance papers are not directly reusable because they depend on proprietary tools, HBM boards, unpublished RTL, or multi-FPGA assumptions.
4. Task 6 should evaluate throughput and latency with bytes/token and cycles/token, not only resource fit.
5. Int8 is the near-term quantization baseline until full-checkpoint evidence promotes another format.
```

- [ ] **Step 4: Update the decision doc survey section**

Modify the `Quick Architecture Survey` section in `docs/task6-architecture-decision.md` so it points to:

```markdown
Detailed bounded survey artifact: `artifacts/task6/architecture-decision/paper-architecture-survey.md`.
```

Keep the existing compact table in the decision doc.

- [ ] **Step 5: Commit the survey artifact**

Run:

```bash
git add docs/task6-architecture-decision.md artifacts/task6/architecture-decision/paper-architecture-survey.md
git commit -m "Add Task 6 architecture survey artifact"
```

Expected:

- Commit succeeds.

## Task 3: Audit Representative-Core As The POC Target

**Files:**
- Modify: `docs/task6-architecture-decision.md`
- Modify: `docs/task6-resource-usage-reduction-notes.md`
- Create: `artifacts/task6/architecture-decision/representative-core-audit.md`

- [ ] **Step 1: Build the sweep manifest**

Run:

```bash
nix build .#tiny-stories-1m-representative-core-sweep-manifest --no-link --print-out-paths
```

Expected:

- Exit code `0`.
- Output path ends in `tiny-stories-1m-representative-core-sweep-manifest.json`.

- [ ] **Step 2: Build the op-coverage bundle**

Run:

```bash
nix build .#tiny-stories-1m-baseline-float-vs-representative-core-op-coverage --no-link --print-out-paths -L
```

Expected:

- Exit code `0`.
- Output path ends in `tiny-stories-1m-baseline-float-vs-representative-core-op-coverage-bundle`.

- [ ] **Step 3: Inspect coverage summaries**

Run:

```bash
coverage_out="$(nix build .#tiny-stories-1m-baseline-float-vs-representative-core-op-coverage --no-link --print-out-paths)"
sed -n '1,220p' "$coverage_out/summary.txt"
sed -n '1,220p' "$coverage_out/cf/summary.txt"
sed -n '1,220p' "$coverage_out/torch/summary.txt"
```

Expected:

- Torch coverage says `ops_complete=True dialects_complete=True`.
- CF coverage says `ops_complete=True dialects_complete=True`.
- Missing ops and missing dialects are `none`.

- [ ] **Step 4: Write the audit artifact**

Create `artifacts/task6/architecture-decision/representative-core-audit.md` with:

```markdown
# Representative-Core Audit

## Result

`tiny-stories-1m-representative-core` is accepted as the first architecture POC smoke target for operator and dialect coverage.

## Evidence

- Sweep manifest build: PASS.
- Baseline-vs-representative-core op coverage build: PASS.
- Torch: complete op and dialect coverage; no missing ops or dialects.
- CF: complete op and dialect coverage; no missing ops or dialects.

## Limits

- The representative core uses synthetic weights seeded from config, not the pretrained TinyStories-1M checkpoint.
- It is a hardware-structure and toolchain proxy.
- It does not replace full TinyStories-1M fidelity, latency, throughput, or board evidence.

## Decision

Use the minimum representative core first. Promote to `tiny-stories-1m-representative-core-v64-h4` or larger only when a POC needs scale beyond operator coverage.
```

- [ ] **Step 5: Update docs with the audit result**

Ensure `docs/task6-architecture-decision.md` and `docs/task6-resource-usage-reduction-notes.md` both state:

```markdown
The minimum representative core preserves all distinct Torch and CF ops/dialects versus the baseline in this audit, so it is accepted as the first architecture POC smoke target.
```

- [ ] **Step 6: Commit the audit**

Run:

```bash
git add docs/task6-architecture-decision.md docs/task6-resource-usage-reduction-notes.md artifacts/task6/architecture-decision/representative-core-audit.md
git commit -m "Audit representative core for architecture POCs"
```

Expected:

- Commit succeeds.

## Task 4: Run The Automatic Compiler-To-RTL Viability Spike

**Files:**
- Modify: `docs/task6-architecture-decision.md`
- Modify: `docs/task6-resource-usage-reduction-notes.md`
- Create: `artifacts/task6/architecture-decision/compiler-to-rtl-spike.md`

- [ ] **Step 1: Confirm quantized representative-core frontend status**

Run:

```bash
nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats --no-link --print-out-paths -L
```

Expected:

- Exit code `0`, or a concrete failure stage that can be copied into the spike artifact.

- [ ] **Step 2: Confirm current handshake/HW lowering status**

Run:

```bash
nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L
```

Expected:

- Exit code `0`, or a concrete CIRCT/pass failure.
- If this fails, record the exact failing pass and do not hide the failure behind a broader architecture claim.

- [ ] **Step 3: Inspect existing external-memory outputs**

Run:

```bash
nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-external-memory-plan --no-link --print-out-paths
nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-utilization --no-link --print-out-paths -L
```

Expected:

- Exit code `0`, or the exact failing stage is recorded.
- If utilization is emitted, inspect whether DSP/BRAM move from zero.

- [ ] **Step 4: Write the spike artifact**

Create `artifacts/task6/architecture-decision/compiler-to-rtl-spike.md` with these sections:

```markdown
# Automatic Compiler-To-RTL Spike

## Route

PyTorch representative-core -> PT2E/static quantization -> Torch/CF/Handshake/CIRCT route -> external-memory shell or generated RTL.

## Commands

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats --no-link --print-out-paths -L`
- `nix build .#tiny-stories-1m-representative-core-pt2e-static-handshake --no-link --print-out-paths -L`
- `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-external-memory-plan --no-link --print-out-paths`
- `nix build .#tiny-stories-1m-representative-core-selftest-top4-memory-utilization --no-link --print-out-paths -L`

## Results Format

For each command, write one bullet that includes command label, status, output path when successful, and the first failing stage or error signature when unsuccessful.

## Architecture Verdict Values

Use one of these exact verdicts:

- `compiler-to-rtl-pass`: representative-core quantized route emits memory-externalized hardware artifacts without crash/OOM and shows a plausible resource signature.
- `compiler-to-rtl-research-only`: route fails, embeds weights as fabric constants, keeps DSP/BRAM at zero, or cannot provide a credible path to full TinyStories-1M.
```

Before committing, read `artifacts/task6/architecture-decision/compiler-to-rtl-spike.md` and verify every command from the `Commands` section has one concrete result bullet under `Results Format`.

- [ ] **Step 5: Update the decision doc**

In `docs/task6-architecture-decision.md`, add a subsection under `Required POCs` titled:

```markdown
### Compiler-To-RTL Spike Result
```

Record:

- command statuses;
- whether weights were externalized;
- whether DSP/BRAM appeared;
- final verdict: `compiler-to-rtl-pass` or `compiler-to-rtl-research-only`.

- [ ] **Step 6: Commit the compiler spike**

Run:

```bash
git add docs/task6-architecture-decision.md docs/task6-resource-usage-reduction-notes.md artifacts/task6/architecture-decision/compiler-to-rtl-spike.md
git commit -m "Evaluate compiler-to-RTL architecture spike"
```

Expected:

- Commit succeeds.

## Task 5: Run The Common-Kernel v2 Envelope Spike

**Files:**
- Modify: `docs/task6-architecture-decision.md`
- Modify: `docs/task6-resource-usage-reduction-notes.md`
- Create: `artifacts/task6/architecture-decision/common-kernel-v2-envelope.md`

- [ ] **Step 1: Inspect existing kernel evidence**

Run:

```bash
sed -n '1,220p' artifacts/task6/parallel-hypotheses/h2-int8-l2-selftest-board-comparison.json
sed -n '1,220p' artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json
sed -n '1,220p' artifacts/task6/parallel-hypotheses/h2-v1k-v4k-streaming-contract-score.json
sed -n '1,220p' artifacts/task6/quantization/output-head-v10k-multisample-sweep.json
```

Expected:

- Existing artifacts expose resource, quantization, and v1k/v4k scale-up evidence.

- [ ] **Step 2: Define the generated artifact contract**

Create `artifacts/task6/architecture-decision/common-kernel-v2-envelope.md` with:

```markdown
# Common-Kernel v2 Envelope

## Generated Artifact Contract

The compiler side emits:

- model manifest;
- quantized weight packs;
- DDR3 row layout;
- kernel config;
- schedule/control stream;
- fixed-point oracle vectors;
- run metadata and hashes.

The FPGA side provides:

- reusable quantized GEMV/MLP/attention/output-head kernels;
- DDR3 rowstream movement;
- PCIe/BAR control, status, and result readback;
- no manual per-model RTL edits.

## Existing Evidence

Record resource, pass/fail, and fidelity evidence from the inspected artifacts.

## Envelope Metrics

Record:

- resource usage for the reusable kernel slices;
- estimated full TinyStories-1M model bytes;
- estimated DDR3 bytes/token;
- estimated cycles/token;
- supported decoder-only GPT/GPT-Neo assumptions;
- unsupported features that require kernel changes.

## Architecture Verdict

Use one of these exact verdicts:

- `common-kernel-v2-mainline`: same RTL can plausibly support multiple model shapes by generated artifacts/config only.
- `common-kernel-v2-needs-contract-work`: evidence is promising, but the artifact contract or multi-shape proof is incomplete.
- `common-kernel-v2-reject`: evidence contradicts full TinyStories-1M feasibility.
```

- [ ] **Step 3: Fill in the existing-evidence section**

Use the inspected artifacts to record:

- copied float baseline resource usage;
- H2 int8 MLP/residual resource usage;
- v1k/v4k scale-up result;
- v10k output-head quantization result;
- M2.4/M2.5 boundary status from `docs/task6-crisp-state.org`.

- [ ] **Step 4: Update the decision doc**

In `docs/task6-architecture-decision.md`, add a subsection under `Required POCs` titled:

```markdown
### Common-Kernel v2 Envelope Result
```

Record the verdict from Step 2 and the minimum evidence that supports it.

- [ ] **Step 5: Commit the common-kernel spike**

Run:

```bash
git add docs/task6-architecture-decision.md docs/task6-resource-usage-reduction-notes.md artifacts/task6/architecture-decision/common-kernel-v2-envelope.md
git commit -m "Evaluate common-kernel v2 architecture envelope"
```

Expected:

- Commit succeeds.

## Task 6: Record The Final Architecture Recommendation

**Files:**
- Modify: `docs/task6-architecture-decision.md`
- Modify: `docs/task6-resource-usage-reduction-notes.md`
- Create: `artifacts/task6/architecture-decision/final-scorecard.md`

- [ ] **Step 1: Write the scorecard**

Create `artifacts/task6/architecture-decision/final-scorecard.md` with a complete scorecard using only concrete values from the previous artifacts. Use these scoring terms:

- Hard Gates: `pass` or `fail`.
- Metric columns: `strong`, `mixed`, or `weak`, followed by one short evidence phrase.
- Verdict: `mainline`, `research-only`, or `reject`.

The file must use this structure:

```markdown
# Task 6 Architecture Scorecard

| Candidate | Hard Gates | Scalability | Model Portability | Throughput/Latency | Correctness/Fidelity | Toolchain Risk | Maintainability | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Recommendation

State the selected mainline and the reason in five sentences or fewer, citing the stronger evidence from the table.

## Consequence For M2.5/M3

State what future RTL changes are allowed:

- reusable kernel infrastructure;
- generated artifact/config support;
- bounded diagnostics;
- no manual TinyStories-only RTL growth as architecture.
```

Add exactly two table rows under the header, one for `Automatic compiler-to-RTL`
and one for `Common-kernel v2`. Every metric cell must start with `strong:`,
`mixed:`, or `weak:` followed by one evidence phrase. The `Hard Gates` cells
must be `pass` or `fail`. The `Verdict` cells must be `mainline`,
`research-only`, or `reject`.

- [ ] **Step 2: Update the decision doc recommendation**

In `docs/task6-architecture-decision.md`, update `Immediate Recommendation` so it states the final mainline:

```markdown
Final recommendation: name the route whose `Verdict` cell is `mainline` in the final scorecard.
```

Then add:

```markdown
Final scorecard: `artifacts/task6/architecture-decision/final-scorecard.md`.
```

- [ ] **Step 3: Update Task 6 notes**

At the top of `docs/task6-resource-usage-reduction-notes.md`, add a dated entry summarizing:

- selected route;
- rejected or research-only route;
- next concrete POC or implementation gate;
- reminder that `docs/project-plan*` stayed unchanged.

- [ ] **Step 4: Verify documentation**

Run:

```bash
rg -n "T[B]D|T[O]DO|concrete scor[e]|concrete verdic[t]|selected route nam[e]" docs/task6-architecture-decision.md artifacts/task6/architecture-decision/final-scorecard.md
LC_ALL=C rg -n "[^\\x00-\\x7F]" docs/task6-architecture-decision.md artifacts/task6/architecture-decision/final-scorecard.md
git status --short docs/project-plan_v2.org docs/project-management.org
```

Expected:

- First command has no output.
- Second command has no output unless an existing non-ASCII character is intentionally retained.
- Third command has no output.

- [ ] **Step 5: Commit the final decision**

Run:

```bash
git add docs/task6-architecture-decision.md docs/task6-resource-usage-reduction-notes.md artifacts/task6/architecture-decision/final-scorecard.md
git commit -m "Finalize Task 6 architecture decision"
```

Expected:

- Commit succeeds.

## Task 7: Handoff And Completion Check

**Files:**
- Modify: none unless verification finds a missing link.

- [ ] **Step 1: Run final status checks**

Run:

```bash
git log --oneline -5
git status --short
rg -n "architecture-decision" docs/task6-resource-usage-reduction-notes.md docs/task6-architecture-decision.md docs/superpowers/plans/2026-06-20-task6-architecture-decision.md
```

Expected:

- Recent commits include the architecture decision commits.
- Only unrelated user work remains in `git status --short`.
- The architecture decision is linked from the notes and the plan.

- [ ] **Step 2: Write final handoff summary**

In the final response, report:

- selected architecture route;
- rejected or research-only route;
- artifacts created under `artifacts/task6/architecture-decision/`;
- verification commands run;
- whether any unrelated dirty files remain.
