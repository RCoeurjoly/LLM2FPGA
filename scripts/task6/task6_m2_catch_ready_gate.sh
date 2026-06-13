#!/usr/bin/env bash
set -euo pipefail

ROOT="${TASK6_REPO_ROOT:-/home/roland/LLM2FPGA}"
BDF="${1:-0000:42:00.0}"
if [[ "$#" -gt 0 ]]; then
  shift
fi

ATTEMPTS=12
SLEEP_SECONDS=5
EXTRA_ARGS=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --attempts)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --attempts requires a value" >&2
        exit 2
      fi
      ATTEMPTS="$2"
      shift 2
      ;;
    --sleep)
      if [[ "$#" -lt 2 ]]; then
        echo "error: --sleep requires a value" >&2
        exit 2
      fi
      SLEEP_SECONDS="$2"
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

case "$ATTEMPTS" in
  ""|*[!0-9]*)
    echo "error: --attempts must be a positive integer" >&2
    exit 2
    ;;
esac
if [[ "$ATTEMPTS" -lt 1 ]]; then
  echo "error: --attempts must be at least 1" >&2
  exit 2
fi

DELEGATED_COMMAND="${TASK6_M2_DELEGATED_COMMAND:-}"
if [[ -z "$DELEGATED_COMMAND" ]]; then
  echo "error: TASK6_M2_DELEGATED_COMMAND is required" >&2
  exit 2
fi

ready_log=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  lifecycle_log="$(mktemp)"
  set +e
  "$ROOT/scripts/task6/task6_pcie_user_gate.sh" lifecycle "$BDF" \
    --label task6-m2-catch-ready-preflight >"$lifecycle_log" 2>&1
  lifecycle_rc="$?"
  set -e
  echo "=== lifecycle attempt $attempt/$ATTEMPTS ==="
  cat "$lifecycle_log"
  if [[ "$lifecycle_rc" -eq 0 ]] && grep -q '^classification: pcie_ready$' "$lifecycle_log"; then
    ready_log="$lifecycle_log"
    break
  fi
  if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
    sleep "$SLEEP_SECONDS"
  fi
done

if [[ -z "$ready_log" ]]; then
  cat >&2 <<'EOM'
error: no pcie_ready lifecycle observed in the bounded catch window.
No BAR gate was launched. Re-enumerate/cold-boot again with the FPGA already configured.
EOM
  exit 10
fi

set +e
"$ROOT/scripts/task6/task6_pcie_user_gate.sh" bar "$BDF" --mode header
bar_header_rc="$?"
set -e
if [[ "$bar_header_rc" -ne 0 ]]; then
  echo "error: BAR header smoke did not pass; M2 gate was not launched" >&2
  exit 11
fi

exec "$DELEGATED_COMMAND" "$BDF" "${EXTRA_ARGS[@]}"
