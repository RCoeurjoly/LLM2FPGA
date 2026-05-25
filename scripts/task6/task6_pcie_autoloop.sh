#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/task6/task6_pcie_autoloop.sh [options]

Unprivileged autonomous PCIe bring-up loop for YPCB + OWC Helios. The loop
captures host state, optionally checks/programs the FPGA over JTAG, diffs each
iteration, and stops when a likely FPGA endpoint appears.

Options:
  --run-dir DIR              Output directory.
  --interval SEC             Delay between iterations. Default: 15.
  --iterations N             Max iterations; 0 means run until endpoint. Default: 120.
  --port-bdf BDF             Helios downstream port. Default: 0000:41:00.0.
  --endpoint-regex REGEX     Endpoint detection regex. Default: Xilinx|\[10ee:.
  --bitstream PATH           Optional SRAM bitstream to program.
  --program-once             Program --bitstream before loop capture.
  --program-each N           Reprogram every N iterations. Default: 0 disabled.
  --loader PATH              openFPGALoader binary. Default: local build if present.
  --serial SERIAL            FTDI serial for openFPGALoader. Default: 210299BF3824.
  --no-jtag-detect           Skip unprivileged openFPGALoader --detect captures.
  --no-pcie-jtag-status      Skip Task 6 PCIe USER1 status reads.
  --pcie-tdo-bit BIT         FTDI TDO bit for PCIe status reads. Default: 7.
  -h, --help                 Show this help.
EOF
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_DIR=""
INTERVAL=15
ITERATIONS=120
PORT_BDF="0000:41:00.0"
ENDPOINT_REGEX='Xilinx|\[10ee:'
BITSTREAM=""
PROGRAM_ONCE=0
PROGRAM_EACH=0
SERIAL="210299BF3824"
JTAG_DETECT=1
PCIE_JTAG_STATUS=1
PCIE_TDO_BIT=7

if [[ -x /home/roland/openFPGALoader/build/openFPGALoader ]]; then
  LOADER=/home/roland/openFPGALoader/build/openFPGALoader
else
  LOADER="$(command -v openFPGALoader || true)"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:?missing value for --run-dir}"; shift 2 ;;
    --interval) INTERVAL="${2:?missing value for --interval}"; shift 2 ;;
    --iterations) ITERATIONS="${2:?missing value for --iterations}"; shift 2 ;;
    --port-bdf) PORT_BDF="${2:?missing value for --port-bdf}"; shift 2 ;;
    --endpoint-regex) ENDPOINT_REGEX="${2:?missing value for --endpoint-regex}"; shift 2 ;;
    --bitstream) BITSTREAM="${2:?missing value for --bitstream}"; shift 2 ;;
    --program-once) PROGRAM_ONCE=1; shift ;;
    --program-each) PROGRAM_EACH="${2:?missing value for --program-each}"; shift 2 ;;
    --loader) LOADER="${2:?missing value for --loader}"; shift 2 ;;
    --serial) SERIAL="${2:?missing value for --serial}"; shift 2 ;;
    --no-jtag-detect) JTAG_DETECT=0; shift ;;
    --no-pcie-jtag-status) PCIE_JTAG_STATUS=0; shift ;;
    --pcie-tdo-bit) PCIE_TDO_BIT="${2:?missing value for --pcie-tdo-bit}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$RUN_DIR" ]]; then
  TS="$(date +%Y-%m-%dT%H-%M-%S%z)"
  RUN_DIR="artifacts/task6/runs/${TS}-pcie-autoloop"
fi

mkdir -p "$RUN_DIR"
SUMMARY="$RUN_DIR/summary.jsonl"
: > "$SUMMARY"

run_capture() {
  local log="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"$log" 2>&1 || {
    local rc=$?
    printf 'command failed with exit code %d\n' "$rc" >>"$log"
    return 0
  }
}

program_bitstream() {
  local iter="$1"
  local log="$RUN_DIR/program-${iter}.log"
  if [[ -z "$BITSTREAM" ]]; then
    return 0
  fi
  if [[ -z "$LOADER" || ! -x "$LOADER" ]]; then
    printf 'missing executable openFPGALoader: %s\n' "$LOADER" >"$log"
    return 0
  fi
  run_capture "$log" "$LOADER" -c digilent_hs3 --ftdi-serial "$SERIAL" "$BITSTREAM"
}

filter_kernel_log() {
  local iter_dir="$1"
  if [[ -s "$iter_dir/kernel-log.log" ]]; then
    if command -v rg >/dev/null 2>&1; then
      rg -i '42:00|41:00|aer|pcie|completion|timeout|link|hotplug|thunderbolt|bolt' \
        "$iter_dir/kernel-log.log" >"$iter_dir/kernel-log-filtered.log" || true
    else
      grep -Ei '42:00|41:00|aer|pcie|completion|timeout|link|hotplug|thunderbolt|bolt' \
        "$iter_dir/kernel-log.log" >"$iter_dir/kernel-log-filtered.log" || true
    fi
  fi
}

find_endpoint() {
  local lspci_log="$1"
  if [[ ! -s "$lspci_log" ]]; then
    return 1
  fi
  while IFS= read -r line; do
    local bdf
    bdf="${line%% *}"
    local detail
    detail="$(lspci -vv -s "$bdf" 2>&1 || true)"
    if grep -qi 'Unknown header type 7f' <<<"$detail"; then
      continue
    fi
    printf '%s\n' "$line"
    return 0
  done < <(grep -Ei "$ENDPOINT_REGEX" "$lspci_log" \
    | grep -Eiv 'Thunderbolt|USB controller|PCI bridge|Host bridge|Root Port')
  return 1
}

write_readme() {
  cat >"$RUN_DIR/README.md" <<EOF_README
# PCIe Autonomous Loop

- started: $(date -Iseconds)
- port BDF: \`$PORT_BDF\`
- endpoint regex: \`$ENDPOINT_REGEX\`
- interval seconds: \`$INTERVAL\`
- iterations: \`$ITERATIONS\`
- bitstream: \`${BITSTREAM:-none}\`
- loader: \`${LOADER:-none}\`
- sudo: not used
- pcie jtag status: \`$PCIE_JTAG_STATUS\`
- pcie tdo bit: \`$PCIE_TDO_BIT\`

Each \`iter-NNNN\` directory contains unprivileged captures of \`boltctl\`,
\`lspci -Dnn\`, \`lspci -tv\`, \`lspci -vvv -s $PORT_BDF\`, best-effort
kernel journal output, optional JTAG detect, and diffs against the previous
iteration. \`summary.jsonl\` records one JSON object per iteration.
EOF_README
}

write_readme

if [[ "$PROGRAM_ONCE" -eq 1 ]]; then
  program_bitstream "initial"
fi

previous_dir=""
found=0
i=1
while [[ "$ITERATIONS" -eq 0 || "$i" -le "$ITERATIONS" ]]; do
  iter="$(printf '%04d' "$i")"
  iter_dir="$RUN_DIR/iter-$iter"
  mkdir -p "$iter_dir"

  if [[ "$PROGRAM_EACH" -gt 0 && -n "$BITSTREAM" ]]; then
    if (( (i - 1) % PROGRAM_EACH == 0 )); then
      program_bitstream "$iter"
    fi
  fi

  run_capture "$iter_dir/boltctl.log" boltctl
  run_capture "$iter_dir/lspci-Dnn.log" lspci -Dnn
  run_capture "$iter_dir/lspci-tv.log" lspci -tv
  run_capture "$iter_dir/lspci-port-vvv.log" lspci -vvv -s "$PORT_BDF"
  run_capture "$iter_dir/kernel-log.log" timeout 8 journalctl -k -b --no-pager -n 500
  filter_kernel_log "$iter_dir"

  if [[ "$JTAG_DETECT" -eq 1 && -n "$LOADER" && -x "$LOADER" ]]; then
    run_capture "$iter_dir/openfpgaloader-detect.log" "$LOADER" -c digilent_hs3 --ftdi-serial "$SERIAL" --detect
  fi

  if [[ "$PCIE_JTAG_STATUS" -eq 1 ]]; then
    run_capture "$iter_dir/pcie-jtag-status.log" scripts/task6/read_pcie_jtag_status.py --serial "$SERIAL" --tdo-bit "$PCIE_TDO_BIT" --json-only
  fi

  if [[ -n "$previous_dir" ]]; then
    diff -u "$previous_dir/lspci-Dnn.log" "$iter_dir/lspci-Dnn.log" >"$iter_dir/lspci-Dnn.diff" || true
    diff -u "$previous_dir/boltctl.log" "$iter_dir/boltctl.log" >"$iter_dir/boltctl.diff" || true
    diff -u "$previous_dir/lspci-port-vvv.log" "$iter_dir/lspci-port-vvv.log" >"$iter_dir/lspci-port-vvv.diff" || true
  fi

  endpoint_line="$(find_endpoint "$iter_dir/lspci-Dnn.log" || true)"
  if [[ -n "$endpoint_line" ]]; then
    status="endpoint-found"
    found=1
  else
    status="no-endpoint"
  fi

  python3 -c 'import json,sys; print(json.dumps({"iteration": int(sys.argv[1]), "time": sys.argv[2], "status": sys.argv[3], "endpoint": sys.argv[4], "dir": sys.argv[5]}))' \
    "$i" "$(date -Iseconds)" "$status" "$endpoint_line" "$iter_dir" >>"$SUMMARY"

  printf '[%s] iter %s: %s%s\n' "$(date -Iseconds)" "$iter" "$status" "${endpoint_line:+: $endpoint_line}" | tee -a "$RUN_DIR/progress.log"

  if [[ "$found" -eq 1 ]]; then
    break
  fi
  previous_dir="$iter_dir"
  sleep "$INTERVAL"
  i=$((i + 1))
done

if [[ "$found" -eq 1 ]]; then
  echo "PASS: endpoint detected; run dir: $RUN_DIR"
  exit 0
fi

echo "TIMEOUT: no endpoint detected; run dir: $RUN_DIR"
exit 1
