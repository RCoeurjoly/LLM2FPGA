#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: $0 [--plan-id PLAN_ID] [--hypothesis HYPOTHESIS_ID] [--notes NOTES] <lane> [slug] [timestamp]

Required:
  lane             Experiment lane name (for example: ddr3, task6flow, tinystories)

Optional:
  slug             Short label for run folder (default: run)
  timestamp        ISO-ish timestamp to use for folder naming (default: now)

Run metadata (optional):
  --plan-id        Plan identifier (default: plan-unknown)
  --hypothesis     Hypothesis identifier (default: hypothesis-unknown)
  --notes          Short note string to persist in summary.json

Examples:
  $0 --plan-id plan-2026-05-21-ddr3-tinystories-anchor --hypothesis anchor-baseline ddr3 anchor-repro
  $0 ddr3 anchor-repro "$(date +%Y%m%dT%H%M%S)"
USAGE
}

plan_id="plan-unknown"
hypothesis_id="hypothesis-unknown"
notes=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-id)
      plan_id="${2:?Missing --plan-id value}"
      shift 2
      ;;
    --hypothesis)
      hypothesis_id="${2:?Missing --hypothesis value}"
      shift 2
      ;;
    --notes)
      notes="${2:?Missing --notes value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage >&2
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
  "plan_id": "${plan_id}",
  "hypothesis_id": "${hypothesis_id}",
  "lane": "${lane}",
  "slug": "${slug}",
  "timestamp": "$(date -Iseconds)",
  "notes": "${notes}",
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

# lane: ${lane}
# plan_id: ${plan_id}
# hypothesis_id: ${hypothesis_id}

EOF2

echo "Initialized run root: ${run_root}"
echo "summary template: ${run_root}/summary.json"
echo "commands template: ${run_root}/commands.txt"
