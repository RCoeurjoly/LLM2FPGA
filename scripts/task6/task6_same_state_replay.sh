#!/usr/bin/env bash
set -euo pipefail
set -o pipefail

ROOT="${TASK6_REPO_ROOT:-/home/roland/LLM2FPGA}"
BDF="${TASK6_PCIE_ALLOWED_BDF:-0000:42:00.0}"
REFERENCE_JSON="${TASK6_M2_REPLAY_REFERENCE_JSON:-${ROOT}/artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json}"
SAMPLE_COUNT=1
PACKET_LOAD_MODE="pair"
PACKET_ECHO_MODE="off"
VERIFY_SAMPLES=8
RUN_ROOT="${ROOT}/artifacts/task6/runs"
LABEL_PREFIX="task6-same-state-replay"

usage() {
  cat >&2 <<'EOF'
Usage:
  TASK6_PCIE_HARDWARE_ENABLE=1 scripts/task6/task6_same_state_replay.sh [options] [BDF]

Options:
  --reference-json PATH    Override frozen reference JSON path.
  --sample-count N         Number of samples (default: 1).
  --packet-load-mode M     rowstream packet mode: pair|single (default: pair).
  --packet-echo-mode M     packet echo policy: off|require|auto (default: off).
  --verify-samples N       How many top1 rows to verify readback (default: 8).
  --run-root PATH          Artifact root for run directories.

Examples:
  TASK6_PCIE_HARDWARE_ENABLE=1 \
    scripts/task6/task6_same_state_replay.sh 0000:42:00.0
EOF
  exit 2
}

while [[ "$#" -gt 0 ]]; do
  case "${1:-}" in
    --reference-json)
      [[ "${2-}" ]] || usage
      REFERENCE_JSON="$2"
      shift 2
      ;;
    --sample-count)
      [[ "${2-}" ]] || usage
      SAMPLE_COUNT="$2"
      shift 2
      ;;
    --packet-load-mode)
      [[ "${2-}" ]] || usage
      PACKET_LOAD_MODE="$2"
      shift 2
      ;;
    --packet-echo-mode)
      [[ "${2-}" ]] || usage
      PACKET_ECHO_MODE="$2"
      shift 2
      ;;
    --verify-samples)
      [[ "${2-}" ]] || usage
      VERIFY_SAMPLES="$2"
      shift 2
      ;;
    --run-root)
      [[ "${2-}" ]] || usage
      RUN_ROOT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ "$1" != "" ]]; then
        BDF="$1"
        shift
      fi
      if [[ "$#" -gt 0 ]]; then
        usage
      fi
      ;;
  esac
done

if [[ "${TASK6_PCIE_HARDWARE_ENABLE:-0}" != "1" ]]; then
  cat >&2 <<'EOF'
error: hardware access disabled.
Set TASK6_PCIE_HARDWARE_ENABLE=1 before running.
EOF
  exit 2
fi

if [[ ! -f "$REFERENCE_JSON" ]]; then
  echo "error: reference json not found: $REFERENCE_JSON" >&2
  exit 2
fi

RUN_DIR="${RUN_ROOT}/$(date -u +%Y-%m-%dT%H-%M-%S%z)-${LABEL_PREFIX}"
mkdir -p "$RUN_DIR"

LIFECYCLE_OUT="$RUN_DIR/lifecycle.out"
TOP1_OUT="$RUN_DIR/rowstream-top1.out"
TOP1_JSON="$RUN_DIR/rowstream-top1-board-summary.json"
SUMMARY_JSON="$RUN_DIR/same-state-replay-summary.json"

echo "run_dir: $RUN_DIR"
echo "bdf: $BDF"
echo "reference_json: $REFERENCE_JSON"
echo
echo "== lifecycle =="

set +e
TASK6_PCIE_HARDWARE_ENABLE=1 \
  "$ROOT/scripts/task6/task6_pcie_user_gate.sh" lifecycle "$BDF" --label "$LABEL_PREFIX-lifecycle" \
  | tee "$LIFECYCLE_OUT"
lifecycle_rc="${PIPESTATUS[0]}"
set -e

if [[ ! -s "$LIFECYCLE_OUT" ]]; then
  echo "error: empty lifecycle output" >&2
  exit 1
fi

classification="$(awk '/^classification:/{print $2}' "$LIFECYCLE_OUT" | tail -n 1)"
lifecycle_run_dir="$(awk '/^run_dir:/{print $2}' "$LIFECYCLE_OUT" | tail -n 1)"

if [[ -z "${classification}" ]]; then
  echo "error: lifecycle classification missing" >&2
  exit 2
fi

echo "classification: $classification"
if [[ "${classification}" != "pcie_ready" ]]; then
  python3 - "$LIFECYCLE_OUT" "$SUMMARY_JSON" \
    "$classification" "$BDF" "$SAMPLE_COUNT" "$PACKET_LOAD_MODE" "$PACKET_ECHO_MODE" "$VERIFY_SAMPLES" \
    "$REFERENCE_JSON" "$lifecycle_run_dir" <<'PY'
import json
import re
from pathlib import Path
import sys

lifecycle_path, summary_path = sys.argv[1:3]
classification = sys.argv[3]
bdf = sys.argv[4]
sample_count = int(sys.argv[5])
packet_load_mode = sys.argv[6]
packet_echo_mode = sys.argv[7]
verify_samples = int(sys.argv[8])
reference_json = sys.argv[9]
lifecycle_run_dir = sys.argv[10]
lifecycle_text = Path(lifecycle_path).read_text(encoding="utf-8")
match = re.search(r"^classification:\s*(\S+)", lifecycle_text, re.MULTILINE)
payload = {
    "status": "FAIL",
    "inputs": {
        "reference_json": reference_json,
        "sample_count": sample_count,
        "packet_load_mode": packet_load_mode,
        "packet_echo_mode": packet_echo_mode,
        "verify_samples": verify_samples,
        "bdf": bdf,
    },
    "lifecycle": {
        "path": lifecycle_path,
        "classification": match.group(1) if match else classification,
        "classification_line": match.group(0) if match else f"classification: {classification}",
        "run_dir": lifecycle_run_dir,
    },
    "top1": None,
}
Path(summary_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({"status": "FAIL", "path": summary_path}, indent=2))
PY
  echo "abort: replay requires pcie_ready; run recommendations in lifecycle output and resume once stable."
  echo "lifecycle_run_dir: ${lifecycle_run_dir:-N/A}"
  echo "summary: $SUMMARY_JSON"
  exit "$lifecycle_rc"
fi

if [[ "${lifecycle_rc}" -ne 0 ]]; then
  echo "warning: lifecycle returned non-zero despite pcie_ready; continuing with top1 gate for explicit reproducibility"
fi

echo
echo "== rowstream-top1 replay =="

set +e
TASK6_PCIE_HARDWARE_ENABLE=1 \
  "$ROOT/scripts/task6/task6_pcie_user_gate.sh" \
    rowstream-top1 "$BDF" \
    --sample-count "$SAMPLE_COUNT" \
    --reference-json "$REFERENCE_JSON" \
    --packet-load-mode "$PACKET_LOAD_MODE" \
    --packet-echo-mode "$PACKET_ECHO_MODE" \
    --verify-samples "$VERIFY_SAMPLES" \
    --json-out "$TOP1_JSON" \
  | tee "$TOP1_OUT"
top1_rc="${PIPESTATUS[0]}"
set -e

if [[ ! -f "$TOP1_JSON" ]]; then
  echo "error: rowstream-top1 did not emit JSON summary at $TOP1_JSON"
  exit "$top1_rc"
fi

TOP1_STATUS="$(python3 - "$TOP1_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(data.get("status", "UNKNOWN"))
PY
)"
TOP1_MISMATCH="$(python3 - "$TOP1_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(data.get("validation", {}).get("mismatch_count", "NA"))
PY
)"
TOP1_RESERVED="$(python3 - "$TOP1_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(data.get("validation", {}).get("reserved_nonzero_count", "NA"))
PY
)"

echo "top1_status: $TOP1_STATUS"
echo "top1_mismatch_count: $TOP1_MISMATCH"
echo "top1_reserved_nonzero_count: $TOP1_RESERVED"
echo "top1_return_code: $top1_rc"

python3 - "$LIFECYCLE_OUT" "$TOP1_JSON" "$SUMMARY_JSON" \
  "$classification" "$BDF" "$SAMPLE_COUNT" "$PACKET_LOAD_MODE" "$PACKET_ECHO_MODE" "$VERIFY_SAMPLES" \
  "$TOP1_STATUS" "$top1_rc" "$REFERENCE_JSON" "$lifecycle_run_dir" <<'PY'
import json
import re
import sys
from pathlib import Path

lifecycle_path, top1_path, summary_path = sys.argv[1:4]
lifecycle_classification = sys.argv[4]
bdf = sys.argv[5]
sample_count = int(sys.argv[6])
packet_load_mode = sys.argv[7]
packet_echo_mode = sys.argv[8]
verify_samples = int(sys.argv[9])
top1_status = sys.argv[10]
top1_return_code = int(sys.argv[11])
reference_json = sys.argv[12]
lifecycle_run_dir = sys.argv[13]
lifecycle_text = Path(lifecycle_path).read_text(encoding="utf-8")
top1_json = json.loads(Path(top1_path).read_text(encoding="utf-8"))
result = {
    "status": "FAIL",
    "inputs": {
        "reference_json": reference_json,
        "sample_count": sample_count,
        "packet_load_mode": packet_load_mode,
        "packet_echo_mode": packet_echo_mode,
        "verify_samples": verify_samples,
        "bdf": bdf,
    },
    "lifecycle": {
        "path": str(lifecycle_path),
        "classification": None,
        "classification_line": None,
        "run_dir": lifecycle_run_dir,
    },
    "top1": {
        "path": str(top1_path),
        "json": top1_json,
        "status": top1_status,
        "status_line": None,
        "return_code": top1_return_code,
        "mismatch_count": top1_json.get("validation", {}).get("mismatch_count"),
        "reserved_nonzero_count": top1_json.get("validation", {}).get("reserved_nonzero_count"),
    },
}
match = re.search(r"^classification:\s*(\S+)", lifecycle_text, re.MULTILINE)
if match:
    result["lifecycle"]["classification"] = match.group(1)
    result["lifecycle"]["classification_line"] = match.group(0)

result["top1"]["status_line"] = f"status: {result['top1']['status']}"
if (
    result["lifecycle"]["classification"] == "pcie_ready"
    and result["top1"]["status"] == "PASS"
):
    result["status"] = "PASS"
Path(summary_path).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(result["status"])
PY

if [[ "${TOP1_STATUS}" != "PASS" ]]; then
  echo "replay: FAIL"
  exit 1
fi

if (( top1_rc != 0 )); then
  echo "replay: FAIL (top1 rc=$top1_rc)"
  exit "$top1_rc"
fi

echo "replay: PASS"
exit 0
