# L1 Post-Branch Out-Buffer FIFO2 Proof

## Commands

- Functional proof:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-sv-sim --no-link -L`
- Mapped utilization:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9-utilization --no-link --print-out-paths`

## Logs

- [sv-sim.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-outbuf-fifo2-proof/sv-sim.log)
- [abc9-utilization.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T13-55-32+0200/l1-index-ring3-postbranch-outbuf-fifo2-proof/abc9-utilization.log)

## Metrics

- DSP:
  - `4`
- BRAM36:
  - `0`
- LUT:
  - `29,778`
- FF:
  - `46,352`
- Verilator passed:
  - `yes`
- Yosys stat finished within budget:
  - `yes`
- Large weights emitted as RTL constants:
  - `no`
- Verilator wall-clock / RSS:
  - `133.51 s` / `437,680 KB`
- `abc9` wall-clock / RSS:
  - `149.06 s` / `562,936 KB`
- Delta vs first post-branch cut:
  - `LUT -189`
  - `FF -260`
- Delta vs frozen ring-3 reference:
  - `LUT -542`
  - `FF -1,040`

## Verdict

- This bounded out-buffer extension clears the `L1` LUT ceiling while
  preserving the existing external-weight and DSP-backed proof.
- `task6-l1-c-fc-redirect-index-ring3-postbranch-outbuf-fifo2-abc9` is the
  new `L1` reference.

## Next Action

- Replay the new `L1` reference on `L2` before any promotion to `L3`.
