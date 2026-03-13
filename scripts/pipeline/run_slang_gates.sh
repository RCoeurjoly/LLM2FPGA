#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/pipeline/run_slang_gates.sh <filelist.f> [top-module]

Runs two gates:
  1) Parse/lint gate over full file list.
  2) Top gate using AST compilation only (no deep elaboration).

Env:
  YOSYS_BIN        default: yosys
  YOSYS_SLANG_SO   default: $HOME/yosys-slang/build/slang.so
  THREADS          default: 1
  IGNORE_ASSERTS   default: 1
  RUN_TOP_AST      default: 1
  LOG_DIR          default: /tmp/slang_gates_<timestamp>
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

FILELIST="$1"
TOP="${2:-main}"
if [[ ! -f "$FILELIST" ]]; then
  echo "[FAIL] file list not found: $FILELIST" >&2
  exit 2
fi

YOSYS_BIN="${YOSYS_BIN:-yosys}"
SLANG_SO="${YOSYS_SLANG_SO:-$HOME/yosys-slang/build/slang.so}"
THREADS="${THREADS:-1}"
IGNORE_ASSERTS="${IGNORE_ASSERTS:-1}"
RUN_TOP_AST="${RUN_TOP_AST:-1}"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-/tmp/slang_gates_${TS}}"
mkdir -p "$LOG_DIR"

if ! command -v "$YOSYS_BIN" >/dev/null 2>&1; then
  echo "[FAIL] yosys not found: $YOSYS_BIN" >&2
  exit 2
fi
if [[ ! -f "$SLANG_SO" ]]; then
  echo "[FAIL] slang plugin not found: $SLANG_SO" >&2
  exit 2
fi

base_args=("--lint-only" "-j" "$THREADS")
if [[ "$IGNORE_ASSERTS" == "1" ]]; then
  base_args+=("--ignore-assertions")
fi

run_gate() {
  local name="$1"
  shift
  local -a args=("$@")
  local log="$LOG_DIR/${name}.log"
  local cmd="read_slang"
  local a
  for a in "${args[@]}"; do
    cmd+=" ${a}"
  done

  echo "[info] running $name"
  set +e
  /usr/bin/time -v "$YOSYS_BIN" -m "$SLANG_SO" -p "$cmd" >"$log" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name (rc=$rc)"
    sed -n '1,120p' "$log"
    return 1
  fi

  local mem
  mem="$(rg -n "Maximum resident set size|MEM:" "$log" -N || true)"
  if [[ -n "$mem" ]]; then
    echo "[info] $name resource summary:"
    echo "$mem"
  fi
  return 0
}

fail=0

run_gate parse_gate "${base_args[@]}" "-F" "$FILELIST" || fail=1

if [[ "$RUN_TOP_AST" == "1" ]]; then
  run_gate top_ast_gate "${base_args[@]}" "--ast-compilation-only" "--top" "$TOP" "-F" "$FILELIST" || fail=1
else
  echo "[info] skipping top AST gate (RUN_TOP_AST=$RUN_TOP_AST)"
fi

echo "[info] logs: $LOG_DIR"
if [[ $fail -ne 0 ]]; then
  echo "[RESULT] SLANG GATES: FAIL"
  exit 1
fi

echo "[RESULT] SLANG GATES: PASS"
