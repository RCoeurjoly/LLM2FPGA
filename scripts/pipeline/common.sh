#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: $name" >&2
    exit 2
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing input file: $path" >&2
    exit 2
  fi
}

require_executable() {
  local path="$1"
  if [[ ! -x "$path" ]]; then
    echo "missing executable: $path" >&2
    exit 2
  fi
}

run_to_output() {
  local output="$1"
  shift
  "$@" >"$output"
}

write_yosys_slang_script() {
  local script="$1"
  local yosys_slang_so="$2"
  local input="$3"
  local -a slang_files=()

  : >"$script"
  echo "plugin -i ${yosys_slang_so}" >>"$script"

  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line#\#}" != "$line" ]] && continue
    slang_files+=("$line")
  done <"$input"

  if [[ "${#slang_files[@]}" -eq 0 ]]; then
    echo "empty or comment-only file list: $input" >&2
    exit 2
  fi

  printf 'read_slang --threads 1 --no-proc --top main' >>"$script"
  printf ' %q' "${slang_files[@]}" >>"$script"
  printf '\n' >>"$script"
}

run_yosys_script() {
  local label="$1"
  local yosys="$2"
  local input="$3"
  local stage_hint="$4"
  local errexit_was_on=0
  shift 4

  if [[ $- == *e* ]]; then
    errexit_was_on=1
  fi

  set +e
  "$yosys" "$@"
  local rc=$?
  if [[ "$errexit_was_on" -eq 1 ]]; then
    set -e
  else
    set +e
  fi

  if [[ "$rc" -eq 137 || "$rc" -eq 9 ]]; then
    echo "[$label] ERROR: Yosys was killed while processing '$input' (exit code $rc)." >&2
    echo "[$label] This is usually an out-of-memory condition." >&2
    echo "[$label] Try a host with more RAM, or reduce model complexity before ${stage_hint}." >&2
  fi

  return "$rc"
}
