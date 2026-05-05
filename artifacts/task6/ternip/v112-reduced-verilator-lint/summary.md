# v112 Ternip reduced Verilator lint/report gate

## Hypothesis

A Verilator lint/report target can bypass the broken custom-Yosys/yosys-slang
path and reach the first real reduced Ternip RTL blocker.

## Source commit

- Source/config commit: `54a32c4`
- Flake target: `.#task6-ternip-reduced-verilator-lint-report`

## Command

```bash
nix build .#task6-ternip-reduced-verilator-lint-report -L
```

## Result

- Status: `FAIL_BASEJUMP_INCLUDE_PATH`
- Result path: `/nix/store/xc1yiwf8d7ah42bh13rbx1zqjfcpx60q-task6-ternip-reduced-verilator-lint-report`
- Verilator exit code: `1`
- Ternip board run: `false`

First concrete blocker:

```text
Cannot find include file: bsg_defines.sv
Define or directive not defined: `BSG_INV_PARAM
Define or directive not defined: `BSG_SAFE_CLOG2
```

## Interpretation

This is still not evidence against Ternip logic. The new gate reached the
BaseJump dependency, but the report target did not pass BaseJump's include path
to Verilator.

## Decision

Next source fix should add the BaseJump include directory containing
`bsg_defines.sv` to the Verilator lint/report target.

Do not change Ternip RTL, reduced parameters, or board-wrapper logic for this
blocker.
