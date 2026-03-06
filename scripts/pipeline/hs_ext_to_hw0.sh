#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_env CIRCT_OPT
input="${1:?usage: hs_ext_to_hw0.sh <input-hs-ext-mlir> <output-hw0-mlir>}"
output="${2:?usage: hs_ext_to_hw0.sh <input-hs-ext-mlir> <output-hw0-mlir>}"
require_file "$input"

tmp_legalized="$(mktemp /tmp/hs_ext_to_hw0_legalized_XXXXXX.mlir)"
cleanup_tmp() {
  rm -f "$tmp_legalized"
}
trap cleanup_tmp EXIT

# CIRCT's handshake->hw conversion rejects integer-to-float casts. Torch
# exports one mask idiom as i1 -> f32 cast followed by mul; rewrite it into an
# equivalent float select form while preserving one-use Handshake invariants.
perl -0777 -pe 'BEGIN { $i = 0; } s{^(\s*)(%[[:alnum:]_.-]+) = arith\.uitofp (%[[:alnum:]_.-]+) : i1 to (f[0-9]+)\n\1(%[[:alnum:]_.-]+) = buffer \[2\] seq \2 : \4\n\1(%[[:alnum:]_.-]+) = arith\.mulf (%[[:alnum:]_.-]+), \5 : \4\n\1(%[[:alnum:]_.-]+) = buffer \[2\] seq \6 : \4$}{ my ($ind,$cast,$pred,$ty,$buf_cast,$mul,$lhs,$buf_mul)=($1,$2,$3,$4,$5,$6,$7,$8); my $fork="%uifp_fix".(++$i)."_f"; "${ind}${fork}:3 = fork [3] ${lhs} : ${ty}\n${ind}${cast} = arith.subf ${fork}#0, ${fork}#1 : ${ty}\n${ind}${buf_cast} = arith.select ${pred}, ${fork}#2, ${cast} : ${ty}\n${ind}${mul} = buffer [2] seq ${buf_cast} : ${ty}\n${ind}${buf_mul} = buffer [2] seq ${mul} : ${ty}" }mge' "$input" > "$tmp_legalized"

run_to_output "$output" "$CIRCT_OPT" "$tmp_legalized" \
  -lower-handshake-to-hw \
  -canonicalize
