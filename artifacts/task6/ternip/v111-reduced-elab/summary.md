# v111 Ternip reduced elaboration gate

## Hypothesis

The pinned Ternip source can elaborate as a reduced `D=64` core with open-source
tools before any YPCB wrapper or DDR integration is attempted.

## Source commit

- Source/config commit: `54079f8`
- Prior source gate: `2e9780c`
- Flake target: `.#task6-ternip-reduced-elab-json`

## Command

```bash
nix build .#task6-ternip-reduced-elab-json -L
```

## Result

- Status: `BLOCKED_TOOLCHAIN`
- Ternip RTL reached: `false`
- Board run: `false`
- Synthesis run: `false`

The build failed while constructing the existing `yosys-slang` dependency path:

```text
yosys> /nix/store/shkw4qm9qcw5sc5n1k5jznc83ny02r39-default-builder.sh: line 1: genericBuild: command not found
error: Cannot build '/nix/store/gqmmjllpz09zx99p20w937dff7b5bals-yosys-0.64.drv'.
```

## Interpretation

This is not yet evidence about Ternip RTL compatibility. The reduced
elaboration target is blocked before parsing Ternip because the repo's
custom-Yosys/yosys-slang build path is currently broken.

## Decision

Do not move to a YPCB Ternip wrapper or bitstream.

Next source fix should make the first Ternip RTL gate independent from this
broken custom-Yosys path, either by:

```text
1. adding a Verilator reduced lint/elaboration gate first, or
2. replacing/fixing the yosys-slang dependency with a working packaged Yosys pair.
```
