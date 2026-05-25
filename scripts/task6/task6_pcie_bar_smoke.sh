#!/usr/bin/env bash
set -euo pipefail

BDF="${1:-}"

if [[ -z "$BDF" ]]; then
  echo "usage: $0 <pci-bdf>" >&2
  echo "example: $0 26:00.0" >&2
  exit 2
fi

shift
exec "$(dirname "$0")/task6_pcie_bar_smoke.py" "$BDF" "$@"
