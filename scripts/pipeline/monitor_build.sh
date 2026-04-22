#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  monitor_build.sh OUTPUT_DIR [INTERVAL_SECONDS] -- COMMAND [ARG ...]

Example:
  monitor_build.sh artifacts/task6/runs/top4 5 -- \
    nix build .#tiny-stories-1m-baseline-float-selftest-top4-memory-utilization -L

Artifacts written under OUTPUT_DIR:
  build.log           Full command output
  processes.tsv       First-seen process metadata
  process-samples.tsv Periodic VmRSS/VmHWM samples for the command tree
  summary.txt         Exit status, wall-clock time, peak memory summary

Optional environment:
  MONITOR_GLOBAL_PGREP_PATTERN
    Extra global process regex to sample in addition to the command tree.
    Useful for daemonized builds where the heavy worker is not a child of the
    front-end command, e.g.:
      MONITOR_GLOBAL_PGREP_PATTERN='yosys -q -s run.ys'
EOF
}

if [[ $# -lt 3 ]]; then
  usage >&2
  exit 2
fi

output_dir=$1
shift

interval_seconds=5
if [[ $# -gt 0 && $1 != "--" ]]; then
  interval_seconds=$1
  shift
fi

if [[ $# -eq 0 || $1 != "--" ]]; then
  usage >&2
  exit 2
fi
shift

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

mkdir -p "$output_dir"

build_log="$output_dir/build.log"
process_log="$output_dir/processes.tsv"
sample_log="$output_dir/process-samples.tsv"
summary_log="$output_dir/summary.txt"

printf 'pid\tname\tcmdline\n' > "$process_log"
printf 'timestamp_epoch\tsample_index\tpid\tppid\tname\tstate\tvmrss_kb\tvmhwm_kb\tvmsize_kb\tthreads\n' > "$sample_log"

declare -A seen_pids=()
command=( "$@" )
command_string=$(printf '%q ' "${command[@]}")

collect_descendants() {
  local pid=$1
  local child
  printf '%s\n' "$pid"
  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    collect_descendants "$child"
  done < <(pgrep -P "$pid" || true)
}

collect_sample_pids() {
  local root_pid=$1
  collect_descendants "$root_pid"
  if [[ -n ${MONITOR_GLOBAL_PGREP_PATTERN:-} ]]; then
    pgrep -f "$MONITOR_GLOBAL_PGREP_PATTERN" || true
  fi
}

record_process_metadata() {
  local pid=$1
  local name cmdline

  if [[ -n ${seen_pids[$pid]:-} ]]; then
    return
  fi
  [[ -r /proc/$pid/status ]] || return

  name=$(awk '/^Name:/ { print $2; exit }' /proc/"$pid"/status)
  cmdline=$(tr '\0' ' ' < /proc/"$pid"/cmdline 2>/dev/null || true)
  printf '%s\t%s\t%s\n' "$pid" "$name" "$cmdline" >> "$process_log"
  seen_pids[$pid]=1
}

sample_tree() {
  local root_pid=$1
  local sample_index=$2
  local timestamp pid

  timestamp=$(date +%s)
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    [[ -r /proc/$pid/status ]] || continue
    record_process_metadata "$pid"

    awk -v ts="$timestamp" -v sample="$sample_index" -v pid="$pid" '
      BEGIN {
        ppid = "";
        name = "";
        state = "";
        vmrss = "";
        vmhwm = "";
        vmsize = "";
        threads = "";
      }
      /^PPid:/ { ppid = $2 }
      /^Name:/ { name = $2 }
      /^State:/ { state = $2 }
      /^VmRSS:/ { vmrss = $2 }
      /^VmHWM:/ { vmhwm = $2 }
      /^VmSize:/ { vmsize = $2 }
      /^Threads:/ { threads = $2 }
      END {
        print ts "\t" sample "\t" pid "\t" ppid "\t" name "\t" state "\t" vmrss "\t" vmhwm "\t" vmsize "\t" threads
      }
    ' /proc/"$pid"/status >> "$sample_log"
  done < <(collect_sample_pids "$root_pid" | sort -n -u)
}

start_time=$(date +%s)

(
  "${command[@]}"
) > >(tee "$build_log") 2>&1 &
root_pid=$!

sample_index=0
sample_index=$((sample_index + 1))
sample_tree "$root_pid" "$sample_index"

while kill -0 "$root_pid" 2>/dev/null; do
  sample_index=$((sample_index + 1))
  sample_tree "$root_pid" "$sample_index"
  sleep "$interval_seconds"
done

set +e
wait "$root_pid"
command_status=$?
set -e

sample_index=$((sample_index + 1))
sample_tree "$root_pid" "$sample_index"

end_time=$(date +%s)
wall_seconds=$((end_time - start_time))

last_stage_line=$(grep -F '[mkSynthJson:' "$build_log" | tail -n 1 || true)

awk -F '\t' -v status="$command_status" -v wall="$wall_seconds" \
  -v interval="$interval_seconds" -v command="$command_string" \
  -v last_stage="$last_stage_line" '
  BEGIN {
    max_rss = -1;
    max_hwm = -1;
    max_rss_pid = "";
    max_rss_name = "";
    max_hwm_pid = "";
    max_hwm_name = "";
  }
  NR == 1 { next }
  {
    vmrss = ($7 == "" ? 0 : $7) + 0;
    vmhwm = ($8 == "" ? 0 : $8) + 0;
    if (vmrss > max_rss) {
      max_rss = vmrss;
      max_rss_pid = $3;
      max_rss_name = $5;
    }
    if (vmhwm > max_hwm) {
      max_hwm = vmhwm;
      max_hwm_pid = $3;
      max_hwm_name = $5;
    }
  }
  END {
    print "command: " command;
    print "exit_status: " status;
    print "wall_seconds: " wall;
    print "sample_interval_seconds: " interval;
    if (max_rss < 0) {
      print "peak_vmrss_kb: n/a";
      print "peak_vmrss_pid: ";
      print "peak_vmrss_name: ";
      print "peak_vmhwm_kb: n/a";
      print "peak_vmhwm_pid: ";
      print "peak_vmhwm_name: ";
    } else {
      print "peak_vmrss_kb: " max_rss;
      print "peak_vmrss_pid: " max_rss_pid;
      print "peak_vmrss_name: " max_rss_name;
      print "peak_vmhwm_kb: " max_hwm;
      print "peak_vmhwm_pid: " max_hwm_pid;
      print "peak_vmhwm_name: " max_hwm_name;
    }
    print "last_stage_line: " last_stage;
  }
' "$sample_log" > "$summary_log"

exit "$command_status"
