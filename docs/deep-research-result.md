I inspected the uploaded prompt and tool-help file, the `task6` branch, the starting commit `fbe04ecae63274b37672a3396c2e2f6142bec2fb`, the current branch head, and the pinned UberDDR3 revision. I could not inspect your local-only `~/UberDDR3` checkout, so conclusions about that part rely on the pinned GitHub revision and the seed-sensitivity evidence stated in the prompt.  

## Bottom-line diagnosis

Your mental model is incomplete at the boundary between “digital RTL correctness” and “physical PHY/protocol correctness”.

A more accurate diagnosis is:

**The most likely primary failure class is marginal or under-constrained DDR3 PHY implementation under the open-source Xilinx 7-series flow, amplified by placement/routing seed variation and by integration with PCIe.** The fact that standalone DDR3 already showed seed sensitivity is important: it means the issue cannot be explained only as a PCIe integration bug. PCIe integration can still make it worse through congestion, clock/reset interactions, hard-block placement pressure, power/SSO noise, and new CDC paths.

The starting commit is already evidence that PCIe itself is not the whole failure: the combined image reached PCIe link-up, host enumeration, and BAR smoke success, while the next step was DDR rowstream loader smoke testing. The commit added the PCIe↔DDR ingress CDC bridge, combined PCIe and UberDDR3 top, merged PCIe lane-0 XDC with DDR3 XDC, used seed 15, and passed PCIe BAR-level checks. 

The current branch head shows the project moved to a seed20 candidate, with notes that this followed a “loader-only seed20 cold DDR pass” and that the full PCIe+DDR rowstream/top1 image was flashed to BPI for cold enumeration testing. That is the right direction: cold boot from flash is a better PCIe endpoint test than repeated JTAG reconfiguration while the host thinks the endpoint is alive. 

## Why “passes timing” can still fail on DDR3 hardware

Timing closure only covers what the tool knows, what is constrained, and what its device/timing model can represent. DDR3 calibration depends on several effects that can escape or exceed that model:

1. **DDR3 I/O timing is not just fabric timing.** DQ/DQS phase, IDELAY/ODELAY tap behavior, ISERDES/OSERDES placement, IDELAYCTRL readiness, VREF, DCI/termination, bank placement, clock forwarding, and board skew matter. UberDDR3’s own README says the PHY calibration performs bitslip training, MPR read calibration, write leveling, and optional read/write tests before user access. 

2. **The open-source Xilinx 7-series flow is not Vivado signoff.** The upstream nextpnr README still describes Xilinx 7-series support as experimental, and Project X-Ray documents the 7-series bitstream format by fuzzing/cross-correlation against Vivado-generated designs. That does not make the flow unusable, but it means “nextpnr timing passed” is not equivalent to “Vivado signoff timing and PHY constraints passed”. ([GitHub][1]) ([GitHub][2])

3. **Kintex-7/OpenXC7 coverage is exactly in the risky region.** Project X-Ray historically focused on Artix-7 50T and notes that Kintex-7 work had started, not that every hard/IO/PHY corner is vendor-grade. Your design uses Kintex-7, PCIe/GT, DDR3, IDELAY/OSERDES/ISERDES, and custom bitstream generation: the hardest combination. ([GitHub][2])

4. **Constraints may be incomplete after integration.** Vivado’s constraint guide explicitly treats clocks, generated clocks, input/output delays, clock groups, CDC constraints, false/multicycle paths, bus skew, and placement/BEL constraints as separate classes of constraints. A design can “pass” while missing a required generated clock, async clock grouping, IO delay, or physical placement constraint if the tool never sees the real requirement. ([AMD Documentation][3])

5. **Seed sensitivity is a symptom, not a strategy by itself.** If seed A passes and seed B fails, then the design is probably near a physical/timing/calibration margin or has an unconstrained path/CDC/reset issue. A robust DDR3 design should pass across a meaningful set of seeds, cold/warm boots, temperature, and voltage variation.

## Repository-specific high-risk areas

### 1. Combined XDC generation

`make_pcie_uberddr3_xdc.py` is a high-risk file. It hard-codes 2 byte lanes, drops DDR DQ bits above 15 and DQS lanes above 1, then skips every DDR XDC line containing `SYS_RSTN` or `clk50`.  

That may be correct for avoiding duplicate top-level reset/clock constraints, but it must be audited. The danger is that a standalone DDR3 clock constraint, generated-clock relation, reset exception, or IO constraint may be lost during the merge. The combined top has both PCIe clocks and a separate DDR PLL from `clk_50`; dropping DDR `clk50` lines without recreating equivalent constraints is suspicious.

Immediate action: build the generated combined XDC and compare it mechanically against the standalone DDR XDC and PCIe XDC. Check for:

```text
create_clock
create_generated_clock
set_clock_groups
set_false_path
set_max_delay / set_min_delay
set_input_delay / set_output_delay
INTERNAL_VREF
BITSTREAM.STARTUP.MATCH_CYCLE
IDELAYCTRL / IODELAY / IDELAY / ODELAY related LOCs
BEL / LOC constraints
PCIe hard block / GTX placement constraints
DDR byte-lane / DQS / DQ constraints
```

### 2. PCIe↔DDR CDC bridge

`task6_pcie_axil_rowstream_loader_ingress_cdc.v` bridges `pcie_clk` to `rowstream_clk`. It uses toggle synchronizers for commands and status-clear events, which is a reasonable pattern, but it also appears to sample several multi-bit status/readback buses from the rowstream domain directly into the PCIe domain. That can make host-side diagnostics incoherent even if the command path is safe. The file also has mixed reset usage, including a rowstream-clock heartbeat counter reset by `pcie_rst_n`, which deserves review. 

This is unlikely to be the root cause of DDR calibration failing before BAR writes, but it can produce false conclusions once you test through PCIe. Add `ASYNC_REG` attributes to synchronizer flops where supported and formally verify the toggle handshake. AMD recommends marking synchronizer flip-flops with `ASYNC_REG` so optimization preserves them and placement improves MTBF. ([AMD Documentation][4])

### 3. Combined top-level clock/reset composition

The combined top instantiates PCIe and DDR side by side, with `DDR_BYTE_LANES = 2`, PCIe differential clock/reset, a separate `clk_50`, and DDR pins. 

The DDR wrapper generates `controller_clk`, `ddr3_clk`, `ddr3_clk_90`, and `ref_clk` from `clk50` using `PLLE2_BASE`, then assigns `rst_n = mmcm_locked`.  That reset scheme is minimal. For hardware bring-up, record reset release timestamps in every clock domain and verify that DDR reset, IDELAYCTRL reset, controller reset, and PCIe user reset are not interacting accidentally.

### 4. Patched PCIe source

`patch_pcie_rowstream_ingress_source.py` force-selects the GTX wrapper path by rewriting `PCIE_GT_DEVICE` and replacing the generate condition with `if (1)`. It also replaces the original AXI-lite BAR responder with exported AXI-lite signals.  

This is acceptable as an experiment, but it is brittle. Any upstream source change can silently invalidate assumptions. Treat this as a formal inspection target: prove the exported AXI-lite signals preserve handshake semantics and confirm that hard-block/GTX placement constraints still match the selected wrapper.

### 5. UberDDR3 patches

The YPCB-specific DM patch disables DDR3 DM OSERDES/OBUF generation because the board definition does not expose DM pins; it ties `o_ddr3_dm` to zero and disables the DM generate loop.  That is probably necessary for this board, but it means tests involving byte masks are not equivalent to the original controller.

The fast-BIST patch skips the full-address-space BIST when `BIST_MODE == 1`, jumping from `BURST_WRITE` toward `FINISH_READ`.  This is useful for iteration speed, but it weakens the meaning of “calibration complete”. For final confidence, you need a separate bounded integrity test that records address/data/lane failures, or temporarily re-enable stronger BIST on a reduced address window.

## Files to inspect first

For `LLM2FPGA/task6`:

```text
flake.nix
scripts/task6/make_pcie_uberddr3_xdc.py
scripts/task6/patch_pcie_rowstream_ingress_source.py
fpga/rtl/task6_ypcb_pcie_uberddr3_rowstream_loader_top.sv
fpga/rtl/task6_pcie_axil_rowstream_loader_ingress_cdc.v
fpga/rtl/task6_pcie_axil_rowstream_loader_ingress.v
fpga/rtl/task6_ypcb_uberddr3_bist_rowstream_loader_top.sv
patches/uberddr3/0001-ypcb-disable-unpinned-ddr3-dm-outputs.patch
patches/uberddr3/0003-ypcb-fast-bist-exit.patch
scripts/task6/task6_pcie_rowstream_loader_smoke.py
scripts/task6/task6_pcie_gate_root.sh
docs/task6-resource-usage-reduction-notes.md
artifacts/task6/runs/*
```

For pinned `UberDDR3`:

```text
rtl/ddr3_top.v
rtl/ddr3_phy.v
rtl/ddr3_controller.v
rtl/ecc/ecc_enc.sv
rtl/ecc/ecc_dec.sv
formal/*
example_demo/*/*.xdc
any YPCB-specific standalone XDC/build scripts/seed logs
```

`ddr3_top.v` exposes the key parameters: controller period, DDR3 period, byte lanes, ODELAY support, DLL mode, BIST mode, DIC/RTT termination, and Wishbone widths.  `ddr3_phy.v` is the most critical file for seed sensitivity because it instantiates IOSERDES, IODELAY, IOBUF, DQS/DQ logic, and IDELAYCTRL/DCI readiness.  `ddr3_controller.v` contains the calibration FSM, BIST, read/write leveling, bitslip, and debug UART hooks. 

## Prioritized debug plan

### Phase 1 — freeze reproducible artifacts

Create a matrix with at least:

```text
standalone DDR good seed
standalone DDR bad seed
combined PCIe+DDR good or partially good seed
combined PCIe+DDR bad seed
loader-only seed20
full rowstream/top1 seed20
```

For each run, store:

```text
git SHA
flake.lock
Yosys version and log
nextpnr version and log
chipdb hash
XDC file
JSON netlist hash
FASM hash
FRM hash
BIT hash
seed
placer/router options
--no-tmdriv on/off
timing summary
all nextpnr warnings
hardware result
cold/warm boot condition
PCIe enumeration result
DDR calibration state
rowstream smoke result
```

Use deterministic nextpnr seeds, not `--randomize-seed`. The uploaded tool help confirms nextpnr exposes `--seed`, `--randomize-seed`, `--placer`, `--router`, `--freq`, `--timing-allow-fail`, `--no-tmdriv`, `--sdf`, `--log`, and FASM output options. 

### Phase 2 — audit constraints before more seed hunting

Generate the combined XDC and compare against the standalone DDR XDC. The goal is not visual inspection; write a small script that classifies every constraint by port/net/site/clock and reports what disappeared in the combined build.

Specific red flags:

```text
No create_clock on clk_50 / DDR PLL input
No generated-clock relation for controller_clk, ddr3_clk, ddr3_clk_90, ref_clk
No async clock groups between PCIe user clock and DDR controller clock
No IDELAYCTRL/refclk constraint
No INTERNAL_VREF / DCI / SSTL15 constraints for the DDR bank
No explicit constraints for DDR DQS/DQ byte-lane physical grouping
No PCIe hard-block/GTX site constraints
No constraints for async resets
Unexpected false paths hiding real DDR or CDC timing
```

AMD’s constraint documentation explicitly separates clock definition, generated clocks, clock groups, CDC constraints, timing exceptions, IO delay constraints, and physical placement constraints; all of these are relevant here. ([AMD Documentation][3])

### Phase 3 — CDC/RDC proof

Focus on `task6_pcie_axil_rowstream_loader_ingress_cdc.v`.

Prove or check:

```text
payload_hold_pcie_q remains stable until rowstream side consumes it
rowstream_command_event_o is exactly one pulse per accepted command, unless duplicate pulse is intentional
no event is lost if PCIe writes while rowstream reset toggles
status clear is not lost
top1_start/top1_clear toggles cannot collapse
rowstream reset and PCIe reset cannot leave seen/toggle bits inconsistent
multi-bit readback is either latched atomically in rowstream domain or treated as diagnostic-only
```

Add `(* ASYNC_REG = "TRUE" *)` or the open-flow-supported equivalent on synchronizer flops, and test that Yosys/nextpnr do not optimize them away.

### Phase 4 — isolate PCIe hard block from DDR physical margin

Build a “DDR + dummy load” design with the same DDR wrapper, same byte-lane count, same clocks, same BIST/probe, and approximately similar LUT/FF/BRAM congestion, but no PCIe hard block. Then build:

```text
DDR only, original standalone
DDR only, same wrapper parameters as combined
DDR + dummy logic
DDR + PCIe hard block instantiated but BAR logic disconnected
DDR + PCIe BAR but no rowstream top1
full design
```

If DDR fails only when the hard block is present, suspect placement/resource/clock/power/GT interaction. If it fails with dummy load, suspect DDR PHY margin/constraints/floorplanning. If it fails with only the new wrapper parameters, suspect parameterization or BIST patch.

### Phase 5 — floorplan DDR

For DDR3, random seed success is not enough. The PHY should be physically constrained or at least strongly guided:

```text
Constrain DQ/DQS/DM/ODELAY/IDELAY/ISERDES/OSERDES near the relevant IO bank.
Keep byte lanes compact.
Keep IDELAYCTRL/refclk associated with the correct IO bank region.
Separate PCIe/GT placement pressure from DDR byte lanes.
Compare successful and failing seed placement/routing for DDR byte lanes.
```

A practical metric: extract physical locations and route delays for each DQS/DQ lane for every seed and correlate them with calibration pass/fail.

### Phase 6 — Vivado as a control experiment

A temporary Vivado reproduction is useful, even if the final project remains open source.

Interpretation:

```text
Vivado passes robustly, OpenXC7/nextpnr seed-sensitive:
    likely open-flow timing/bitstream/placement/constraint modeling gap.

Vivado also seed-sensitive or fails:
    likely RTL, board, constraints, DDR margin, or board signal integrity.

Vivado passes only with MIG-style/floorplanned constraints:
    your open flow probably needs equivalent explicit physical/IO constraints.
```

This is not a recommendation to abandon the open-source flow. It is a controlled experiment to locate the failure class.

## Additional instrumentation to add

Add a compact DDR calibration telemetry register block exposed through JTAG and, after PCIe is stable, through BAR:

```text
PLL locked
IDELAYCTRL ready
DCI locked
DDR reset released timestamp
controller reset released timestamp
calibration FSM state
last calibration substate
per-lane bitslip count
per-lane read-level tap
per-lane write-level tap
per-lane MPR pass/fail
per-lane DQS window left/right/center if available
first failing BIST address
expected data
observed data
failing byte lane
failing bit mask
Wishbone request/ack/stall counters
calibration timeout counter
rowstream command accepted count
rowstream command error code
```

The important change is to stop reporting only “calibration failed”. Report **which calibration phase failed and on which lane/tap/address**.

Also add host-side run logging:

```text
lspci -Dnn
lspci -vv
setpci COMMAND/STATUS
BAR magic/version/status
dmesg excerpt
Thunderbolt authorization state
cold/warm boot marker
JTAG status snapshot
DDR telemetry snapshot
```

## Seed sweeping recommendation

Seed sweeping is acceptable only as **characterization** or a temporary workaround. It is useful to answer:

```text
What percentage of seeds pass?
Do passing seeds cluster by placement/routing pattern?
Does floorplanning increase pass rate?
Does removing --no-tmdriv improve pass rate?
Does temperature or cold/warm boot change pass rate?
```

It becomes a red flag when:

```text
The only acceptance criterion is “some seed works”.
No failing-seed telemetry is recorded.
No XDC/CDC audit has been done.
A single seed is flashed without voltage/temp/cold-boot repetition.
Standalone DDR is already seed-sensitive and no margin measurement exists.
```

For this project, seed sweeping is reasonable **only if each seed is logged as an experiment**. It should feed a constraint/floorplanning fix, not replace one.

## Toolchain determinism and options

For determinism:

```text
Yosys:
  Use logs with timestamps.
  Avoid --randomize-pointers.
  Consider fixed --hash-seed / --autoidx for reproducibility experiments.
  Turn important warnings into errors.

nextpnr-xilinx:
  Always set --seed explicitly.
  Do not use --randomize-seed for debug runs.
  A/B test --no-tmdriv versus timing-driven placement.
  Record --placer and --router.
  Emit --log and optionally --sdf.

FASM/fasm2frames:
  Hash canonicalized FASM.
  Use fasm2frames --debug for suspicious builds.
  Avoid changing --sparse between comparable runs unless intentionally testing it.

xc7frames2bit:
  Record exact part_name, part_file, and DB root.
```

FASM itself is a good comparison boundary: the FASM spec says sorting FASM does not change the resulting bitstream and canonical forms that match must enable the same features. Use that property to separate “different implementation” from “different bitstream-generation behavior”. ([fasm.readthedocs.io][5])

## PCIe reboot / chassis power-cycle question

A full laptop reboot should **not** be the default after every test.

Your repository already has the right structure in `task6_pcie_gate_root.sh`: it can remove/rescan the endpoint, enable memory space, try device reset, subordinate bus reset, bridge hot reset via `BRIDGE_CONTROL`, upstream/root bridge recovery, and Thunderbolt deauthorize/reauthorize.  

Linux PCI driver flow normally includes enabling the PCI device, requesting regions, setting DMA masks, enabling bus mastering, then reversing this on removal; config/device state can be manipulated by drivers and sysfs, but only if the device and upstream path still respond sanely. ([Kernel Documentation][6]) ([Kernel Documentation][6])

Thunderbolt adds another layer: security levels can require authorization before PCIe tunnels are created, writing `1` to `authorized` creates tunnels, and writing `0` tears them down analogously to hot-remove. ([Kernel Documentation][7])

Recommended reset ladder:

```text
1. Stop user process touching BAR.
2. Unbind driver if any.
3. echo 1 > /sys/bus/pci/devices/$BDF/remove
4. echo 1 > /sys/bus/pci/rescan
5. If stale: echo 1 > /sys/bus/pci/devices/$BDF/reset if present.
6. If stale: echo 1 > bridge/reset_subordinate if present.
7. If stale: toggle bridge secondary bus reset with setpci BRIDGE_CONTROL bit 6.
8. If stale: deauthorize/authorize Thunderbolt device.
9. If stale: power-cycle chassis or assert PERST#.
10. Full laptop reboot only after bridge/root/TB recovery fails.
```

What software usually cannot guarantee:

```text
Recovering a Thunderbolt bridge firmware state that is wedged.
Recovering an endpoint reconfigured while the host still owns stale BAR/config state.
Toggling endpoint PERST# if the chassis does not expose it.
Recovering from bad LTSSM/electrical state if the link partner never retrains.
Power-rail or refclock recovery.
```

Best autonomous workflow:

```text
Use BPI flash for PCIe enumeration tests.
Use JTAG-only DDR tests before involving PCIe.
Install the root helper permanently.
Add a USB relay or controllable AC switch for the Thunderbolt chassis.
If possible, add controllable PERST# or FPGA PROGRAM_B.
Separate “DDR calibration passed” from “PCIe enumerated” from “BAR transactions work”.
```

## Constraint and CDC checklist

Before trusting another bitstream, require this checklist:

```text
Clocks
  Primary clocks defined.
  PLL/MMCM generated clocks represented or intentionally equivalent.
  PCIe user clock constrained.
  DDR controller, DDR 0°, DDR 90°, and 200 MHz ref clock constrained.
  No unconstrained clock domains.

CDC/RDC
  PCIe user clock ↔ DDR controller clock crossings enumerated.
  All single-bit crossings synchronized.
  Multi-bit crossings use handshake, FIFO, stable latch, or are diagnostic-only.
  ASYNC_REG or equivalent applied and preserved.
  Async resets either synchronized per domain or constrained intentionally.

DDR IO
  DQ/DQS byte lanes physically grouped.
  IDELAYCTRL/refclk correct.
  INTERNAL_VREF correct for bank voltage.
  DCI/termination/ODT/DIC/RTT_NOM reviewed.
  DQS/DQ/clock forwarding constraints reviewed.
  DM disabled intentionally and tests adjusted accordingly.

Timing exceptions
  False paths justified.
  Multicycle paths justified.
  No false path hides DDR calibration logic.
  No unconstrained endpoints.
  No cross-domain path accidentally timed as synchronous.

Physical
  PCIe hard block/GTX placement constrained.
  DDR IO primitives placed legally and consistently.
  BSCAN chains non-conflicting.
  Critical DDR PHY logic not randomly scattered.
```

## Revised mental model

Use this model instead:

```text
RTL simulation:
  Shows behavior under a model.

Formal:
  Proves selected properties under assumptions.

Synthesis:
  Preserves intended logic only if attributes, resets, memories, and primitives are mapped correctly.

Place and route:
  Creates one physical implementation among many possible implementations.

Timing closure:
  Proves only modeled timing paths under declared constraints and the tool’s timing model.

DDR3 calibration:
  Tests real DQ/DQS phase, delay taps, board skew, IO banks, VREF/termination, jitter, and power integrity.

PCIe:
  Requires protocol/link training, reset sequencing, host enumeration, BAR ownership, and recoverable hotplug/reset behavior.

Open-source Xilinx flow:
  Adds uncertainty in device model, hard-block support, timing model, bitstream feature coverage, and XDC subset semantics.

Hardware correctness:
  Requires all of the above to hold across seeds, cold/warm boot, temperature, voltage, and host reset states.
```

The actionable interpretation for Task 6 is: **stop treating seed choice as the independent variable to optimize; treat it as a probe of missing margin.** The next best work is constraint diffing, CDC proof, DDR calibration telemetry, and a controlled seed matrix with floorplanning experiments.

[1]: https://github.com/YosysHQ/nextpnr "GitHub - YosysHQ/nextpnr: nextpnr portable FPGA place and route tool · GitHub"
[2]: https://github.com/f4pga/prjxray "GitHub - f4pga/prjxray: Documenting the Xilinx 7-series bit-stream format. · GitHub"
[3]: https://docs.amd.com/r/en-US/ug903-vivado-using-constraints "Vivado Design Suite User Guide: Using Constraints (UG903) - 2025.2 English - Describes the AMD Vivado™ design tools, features, and user interface. - UG903"
[4]: https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/CDC-Synchronizers-and-ASYNC_REG-Property?contentId=YbjfvWgQlydYf33g1QZhtw "CDC Synchronizers and ASYNC_REG Property - 2025.2 English - UG903"
[5]: https://fasm.readthedocs.io/en/latest/specification/syntax.html "File Syntax description — FPGA Assembly (FASM) 0.0.2-100-gffafe82 documentation"
[6]: https://docs.kernel.org/PCI/pci.html "1. How To Write Linux PCI Drivers — The Linux Kernel  documentation"
[7]: https://docs.kernel.org/admin-guide/thunderbolt.html "USB4 and Thunderbolt — The Linux Kernel  documentation"
