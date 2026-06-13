#!/usr/bin/env bash
set -euo pipefail

ROOT="${TASK6_REPO_ROOT:-/home/roland/LLM2FPGA}"
BDF="${1:-0000:42:00.0}"
if [[ "$#" -gt 0 ]]; then
  shift
fi

BRIDGE_BDF="0000:41:00.0"
LABEL="task6-m2-make-stable-root-prepare"
CATCH_ATTEMPTS=3
CATCH_SLEEP=2
ROOT_MAX_ACTIONS=2
COMMAND_TIMEOUT=120
EXTRA_ARGS=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --bridge-bdf)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --bridge-bdf requires a value" >&2
        exit 2
      fi
      BRIDGE_BDF="$2"
      shift 2
      ;;
    --label)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --label requires a value" >&2
        exit 2
      fi
      LABEL="$2"
      shift 2
      ;;
    --catch-attempts)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --catch-attempts requires a value" >&2
        exit 2
      fi
      CATCH_ATTEMPTS="$2"
      shift 2
      ;;
    --catch-sleep)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --catch-sleep requires a value" >&2
        exit 2
      fi
      CATCH_SLEEP="$2"
      shift 2
      ;;
    --root-max-actions)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --root-max-actions requires a value" >&2
        exit 2
      fi
      ROOT_MAX_ACTIONS="$2"
      shift 2
      ;;
    --command-timeout)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --command-timeout requires a value" >&2
        exit 2
      fi
      COMMAND_TIMEOUT="$2"
      shift 2
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "${TASK6_PCIE_HARDWARE_ENABLE:-0}" != "1" ]]; then
  cat >&2 <<'EOM'
error: hardware access is disabled.
Re-run only after explicit hardware approval with:
  TASK6_PCIE_HARDWARE_ENABLE=1 <this command>
EOM
  exit 2
fi

if [[ -z "${TASK6_M2_DELEGATED_COMMAND:-}" ]]; then
  echo "error: TASK6_M2_DELEGATED_COMMAND is required" >&2
  exit 2
fi

set +e
"$ROOT/scripts/task6/task6_m2_catch_ready_gate.sh" "$BDF" \
  --attempts "$CATCH_ATTEMPTS" \
  --sleep "$CATCH_SLEEP" \
  -- "${EXTRA_ARGS[@]}"
catch_rc="$?"
set -e
if [[ "$catch_rc" -eq 0 ]]; then
  exit 0
fi

if [[ "${TASK6_PCIE_HOST_FREEZE_RISK_ACK:-0}" != "1" ]]; then
  cat >&2 <<'EOM'
error: PCIe is not pcie_ready, and host reset/remove/rescan recovery is not acknowledged.

The remaining automated recovery path uses the freeze-prone host PCIe
remove/rescan/reset class. Set TASK6_PCIE_HOST_FREEZE_RISK_ACK=1 only after
explicitly accepting that host-freeze risk for this run.
EOM
  exit 3
fi

"$ROOT/scripts/task6/task6_pcie_user_gate.sh" recover-auto "$BDF" \
  --bridge-bdf "$BRIDGE_BDF" \
  --label "$LABEL" \
  --allow-root-recovery \
  --max-actions "$ROOT_MAX_ACTIONS" \
  --command-timeout "$COMMAND_TIMEOUT"

exec "$ROOT/scripts/task6/task6_m2_catch_ready_gate.sh" "$BDF" \
  --attempts "$CATCH_ATTEMPTS" \
  --sleep "$CATCH_SLEEP" \
  -- "${EXTRA_ARGS[@]}"
