#!/usr/bin/env bash
set -euo pipefail

ALLOWED_BDF="${TASK6_PCIE_ALLOWED_BDF:-0000:42:00.0}"
BRIDGE_BDF="${TASK6_PCIE_BRIDGE_BDF:-0000:41:00.0}"
LIBEXEC_DIR="${TASK6_PCIE_LIBEXEC_DIR:-/usr/local/libexec/task6-pcie}"

usage() {
  cat >&2 <<'EOF'
usage: task6-pcie-gate <prepare|bar|command|command-header|command-echo|command-doorbell> [0000:42:00.0]

Install this file root-owned as /usr/local/sbin/task6-pcie-gate when enabling
hands-free PCIe gates. It accepts only the configured YPCB endpoint BDF.
EOF
  exit 2
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "error: task6-pcie-gate must run as root" >&2
  exit 2
fi

MODE="${1:-}"
BDF="${2:-$ALLOWED_BDF}"
case "$MODE" in
  prepare|bar|command|command-header|command-echo|command-doorbell) ;;
  *) usage ;;
esac
if [[ "$BDF" != "$ALLOWED_BDF" ]]; then
  echo "error: refusing BDF $BDF; allowed BDF is $ALLOWED_BDF" >&2
  exit 2
fi

command_value() {
  setpci -s "$BDF" COMMAND
}

hot_reset_bridge() {
  local before asserted restored
  echo "hot-resetting downstream bridge $BRIDGE_BDF"
  before="$(setpci -s "$BRIDGE_BDF" BRIDGE_CONTROL)"
  asserted="$(printf "%04x" "$((0x$before | 0x0040))")"
  setpci -s "$BRIDGE_BDF" "BRIDGE_CONTROL=$asserted"
  sleep 1
  restored="$(printf "%04x" "$((0x$before & ~0x0040))")"
  setpci -s "$BRIDGE_BDF" "BRIDGE_CONTROL=$restored"
  sleep 2
}

dump_failure_context() {
  lspci -Dnn -s "$BDF" || true
  lspci -vv -s "$BDF" || true
  echo "PCI tree:"
  lspci -Dtv || true
  echo "Bridge detail:"
  lspci -Dnnvvv -s "$BRIDGE_BDF" || true
}

enable_memory_space() {
  local before desired after enable
  before="$(command_value)"
  desired="$(printf "%04x" "$((0x$before | 0x0002))")"
  setpci -s "$BDF" "COMMAND=$desired" 2>/dev/null || true
  after="$(command_value)"
  if (( (0x$after & 0x0002) == 0 )); then
    enable="/sys/bus/pci/devices/$BDF/enable"
    if [[ -e "$enable" ]]; then
      echo 1 >"$enable" || true
    fi
  fi
  after="$(command_value)"
  if (( (0x$after & 0x0002) == 0 )); then
    echo "error: PCI memory space did not enable; COMMAND before=0x$before after=0x$after" >&2
    exit 1
  fi
}

wait_for_endpoint() {
  local tmp detail endpoint
  tmp="/tmp/task6-pcie-gate-lspci.$$"
  endpoint=""
  for _ in $(seq 1 20); do
    if lspci -Dnn -s "$BDF" >"$tmp" 2>&1 && [[ -s "$tmp" ]]; then
      detail="$(lspci -vv -s "$BDF" 2>&1 || true)"
      if grep -qi 'Unknown header type 7f' <<<"$detail"; then
        echo "found $BDF but config header is invalid/stale; waiting"
      else
        endpoint="$(cat "$tmp")"
        break
      fi
    fi
    sleep 1
  done
  rm -f "$tmp"

  if [[ -z "$endpoint" ]]; then
    echo "FAIL: no valid endpoint at $BDF after remove/rescan"
    dump_failure_context
    return 1
  fi
  if ! grep -q '\[10ee:0480\]' <<<"$endpoint"; then
    echo "error: endpoint is not the expected Xilinx 10ee:0480 device: $endpoint" >&2
    exit 1
  fi

  echo "endpoint: $endpoint"
  lspci -vv -s "$BDF"
}

prepare_endpoint() {
  local device
  device="/sys/bus/pci/devices/$BDF"
  echo "Task 6 PCIe privileged prepare for $BDF"
  if [[ -e "$device/remove" ]]; then
    echo "removing existing/stale $BDF"
    echo 1 >"$device/remove"
  else
    echo "no existing $BDF device to remove"
  fi
  sleep 1
  echo "rescanning PCI bus"
  echo 1 >/sys/bus/pci/rescan
  if ! wait_for_endpoint; then
    hot_reset_bridge
    echo "rescanning PCI bus after bridge hot reset"
    echo 1 >/sys/bus/pci/rescan
    wait_for_endpoint || exit 1
  fi
  enable_memory_space
}

prepare_endpoint
case "$MODE" in
  prepare)
    ;;
  bar)
    exec python3 "$LIBEXEC_DIR/task6_pcie_bar_smoke.py" "$BDF"
    ;;
  command-header)
    exec python3 "$LIBEXEC_DIR/task6_pcie_command_bridge_smoke.py" "$BDF" --stage header
    ;;
  command-echo)
    exec python3 "$LIBEXEC_DIR/task6_pcie_command_bridge_smoke.py" "$BDF" --stage echo
    ;;
  command-doorbell)
    exec python3 "$LIBEXEC_DIR/task6_pcie_command_bridge_smoke.py" "$BDF" --stage doorbell
    ;;
  command)
    exec python3 "$LIBEXEC_DIR/task6_pcie_command_bridge_smoke.py" "$BDF" --stage full
    ;;
esac
