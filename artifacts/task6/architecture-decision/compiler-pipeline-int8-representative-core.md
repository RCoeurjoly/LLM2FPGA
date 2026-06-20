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
