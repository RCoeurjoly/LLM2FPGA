#!/usr/bin/env bash
set -euo pipefail

# Gate Task 6 DDR3 experiments through the seed15 two-lane BIST_MODE=2 target.
# This is intentionally a DDR3 admission test, not a rowstream/user-port test.
# Use it before programming a more advanced seed15 rowstream or inference bitstream.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LABEL="${1:-seed15-bist2-gate}"
BITSTREAM="${TASK6_SEED15_BIST2_BITSTREAM:-}"

if [[ -z "$BITSTREAM" ]]; then
  BITSTREAM="$(NIXPKGS_ALLOW_UNFREE=1 nix build \
    .#task6-ypcb-uberddr3-bist-2lane-mode2-robust-seed15-bitstream \
    --override-input uberDdr3 path:/home/roland/UberDDR3 \
    --impure \
    --print-out-paths \
    -L | tail -n 1)"
fi

python3 scripts/task6/task6_ddr3_experiment_runner.py \
  --label "$LABEL" \
  --variant robust-bist2-seed15 \
  --bitstream "$BITSTREAM" \
  --notes "Seed15 BIST_MODE=2 admission gate before Task 6 rowstream/user-port/inference experiment" \
  --bits 1024 \
  --bist-only \
  --post-program-delay 15
