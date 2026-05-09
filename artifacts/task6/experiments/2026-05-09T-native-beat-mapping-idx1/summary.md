# LiteDRAM native beat mapping analysis

- Source: `artifacts/task6/runs/2026-05-08T22-20-18+0200-v117-cmdaddr-idx1-board-check/logs/read-litedram-probe-jtag-ftdi-11264.log`
- State: `PROBE_DONE`
- Version: `116`
- Command/response count: `16` / `16`
- Valid samples: `16`
- Mismatches: `16`
- Unique native beats: `1`

## Command Address Trace

| command index | scheduled | presented | accepted | accepted=requested |
| ---: | ---: | ---: | ---: | --- |
| 1 | 1 | 1 | 1 | True |

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
