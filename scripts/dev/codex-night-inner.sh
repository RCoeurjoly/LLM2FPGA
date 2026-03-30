#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"

prompt_file="${CODEX_NIGHT_PROMPT_FILE:-${repo_root}/codex-night-prompt.txt}"
log_file="${CODEX_NIGHT_LOG_FILE:-/tmp/codex-night.log}"
last_file="${CODEX_NIGHT_LAST_FILE:-/tmp/codex-night-last.txt}"
duration="${CODEX_NIGHT_DURATION:-8h}"
mode="${CODEX_NIGHT_MODE:-exec}"
model="${CODEX_NIGHT_MODEL:-gpt-5.4}"
use_search="${CODEX_NIGHT_SEARCH:-1}"

if [[ ! -f "${prompt_file}" ]]; then
  echo "prompt file not found: ${prompt_file}" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex not found in PATH" >&2
  exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
  echo "timeout not found in PATH" >&2
  exit 1
fi

cd "${repo_root}"

prompt="$(<"${prompt_file}")"

cmd=(
  codex
)

if [[ "${use_search}" == "1" ]]; then
  cmd+=(--search)
fi

case "${mode}" in
  exec)
    cmd+=(exec)
    ;;
  resume-last)
    cmd+=(exec resume --last)
    ;;
  *)
    echo "unsupported CODEX_NIGHT_MODE: ${mode}" >&2
    exit 1
    ;;
esac

cmd+=(
  --dangerously-bypass-approvals-and-sandbox
  --skip-git-repo-check
  -m "${model}"
  -o "${last_file}"
)

if [[ "${mode}" == "exec" ]]; then
  cmd+=(-C "${repo_root}")
fi

cmd+=("${prompt}")

mkdir -p "$(dirname -- "${log_file}")" "$(dirname -- "${last_file}")"

{
  echo "[$(date --iso-8601=seconds)] starting codex night run"
  echo "repo_root=${repo_root}"
  echo "mode=${mode}"
  echo "duration=${duration}"
  echo "model=${model}"
  echo "search=${use_search}"
  echo "prompt_file=${prompt_file}"
  echo "log_file=${log_file}"
  echo "last_file=${last_file}"
  echo
} | tee "${log_file}"

timeout "${duration}" "${cmd[@]}" |& tee -a "${log_file}"
