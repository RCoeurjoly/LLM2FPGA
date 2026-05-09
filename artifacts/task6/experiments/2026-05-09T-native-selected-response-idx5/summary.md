# LiteDRAM native beat mapping analysis

- Source: `artifacts/task6/runs/2026-05-09T08-10-26+0200-v117-cmdaddr-idx5-board-health-recheck/logs/read-litedram-probe-jtag-ftdi-11264.log`
- State: `PROBE_DONE`
- Version: `116`
- Command/response count: `16` / `16`
- Valid samples: `16`
- Start index override: `0`
- Mismatches: `16`
- Unique native beats: `1`

## Command Address Trace

| command index | scheduled | presented | accepted | accepted=requested |
| ---: | ---: | ---: | ---: | --- |
| 5 | 15 | 15 | 15 | True |

## Selected Response

- Response index: `5`
- Valid: `True`
- Accepted command address: `15`
- Response requested native address: `15`
- Accepted matches response request: `True`
- Best same-position DFII addr: `15`
- Same-position chunks: `2`
- Best any-position DFII addr: `15`
- Any-position chunks: `3`
- Byte-exact matches: `18`
- Top byte votes: `15:528`

## Sample Summary

| sample | requested native addr | best same-position addr | same chunks | best any-position addr | any chunks | byte exact | top byte votes |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0 | 0 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 1 | 1 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 2 | 2 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 3 | 3 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 4 | 8 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 5 | 15 | 15 | 2 | 15 | 3 | 18 | 15:528 |
| 6 | 16 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 7 | 31 | 15 | 2 | 15 | 3 | 18 | 15:528 |
| 8 | 64 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 9 | 128 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 10 | 256 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 11 | 512 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 12 | 1024 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 13 | 2048 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 14 | 4096 | 15 | 2 | 15 | 3 | 0 | 15:528 |
| 15 | 8192 | 15 | 2 | 15 | 3 | 0 | 15:528 |

## Interpretation

- `same chunks` counts 64-bit chunks matching the same chunk position.
- `any chunks` counts 64-bit chunks matching any expected chunk position for one DFII address index.
- `byte exact` counts byte matches at the requested address and exact byte position.
- If all samples share one beat but command addresses differ, the failure is below native command acceptance.
