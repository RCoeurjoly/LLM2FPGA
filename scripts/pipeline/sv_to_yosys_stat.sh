#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

yosys="${1:?usage: sv_to_yosys_stat.sh <yosys> <yosys-slang-so> <input-filelist> <output-json>}"
yosys_slang_so="${2:?usage: sv_to_yosys_stat.sh <yosys> <yosys-slang-so> <input-filelist> <output-json>}"
input="${3:?usage: sv_to_yosys_stat.sh <yosys> <yosys-slang-so> <input-filelist> <output-json>}"
output="${4:?usage: sv_to_yosys_stat.sh <yosys> <yosys-slang-so> <input-filelist> <output-json>}"
require_executable "$yosys"
require_file "$yosys_slang_so"
require_file "$input"

tmp_ys="$(mktemp /tmp/ts_yosys_stat_XXXXXX.ys)"
tmp_stat="$(mktemp /tmp/ts_yosys_stat_raw_XXXXXX.json)"
tmp_inventory="$(mktemp /tmp/ts_yosys_mem_inventory_XXXXXX.json)"
trap 'rm -f "$tmp_ys" "$tmp_stat" "$tmp_inventory"' EXIT

python3 "$SCRIPT_DIR/sv_memory_inventory.py" \
  --input-filelist "$input" \
  --output "$tmp_inventory"

write_yosys_slang_script "$tmp_ys" "$yosys_slang_so" "$input"

cat >>"$tmp_ys" <<EOS
hierarchy -check -top main
tee -o $tmp_stat stat -json
EOS

set +e
run_yosys_script "sv_to_yosys_stat" "$yosys" "$input" "Yosys stat" -s "$tmp_ys"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  python3 "$SCRIPT_DIR/write_yosys_stat_report.py" \
    --output "$output" \
    --status ok \
    --input-filelist "$input" \
    --memory-inventory "$tmp_inventory" \
    --raw-yosys-json "$tmp_stat" \
    --top main
  exit 0
fi

if [[ "$rc" -eq 137 || "$rc" -eq 9 ]]; then
  python3 "$SCRIPT_DIR/write_yosys_stat_report.py" \
    --output "$output" \
    --status oom-bottleneck \
    --input-filelist "$input" \
    --memory-inventory "$tmp_inventory" \
    --exit-code "$rc" \
    --top main
  exit 0
fi

exit "$rc"
