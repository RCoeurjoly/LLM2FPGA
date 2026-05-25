#!/usr/bin/env bash
set -euo pipefail

ALLOWED_BDF="${TASK6_PCIE_ALLOWED_BDF:-0000:42:00.0}"
BRIDGE_BDF="${TASK6_PCIE_BRIDGE_BDF:-0000:41:00.0}"
UPSTREAM_BRIDGE_BDF="${TASK6_PCIE_UPSTREAM_BRIDGE_BDF:-0000:40:00.0}"
ROOT_PORT_BDF="${TASK6_PCIE_ROOT_PORT_BDF:-0000:00:07.2}"
TB_DEVICE="${TASK6_PCIE_TB_DEVICE:-1-1}"
TB_DEVICE_NAME="${TASK6_PCIE_TB_DEVICE_NAME:-Helios 5S}"
TB_UNIQUE_ID="${TASK6_PCIE_TB_UNIQUE_ID:-c4148780-0010-1ed9-ffff-ffffffffffff}"
LIBEXEC_DIR="${TASK6_PCIE_LIBEXEC_DIR:-/usr/local/libexec/task6-pcie}"

usage() {
  cat >&2 <<'EOF'
usage: task6-pcie-gate <prepare|bar|rowstream-loopback|rowstream-loader|rowstream-packet|command|command-header|command-echo|command-doorbell> [0000:42:00.0] [mode args...]

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
  prepare|bar|rowstream-loopback|rowstream-loader|rowstream-packet|command|command-header|command-echo|command-doorbell) ;;
  *) usage ;;
esac
if [[ "$BDF" != "$ALLOWED_BDF" ]]; then
  echo "error: refusing BDF $BDF; allowed BDF is $ALLOWED_BDF" >&2
  exit 2
fi

command_value() {
  setpci -s "$BDF" COMMAND
}

reset_subordinate_bus() {
  local bridge_bdf reset_file
  bridge_bdf="$1"
  reset_file="/sys/bus/pci/devices/$bridge_bdf/reset_subordinate"
  if [[ -e "$reset_file" ]]; then
    echo "kernel-resetting subordinate bus below $bridge_bdf"
    echo 1 >"$reset_file"
    sleep 3
    return 0
  fi
  return 1
}

reset_pci_device() {
  local dev_bdf reset_file
  dev_bdf="$1"
  reset_file="/sys/bus/pci/devices/$dev_bdf/reset"
  if [[ -e "$reset_file" ]]; then
    echo "kernel-resetting PCI device $dev_bdf"
    echo 1 >"$reset_file"
    sleep 3
    return 0
  fi
  return 1
}

hot_reset_bridge() {
  local bridge_bdf before asserted restored
  bridge_bdf="$1"
  echo "hot-resetting downstream bridge $bridge_bdf"
  before="$(setpci -s "$bridge_bdf" BRIDGE_CONTROL)"
  asserted="$(printf "%04x" "$((0x$before | 0x0040))")"
  setpci -s "$bridge_bdf" "BRIDGE_CONTROL=$asserted"
  sleep 2
  restored="$(printf "%04x" "$((0x$before & ~0x0040))")"
  setpci -s "$bridge_bdf" "BRIDGE_CONTROL=$restored"
  sleep 3
}

rescan_pci() {
  echo "rescanning PCI bus"
  echo 1 >/sys/bus/pci/rescan
}

thunderbolt_reauthorize() {
  local dev_dir auth name uuid
  dev_dir="/sys/bus/thunderbolt/devices/$TB_DEVICE"
  auth="$dev_dir/authorized"
  if [[ ! -e "$auth" ]]; then
    return 1
  fi
  name="$(cat "$dev_dir/device_name" 2>/dev/null || true)"
  uuid="$(cat "$dev_dir/unique_id" 2>/dev/null || true)"
  if [[ "$name" != "$TB_DEVICE_NAME" || "$uuid" != "$TB_UNIQUE_ID" ]]; then
    echo "refusing Thunderbolt reauthorize for $TB_DEVICE: name='$name' uuid='$uuid'" >&2
    return 1
  fi
  echo "reauthorizing Thunderbolt device $TB_DEVICE ($name)"
  echo 0 >"$auth"
  sleep 5
  echo 1 >"$auth"
  sleep 8
}

reset_bridge_for_recovery() {
  local step
  for step in     "subordinate:$BRIDGE_BDF"     "device:$BRIDGE_BDF"     "hot:$BRIDGE_BDF"     "subordinate:$UPSTREAM_BRIDGE_BDF"     "device:$UPSTREAM_BRIDGE_BDF"     "subordinate:$ROOT_PORT_BDF"     "thunderbolt:$TB_DEVICE"; do
    case "$step" in
      subordinate:*) reset_subordinate_bus "${step#subordinate:}" || continue ;;
      device:*) reset_pci_device "${step#device:}" || continue ;;
      hot:*) hot_reset_bridge "${step#hot:}" || continue ;;
      thunderbolt:*) thunderbolt_reauthorize || continue ;;
    esac
    rescan_pci
    if wait_for_endpoint; then
      return 0
    fi
  done
  return 1
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
  rescan_pci
  if ! wait_for_endpoint; then
    reset_bridge_for_recovery || exit 1
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
  rowstream-loopback)
    exec python3 "$LIBEXEC_DIR/task6_pcie_rowstream_loopback_smoke.py" "$BDF"
    ;;
  rowstream-loader)
    exec python3 "$LIBEXEC_DIR/task6_pcie_rowstream_loader_smoke.py" "$BDF"
    ;;
  rowstream-packet)
    exec python3 "$LIBEXEC_DIR/task6_pcie_rowstream_packet_loader.py" "$BDF" "${@:3}"
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
