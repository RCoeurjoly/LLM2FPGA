#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <lane> [slug] [timestamp]" >&2
  echo "Example: $0 ddr3 tinystories-inference \"$(date +%Y%m%dT%H%M%S)" >&2
  exit 1
fi

lane="${1}"
slug="${2:-run}"
raw_ts="${3:-$(date +%Y%m%dT%H%M%S)}"
ts="${raw_ts//:/-}"

run_root="artifacts/task6/runs/${ts}-task6-${lane}-${slug}"
mkdir -p "${run_root}"

cat <<JSON > "${run_root}/summary.json"
{
  "lane": "${lane}",
  "slug": "${slug}",
  "timestamp": "$(date -Iseconds)",
  "status": "IN_PROGRESS",
  "commands": {
    "boot_only": null,
    "diagnostic_fullbeat": null,
    "memory_contract": null,
    "tinystories_inference": null,
    "resource_check": null
  },
  "gates": {
    "boot_gate": null,
    "fullbeat_gate": null,
    "boundary_rows_gate": null,
    "full_readback_gate": null,
    "top1_gate": null,
    "resource_gate": null
  },
  "artifacts": []
}
JSON

cat <<EOF2 > "${run_root}/commands.txt"
# Canonical command log for this run (append actual commands in order).
# Replace this file with the exact commands used once they are executed.

EOF2

echo "Initialized run root: ${run_root}"
echo "summary template: ${run_root}/summary.json"
echo "commands template: ${run_root}/commands.txt"
