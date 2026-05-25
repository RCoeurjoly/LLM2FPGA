#!/usr/bin/env bash
set -euo pipefail

BDF="${1:-0000:42:00.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVICE="/sys/bus/pci/devices/$BDF"

echo "Task 6 PCIe command bridge rescan/BAR gate for $BDF"
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "error: this gate requires root for PCI remove/rescan and BAR MMIO" >&2
  echo "usage: sudo $0 [$BDF]" >&2
  exit 2
fi

if [[ -e "$DEVICE/remove" ]]; then
  echo "removing existing/stale $BDF"
  echo 1 >"$DEVICE/remove"
else
  echo "no existing $BDF device to remove"
fi

sleep 1
echo "rescanning PCI bus"
echo 1 >/sys/bus/pci/rescan

endpoint=""
for _ in $(seq 1 20); do
  if lspci -Dnn -s "$BDF" >/tmp/task6-pcie-command-rescan-lspci.$$ 2>&1; then
    if [[ -s /tmp/task6-pcie-command-rescan-lspci.$$ ]]; then
      detail="$(lspci -vv -s "$BDF" 2>&1 || true)"
      if grep -qi 'Unknown header type 7f' <<<"$detail"; then
        echo "found $BDF but config header is invalid/stale; waiting"
      else
        endpoint="$(cat /tmp/task6-pcie-command-rescan-lspci.$$)"
        break
      fi
    fi
  fi
  sleep 1
done
rm -f /tmp/task6-pcie-command-rescan-lspci.$$

if [[ -z "$endpoint" ]]; then
  echo "FAIL: no valid endpoint at $BDF after remove/rescan"
  lspci -Dnn -s "$BDF" || true
  lspci -vv -s "$BDF" || true
  exit 1
fi

echo "endpoint: $endpoint"
lspci -vv -s "$BDF"
exec "$ROOT/scripts/task6/task6_pcie_command_bridge_smoke.py" "$BDF"
