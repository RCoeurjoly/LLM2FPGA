#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
inner_script="${script_dir}/codex-night-inner.sh"

session_name="${CODEX_NIGHT_SESSION:-codex-night}"
duration="${CODEX_NIGHT_DURATION:-8h}"
prompt_file="${CODEX_NIGHT_PROMPT_FILE:-${repo_root}/codex-night-prompt.txt}"
log_file="${CODEX_NIGHT_LOG_FILE:-/tmp/codex-night.log}"
last_file="${CODEX_NIGHT_LAST_FILE:-/tmp/codex-night-last.txt}"
state_file="${CODEX_NIGHT_STATE_FILE:-/tmp/codex-night-state.txt}"
model="${CODEX_NIGHT_MODEL:-gpt-5.4}"
stale_passes="${CODEX_NIGHT_STALE_PASSES:-2}"
mode="exec"
attach=0
kill_existing=0
use_search="${CODEX_NIGHT_SEARCH:-1}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --resume-last     Resume the most recent Codex session instead of starting fresh
  --attach          Attach to tmux after starting
  --kill-existing   Kill an existing tmux session with the same name first
  --search          Enable Codex live web search (default)
  --no-search       Disable Codex live web search
  --session NAME    tmux session name (default: ${session_name})
  --duration DUR    timeout duration passed to timeout(1) (default: ${duration})
  --model MODEL     Codex model (default: ${model})
  --prompt FILE     Prompt file (default: ${prompt_file})
  --log FILE        Log file (default: ${log_file})
  --last FILE       Last-message output file (default: ${last_file})
  --state FILE      State file (default: ${state_file})
  --stale N         Escalate after N unchanged passes (default: ${stale_passes})
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume-last)
      mode="resume-last"
      shift
      ;;
    --attach)
      attach=1
      shift
      ;;
    --kill-existing)
      kill_existing=1
      shift
      ;;
    --search)
      use_search=1
      shift
      ;;
    --no-search)
      use_search=0
      shift
      ;;
    --session)
      session_name="$2"
      shift 2
      ;;
    --duration)
      duration="$2"
      shift 2
      ;;
    --model)
      model="$2"
      shift 2
      ;;
    --prompt)
      prompt_file="$2"
      shift 2
      ;;
    --log)
      log_file="$2"
      shift 2
      ;;
    --last)
      last_file="$2"
      shift 2
      ;;
    --state)
      state_file="$2"
      shift 2
      ;;
    --stale)
      stale_passes="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for cmd in tmux codex timeout; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "${cmd} not found in PATH" >&2
    exit 1
  fi
done

if [[ ! -f "${prompt_file}" ]]; then
  echo "prompt file not found: ${prompt_file}" >&2
  exit 1
fi

if tmux has-session -t "${session_name}" 2>/dev/null; then
  if [[ "${kill_existing}" == "1" ]]; then
    tmux kill-session -t "${session_name}"
  else
    echo "tmux session already exists: ${session_name}" >&2
    echo "use --kill-existing or choose another --session name" >&2
    exit 1
  fi
fi

q() {
  printf '%q' "$1"
}

tmux_cmd="env \
CODEX_NIGHT_MODE=$(q "${mode}") \
CODEX_NIGHT_DURATION=$(q "${duration}") \
CODEX_NIGHT_MODEL=$(q "${model}") \
CODEX_NIGHT_PROMPT_FILE=$(q "${prompt_file}") \
CODEX_NIGHT_LOG_FILE=$(q "${log_file}") \
CODEX_NIGHT_LAST_FILE=$(q "${last_file}") \
CODEX_NIGHT_STATE_FILE=$(q "${state_file}") \
CODEX_NIGHT_STALE_PASSES=$(q "${stale_passes}") \
CODEX_NIGHT_SEARCH=$(q "${use_search}") \
$(q "${inner_script}")"

tmux new-session -d -s "${session_name}" "${tmux_cmd}"

echo "started tmux session: ${session_name}"
echo "log: ${log_file}"
echo "last message: ${last_file}"
echo "state: ${state_file}"
echo "attach: tmux attach -t ${session_name}"
echo "stop: tmux kill-session -t ${session_name}"

if [[ "${attach}" == "1" ]]; then
  exec tmux attach -t "${session_name}"
fi
