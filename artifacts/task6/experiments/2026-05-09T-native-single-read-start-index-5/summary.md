# LiteDRAM native beat mapping analysis

- Source: `/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6/runs/2026-05-09T08-06-39+0200-v118-single-read-start-index-5-board-check/logs/read-litedram-probe-jtag-ftdi-11264.log`
- State: `PROBE_ERROR`
- Version: `116`
- Command/response count: `0` / `0`
- Valid samples: `0`
- Start index override: `5`
- Mismatches: `0`
- Unique native beats: `0`

## Sample Summary

| sample | requested native addr | best same-position addr | same chunks | best any-position addr | any chunks | byte exact | top byte votes |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |

## Interpretation

- `same chunks` counts 64-bit chunks matching the same chunk position.
- `any chunks` counts 64-bit chunks matching any expected chunk position for one DFII address index.
- `byte exact` counts byte matches at the requested address and exact byte position.
- If all samples share one beat but command addresses differ, the failure is below native command acceptance.
