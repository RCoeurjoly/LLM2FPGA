#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/task2d_led_selftest.sh [options]

Options:
  --bit <path>            Use a specific bitstream path.
  --programmer <cmd>      Programmer command (default: openFPGALoader).
  --skip-build            Skip nix build step.
  --skip-scan             Skip JTAG scan step.
  --skip-program          Skip programming step.
  -h, --help              Show this help.

Examples:
  scripts/task2d_led_selftest.sh
  scripts/task2d_led_selftest.sh --skip-build
  scripts/task2d_led_selftest.sh --bit /path/to/matmul-selftest.bit
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bit_path=""
programmer_cmd="openFPGALoader"
do_build=1
do_scan=1
do_program=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bit)
      bit_path="$2"
      shift 2
      ;;
    --programmer)
      programmer_cmd="$2"
      shift 2
      ;;
    --skip-build)
      do_build=0
      shift
      ;;
    --skip-scan)
      do_scan=0
      shift
      ;;
    --skip-program)
      do_program=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if (( do_build )); then
  echo "[1/4] Building self-test bitstream..."
  nix build .#matmul-selftest-bitstream -L
fi

if [[ -z "$bit_path" ]]; then
  if [[ ! -e result ]]; then
    echo "result symlink not found. Run build or pass --bit." >&2
    exit 2
  fi
  bit_path="$(readlink -f result)"
fi

if [[ ! -f "$bit_path" ]]; then
  echo "Bitstream not found: $bit_path" >&2
  exit 2
fi

echo "[2/4] Bitstream: $bit_path"

if (( do_scan || do_program )); then
  if ! command -v "$programmer_cmd" >/dev/null 2>&1; then
    echo "Programmer command not found: $programmer_cmd" >&2
    exit 2
  fi
fi

if (( do_scan )); then
  echo "[3/4] Scanning JTAG chain..."
  "$programmer_cmd" --scan-jtag
fi

if (( do_program )); then
  echo "[3/4] Programming self-test bitstream..."
  "$programmer_cmd" "$bit_path"
fi

echo "[4/4] LED self-test expectations:"
cat <<'EOF'
  led_3bits_tri_o[0]: heartbeat blink (clock/alive)
  led_3bits_tri_o[1]: PASS latched (matmul output == 816)
  led_3bits_tri_o[2]: FAIL latched (mismatch or timeout)

Reset SYS_RSTN or reprogram to re-run the single-shot self-test.
EOF
