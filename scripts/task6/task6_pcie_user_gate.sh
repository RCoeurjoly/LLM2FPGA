#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ALLOWED_BDF="${TASK6_PCIE_ALLOWED_BDF:-0000:42:00.0}"
MODE="${1:-}"
BDF="${2:-$ALLOWED_BDF}"

usage() {
  cat >&2 <<'EOF'
usage: scripts/task6/task6_pcie_user_gate.sh <bridge-rescan|lifecycle|flash|recover|bar|debug-dump|rowstream-loopback|rowstream-loader|rowstream-packet|rowstream-run|rowstream-top1|command|command-header|command-echo|command-doorbell> [0000:42:00.0] [mode args...]

Rootless Task 6 PCIe gate dispatcher. This assumes the Task 6 YPCB PCIe udev
rule has enabled PCI memory space, granted plugdev read/write access to
/sys/bus/pci/devices/<BDF>/resource0, and delegated narrowly scoped recovery
nodes for recover mode.
EOF
  exit 2
}

case "$MODE" in
  bridge-rescan|lifecycle|flash|recover|bar|debug-dump|rowstream-loopback|rowstream-loader|rowstream-packet|rowstream-run|rowstream-top1|command|command-header|command-echo|command-doorbell) ;;
  *) usage ;;
esac

if [[ "$BDF" != "$ALLOWED_BDF" ]]; then
  echo "error: refusing BDF $BDF; allowed BDF is $ALLOWED_BDF" >&2
  exit 2
fi

DEVICE="/sys/bus/pci/devices/$BDF"
RESOURCE0="$DEVICE/resource0"

if [[ "$MODE" == "bridge-rescan" ]]; then
  exec python3 "$ROOT/scripts/task6/task6_pcie_bridge_rescan.py" "${3:-0000:41:00.0}"
fi

if [[ "$MODE" == "lifecycle" ]]; then
  exec python3 "$ROOT/scripts/task6/task6_pcie_lifecycle_gate.py" "$BDF" "${@:3}"
fi

if [[ "$MODE" == "flash" ]]; then
  exec python3 "$ROOT/scripts/task6/task6_pcie_flash.py" "${@:3}"
fi

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

mapfile -t config_words < <(setpci -s "$BDF" COMMAND VENDOR_ID DEVICE_ID HEADER_TYPE 2>/dev/null || true)
if (( ${#config_words[@]} < 4 )); then
  echo "error: PCI config space is not readable for $BDF; stop BAR access and re-enumerate the chassis/host" >&2
  exit 1
fi
command_value="${config_words[0],,}"
vendor_value="${config_words[1],,}"
device_value="${config_words[2],,}"
header_value="${config_words[3],,}"
if [[ "$command_value" == "ffff" || "$vendor_value" != "10ee" || "$device_value" != "0480" || ( "$header_value" != "00" && "$header_value" != "0000" ) ]]; then
  cat >&2 <<EOF
error: refusing BAR access because PCI config is not clean for $BDF
config: COMMAND=$command_value VENDOR=$vendor_value DEVICE=$device_value HEADER=$header_value
Run the non-BAR lifecycle probe after chassis/host re-enumeration:
  scripts/task6/task6_pcie_user_gate.sh lifecycle $BDF --rescan
EOF
  exit 1
fi

if [[ ! -e "$RESOURCE0" ]]; then
  cat >&2 <<EOF
error: refusing BAR access because BAR0 is absent: $RESOURCE0
Run the non-BAR lifecycle probe after chassis/host re-enumeration:
  scripts/task6/task6_pcie_user_gate.sh lifecycle $BDF --rescan
EOF
  exit 1
fi

if [[ ! -r "$RESOURCE0" || ! -w "$RESOURCE0" ]]; then
  cat >&2 <<EOF
error: BAR0 is not readable/writable by this user: $RESOURCE0
Install/trigger the Task 6 YPCB PCIe udev rule from ~/FutureProofDotfiles/udev:
  sudo /home/roland/FutureProofDotfiles/udev/install-task6-pcie-rules.sh
EOF
  exit 1
fi

if (( (0x$command_value & 0x0002) == 0 )); then
  cat >&2 <<EOF
error: PCI memory space is disabled for $BDF (COMMAND=0x$command_value)
Install/trigger the Task 6 YPCB PCIe udev rule, then re-enumerate and rerun the non-BAR lifecycle probe first.
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
