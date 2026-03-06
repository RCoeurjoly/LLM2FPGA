#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: check_no_sv_blackboxes.sh <input-sv-or-filelist>

Fails if any SystemVerilog source contains `(* blackbox *)`.
USAGE
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

input="$1"
require_file "$input"

if [[ "${ALLOW_SV_BLACKBOXES:-0}" == "1" ]]; then
  echo "[check_no_sv_blackboxes] ALLOW_SV_BLACKBOXES=1 set; skipping check." >&2
  exit 0
fi

is_filelist=0
case "$input" in
  *.f|*.svf|*.lst) is_filelist=1 ;;
esac

tmp_files="$(mktemp /tmp/no_sv_blackboxes_files_XXXXXX.txt)"
cleanup() { rm -f "$tmp_files"; }
trap cleanup EXIT

if [[ "$is_filelist" == "1" ]]; then
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line#\#}" != "$line" ]] && continue
    [[ -f "$line" ]] || continue
    printf '%s\n' "$line" >>"$tmp_files"
  done <"$input"
else
  printf '%s\n' "$input" >"$tmp_files"
fi

if [[ ! -s "$tmp_files" ]]; then
  echo "[check_no_sv_blackboxes] ERROR: no SV files found to check." >&2
  exit 1
fi

if rg -n '\(\*\s*blackbox\s*\*\)' $(cat "$tmp_files") >/dev/null; then
  echo "[check_no_sv_blackboxes] ERROR: blackbox attributes found in SV." >&2
  rg -n '\(\*\s*blackbox\s*\*\)' $(cat "$tmp_files") | sed -n '1,80p' >&2
  exit 1
fi

echo "[check_no_sv_blackboxes] passed: no blackbox attributes found."
