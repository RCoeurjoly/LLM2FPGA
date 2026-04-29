#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

BRANCH_REQUIRED="${BRANCH_REQUIRED:-task6-streamtensor-lite}"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
if [[ "$CURRENT_BRANCH" != "$BRANCH_REQUIRED" ]]; then
  echo "Refusing to run on branch '$CURRENT_BRANCH'; expected '$BRANCH_REQUIRED'." >&2
  echo "Override with BRANCH_REQUIRED=$CURRENT_BRANCH if this is intentional." >&2
  exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found. Install with: npm install -g @openai/codex" >&2
  exit 2
fi

PROGRAM="${PROGRAM:-autonight/task6_codex_program.md}"
STATUS_FILE="${STATUS_FILE:-AUTONIGHT_STATUS.md}"
DURATION_HOURS="${DURATION_HOURS:-8}"
SLICE_MINUTES="${SLICE_MINUTES:-35}"
IDLE_TIMEOUT_MINUTES="${IDLE_TIMEOUT_MINUTES:-90}"
SLEEP_BETWEEN_SECONDS="${SLEEP_BETWEEN_SECONDS:-20}"
SANDBOX="${CODEX_SANDBOX:-workspace-write}"
CODEX_MODEL_ARG=()
if [[ -n "${CODEX_MODEL:-}" ]]; then
  CODEX_MODEL_ARG=(-m "$CODEX_MODEL")
fi

if [[ ! -f "$PROGRAM" ]]; then
  echo "Program prompt not found: $PROGRAM" >&2
  exit 2
fi

SESSION_ID="${SESSION_ID:-$(date +%Y%m%d-%H%M%S)-task6-codex-night}"
RUN_DIR="${RUN_DIR:-artifacts/task6/autonight/$SESSION_ID}"
mkdir -p "$RUN_DIR"/{prompts,logs,diffs,status,results}

START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + DURATION_HOURS * 3600 ))"
DRIVER_CSV="$RUN_DIR/driver.csv"
touch "$DRIVER_CSV"
if [[ ! -s "$DRIVER_CSV" ]]; then
  echo "iteration,start_iso,end_iso,exit_code,reason,log,prompt,diff,status_file" > "$DRIVER_CSV"
fi

if [[ ! -f "$STATUS_FILE" ]]; then
  cat > "$STATUS_FILE" <<STATUS_EOF
# AUTONIGHT_STATUS

## Last iteration
No overnight iteration has completed yet.

## Current best evidence
- v1k bounded int8 L2 MLP/residual-add slice is board validated.
- v4k bounded MLP/residual RTL replay passes.
- vocab memory score indicates v4k can continue on-chip; full vocab/output projection needs external-memory or streaming planning.

## Accepted/promoted changes
None yet in this overnight session.

## Rejected attempts
None yet in this overnight session.

## Commands run
None yet in this overnight session.

## Files changed
None yet in this overnight session.

## Open risks
- v4k embedding/lm_head not yet synthesized.
- multi-sample quantization not yet calibrated.
- attention not yet scored.
- full output-head streaming/DDR3 plan not yet concrete.

## Next recommended step
Start with a small v4k on-chip tied vocab/output-head score or prototype.
STATUS_EOF
fi

cat > "$RUN_DIR/session.md" <<SESSION_EOF
# Task 6 Codex overnight session

- session_id: $SESSION_ID
- branch: $CURRENT_BRANCH
- start: $(date -Is)
- duration_hours: $DURATION_HOURS
- slice_minutes: $SLICE_MINUTES
- idle_timeout_minutes: $IDLE_TIMEOUT_MINUTES
- sandbox: $SANDBOX
- program: $PROGRAM
- status_file: $STATUS_FILE
- codex_version: $(codex --version 2>/dev/null || true)

## Initial git status

\`\`\`
$(git status --short)
\`\`\`
SESSION_EOF

run_with_watchdog() {
  local prompt="$1"
  local log="$2"
  local max_seconds="$3"
  local idle_seconds="$4"

  set +e
  codex exec "${CODEX_MODEL_ARG[@]}" --full-auto --sandbox "$SANDBOX" < "$prompt" > "$log" 2>&1 &
  local pid=$!
  local start_ts
  start_ts="$(date +%s)"
  local reason="exit"

  while kill -0 "$pid" 2>/dev/null; do
    sleep 30
    local now
    now="$(date +%s)"

    if (( now - start_ts > max_seconds )); then
      reason="slice-timeout"
      echo "" >> "$log"
      echo "[supervisor] slice timeout after ${max_seconds}s; terminating codex pid $pid" >> "$log"
      kill -TERM "$pid" 2>/dev/null || true
      sleep 15
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null
      echo "124:$reason"
      set -e
      return 0
    fi

    if [[ -s "$log" ]]; then
      local mtime
      mtime="$(stat -c %Y "$log" 2>/dev/null || echo "$now")"
      if (( now - mtime > idle_seconds )); then
        reason="idle-timeout"
        echo "" >> "$log"
        echo "[supervisor] idle timeout after ${idle_seconds}s without log updates; terminating codex pid $pid" >> "$log"
        kill -TERM "$pid" 2>/dev/null || true
        sleep 15
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null
        echo "125:$reason"
        set -e
        return 0
      fi
    fi
  done

  wait "$pid"
  local rc=$?
  echo "$rc:$reason"
  set -e
  return 0
}

iter=0
while (( "$(date +%s)" < END_EPOCH )); do
  iter=$((iter + 1))
  now_epoch="$(date +%s)"
  remaining_seconds="$(( END_EPOCH - now_epoch ))"
  slice_seconds="$(( SLICE_MINUTES * 60 ))"
  if (( remaining_seconds < slice_seconds )); then
    slice_seconds="$remaining_seconds"
  fi
  if (( slice_seconds < 120 )); then
    break
  fi

  prompt="$RUN_DIR/prompts/iter-$(printf '%03d' "$iter").md"
  log="$RUN_DIR/logs/iter-$(printf '%03d' "$iter").log"
  diff_file="$RUN_DIR/diffs/iter-$(printf '%03d' "$iter").patch"
  status_snapshot="$RUN_DIR/status/iter-$(printf '%03d' "$iter").status.txt"
  start_iso="$(date -Is)"

  cat > "$prompt" <<PROMPT_EOF
$(cat "$PROGRAM")

# Supervisor context for this invocation

You are invocation $iter of an 8-hour supervised overnight run.

The supervisor will restart Codex if this invocation exits before the 8-hour wall-clock budget is over. That is expected. Continue from the repo status and from \`$STATUS_FILE\`; do not repeat completed work.

Time budget for this invocation: about $(( slice_seconds / 60 )) minutes.

Repository root: $ROOT
Run directory: $RUN_DIR
Status file to update before exit: $STATUS_FILE

## Required behavior in this invocation

1. First inspect:
   - \`$STATUS_FILE\`
   - \`artifacts/task6/parallel-hypotheses/h2-int8-l2-selftest-board-comparison.json\`
   - \`artifacts/task6/parallel-hypotheses/h2-v4k-scale-up-summary.json\`
   - \`artifacts/task6/parallel-hypotheses/h2-vocab-memory-surface-score.json\` if present
   - recent files under \`artifacts/task6/autonight/\`
2. Pick one bounded next experiment from the program.
3. Prefer quick scripts/scorecards before synthesis.
4. Keep commands targeted. Do not launch monolithic full-model synthesis.
5. Write results as JSON/CSV artifacts.
6. Update \`$STATUS_FILE\` before exiting with a concrete next step.
7. If you make code changes, run the cheapest meaningful validation and record the command/result.
8. Do not push to remote.

If the best next step is to continue a partially completed previous iteration, continue it. If the previous iteration timed out or was interrupted, inspect the files and logs and recover conservatively.
PROMPT_EOF

  echo "[supervisor] starting iteration $iter at $start_iso; log=$log"
  result="$(run_with_watchdog "$prompt" "$log" "$slice_seconds" "$(( IDLE_TIMEOUT_MINUTES * 60 ))")"
  rc="${result%%:*}"
  reason="${result#*:}"
  end_iso="$(date -Is)"

  git status --short > "$status_snapshot" || true
  git diff --binary > "$diff_file" || true

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$iter" "$start_iso" "$end_iso" "$rc" "$reason" "$log" "$prompt" "$diff_file" "$status_snapshot" >> "$DRIVER_CSV"

  cat > "$RUN_DIR/results/iter-$(printf '%03d' "$iter").json" <<RESULT_EOF
{
  "iteration": $iter,
  "start_iso": "$start_iso",
  "end_iso": "$end_iso",
  "exit_code": $rc,
  "reason": "$reason",
  "log": "$log",
  "prompt": "$prompt",
  "diff": "$diff_file",
  "status": "$status_snapshot"
}
RESULT_EOF

  if grep -qiE 'rate.?limit|quota|429|temporarily unavailable|too many requests' "$log"; then
    echo "[supervisor] possible rate limit detected; sleeping 10 minutes"
    sleep 600
  else
    sleep "$SLEEP_BETWEEN_SECONDS"
  fi
done

python3 scripts/task6/codex_autonight_report.py "$RUN_DIR" || true

cat >> "$RUN_DIR/session.md" <<SESSION_END

## Final git status

\`\`\`
$(git status --short)
\`\`\`

Finished: $(date -Is)
SESSION_END

echo "[supervisor] finished. Run directory: $RUN_DIR"
