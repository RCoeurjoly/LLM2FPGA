#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"

prompt_file="${CODEX_NIGHT_PROMPT_FILE:-${repo_root}/codex-night-prompt.txt}"
log_file="${CODEX_NIGHT_LOG_FILE:-/tmp/codex-night.log}"
last_file="${CODEX_NIGHT_LAST_FILE:-/tmp/codex-night-last.txt}"
state_file="${CODEX_NIGHT_STATE_FILE:-/tmp/codex-night-state.txt}"
duration="${CODEX_NIGHT_DURATION:-8h}"
mode="${CODEX_NIGHT_MODE:-exec}"
model="${CODEX_NIGHT_MODEL:-gpt-5.4}"
use_search="${CODEX_NIGHT_SEARCH:-1}"
stale_pass_limit="${CODEX_NIGHT_STALE_PASSES:-2}"

if [[ ! -f "${prompt_file}" ]]; then
  echo "prompt file not found: ${prompt_file}" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex not found in PATH" >&2
  exit 1
fi

cd "${repo_root}"

prompt="$(<"${prompt_file}")"
stale_passes=0
previous_state_hash=""

file_hash() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    sha256sum "${path}" | awk '{print $1}'
  else
    echo ""
  fi
}

runtime_instructions() {
  local run_mode="$1"
  local continuation_note=""

  if [[ "${run_mode}" == "resume-last" ]]; then
    continuation_note=$(
      cat <<EOF

Resume mode rules:
- do not restate the full project context; use the state file as the source of
  truth
- do not repeat prompt text back to the user
- continue directly from the saved next concrete step
- if a canonical 'nix build' is already running, let that one run to a real
  result instead of spawning redundant 'nix path-info' or duplicate build probes
EOF
    )
  fi

  if (( stale_passes >= stale_pass_limit )); then
    continuation_note+=$(
      cat <<EOF

Stale-state escalation:
- the state file has not changed materially for ${stale_passes} completed pass(es)
- do not spend this pass waiting, rechecking, or rephrasing the same blocker
- either:
  1. make one concrete code change aimed at the blocker, or
  2. run one canonical build to completion and capture its first new failure
- if neither happens, the pass is considered churn
EOF
    )
  fi

  cat <<EOF

Runtime files for this overnight run:
- log file: ${log_file}
- last response file: ${last_file}
- state file: ${state_file}
${continuation_note}

At the start of each pass:
- read the state file first if it exists
- continue from the unfinished "next concrete step" instead of re-summarizing
- keep notes short and implementation-focused
- ignore any earlier 'NOT DONE' or final-style summary in the log or last
  response unless the outer runner is actually ending

During the pass:
- update the state file whenever the blocker changes materially
- include: current blocker, exact failing command, exact failing derivation or
  first log line, files changed, and next concrete step
- if you are about to do another top-level rerun without a code change or a
  smaller reproducer, stop and work the upstream blocker instead
- do not treat completion of one experiment as the end of the pass; choose the
  next concrete fix from the state file and continue

At the end of the pass:
- overwrite the state file with the latest status in plain text
- do not spend time polishing docs unless the build has improved or the doc
  change is required for the build
- only emit 'NOT DONE' if the outer overnight run is actually ending or an
  external blocker prevents further progress
EOF
}

build_cmd() {
  local run_mode="$1"
  local -a cmd=(codex)
  local full_prompt

  if [[ "${use_search}" == "1" ]]; then
    cmd+=(--search)
  fi

  case "${run_mode}" in
    exec)
      cmd+=(exec)
      ;;
    resume-last)
      cmd+=(exec resume --last)
      ;;
    *)
      echo "unsupported CODEX_NIGHT_MODE: ${run_mode}" >&2
      return 1
      ;;
  esac

  cmd+=(
    --dangerously-bypass-approvals-and-sandbox
    --skip-git-repo-check
    -m "${model}"
    -o "${last_file}"
  )

  if [[ "${run_mode}" == "exec" ]]; then
    cmd+=(-C "${repo_root}")
  fi

  if [[ "${run_mode}" == "exec" ]]; then
    full_prompt="${prompt}"$'\n'"$(runtime_instructions "${run_mode}")"
  else
    full_prompt="Continue from the current overnight state in ${state_file}."$'\n'"$(runtime_instructions "${run_mode}")"
  fi
  cmd+=("${full_prompt}")
  printf '%s\0' "${cmd[@]}"
}

mkdir -p "$(dirname -- "${log_file}")" "$(dirname -- "${last_file}")" \
  "$(dirname -- "${state_file}")"

{
  echo "[$(date --iso-8601=seconds)] starting codex night run"
  echo "repo_root=${repo_root}"
  echo "mode=${mode}"
  echo "duration=${duration}"
  echo "model=${model}"
  echo "search=${use_search}"
  echo "stale_pass_limit=${stale_pass_limit}"
  echo "prompt_file=${prompt_file}"
  echo "log_file=${log_file}"
  echo "last_file=${last_file}"
  echo "state_file=${state_file}"
  echo
} | tee "${log_file}"

cat > "${state_file}" <<EOF
[$(date --iso-8601=seconds)] codex-night state initialized
repo_root=${repo_root}
prompt_file=${prompt_file}
log_file=${log_file}
last_file=${last_file}
state_file=${state_file}

Current blocker: unknown
Exact failing command: unknown
Exact failing derivation or log line: unknown
Files changed: none yet
Next concrete step: reproduce the canonical gate once, identify the smallest
upstream failing derivation, and work there instead of editing docs.
EOF

previous_state_hash="$(file_hash "${state_file}")"

timed_out=0
current_child=""
pass_num=0

on_timeout() {
  timed_out=1
  if [[ -n "${current_child}" ]]; then
    kill -TERM "${current_child}" 2>/dev/null || true
  fi
}

trap on_timeout TERM INT

(
  sleep "${duration}"
  kill -TERM "$$" 2>/dev/null || true
) &
timer_pid=$!

current_mode="${mode}"

while (( ! timed_out )); do
  pass_num=$((pass_num + 1))
  {
    echo "[$(date --iso-8601=seconds)] starting codex pass"
    echo "pass_num=${pass_num}"
    echo "pass_mode=${current_mode}"
    echo
  } | tee -a "${log_file}"

  mapfile -d '' -t cmd < <(build_cmd "${current_mode}")

  set +e
  "${cmd[@]}" |& tee -a "${log_file}" &
  current_child=$!
  wait "${current_child}"
  rc=$?
  current_child=""
  set -e

  {
    echo
    echo "[$(date --iso-8601=seconds)] codex pass exited"
    echo "pass_num=${pass_num}"
    echo "pass_mode=${current_mode}"
    echo "exit_code=${rc}"
    echo
  } | tee -a "${log_file}"

  current_state_hash="$(file_hash "${state_file}")"
  if [[ -n "${current_state_hash}" && "${current_state_hash}" == "${previous_state_hash}" ]]; then
    stale_passes=$((stale_passes + 1))
  else
    stale_passes=0
    previous_state_hash="${current_state_hash}"
  fi

  {
    echo "state_hash=${current_state_hash}"
    echo "stale_passes=${stale_passes}"
    echo
  } | tee -a "${log_file}"

  if (( timed_out )); then
    break
  fi

  current_mode="resume-last"
  sleep 1
done

kill "${timer_pid}" 2>/dev/null || true
wait "${timer_pid}" 2>/dev/null || true
