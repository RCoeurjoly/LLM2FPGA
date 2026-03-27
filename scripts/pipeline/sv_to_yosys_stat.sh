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
trap 'rm -f "$tmp_ys"' EXIT

write_yosys_slang_script "$tmp_ys" "$yosys_slang_so" "$input"

cat >>"$tmp_ys" <<EOS
hierarchy -check -top main
tee -o $output stat -json
EOS

run_yosys_script "sv_to_yosys_stat" "$yosys" "$input" "Yosys stat" -s "$tmp_ys"
