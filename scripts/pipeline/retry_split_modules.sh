#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/pipeline/retry_split_modules.sh <sv-dir> <module-list.txt> <out-dir>

Reruns yosys-slang synthesis only for modules listed in <module-list.txt>.
Useful after synth_split_modules.sh emits failed_modules.txt.

Env:
  YOSYS_BIN        default: yosys
  YOSYS_SLANG_SO   default: $HOME/yosys-slang/build/slang.so
  TIMEOUT_SEC      default: 180
  FP_PRIMS_SV      optional SV file containing circt_fp_* module definitions
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 3 ]]; then
  usage
  exit 0
fi

SV_DIR="$1"
MODULE_LIST="$2"
OUT_DIR="$3"

if [[ ! -d "$SV_DIR" ]]; then
  echo "[FAIL] sv dir not found: $SV_DIR" >&2
  exit 2
fi
if [[ ! -f "$MODULE_LIST" ]]; then
  echo "[FAIL] module list not found: $MODULE_LIST" >&2
  exit 2
fi

YOSYS_BIN="${YOSYS_BIN:-yosys}"
SLANG_SO="${YOSYS_SLANG_SO:-$HOME/yosys-slang/build/slang.so}"
TIMEOUT_SEC="${TIMEOUT_SEC:-180}"
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
: > "$pass_list"
: > "$fail_list"

pass=0
fail=0
total=0

while IFS= read -r mod; do
  [[ -z "$mod" ]] && continue
  sv="$SV_DIR/$mod.sv"
  log="$OUT_DIR/logs/$mod.log"
  json="$OUT_DIR/json/$mod.json"
  if [[ ! -f "$sv" ]]; then
    echo "[fail][missing] $mod ($sv)"
    echo "$mod" >> "$fail_list"
    fail=$((fail + 1))
    total=$((total + 1))
    continue
  fi

  total=$((total + 1))
  cmd="read_slang --ignore-assertions --ignore-unknown-modules"
  if [[ -n "$FP_PRIMS_SV" && -f "$FP_PRIMS_SV" ]]; then
    cmd+=" $FP_PRIMS_SV"
  fi
  cmd+=" $sv; hierarchy -check -top $mod; proc; opt; fsm; opt; memory; opt; techmap; opt; abc; opt; stat; write_json $json"

  set +e
  /usr/bin/timeout "$TIMEOUT_SEC" "$YOSYS_BIN" -m "$SLANG_SO" -p "$cmd" >"$log" 2>&1
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "[pass] $mod"
    echo "$mod" >> "$pass_list"
    pass=$((pass + 1))
  else
    echo "[fail] $mod (rc=$rc)"
    echo "$mod" >> "$fail_list"
    fail=$((fail + 1))
  fi
done < "$MODULE_LIST"

echo "[summary] total=$total pass=$pass fail=$fail"
echo "[summary] outputs: $OUT_DIR/json"
echo "[summary] logs:    $OUT_DIR/logs"
echo "[summary] pass-list: $pass_list"
echo "[summary] fail-list: $fail_list"

if [[ $fail -ne 0 ]]; then
  exit 1
fi

