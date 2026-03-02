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

run_to_output() {
  local output="$1"
  shift
  "$@" >"$output"
}
