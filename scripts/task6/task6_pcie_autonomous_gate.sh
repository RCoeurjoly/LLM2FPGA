#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-}"
BDF="${2:-0000:42:00.0}"
RUN_DIR=""
REPEAT=1
GATE="${TASK6_PCIE_GATE:-/usr/local/sbin/task6-pcie-gate}"

usage() {
  cat >&2 <<'EOF'
usage: scripts/task6/task6_pcie_autonomous_gate.sh <bar|command|command-header|command-echo|command-doorbell> [BDF] [--run-dir DIR] [--repeat N]
EOF
  exit 2
}

[[ -n "$MODE" ]] || usage
case "$MODE" in
  bar|command|command-header|command-echo|command-doorbell) ;;
  *) usage ;;
esac
shift || true
if [[ "${1:-}" != --* && -n "${1:-}" ]]; then
  BDF="$1"
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="${2:-}"
      [[ -n "$RUN_DIR" ]] || usage
      shift 2
      ;;
    --repeat)
      REPEAT="${2:-}"
      [[ "$REPEAT" =~ ^[0-9]+$ ]] || usage
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$RUN_DIR" ]]; then
  stamp="$(date -Iseconds | tr ':' '-')"
  RUN_DIR="$ROOT/artifacts/task6/pcie-bringup/${stamp}-${MODE}"
fi
mkdir -p "$RUN_DIR"

overall=0
for iter in $(seq 1 "$REPEAT"); do
  iter_dir="$RUN_DIR/iter-$iter"
  mkdir -p "$iter_dir"
  echo "Task 6 autonomous PCIe gate: mode=$MODE bdf=$BDF iter=$iter"
  set +e
  sudo -n "$GATE" "$MODE" "$BDF" >"$iter_dir/gate.log" 2>&1
  rc=$?
  set -e
  cat "$iter_dir/gate.log"
  printf "%s\n" "$rc" >"$iter_dir/exit-code.txt"

  "$ROOT/scripts/task6/read_pcie_jtag_status.py" --json-only >"$iter_dir/pcie-jtag-status.json" 2>"$iter_dir/pcie-jtag-status.err" || true

  python3 - "$iter_dir" "$MODE" "$BDF" "$rc" <<'PY'
import json
import sys
from pathlib import Path

iter_dir = Path(sys.argv[1])
summary = {
    "mode": sys.argv[2],
    "bdf": sys.argv[3],
    "returncode": int(sys.argv[4]),
}
summary["pass"] = summary["returncode"] == 0
summary["gate_log"] = str(iter_dir / "gate.log")
summary["jtag_status"] = str(iter_dir / "pcie-jtag-status.json")
(iter_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
PY
  if [[ "$rc" -ne 0 ]]; then
    overall="$rc"
    break
  fi
done

python3 - "$RUN_DIR" "$MODE" "$BDF" "$overall" "$REPEAT" <<'PY'
import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
iters = [json.loads(path.read_text()) for path in sorted(run_dir.glob("iter-*/summary.json"))]
summary = {
    "mode": sys.argv[2],
    "bdf": sys.argv[3],
    "returncode": int(sys.argv[4]),
    "requested_iterations": int(sys.argv[5]),
    "iterations": iters,
}
summary["pass"] = summary["returncode"] == 0 and len(iters) == summary["requested_iterations"] and all(item.get("pass") for item in iters)
(run_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
PY

echo "artifact: $RUN_DIR"
exit "$overall"
