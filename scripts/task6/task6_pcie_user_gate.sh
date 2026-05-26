#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ALLOWED_BDF="${TASK6_PCIE_ALLOWED_BDF:-0000:42:00.0}"
MODE="${1:-}"
BDF="${2:-$ALLOWED_BDF}"

usage() {
  cat >&2 <<'EOF'
usage: scripts/task6/task6_pcie_user_gate.sh <recover|bar|debug-dump|rowstream-loopback|rowstream-loader|rowstream-packet|rowstream-run|rowstream-top1|command|command-header|command-echo|command-doorbell> [0000:42:00.0] [mode args...]

Rootless Task 6 PCIe gate dispatcher. This assumes the Task 6 YPCB PCIe udev
rule has enabled PCI memory space, granted plugdev read/write access to
/sys/bus/pci/devices/<BDF>/resource0, and delegated narrowly scoped recovery
nodes for recover mode.
EOF
  exit 2
}

case "$MODE" in
  recover|bar|debug-dump|rowstream-loopback|rowstream-loader|rowstream-packet|rowstream-run|rowstream-top1|command|command-header|command-echo|command-doorbell) ;;
  *) usage ;;
esac

if [[ "$BDF" != "$ALLOWED_BDF" ]]; then
  echo "error: refusing BDF $BDF; allowed BDF is $ALLOWED_BDF" >&2
  exit 2
fi

DEVICE="/sys/bus/pci/devices/$BDF"
RESOURCE0="$DEVICE/resource0"

if [[ ! -d "$DEVICE" ]]; then
  echo "error: missing PCI endpoint $BDF; rootless gate does not rescan/recover PCIe" >&2
  exit 1
fi

endpoint="$(lspci -Dnn -s "$BDF" || true)"
if [[ -z "$endpoint" ]]; then
  echo "error: no lspci endpoint for $BDF; rootless gate does not rescan/recover PCIe" >&2
  exit 1
fi
if ! grep -q '\[10ee:0480\]' <<<"$endpoint"; then
  echo "error: endpoint is not the expected Xilinx 10ee:0480 device: $endpoint" >&2
  exit 1
fi

if [[ "$MODE" == "recover" ]]; then
  exec python3 "$ROOT/scripts/task6/task6_pcie_recover.py" "$BDF" "${@:3}"
fi

if [[ ! -r "$RESOURCE0" || ! -w "$RESOURCE0" ]]; then
  cat >&2 <<EOF
error: BAR0 is not readable/writable by this user: $RESOURCE0
Install/trigger the Task 6 YPCB PCIe udev rule from ~/FutureProofDotfiles/udev:
  sudo /home/roland/FutureProofDotfiles/udev/install-task6-pcie-rules.sh
EOF
  exit 1
fi

command_value="$(setpci -s "$BDF" COMMAND)"
if (( (0x$command_value & 0x0002) == 0 )); then
  cat >&2 <<EOF
error: PCI memory space is disabled for $BDF (COMMAND=0x$command_value)
Install/trigger the Task 6 YPCB PCIe udev rule from ~/FutureProofDotfiles/udev:
  sudo /home/roland/FutureProofDotfiles/udev/install-task6-pcie-rules.sh
EOF
  exit 1
fi

export TASK6_REPO_ROOT="${TASK6_REPO_ROOT:-$ROOT}"

case "$MODE" in
  bar) exec python3 "$ROOT/scripts/task6/task6_pcie_bar_smoke.py" "$BDF" "${@:3}" ;;
  debug-dump) exec python3 "$ROOT/scripts/task6/task6_pcie_debug_dump.py" "$BDF" "${@:3}" ;;
  rowstream-loopback) exec python3 "$ROOT/scripts/task6/task6_pcie_rowstream_loopback_smoke.py" "$BDF" "${@:3}" ;;
  rowstream-loader) exec python3 "$ROOT/scripts/task6/task6_pcie_rowstream_loader_smoke.py" "$BDF" "${@:3}" ;;
  rowstream-packet) exec python3 "$ROOT/scripts/task6/task6_pcie_rowstream_packet_loader.py" "$BDF" "${@:3}" ;;
  rowstream-run) exec python3 "$ROOT/scripts/task6/task6_pcie_rowstream_run_gate.py" "$BDF" "${@:3}" ;;
  rowstream-top1) exec python3 "$ROOT/scripts/task6/task6_pcie_rowstream_top1_gate.py" "$BDF" "${@:3}" ;;
  command-header) exec python3 "$ROOT/scripts/task6/task6_pcie_command_bridge_smoke.py" "$BDF" --stage header ;;
  command-echo) exec python3 "$ROOT/scripts/task6/task6_pcie_command_bridge_smoke.py" "$BDF" --stage echo ;;
  command-doorbell) exec python3 "$ROOT/scripts/task6/task6_pcie_command_bridge_smoke.py" "$BDF" --stage doorbell ;;
  command) exec python3 "$ROOT/scripts/task6/task6_pcie_command_bridge_smoke.py" "$BDF" --stage full ;;
esac
