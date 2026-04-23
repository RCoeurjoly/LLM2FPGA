# Reduced-Vocab One-Block Top Yosys Gate

## Commands

`/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json --no-link --print-out-paths`

## Logs

- `tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json`
  - output: `/nix/store/hh7fkqlis1kdgi07qgmxxjl1nl6lxrq9-tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys.json`
  - `ELAPSED=99.26`
  - `RSS_KB=564340`

## Metrics

- DSP: `pending pre-map`
- BRAM36: `pending pre-map`
- LUT: `pending pre-map`
- FF: `pending pre-map`
- wall-clock runtime: `99.26 s`
- large weights emitted as RTL constants: `no`, inherited from the externalized reduced-vocab `L1` path; this gate does not re-embed weights
- Verilator passed: `yes`, inherited from the frozen `L1` kernel reference; this step only checks the one-block-top Yosys gate
- Yosys stat finished within budget: `yes`, the available repo one-block-top gate surface completed within the `< 2 min` budget

## Verdict

The repo's available reduced-vocab one-block-top Yosys gate,
`tiny-stories-v1k-h64-l1-selftest-top4-memory-yosys-json`, completes in
`99.26 s`, so the pending promotion gate is no longer missing. That answers the
runtime question, but it does not change the fit-first decision because the
best frozen `L1` point still misses the LUT ceiling.

## Next Action

Do not widen to `L3` or `L4` from this result alone. Keep the frozen
`L1` ring-3 `abc9` point as the reference and only spend another slice if it is
a different fit lever than the rejected control/merge hotspot.

