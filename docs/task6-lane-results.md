# Task 6 Board RAM Lane Results

Date: 2026-04-17
Branch: `task6-board-ram`

## Baseline used for comparison

All comparisons in this note use the copied baseline bundle:

- `artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization`

Baseline summary from that bundle:

- top module: `tiny_stories_selftest_top`
- LUTs: `40,416,086 / 298,600`
- FFs: `58,072,527 / 597,200`
- DSPs: `0 / 1,920`
- BRAM36-equivalent: `0 / 955`
- result: `fits_overall = false`

Important interpretation:

- The copied baseline already reports `0` BRAM usage, so the current all-on-chip
  memory pressure is being materialized mostly as LUT/FF logic rather than neat
  block RAM inference.
- For this lane, the meaningful savings number is therefore "modeled memory
  bits removed from the on-chip implementation path", plus any observed LUT/FF
  relief from shell-mode experiments.

## Memory picture

Prior RTLIL inventory work on the same TinyStories all-memory path in
`origin/task3-rfp-sandbox` reported:

- `326` memories
- `433,040,010` total memory bits
- four `3216448 x 32` memories alone account for `411,705,344` bits
- those four memories are `95.1%` of the modeled memory bits
- after removing only those four, the remaining modeled memory bits are
  `21,334,666` bits (`2.54 MiB`)

Most relevant prior shell-mode comparison against the copied baseline:

- externalizing all memories `>= 131072` bits reduced LUTs from `40,416,086`
  to `34,950,553` (`-5,465,533`, about `-13.5%`)
- FFs stayed at `58,072,527`
- BRAM36-equivalent still reported `0`
- because the four giant vocab-sized tables dominate the memory bits, they are
  the most credible first subset to move before attempting broader off-chip
  coverage

Why the four giant memories matter:

- `3216448 = 50257 * 64`
- the TinyStories-1M config used in this repo fixes `vocab_size = 50257` and
  `hidden_size = 64`
- that shape strongly suggests these are vocab-sized tables, most plausibly
  embedding / LM-head style tables or replicated copies of that data in the
  lowered design

## Candidate DDR3 placements

| Candidate memory | Expected saving versus baseline | Interface cost added | DDR3 access pattern | Viability |
| --- | --- | --- | --- | --- |
| Four `3216448 x 32` vocab-sized tables | Move `411,705,344` bits (`49.08 MiB`) off the on-chip path. This is `11.7x` the board BRAM capacity model (`35,205,120` bits). These four memories dominate the baseline memory picture. | Read-only DDR3 table interface, burst reader, small on-chip row/burst buffer, arbitration across the logical tables. No full LSQ/system rewrite required. | Plausible if treated as read-mostly tables. Embedding-style lookup is a small random row fetch. LM-head-style use requires burst streaming through the table while keeping the 64-element hidden vector on-chip. | `recommended` |
| Remaining `>= 131072`-bit memories beyond the four giant tables | Adds only `20,744,736` bits (`2.47 MiB`) of extra saving beyond the primary cut. | More ports, more address/control plumbing, weaker payoff. | Mixed. Some are still table-like, but the marginal gain is much smaller. | `conditional` |
| Attention-mask / cache-like 2048-scale memories | Smaller than the primary vocab-sized tables and not the dominant baseline pressure point. | Would need deeper schedule/control changes and stronger guarantees about sequential access and reuse. | Risky for a first DDR3 experiment because repeated fine-grained accesses can erase the BRAM win. | `reject` |

## DDR3 assumptions

Conservative assumptions used for this lane result:

- Capacity floor: use the lane document's `2 Gb DDR3` assumption, and treat
  the external-memory budget as at least `256 MiB` usable before claiming
  success.
- Bandwidth floor: require at least `0.8 GB/s` sustained read bandwidth as a
  credible lower bound for a board-facing experiment.
- Controller style: read-only or read-mostly table access first; do not start
  with a general shared read/write memory subsystem.

Capacity consequence:

- The recommended `49.08 MiB` cut fits comfortably inside the conservative
  `256 MiB` assumption.

Bandwidth consequence:

- One `50257 x 64 x f32` table is `12.27 MiB`.
- Streaming one such table once per generated token needs about `12.27 MiB`
  per token.
- Ideal ceilings for one streamed table are `31 tok/s` at `0.4 GB/s`,
  `62 tok/s` at `0.8 GB/s`, and `124 tok/s` at `1.6 GB/s`.
- Streaming all four giant tables every token would be `49.08 MiB` per token
  and is not a credible assumption unless later instrumentation proves all four
  are truly hot on every decode step.

Board-spec caveat:

- `docs/task6-lane.md` says to reason with the board's `2 Gb DDR3`.
- External reverse-engineering sources for `YPCB-00338-1P1` describe a much
  larger dual-bank DDR3 setup and faster MIG examples.
- This lane result does not rely on that larger external figure; it keeps the
  conservative `2 Gb` floor explicit.

## Recommendation

Recommended first off-chip strategy:

- Move the four `3216448 x 32` vocab-sized tables to DDR3 first.
- Treat them as read-mostly external tables, not as a general-purpose external
  scratchpad.
- Reuse the donor branch's narrow helper approach
  (`externalize_large_memories.py`-style shell measurement) if implementation
  work starts, because it isolates the memory move without demanding a full
  LSQ/SoC rewrite.

Why this is the narrowest credible experiment:

- It attacks `95.1%` of the modeled memory bits.
- The access story is plausible for DDR3 if the table path is burst-oriented.
- It avoids drifting into cache redesign, full activation offload, or broad
  LSQ benchmarking.

Current lane verdict:

- primary candidate: four vocab-sized tables
- overall viability: `recommended`
- rejected as first experiment: broad activation/cache offload

## Implementation follow-up

To keep this lane moving toward a shell-mode experiment without forcing a full
LSQ or board-handoff rewrite, this branch now carries:

- `scripts/pipeline/externalize_large_memories.py`

Intended use:

- scan emitted RTLIL for oversized `\handshake_memory_*` modules
- auto-generate a Yosys script that blackboxes those modules
- measure the shell/controller fabric after removing the chosen memory modules

Practical next shell experiment:

- start with the dominant threshold that isolates the four giant vocab-sized
  tables first
- compare the generated shell report against the copied baseline bundle before
  broadening to smaller memories
