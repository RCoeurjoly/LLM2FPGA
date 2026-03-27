#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

yosys="${1:?usage: sv_to_il.sh <yosys> <yosys-slang-so> <input-filelist> <output-il>}"
yosys_slang_so="${2:?usage: sv_to_il.sh <yosys> <yosys-slang-so> <input-filelist> <output-il>}"
input="${3:?usage: sv_to_il.sh <yosys> <yosys-slang-so> <input-filelist> <output-il>}"
output="${4:?usage: sv_to_il.sh <yosys> <yosys-slang-so> <input-filelist> <output-il>}"
require_executable "$yosys"
require_file "$yosys_slang_so"
require_file "$input"

tmp_ys="$(mktemp /tmp/ts_yosys_il_XXXXXX.ys)"
trap 'rm -f "$tmp_ys"' EXIT

write_yosys_slang_script "$tmp_ys" "$yosys_slang_so" "$input"

cat >>"$tmp_ys" <<EOS
hierarchy -check -top main
stat
write_rtlil $output
EOS

run_yosys_script "sv_to_il" "$yosys" "$input" "SV->IL" -s "$tmp_ys"
