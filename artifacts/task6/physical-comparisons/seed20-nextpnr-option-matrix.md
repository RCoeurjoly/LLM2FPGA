# Task 6 Seed20 nextpnr Option Matrix

Baseline failing candidate: `task6-ypcb-pcie-uberddr3-rowstream-loader-seed20`.
Passing reference: `task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20`.

Every row is one-factor-at-a-time unless noted. Hardware acceptance always starts with lifecycle. If lifecycle is not `pcie_ready`, stop before BAR access.

| Order | Variant | Package suffix | Controlled option change | Why it matters | Build first | Hardware gate |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | baseline | `seed20` | `--no-tmdriv`, default heap placer, router2, no top-level `--freq` | Known full-image `missing_resource0` control | already built | already failed as `missing_resource0` |
| 1 | timing-driven placement | `seed20-tmdriv` | remove `--no-tmdriv` | Tests whether timing-driven placement fixes PCIe/BAR physical fragility | placed JSON + FASM | lifecycle, then BAR/debug if `pcie_ready` |
| 2 | explicit frequency | `seed20-freq625` | keep `--no-tmdriv`, add `--freq 62.5` | Tests whether a top-level target frequency changes budgeting/route choices | placed JSON + FASM | lifecycle, then BAR/debug if `pcie_ready` |
| 3 | placer algorithm | `seed20-placer-sa` | keep `--no-tmdriv`, add `--placer sa` | Tests whether heap placement is the fragile variable | placed JSON + FASM | lifecycle, then BAR/debug if `pcie_ready` |
| 4 | router algorithm | `seed20-router1` | keep `--no-tmdriv`, add `--router router1` | Tests whether router2 creates fragile PCIe/GT/BAR routing | placed JSON + FASM | lifecycle, then BAR/debug if `pcie_ready` |
| 5 | placer budgets | `seed20-placer-budgets` | keep `--no-tmdriv`, add `--placer-budgets` | Tests binary timing-weighting behavior without changing placer/router | placed JSON + FASM | lifecycle, then BAR/debug if `pcie_ready` |
| 6 | combined timing-driven + freq | `seed20-tmdriv-freq625` | remove `--no-tmdriv`, add `--freq 62.5` | Tests the most plausible binary flag combination after rows 1 and 2 | placed JSON + FASM | lifecycle, then BAR/debug if `pcie_ready` |

For each variant, compare against loader-only seed20 and baseline full seed20:

```sh
scripts/task6/task6_compare_seed20_physical.py \
  --loader-only-yosys-json <loader-only-yosys-json> \
  --full-yosys-json <full-yosys-json> \
  --loader-only-placed-json <loader-only-seed20-placed-json> \
  --full-placed-json <variant-placed-json> \
  --loader-only-fasm <loader-only-seed20-fasm> \
  --full-fasm <variant-fasm> \
  --label <variant>
```

Binary flags to prioritize: `--no-tmdriv` on/off, `--placer-budgets` off/on. Algorithm switches to evaluate next: `--placer heap/sa`, `--router router2/router1`. Numeric knobs (`--freq`, `--cstrweight`, `--starttemp`, `--slack_redist_iter`) should be added only after the binary and algorithm rows are classified.

## Static Results So Far

| Variant | Static artifact | Classification | PCIe primitive changed cells | PCIe/GT FASM added/removed | DDR3 placement | DDR3 FASM | Hardware status |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| `seed20` baseline | `artifacts/task6/physical-comparisons/2026-05-26T22-56-10+0200-loader-only-seed20-vs-full-seed20` | `pcie_physical_delta` | 0 | 443930 / 277517 | PASS | FAIL | cold BPI `missing_resource0` |
| `seed20-tmdriv` | `artifacts/task6/physical-comparisons/2026-05-26T23-22-26+0200-seed20-tmdriv` | `pcie_physical_delta` | 0 | 448902 / 280612 | PASS | FAIL | not flashed |
| `seed20-placer-budgets` | `artifacts/task6/physical-comparisons/2026-05-26T23-29-26+0200-seed20-placer-budgets` | `pcie_physical_delta` | 0 | 443927 / 277514 | PASS | FAIL | not flashed |

Initial read: the two prioritized binary flags do not collapse the physical delta against the known-good loader-only seed20 image. `--placer-budgets` is almost identical to baseline at the coarse FASM-count level; removing `--no-tmdriv` moves even more FASM. Hardware flashing should still use the lifecycle gate first, but neither row is a strong determinism candidate from static evidence alone.

## Finite-Choice Clarification

Treat "binary/easy flags" here as finite-choice implementation knobs: booleans plus small enums such as `--placer heap|sa` and `--router router1|router2`.

Interactive build-cost result:

| Variant | Option change | Interactive result | Matrix status |
| --- | --- | --- | --- |
| `seed20-placer-sa` | `--placer sa` instead of default heap | stopped after several minutes of active nextpnr CPU with no artifact; substantially slower than the default heap row | cost-prohibitive for quick matrix; run as an overnight/long-budget job if still needed |
| `seed20-router1` | `--router router1` instead of default router2 | stopped after several minutes of active nextpnr CPU with no artifact; substantially slower than the default router2 row | cost-prohibitive for quick matrix; run as an overnight/long-budget job if still needed |

SDF options:

- `--sdf <file>` is diagnostically interesting because it emits delay back-annotation for timing simulation or delay inspection.
- `--sdf-cvc` is only interesting if the SDF consumer is CVC; it should affect SDF formatting/compatibility, not implementation quality.
- Neither option should be treated as a determinism/fix candidate for placement, routing, FASM, or hardware behavior unless nextpnr has an unintended side effect. They belong in a diagnostics-artifact lane, not in the hardware-candidate lane.

## SDF Diagnostic Lane

Correction: `--sdf <file>` is a debug-output option, not a bitstream-improvement option. It is still important because it emits post-implementation delay data that can be mined for timing-model clues around DDR3 PHY, PCIe/GT, clocking, and CDC-adjacent paths.

Built SDF artifacts for the current A/B pair:

| Image | SDF artifact | Lines | Use |
| --- | --- | ---: | --- |
| loader-only seed20, passing hardware reference | `/nix/store/2nffvbhh7p3plhrp1y382rmrlpvs4w4b-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.sdf` | 450591 | reference delay model |
| full seed20, failing `missing_resource0` candidate | `/nix/store/j6sha4hcnlrid0sgsmviq3314m4ck68s-task6-ypcb-pcie-uberddr3-rowstream-loader-seed20.sdf` | 630355 | failing delay model |

Initial sanity check: both SDF files are valid SDF 3.0 from nextpnr and include DDR PHY/IDELAY-related instance names. The raw SDF is too large for manual review; the next useful step is a focused SDF summarizer that extracts and compares delay distributions for `PCIE`, `GT`, `BUFG`, `ddr3_phy`, `IDELAYE2`, `ISERDESE2`, `OSERDESE2`, and known CDC/reset boundary paths.

`--sdf-cvc` remains a consumer-compatibility option. Use it only if CVC will consume the SDF; it should not be expected to change implementation or add materially different debug data.
