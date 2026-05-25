#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/task6/task6_pcie_bringup_probe.sh [--run-dir DIR] [--port-bdf BDF] [--endpoint-bdf BDF]

Capture the host-side PCIe/Thunderbolt evidence needed for the YPCB + OWC
Helios bring-up gate. Only unprivileged commands are used; dmesg is replaced with best-effort
journalctl kernel capture when available.

Defaults:
  --run-dir       artifacts/task6/runs/<timestamp>-pcie-bringup-probe
  --port-bdf      0000:41:00.0
  --endpoint-bdf  unset; when provided, also run BAR smoke
EOF
}

RUN_DIR=""
PORT_BDF="0000:41:00.0"
ENDPOINT_BDF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="${2:?missing value for --run-dir}"
      shift 2
      ;;
    --port-bdf)
      PORT_BDF="${2:?missing value for --port-bdf}"
      shift 2
      ;;
    --endpoint-bdf)
      ENDPOINT_BDF="${2:?missing value for --endpoint-bdf}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$RUN_DIR" ]]; then
  TS="$(date +%Y-%m-%dT%H-%M-%S%z)"
  RUN_DIR="artifacts/task6/runs/${TS}-pcie-bringup-probe"
fi

mkdir -p "$RUN_DIR"

run_capture() {
  local name="$1"
  shift
  local log="${RUN_DIR}/${name}.log"
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

run_capture "boltctl" boltctl
run_capture "lspci-Dnn" lspci -Dnn
run_capture "lspci-tv" lspci -tv
run_capture "lspci-port-vvv" lspci -vvv -s "$PORT_BDF"
run_capture "kernel-log" timeout 10 journalctl -k -b --no-pager -n 500

if command -v rg >/dev/null 2>&1; then
  rg -i '42:00|41:00|aer|pcie|completion|timeout|link|hotplug' \
    "${RUN_DIR}/kernel-log.log" \
    >"${RUN_DIR}/kernel-log-filtered.log" || true
else
  grep -Ei '42:00|41:00|aer|pcie|completion|timeout|link|hotplug' \
    "${RUN_DIR}/kernel-log.log" \
    >"${RUN_DIR}/kernel-log-filtered.log" || true
fi

if [[ -n "$ENDPOINT_BDF" ]]; then
  run_capture "bar-smoke" scripts/task6/task6_pcie_bar_smoke.sh "$ENDPOINT_BDF"
fi

cat >"${RUN_DIR}/README.md" <<EOF
# PCIe Bring-Up Probe

- port BDF: \`${PORT_BDF}\`
- endpoint BDF: \`${ENDPOINT_BDF:-not provided}\`
- capture time: \`$(date -Iseconds)\`

Inspect:

- \`boltctl.log\`
- \`lspci-Dnn.log\`
- \`lspci-tv.log\`
- \`lspci-port-vvv.log\`
- \`dmesg-pcie-filtered.log\`
- \`bar-smoke.log\` when an endpoint BDF was provided

Gate interpretation:

- Endpoint present in \`lspci -Dnn\`: proceed to BAR smoke.
- Port has \`PresDet+\` and trained link but no endpoint: focus on endpoint config-space/TLP behavior.
- No presence or no link: focus on reset, refclk, lane pins, chassis slot behavior, and flash boot state.
EOF

echo "$RUN_DIR"
