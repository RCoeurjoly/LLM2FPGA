#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/pipeline/synth_split_modules.sh <sv-dir> <out-dir>

Performs per-module synthesis on split SV files to avoid top-level OOM.
- Skips files that contain real/shortreal or real-valued math funcs.
- Runs yosys-slang per module with a timeout.
- Writes per-module JSON netlists and logs.

Env:
  YOSYS_BIN        default: yosys
  YOSYS_SLANG_SO   default: $HOME/yosys-slang/build/slang.so
  TIMEOUT_SEC      default: 120
  MAX_FILES        default: 0 (0 = all files)
  FP_PRIMS_SV      optional SV file containing circt_fp_* module definitions
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 2 ]]; then
  usage
  exit 0
fi

SV_DIR="$1"
OUT_DIR="$2"
if [[ ! -d "$SV_DIR" ]]; then
  echo "[FAIL] sv dir not found: $SV_DIR" >&2
  exit 2
fi

YOSYS_BIN="${YOSYS_BIN:-yosys}"
SLANG_SO="${YOSYS_SLANG_SO:-$HOME/yosys-slang/build/slang.so}"
TIMEOUT_SEC="${TIMEOUT_SEC:-120}"
MAX_FILES="${MAX_FILES:-0}"
FP_PRIMS_SV="${FP_PRIMS_SV:-}"

if ! command -v "$YOSYS_BIN" >/dev/null 2>&1; then
  echo "[FAIL] yosys not found: $YOSYS_BIN" >&2
  exit 2
fi
if [[ ! -f "$SLANG_SO" ]]; then
  echo "[FAIL] slang plugin not found: $SLANG_SO" >&2
  exit 2
fi

mkdir -p "$OUT_DIR/json" "$OUT_DIR/logs"
pass_list="$OUT_DIR/passed_modules.txt"
fail_list="$OUT_DIR/failed_modules.txt"
skip_list="$OUT_DIR/skipped_modules.txt"
: > "$pass_list"
: > "$fail_list"
: > "$skip_list"

mapfile -t files < <(find "$SV_DIR" -type f -name '*.sv' | sort)
if [[ "$MAX_FILES" -gt 0 && "${#files[@]}" -gt "$MAX_FILES" ]]; then
  files=("${files[@]:0:$MAX_FILES}")
fi

echo "[info] files to process: ${#files[@]}"

actionable=0
skipped_float=0
pass=0
fail=0

# shellcheck disable=SC2016
auto_skip_pattern='\b(shortreal|real)\b|\$(bitstoshortreal|shortrealtobits|bitstoreal|realtobits|exp|sqrt|pow|tanh)\b'

for f in "${files[@]}"; do
  mod="$(basename "$f" .sv)"
  log="$OUT_DIR/logs/${mod}.log"
  json="$OUT_DIR/json/${mod}.json"

  if rg -q -e "$auto_skip_pattern" "$f"; then
    echo "[skip][float] $mod"
    skipped_float=$((skipped_float + 1))
    echo "$mod" >> "$skip_list"
    continue
  fi

  actionable=$((actionable + 1))
  cmd="read_slang --ignore-assertions --ignore-unknown-modules"
  if [[ -n "$FP_PRIMS_SV" && -f "$FP_PRIMS_SV" ]]; then
    cmd+=" $FP_PRIMS_SV"
  fi
  cmd+=" $f; hierarchy -check -top $mod; proc; opt; fsm; opt; memory; opt; techmap; opt; abc; opt; stat; write_json $json"

  set +e
  /usr/bin/timeout "$TIMEOUT_SEC" "$YOSYS_BIN" -m "$SLANG_SO" -p "$cmd" >"$log" 2>&1
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "[pass] $mod"
    pass=$((pass + 1))
    echo "$mod" >> "$pass_list"
  else
    echo "[fail] $mod (rc=$rc)"
    fail=$((fail + 1))
    echo "$mod" >> "$fail_list"
  fi

done

echo "[summary] total=${#files[@]} actionable=$actionable skipped_float=$skipped_float pass=$pass fail=$fail"
echo "[summary] outputs: $OUT_DIR/json"
echo "[summary] logs:    $OUT_DIR/logs"
echo "[summary] pass-list: $pass_list"
echo "[summary] fail-list: $fail_list"
echo "[summary] skip-list: $skip_list"

if [[ $fail -ne 0 ]]; then
  exit 1
fi
