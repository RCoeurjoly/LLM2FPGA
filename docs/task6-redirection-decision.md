# Task 6 Redirection Decision

Date: 2026-04-28
Branch: `task6-streamtensor-lite`

## Decision

Pivot Task 6 away from `topN-memory` / full-model external-memory synthesis as
the mainline. Keep that path only as a negative mapped-resource baseline and a
toolchain stress test.

The active mainline is now:

- reusable tiled compute engines, starting with GEMV
- external memory as sequential/burst weight storage feeding those engines
- explicit int8/int4 weight packs and bounded fixed-point kernels
- representative-core and reduced-vocab rungs as fast validation surfaces
- synthetic DRAM behavior measured before board DRAM integration

## Why

The latest `top34-memory` result completed but mapped to:

- `56,899,009` CLB LUTs
- `58,496,710` CLB FFs
- `0` DSP
- `0` BRAM36

That is `19055.26%` of LUT budget and `9795.16%` of FF budget. It is a
toolchain-frontier success, but not a board-fit architecture.

The copied all-memory baseline is still the comparison point:

- `40,416,086` CLB LUTs
- `58,072,527` CLB FFs
- `0` DSP
- `0` BRAM36 equivalent

So `top34-memory` regresses mapped resources by:

- `+16,482,923` LUTs (`+40.78%`)
- `+424,183` FFs (`+0.73%`)
- no DSP or BRAM improvement

The implementation also does not instantiate a real DDR/burst subsystem. It
blackboxes selected lowered `handshake_memory_*` modules and leaves a large
float32, handshake-heavy shell around them. That explains why it can move the
synthesis frontier while still increasing mapped fabric.

## Closed Mainline

Closed as a board-fit mainline:

- `topN-memory` as "externalize some lowered memories and synthesize the rest"
- monolithic float32 full-model RTL lowering
- additional full-model mapped runs before a small kernel predicts an order of
  magnitude resource reduction
- more local tiled `L2 c_fc` buffer surgery without a stronger structural
  hypothesis

Still useful:

- `top34-memory` as a negative baseline row
- external memory as an interface-contract lane
- largest remaining owners from the `top34-memory` artifact as diagnostic
  signals, not as the next default implementation target

## Active Hypotheses

Run these as bounded, fast-reject lanes:

| ID | Hypothesis | Required signal |
| --- | --- | --- |
| `H1` | External memory works only with streaming and tiling | cycles/token, bytes/token, `DSP > 0`, no dominant `handshake_memory_out_*` |
| `H2` | Quantization is required for fit | int8/int4 kernel, bounded error, at least `2x` LUT reduction or `<15k` LUT on `L2` |
| `H3` | Static sequencer beats handshake lowering | deterministic counters/FSM reduce tiled `L2` below current `31,907` LUT |
| `H4` | Fused/approximated MLP removes float helper blowups | `math_fpowi_*` disappears from top owners and fused slice is smaller |
| `H5` | Smaller/staged TinyStories variant may be needed first | exact model bytes and minimum bandwidth for candidate rungs |

Start with `H1`, `H2`, `H3`, and `H5`. Start `H4` only after GEMV/static
plumbing is stable enough to add activation and projection.

## Gate Ladder

Every new hypothesis uses this ladder:

| Gate | Requirement | Target time |
| --- | --- | --- |
| A | structural RTL/IR inspection, owner count, memory count, expected DSP/BRAM | `<5 s` |
| B | Yosys stat or light synthesis | `<30 s` |
| C | mapped `abc9` utilization only for survivors | `<2 min` |

Hard stop rules:

- reject compute-heavy kernels with `DSP == 0`
- reject mapped LUT worse than current reference by more than `10%`
- reject if no Verilator pass after one debug slice
- reject if `handshake_memory_out_*` remains a dominant owner after the
  intended transformation
- reject if a full-model build is needed before the hypothesis can be scored

## Frozen References

| Artifact | LUT | FF | DSP | BRAM36 | Verdict |
| --- | ---: | ---: | ---: | ---: | --- |
| `L1` `c_fc` frozen reference | `29,778` | `46,352` | `4` | `0` | pass |
| `L2` tiled `4 x 64` reference | `31,907` | `45,932` | `4` | `0` | fail LUT ceiling |
| `top34-memory` full-model shell | `56,899,009` | `58,496,710` | `0` | `0` | negative baseline |

The first Task 6 redirection artifact is:

- `artifacts/task6/parallel-hypotheses/baseline-top34.csv`

It records `top34-memory`, `L1`, and `L2` as machine-readable baseline rows for
the parallel hypothesis lanes. Its `top_owners` field is weighted by owner
instance count under `main`, so repeated handshake buffers are visible as the
dominant `top34-memory` shell cost.

The first H1/H2/H5 scoring artifacts are:

- `artifacts/task6/parallel-hypotheses/h5-rung-byte-budgets.csv`
- `artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.csv`
- `artifacts/task6/parallel-hypotheses/h1-h2-streaming-contract-score.json`
- `artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.csv`
- `artifacts/task6/parallel-hypotheses/h2-quantized-weight-replay.json`

The first H3 narrowing artifact is:

- `artifacts/task6/parallel-hypotheses/h3-static-wrapper-inspection.json`
