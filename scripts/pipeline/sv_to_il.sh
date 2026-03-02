#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env YOSYS
input="${1:?usage: sv_to_il.sh <input-sv-or-filelist> <output-il>}"
output="${2:?usage: sv_to_il.sh <input-sv-or-filelist> <output-il>}"
require_file "$input"

fp_prims_default="$(cd "$SCRIPT_DIR/../.." && pwd)/rtl/fp/circt_fp_primitives.sv"
light_mode="${YOSYS_LIGHT_MODE:-0}"

resolve_fp_prims() {
  local in="$1"
  local candidate=""
  if [[ -n "${FP_PRIMS_SV:-}" ]]; then
    echo "$FP_PRIMS_SV"
    return
  fi
  # Prefer an auto-generated per-run stub file colocated with pipeline output.
  if [[ "$in" == *.f || "$in" == *.svf || "$in" == *.lst ]]; then
    candidate="$(dirname "$in")/09-fp-prims-auto.sv"
  else
    candidate="$(dirname "$in")/09-fp-prims-auto.sv"
  fi
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return
  fi
  echo "$fp_prims_default"
}

fp_prims="$(resolve_fp_prims "$input")"

is_filelist=0
case "$input" in
  *.f|*.svf|*.lst) is_filelist=1 ;;
esac

tmp_ys="$(mktemp /tmp/ts_yosys_il_XXXXXX.ys)"
cleanup() { rm -f "$tmp_ys"; }
trap cleanup EXIT

reader_cmd="read_verilog -sv"
if [[ -n "${YOSYS_SLANG_SO:-}" ]]; then
  if [[ ! -f "${YOSYS_SLANG_SO}" ]]; then
    echo "YOSYS_SLANG_SO points to missing file: ${YOSYS_SLANG_SO}" >&2
    exit 2
  fi
  echo "plugin -i ${YOSYS_SLANG_SO}" >>"$tmp_ys"
  reader_cmd="read_slang"
fi

if [[ -f "$fp_prims" ]]; then
  echo "$reader_cmd $fp_prims" >>"$tmp_ys"
fi

if [[ "$is_filelist" == "1" ]]; then
  while IFS= read -r line; do
    # Skip blank lines and comments.
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line#\#}" != "$line" ]] && continue
    echo "$reader_cmd $line" >>"$tmp_ys"
  done <"$input"
else
  echo "$reader_cmd $input" >>"$tmp_ys"
fi

if [[ "$light_mode" == "1" ]]; then
  cat >>"$tmp_ys" <<EOS
hierarchy -check -top main
stat
write_rtlil $output
EOS
else
  cat >>"$tmp_ys" <<EOS
proc
opt
techmap
opt
stat
write_rtlil $output
EOS
fi

"$YOSYS" -s "$tmp_ys"
