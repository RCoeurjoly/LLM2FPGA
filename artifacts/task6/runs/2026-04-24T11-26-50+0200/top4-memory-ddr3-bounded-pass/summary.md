# Top4-Memory DDR3 Bounded Pass

## Commands

```bash
nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan --no-link --print-out-paths
nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization --no-link --print-out-paths
```

The utilization build was interrupted after the narrowed shell had re-entered
staged Yosys and no new mapped result had landed inside the bounded pass
window.

## Outputs

- external-memory-plan:
  - `/nix/store/92wwyy3d90z6kiclnqncig9365ikd64n-tiny-stories-1m-baseline-float-selftest-top4-memory-external-memory-plan`
- rebuilt selected modules:
  - `\handshake_memory_out_f32_id342`
  - `\handshake_memory_out_f32_id341`
  - `\handshake_memory_out_f32_id340`
  - `\handshake_memory_out_f32_id18`

## Metrics

- selected module count: `4`
- eligible module count: `326`
- selected total bits: `411,705,344`
- eligible total bits: `433,040,010`
- selected share of eligible bits: `95.1%`
- selected footprint: `49.08 MiB`
- per selected module:
  - `3216448 x 32`
  - `102,926,336` bits
- live narrowed-shell utilization observations before interruption:
  - reached `stage1.il` and `stage2.il`
  - active staged Yosys RSS observed up to `8,935,948 KB`

## Bandwidth Note

- full cold sweep of the selected top-four footprint:
  - `1.6 GB/s` -> `32.16 ms`
  - `2.0 GB/s` -> `25.73 ms`
  - `3.2 GB/s` -> `16.08 ms`
  - `4.0 GB/s` -> `12.87 ms`
  - `6.4 GB/s` -> `8.04 ms`
- pessimistic upper bound if all four tables were reread every token:
  - `1 tok/s` -> `0.051 GB/s`
  - `10 tok/s` -> `0.515 GB/s`
  - `50 tok/s` -> `2.573 GB/s`
  - `100 tok/s` -> `5.146 GB/s`

This is a sizing worksheet, not a measured DDR3 traffic trace.

## Verdict

`partial`

- The narrowed `top4-memory` plan is still reproducible and still targets the
  same four dominant vocab-sized tables.
- The real-baseline narrowed shell re-entered staged Yosys.
- No new mapped shell utilization result was produced inside this bounded pass.

## Next Action

- If this track gets another slice, rerun
  `tiny-stories-1m-baseline-float-selftest-top4-memory-utilization` under
  `scripts/pipeline/monitor_build.sh` so the late-stage shell frontier is
  captured as a real artifact.
- Otherwise move on to the bounded PT2E-static quantized replay.
