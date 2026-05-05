# v104 host-side v99/v103 matrix analysis

## Inputs

- v99 probe: `artifacts/task6/experiments/v99-dfii-byte-phase-wide-matrix/probe.json`
- v103 exact replay probe: `artifacts/task6/experiments/v103-exact-v99-replay/probe.json`

## Reproducibility verdict

The host-side matrices match between v99 and v103: `True`.
The combined nonzero masks also match: `True`.

Both runs are init-clean and complete at the DFII probe level:

- v99 state: `PROBE_DFII_DONE`
- v103 state: `PROBE_DFII_DONE`
- v103 init: `pll_locked=true`, `init_done=true`, `init_error=false`, `init_seq_done=true`, `init_seq_error=false`, `wb_timeout_seen=false`

## Combined 20-slot matrix

| Source | Match mask | Read slots |
|---:|---:|---|
| 0 | 0x00201 | [0, 9] |
| 1 | 0x00402 | [1, 10] |
| 2 | 0x00804 | [2, 11] |
| 3 | 0x01008 | [3, 12] |
| 4 | 0x02010 | [4, 13] |
| 5 | 0x04020 | [5, 14] |
| 6 | 0x08040 | [6, 15] |
| 7 | 0x00000 | [] |
| 8 | 0x20100 | [8, 17] |
| 9 | 0x00000 | [] |
| 10 | 0x00000 | [] |
| 11 | 0x00000 | [] |
| 12 | 0x00000 | [] |
| 13 | 0x00000 | [] |
| 14 | 0x00000 | [] |
| 15 | 0x00000 | [] |

## Host-side interpretation

The observed subset is deterministic and collision-free on read slots, but it is not bijective from source to read slot because observed sources fan out to two slots each.

Observed pattern:

- sources `0..6` map to read slots `{s, s+9}`
- source `8` maps to read slots `[8, 17]`
- source `7` maps to no read slots
- sources `9..15` map to no read slots

Read slots observed: `[0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 17]`.
Read slots missing: `[7, 16, 18, 19]`.

The strongest host-only inference is that source 7 would have appeared at read slots `[7, 16]` if the observed linear rule continued. Both are absent. This supports a missing `source7` / `slots7,16` hypothesis, but it is not a proof of physical lane mapping.

## Decision

Do not change DDR packing from this analysis alone. The data is enough to constrain the next RTL experiment, but not enough to apply a transform.

Next gate: any new RTL experiment must be smaller than v100-v102 and must include an immediate exact-v99 replay comparator. The current safe correction target is not a byte permutation; it is an instrumented proof of whether source7/slots7,16 are suppressed before or after the DFII write/read association path.
