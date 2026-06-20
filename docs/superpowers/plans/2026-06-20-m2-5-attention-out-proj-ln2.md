# M2.5 Attention Out-Proj Residual LN2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove focused M2.5 on HIL: host token IDs produce the expected attention out-projection, attention residual, and LN2 vector boundary.

**Architecture:** Reuse the existing embedding block-input accelerator, live-context attention accelerator, and `task6_m2_first_token_attention_out_proj_accel_top`. Add a focused PCIe wrapper that stops after LN2 and exposes the LN2 vector/checksum on the existing M2 public output registers. Extend the board gate with an explicit `--require-attention-ln2` contract so M2.5 cannot pass by checking only low checksum bytes.

**Tech Stack:** SystemVerilog, Verilator, Python gate tests, Nix builds, YPCB PCIe HIL.

---

### Task 1: M2.5 Gate Contract And Oracle Parsing

**Files:**
- Modify: `scripts/task6/task6_pcie_m2_full_block_gate.py`
- Modify: `scripts/task6/test_task6_pcie_m2_full_block_gate.py`
- Test: `python3 scripts/task6/test_task6_pcie_m2_full_block_gate.py`

- [ ] **Step 1: Write failing Python tests**

Add tests that require parsing `LN2_EXPECTED_CHECKSUM`, `LN2_EXPECTED_SAMPLE0`, `LN2_EXPECTED_SAMPLE1`, and `ln2_expected_q[0..63]` from the live-KV attention out-projection fixture. Add a test that `--require-attention-ln2` selects milestone `M2.5-attention-out-proj-residual-ln2` and compute path `live-context-attention-ln2`.

- [ ] **Step 2: Verify RED**

Run: `python3 scripts/task6/test_task6_pcie_m2_full_block_gate.py`

Expected: FAIL because there is no M2.5 parser/contract mode yet.

- [ ] **Step 3: Implement parser and contract**

Add `CONTRACT_ATTENTION_LN2`, parse the LN2 vector/checksum/sample fields, set `provenance_mode = 0x4200`, add `--require-attention-ln2`, require `--embedding-tb-data-sv`, `--context-tb-data-sv`, and the attention out-projection `--tb-data-sv`.

- [ ] **Step 4: Verify GREEN**

Run: `python3 scripts/task6/test_task6_pcie_m2_full_block_gate.py`

Expected: PASS.

- [ ] **Step 5: Commit**

Run: `git add scripts/task6/task6_pcie_m2_full_block_gate.py scripts/task6/test_task6_pcie_m2_full_block_gate.py && git commit -m "Add M2.5 board gate contract"`

### Task 2: Focused M2.5 Simulation Wrapper

**Files:**
- Create: `fpga/rtl/task6_m2_embedding_live_context_attention_ln2_pcie_accel_top.sv`
- Create: `sim/task6_m2_embedding_live_context_attention_ln2_pcie_accel_tb_main.sv`
- Modify: `flake.nix`

- [ ] **Step 1: Write failing sim wrapper**

Create a testbench that writes token IDs, starts the focused wrapper, and requires DONE/no ERROR, provenance `0x4d324205`, LN2 checksum/sample/vector equality, debug1 `{block_input_low16, context_low16}`, debug2 `{out_proj_low8, residual_low8, ln2_low8, 8'h00}`, and debug3 `{block_input_low16, ln_input_low16}`.

- [ ] **Step 2: Verify RED**

Run: `nix build .#task6-m2-embedding-live-context-attention-ln2-pcie-accel-sim --no-link --print-out-paths -L`

Expected: FAIL because the wrapper/flake target is not implemented yet.

- [ ] **Step 3: Implement focused wrapper**

Chain embedding -> live-context attention -> out-proj/residual/LN2. Latch LN2 checksum/sample/vector into the existing public output registers. Keep direct token-ID input and direct residual BAR identity behavior.

- [ ] **Step 4: Verify GREEN**

Run: `nix build .#task6-m2-embedding-live-context-attention-ln2-pcie-accel-sim --no-link --print-out-paths -L`, then run the generated `obj_dir/sim_main`.

Expected: PASS with nonzero cycles and expected LN2 boundary values.

- [ ] **Step 5: Commit**

Run: `git add fpga/rtl/task6_m2_embedding_live_context_attention_ln2_pcie_accel_top.sv sim/task6_m2_embedding_live_context_attention_ln2_pcie_accel_tb_main.sv flake.nix && git commit -m "Add focused M2.5 LN2 PCIe sim"`

### Task 3: M2.5 FPGA Build Target

**Files:**
- Modify: `fpga/rtl/task6_ypcb_pcie_rowstream_ingress_dummy_top.sv`
- Modify: `flake.nix`
- Modify: `justfile`

- [ ] **Step 1: Add focused image selection**

Add `M2_ACCEL_KIND == 3` for the M2.5 wrapper, plus Nix Yosys/FASM/bitstream outputs and Just targets for bitstream and board gate.

- [ ] **Step 2: Build timing-clean candidate**

Run: `nix build .#task6-m2-5-attention-ln2-pnr100-seed16-bitstream --no-link --print-out-paths -L`

Expected: routed timing PASS at the 62.50 MHz PCIe user-clock target.

- [ ] **Step 3: Commit build plumbing**

Run: `git add fpga/rtl/task6_ypcb_pcie_rowstream_ingress_dummy_top.sv flake.nix justfile && git commit -m "Add M2.5 FPGA build target"`

### Task 4: M2.5 HIL Evidence

**Files:**
- Add artifacts under `artifacts/task6/bitstreams/`
- Add artifacts under `artifacts/task6/runs/task6-bottleneck/`
- Modify: `docs/task6-crisp-state.org`
- Modify: `docs/task6-crisp-state.json`
- Modify: `docs/task6-resource-usage-reduction-notes.md`

- [ ] **Step 1: Preserve bitstream**

Copy the timing-clean bitstream into `artifacts/task6/bitstreams/` and record its SHA256.

- [ ] **Step 2: Flash and recover**

Run: `TASK6_PCIE_HARDWARE_ENABLE=1 scripts/task6/task6_pcie_user_gate.sh flash ... --confirm-write-flash`.

Run: `nix develop -c just task6-pcie-recover 0000:42:00.0 task6-m2-5-attention-ln2-<label>-recover 5`.

Expected: final classification `pcie_ready`.

- [ ] **Step 3: BAR identity guard**

Run: `nix develop -c python3 scripts/task6/task6_pcie_m2_vector_rw_probe.py 0000:42:00.0 --json-out artifacts/task6/runs/task6-bottleneck/m2-5-vector-rw-direct-probe-<label>.json`.

Expected: PASS for input and residual identity.

- [ ] **Step 4: Board gate**

Run: `nix develop -c just task6-m2-5-attention-ln2-board-gate 0000:42:00.0 artifacts/task6/runs/task6-bottleneck/m2-5-attention-ln2-<label>.json`.

Expected: PASS with live compute, direct mode, strict readback, DONE/no ERROR, and full LN2 vector match.

- [ ] **Step 5: Update state and commit evidence**

Run: `python3 scripts/task6/task6_state_validate.py` and `git diff --check`.

Commit: `git commit -m "Record M2.5 HIL acceptance"` if HIL passes. If HIL fails, update crisp state with the exact failure and reproduce the public-interface failure in simulation before attempting another RTL fix.
