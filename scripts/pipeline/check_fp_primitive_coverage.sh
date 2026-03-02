#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: check_fp_primitive_coverage.sh <input-sv-or-filelist> [fp-prims-sv]

Checks that every referenced circt_fp_* cell in the input SystemVerilog has a
module definition either in the input SV set itself or in the supplied (or
default) fp primitive file.
USAGE
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

input="$1"
require_file "$input"
fp_prims_default="$(cd "$SCRIPT_DIR/../.." && pwd)/rtl/fp/circt_fp_primitives.sv"
fp_prims="${2:-${FP_PRIMS_SV:-$fp_prims_default}}"

is_filelist=0
case "$input" in
  *.f|*.svf|*.lst) is_filelist=1 ;;
esac

tmp_defs="$(mktemp /tmp/ts_fp_defs_XXXXXX.txt)"
tmp_uses="$(mktemp /tmp/ts_fp_uses_XXXXXX.txt)"
cleanup() { rm -f "$tmp_defs" "$tmp_uses"; }
trap cleanup EXIT

collect_defs_uses() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  awk '
    {
      if (match($0, /^[[:space:]]*module[[:space:]]+(circt_fp_[A-Za-z0-9_]+)/, m))
        print m[1] >> "'"$tmp_defs"'";
      if (match($0, /^[[:space:]]*(circt_fp_[A-Za-z0-9_]+)[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*[[:space:]]*\(/, m))
        print m[1] >> "'"$tmp_uses"'";
      if (match($0, /^[[:space:]]*(circt_fp_[A-Za-z0-9_]+)[[:space:]]*#[[:space:]]*\(/, m))
        print m[1] >> "'"$tmp_uses"'";
    }
  ' "$f"
}

if [[ "$is_filelist" == "1" ]]; then
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line#\#}" != "$line" ]] && continue
    collect_defs_uses "$line"
  done <"$input"
else
  collect_defs_uses "$input"
fi

collect_defs_uses "$fp_prims"

sort -u -o "$tmp_defs" "$tmp_defs"
sort -u -o "$tmp_uses" "$tmp_uses"

missing=0
while IFS= read -r u; do
  [[ -z "$u" ]] && continue
  if ! grep -qx "$u" "$tmp_defs"; then
    echo "missing circt_fp module definition: $u" >&2
    missing=1
  fi
done <"$tmp_uses"

if [[ "$missing" -ne 0 ]]; then
  echo "fp primitive coverage check failed" >&2
  exit 1
fi

echo "fp primitive coverage check passed"
