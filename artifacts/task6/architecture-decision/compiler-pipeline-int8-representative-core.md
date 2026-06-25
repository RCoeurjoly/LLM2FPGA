# Compiler Pipeline Int8 Representative-Core Spike

Date: 2026-06-20

## Purpose

Test the compiler-pipeline candidate on the fastest meaningful target:
`tiny-stories-1m-representative-core` with PT2E/static int8 quantization, before
attempting DDR3 memory externalization.

## Commands And Results

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-cf-stats --no-link --print-out-paths -L`
  - status: pass
  - output: `/nix/store/vdzq00gfhfybwn0h1vf6jsswdj3na5qn-tiny-stories-1m-representative-core-pt2e-static-cf.stats`
  - note: Torch-MLIR emitted warnings that some quantized matmul operands remain
    in QDQ form.

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-yosys-stat --no-link --print-out-paths -L`
  - status: fail before SV/Yosys
  - blocker: `lower-cf-to-handshake=lsq` is requested by the quantized pipeline,
    but the current CIRCT pass reports `no such option lsq`.

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-nolsq-cf-stats --no-link --print-out-paths -L`
  - status: pass
  - output: `/nix/store/yx0vdx7crsih1ihysv9x4plpy0570yq3-tiny-stories-1m-representative-core-pt2e-static-nolsq-cf.stats`
  - note: this is an experimental target using the same PT2E/static int8
    representative-core adapter but the default non-LSQ handshake lowering.

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-nolsq-yosys-stat --no-link --print-out-paths -L`
  - status: fail at SV export
  - durable preceding stage:
    `/nix/store/6phcl3fx04b5p16n5xx6g7p9h2vpfnzl-tiny-stories-1m-representative-core-pt2e-static-nolsq-hw-clean.mlir`
  - `hw-clean` size: `348,228,649` bytes
  - failure signature:
    `/nix/store/.../pipeline/common.sh: line 28: 49 Killed "$@" > "$output"`
  - exit code: `137`
  - interpretation: the non-LSQ route reaches HW-clean, then CIRCT split
    SystemVerilog export is killed, likely by memory pressure.

## Implementation Notes

- Added `tiny-stories-1m-representative-core-pt2e-static-nolsq` as an
  explicitly experimental target. It does not replace the official
  `tiny-stories-1m-representative-core-pt2e-static` LSQ route.
- Fixed `scripts/pipeline/hw_clean_to_sv.sh` shell syntax so non-quantized and
  experimental SV-export attempts can reach the real CIRCT export stage.

## Current Verdict

Int8 quantization on the minimum representative core is not enough to produce a
fit/no-fit resource answer today. The frontend and lowering can reach HW-clean
through the experimental non-LSQ route, but SV generation is killed before Yosys
can emit resource statistics.

The next compiler-pipeline decision is whether to spend effort on:

1. restoring the LSQ pass option in the CIRCT patch stack;
2. reducing or chunking SV export for the `348 MB` HW-clean MLIR;
3. adding memory externalization before SV export so CIRCT has less hardware to
materialize.

## SV Export Follow-Up

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-nolsq-sv-mlir --no-link --print-out-paths -L`
  - status: pass
  - output: `/nix/store/fszqgzc1zrzmazfm2gf2ip8a73paz9k9-tiny-stories-1m-representative-core-pt2e-static-nolsq-sv-mlir`
  - `model.sv.mlir` size: `331 MB`
  - interpretation: `-lower-seq-to-sv` / `-lower-hw-to-sv` can complete; the
    previous OOM was not caused by the lowering-to-SV-dialect step.

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-nolsq-sv --out-link .gcroots/task6-int8-repcore-nolsq-sv -L`
  - status: pass after switching the default SV emitter from
    `--export-split-verilog` to stdout-redirected `--export-verilog`, with
    CIRCT source-location debug info stripped before export.
  - output: `/nix/store/jzq5z9v013dv40d1n7dy257dxysvb7p4-tiny-stories-1m-representative-core-pt2e-static-nolsq-sv`
  - emitted files:
    - `sv/main.sv`: `1,610,623,489` bytes, `19,980,042` lines
    - `sv/zz_circt_fp_primitives.sv`: copied float primitive extern
      implementations
    - `sources.f`: `2` entries

- Direct diagnostic:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' circt-opt model.sv.mlir --export-verilog > /tmp/tiny-stories-representative-core-nolsq.sv`
  - status: pass
  - measurement: `ELAPSED=81.51`, `RSS_KB=7062376`

- Direct diagnostic with source-location stripping:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' circt-opt model.sv.mlir --strip-debuginfo-with-pred=drop-suffix=.mlir --export-verilog > /tmp/tiny-stories-repcore-nolsq-stripped.sv`
  - status: pass
  - measurement: `ELAPSED=77.08`, `RSS_KB=6081144`
  - emitted size: `1.6 GB`

- `nix build .#tiny-stories-1m-representative-core-pt2e-static-nolsq-yosys-stat --out-link .gcroots/task6-int8-repcore-nolsq-yosys-stat -L`
  - status: pass as an explicit bottleneck report
  - output: `/nix/store/r3nwkkl29zdy0k5rnlf4q152z9rl8855-tiny-stories-1m-representative-core-pt2e-static-nolsq-yosys.stat`
  - report status: `oom-bottleneck`
  - failure signature: Yosys was killed with exit code `137` while processing
    the stripped SV bundle.
  - bundle evidence: `2` files, `1,610,640,159` bytes total,
    `main.sv` `19,980,042` lines / `1,610,623,489` bytes.

Updated interpretation: the immediate SV blocker was specifically
`--export-split-verilog`, not SV-dialect lowering. Single-file SV export now
works for the int8 representative-core non-LSQ route, but Yosys still OOMs on
the stripped `1.6 GB` monolithic RTL bundle. This falsifies the idea that debug
source-location comments were the primary Yosys bottleneck. The compiler-pipeline
candidate needs structural reduction before SV/Yosys, most likely DDR3 memory
externalization or further representative-core reduction, before it can produce
a real fit/no-fit synthesis estimate on this host.
