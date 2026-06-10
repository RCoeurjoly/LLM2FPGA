#!/usr/bin/env bash
set -euo pipefail

ALLOWED_BDF="${TASK6_PCIE_ALLOWED_BDF:-0000:42:00.0}"
ALLOWED_BRIDGE_BDF="${TASK6_PCIE_BRIDGE_BDF:-0000:41:00.0}"
UDEV_HELPER="${TASK6_PCIE_UDEV_HELPER:-/usr/local/libexec/task6-pcie/task6-pcie-pci-permissions}"

usage() {
  cat >&2 <<'EOF'
usage: task6-pcie-safe-root-helper <doctor|udev-reload-trigger|repair-permissions> [0000:42:00.0]

Narrow root helper for Task 6 PCIe automation. It deliberately does not issue
PCIe device resets, bridge hot resets, Thunderbolt reauthorization, endpoint
remove, or global PCI rescans.
EOF
  exit 2
}

fail() {
  echo "task6-pcie-safe-root-helper: $*" >&2
  exit 1
}

[[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "must run as root"

MODE="${1:-}"
BDF="${2:-$ALLOWED_BDF}"
case "$MODE" in
  doctor|udev-reload-trigger|repair-permissions) ;;
  *) usage ;;
esac
[[ "$BDF" == "$ALLOWED_BDF" ]] || fail "refusing BDF $BDF; allowed BDF is $ALLOWED_BDF"

device_dir="/sys/bus/pci/devices/$BDF"
bridge_dir="/sys/bus/pci/devices/$ALLOWED_BRIDGE_BDF"

validate_endpoint_if_present() {
  [[ -d "$device_dir" ]] || return 0
  [[ "$(<"$device_dir/vendor")" == "0x10ee" ]] || fail "unexpected endpoint vendor"
  [[ "$(<"$device_dir/device")" == "0x0480" ]] || fail "unexpected endpoint device"
  [[ "$(<"$device_dir/subsystem_vendor")" == "0x10ee" ]] || fail "unexpected endpoint subsystem_vendor"
}

validate_bridge_if_present() {
  [[ -d "$bridge_dir" ]] || return 0
  [[ "$(<"$bridge_dir/vendor")" == "0x8086" ]] || fail "unexpected bridge vendor"
  [[ "$(<"$bridge_dir/device")" == "0x5786" ]] || fail "unexpected bridge device"
  [[ "$(<"$bridge_dir/subsystem_vendor")" == "0x2222" ]] || fail "unexpected bridge subsystem_vendor"
  [[ "$(<"$bridge_dir/subsystem_device")" == "0x1111" ]] || fail "unexpected bridge subsystem_device"
}

run_udev_triggers() {
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=pci --attr-match=vendor=0x8086 || true
  udevadm trigger --subsystem-match=pci --attr-match=vendor=0x10ee || true
  udevadm settle --timeout=10 || true
}

repair_current_endpoint() {
  validate_endpoint_if_present
  validate_bridge_if_present
  run_udev_triggers
  if [[ -d "$device_dir" && -x "$UDEV_HELPER" ]]; then
    real_path="$(readlink -f "$device_dir")"
    devpath="${real_path#/sys}"
    "$UDEV_HELPER" "$devpath" || true
  fi
}

case "$MODE" in
  doctor)
    validate_endpoint_if_present
    validate_bridge_if_present
    [[ -x "$UDEV_HELPER" ]] || fail "missing executable udev helper: $UDEV_HELPER"
    echo "safe-root-helper: ok"
    ;;
  udev-reload-trigger)
    validate_endpoint_if_present
    validate_bridge_if_present
    run_udev_triggers
    ;;
  repair-permissions)
    repair_current_endpoint
    ;;
esac
