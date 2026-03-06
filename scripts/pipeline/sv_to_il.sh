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

is_filelist=0
case "$input" in
  *.f|*.svf|*.lst) is_filelist=1 ;;
esac

light_mode="${YOSYS_LIGHT_MODE:-}"
input_bytes=""

if [[ "$input" == *.sv ]] && [[ -f "$input" ]]; then
  input_bytes="$(wc -c <"$input")"
fi

if [[ -z "$light_mode" ]]; then
  light_mode=0
  # Very large monolithic SV files can OOM in full proc/techmap flow.
  if [[ -n "$input_bytes" ]]; then
    if [[ "$input_bytes" -gt 50000000 ]]; then
      light_mode=1
    fi
  fi
  # Filelist-driven flows are used for very large designs and should stay in
  # lightweight mode by default.
  if [[ "$is_filelist" == "1" ]]; then
    light_mode=1
  fi
fi

# Large generated SV can still OOM inside read_slang; use safer defaults unless
# explicitly overridden via YOSYS_SLANG_ARGS.
slang_args="${YOSYS_SLANG_ARGS:-}"
if [[ -z "$slang_args" ]]; then
  if [[ -n "$input_bytes" ]] && [[ "$input_bytes" -gt 50000000 ]]; then
    slang_args="--threads 1 --no-proc --disable-instance-caching"
  fi
  if [[ "$is_filelist" == "1" ]]; then
    slang_args="--threads 1 --no-proc --disable-instance-caching"
  fi
fi

fp_prims=""
if [[ -n "${FP_PRIMS_SV:-}" ]]; then
  if [[ ! -f "${FP_PRIMS_SV}" ]]; then
    echo "FP_PRIMS_SV points to missing file: ${FP_PRIMS_SV}" >&2
    exit 2
  fi
  fp_prims="${FP_PRIMS_SV}"
fi

tmp_ys="$(mktemp /tmp/ts_yosys_il_XXXXXX.ys)"
cleanup() {
  rm -f "$tmp_ys"
}
trap cleanup EXIT

reader_cmd="read_verilog -sv"
if [[ -n "${YOSYS_SLANG_SO:-}" ]]; then
  if [[ ! -f "${YOSYS_SLANG_SO}" ]]; then
    echo "YOSYS_SLANG_SO points to missing file: ${YOSYS_SLANG_SO}" >&2
    exit 2
  fi
  echo "plugin -i ${YOSYS_SLANG_SO}" >>"$tmp_ys"
  reader_cmd="read_slang${slang_args:+ ${slang_args}}"
fi

if [[ "$reader_cmd" == read_slang* ]] && [[ -n "$slang_args" ]]; then
  echo "[sv_to_il] Using read_slang args: $slang_args" >&2
fi

if [[ -n "$fp_prims" ]]; then
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
hierarchy -check -top main
proc
opt
techmap
opt
stat
write_rtlil $output
EOS
fi

set +e
"$YOSYS" -s "$tmp_ys"
rc=$?
set -e

if [[ "$rc" -eq 137 || "$rc" -eq 9 ]]; then
  size_note="unknown"
  if [[ -n "$input_bytes" ]]; then
    size_note="$input_bytes bytes"
  fi
  echo "[sv_to_il] ERROR: Yosys was killed while processing '$input' (exit code $rc)." >&2
  echo "[sv_to_il] This is usually an out-of-memory condition. Input size: $size_note." >&2
  echo "[sv_to_il] Try a host with more RAM, or reduce model complexity before SV->IL." >&2
  echo "[sv_to_il] Note: weight-int8-dequant does not remove float compute, so SV may remain very large." >&2
fi

exit "$rc"
