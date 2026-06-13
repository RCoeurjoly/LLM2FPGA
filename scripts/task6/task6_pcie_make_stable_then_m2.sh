#!/usr/bin/env bash
set -euo pipefail

ROOT="${TASK6_REPO_ROOT:-/home/roland/LLM2FPGA}"
BDF="${1:-0000:42:00.0}"
if [[ "$#" -gt 0 ]]; then
  shift
fi

BRIDGE_BDF="0000:41:00.0"
LABEL="task6-m2-make-stable"
CATCH_ATTEMPTS=3
CATCH_SLEEP=2
COMMAND_TIMEOUT=120
SAFE_MAX_ACTIONS=3
SAFE_RECOVERY_ARGS=()
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
    --command-timeout)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --command-timeout requires a value" >&2
        exit 2
      fi
      COMMAND_TIMEOUT="$2"
      shift 2
      ;;
    --safe-max-actions)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --safe-max-actions requires a value" >&2
        exit 2
      fi
      SAFE_MAX_ACTIONS="$2"
      shift 2
      ;;
    --allow-power-cycle)
      SAFE_RECOVERY_ARGS+=("$1")
      shift
      ;;
    --max-power-cycles|--power-provider|--power-url|--secret-file|--power-off-wait|--power-on-wait|--power-http-timeout|--tapo-p115-command)
      if [[ "$#" -lt 2 ]]; then
        echo "error: $1 requires a value" >&2
        exit 2
      fi
      SAFE_RECOVERY_ARGS+=("$1" "$2")
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
if [[ "$catch_rc" -ne 10 && "$catch_rc" -ne 11 ]]; then
  echo "error: delegated M2 gate failed after PCIe/BAR preflight; not running PCIe recovery" >&2
  exit "$catch_rc"
fi

set +e
"$ROOT/scripts/task6/task6_pcie_user_gate.sh" recover-auto "$BDF" \
  --bridge-bdf "$BRIDGE_BDF" \
  --label "$LABEL-safe" \
  --max-actions "$SAFE_MAX_ACTIONS" \
  --command-timeout "$COMMAND_TIMEOUT" \
  "${SAFE_RECOVERY_ARGS[@]}"
set -e

set +e
"$ROOT/scripts/task6/task6_m2_catch_ready_gate.sh" "$BDF" \
  --attempts "$CATCH_ATTEMPTS" \
  --sleep "$CATCH_SLEEP" \
  -- "${EXTRA_ARGS[@]}"
post_safe_catch_rc="$?"
set -e
if [[ "$post_safe_catch_rc" -eq 0 ]]; then
  exit 0
fi
if [[ "$post_safe_catch_rc" -ne 10 && "$post_safe_catch_rc" -ne 11 ]]; then
  echo "error: delegated M2 gate failed after safe PCIe/BAR preflight; not running PCIe recovery" >&2
  exit "$post_safe_catch_rc"
fi

cat >&2 <<'EOM'
warning: PCIe is not pcie_ready after the safe recovery ladder.
Stopping before host-side PCIe reset/remove/rescan recovery. The supported
automatic protocol is lifecycle -> safe repair/power cycle -> lifecycle -> BAR
gate only after pcie_ready.
EOM
exit "$post_safe_catch_rc"
