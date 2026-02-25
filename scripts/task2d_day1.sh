#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/task2d_day1.sh [options]

Options:
  --bit <path>            Use a specific bitstream path.
  --got <value>           Observed hardware output (decimal or 0x...).
  --got-json <path>       JSON file containing observed output value.
  --got-key <key>         Key in --got-json (default: got).
  --programmer <cmd>      Programmer command (default: openFPGALoader).
  --skip-build            Skip nix build step.
  --skip-scan             Skip JTAG scan step.
  --skip-program          Skip programming step.
  -h, --help              Show this help.

Examples:
  scripts/task2d_day1.sh --got 816
  scripts/task2d_day1.sh --got-json sim/hw_result.json
  scripts/task2d_day1.sh --skip-build --skip-scan --skip-program --got 816
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bit_path=""
got_value=""
got_json=""
got_key="got"
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
    --got)
      got_value="$2"
      shift 2
      ;;
    --got-json)
      got_json="$2"
      shift 2
      ;;
    --got-key)
      got_key="$2"
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

if [[ -n "$got_value" && -n "$got_json" ]]; then
  echo "Use only one of --got or --got-json." >&2
  exit 2
fi

if (( do_build )); then
  echo "[1/4] Building bitstream..."
  nix build .#matmul-bitstream -L
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
  echo "[3/4] Programming bitstream..."
  "$programmer_cmd" "$bit_path"
fi

echo "[4/4] Comparing hardware output against Task-2 golden..."
if [[ -n "$got_value" ]]; then
  python3 sim/check_hw_result.py --got "$got_value"
elif [[ -n "$got_json" ]]; then
  python3 sim/check_hw_result.py --got-json "$got_json" --got-key "$got_key"
else
  python3 sim/check_hw_result.py --print-expected
  cat <<'EOF'
No observed output provided.
Re-run with one of:
  --got <value>
  --got-json sim/hw_result.json
EOF
fi
