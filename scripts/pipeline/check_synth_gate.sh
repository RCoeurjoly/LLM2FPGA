#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/pipeline/check_synth_gate.sh <sv-dir> [top-module]

Checks:
  1) Disallow real/shortreal declarations and usage.
  2) Disallow real-valued system functions in synth path.
  3) Optional parse-only lint with yosys-slang if available.

Env:
  YOSYS_SLANG_SO   default: $HOME/yosys-slang/build/slang.so
  YOSYS_BIN        default: yosys
  RUN_LINT         default: 1 (set 0 to skip read_slang)
  LINT_WITH_TOP    default: 0 (set 1 to add --top <top-module>)
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

sv_dir="$1"
top="${2:-main}"
if [[ ! -d "$sv_dir" ]]; then
  echo "[FAIL] sv dir not found: $sv_dir" >&2
  exit 2
fi

mapfile -t sv_files < <(find "$sv_dir" -type f -name '*.sv' | sort)
if [[ ${#sv_files[@]} -eq 0 ]]; then
  echo "[FAIL] no .sv files found in: $sv_dir" >&2
  exit 2
fi

tmp_f="$(mktemp /tmp/sv_gate.XXXXXX.f)"
trap 'rm -f "$tmp_f"' EXIT
printf '%s\n' "${sv_files[@]}" > "$tmp_f"

echo "[info] sv files: ${#sv_files[@]}"

fail=0

check_pattern() {
  local label="$1"
  local pattern="$2"
  local out
  out="$(rg -n --no-heading -e "$pattern" "$sv_dir" --glob '*.sv' || true)"
  if [[ -n "$out" ]]; then
    echo "[FAIL] $label"
    echo "$out" | head -n 40
    fail=1
  else
    echo "[PASS] $label"
  fi
}

check_pattern "no shortreal/real tokens" '\b(shortreal|real)\b'
# shellcheck disable=SC2016
check_pattern "no real system funcs" '\$(bitstoshortreal|shortrealtobits|bitstoreal|realtobits|exp|sqrt|pow|tanh)\b'

run_lint="${RUN_LINT:-1}"
if [[ "$run_lint" == "1" ]]; then
  yosys_bin="${YOSYS_BIN:-yosys}"
  slang_so="${YOSYS_SLANG_SO:-$HOME/yosys-slang/build/slang.so}"
  lint_with_top="${LINT_WITH_TOP:-0}"
  if command -v "$yosys_bin" >/dev/null 2>&1 && [[ -f "$slang_so" ]]; then
    echo "[info] running yosys-slang lint"
    lint_cmd="read_slang --lint-only --ignore-assertions --ignore-unknown-modules -F $tmp_f"
    if [[ "$lint_with_top" == "1" ]]; then
      lint_cmd="read_slang --lint-only --ignore-assertions --ignore-unknown-modules --top $top -F $tmp_f"
    fi
    set +e
    "$yosys_bin" -m "$slang_so" -p "$lint_cmd" > /tmp/sv_gate_lint.log 2>&1
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      echo "[PASS] yosys-slang lint"
    else
      echo "[FAIL] yosys-slang lint (rc=$rc)"
      sed -n '1,120p' /tmp/sv_gate_lint.log
      fail=1
    fi
  else
    echo "[WARN] skipping lint: yosys or slang plugin unavailable"
  fi
else
  echo "[info] lint disabled (RUN_LINT=$run_lint)"
fi

if [[ $fail -ne 0 ]]; then
  echo "[RESULT] SYNTH GATE: FAIL"
  exit 1
fi

echo "[RESULT] SYNTH GATE: PASS"
