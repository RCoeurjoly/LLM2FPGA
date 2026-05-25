#!/usr/bin/env bash
set -euo pipefail

BDF="${1:-}"
PCIMEM="${PCIMEM:-pcimem}"

if [[ -z "$BDF" ]]; then
  echo "usage: $0 <pci-bdf>" >&2
  echo "example: $0 26:00.0" >&2
  exit 2
fi

lspci -s "$BDF"
setpci -s "$BDF" COMMAND=0x02

echo "BAR0 read, first 4 KiB:"
"$PCIMEM" -d "$BDF" -a 0x0000 -s 4096 -R 0 -r | hexdump -C | sed -n '1,20p'

echo "BAR0 write/readback smoke:"
printf 'abcdefgh' | "$PCIMEM" -d "$BDF" -a 0x0000 -s 8 -R 0 -w >/dev/null
"$PCIMEM" -d "$BDF" -a 0x0000 -s 64 -R 0 -r | hexdump -C | sed -n '1,8p'
