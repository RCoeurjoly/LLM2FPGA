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
light_mode="${YOSYS_LIGHT_MODE:-}"
fp_auto_tmp=""

if [[ -z "$light_mode" ]]; then
  light_mode=0
  # Very large monolithic SV files can OOM in full proc/techmap flow.
  if [[ "$input" == *.sv ]] && [[ -f "$input" ]]; then
    if [[ "$(wc -c <"$input")" -gt 50000000 ]]; then
      light_mode=1
    fi
  fi
fi

emit_builtin_fp_prims() {
  cat <<'EOS'
(* blackbox *)
module arith_addf_in_f32_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic [31:0] in1, input logic in1_valid,
  input  logic out0_ready,
  output logic in0_ready, output logic in1_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module arith_divf_in_f32_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic [31:0] in1, input logic in1_valid,
  input  logic out0_ready,
  output logic in0_ready, output logic in1_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module arith_maximumf_in_f32_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic [31:0] in1, input logic in1_valid,
  input  logic out0_ready,
  output logic in0_ready, output logic in1_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module arith_mulf_in_f32_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic [31:0] in1, input logic in1_valid,
  input  logic out0_ready,
  output logic in0_ready, output logic in1_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module arith_subf_in_f32_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic [31:0] in1, input logic in1_valid,
  input  logic out0_ready,
  output logic in0_ready, output logic in1_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module arith_cmpf_in_f32_f32_out_ui1_ogt (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic [31:0] in1, input logic in1_valid,
  input  logic out0_ready,
  output logic in0_ready, output logic in1_ready,
  output logic out0, output logic out0_valid
); endmodule

(* blackbox *)
module arith_truncf_in_f64_out_f32 (
  input  logic [63:0] in0, input logic in0_valid,
  input  logic out0_ready,
  output logic in0_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module math_exp_in_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic out0_ready,
  output logic in0_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module math_rsqrt_in_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic out0_ready,
  output logic in0_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module math_tanh_in_f32_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic out0_ready,
  output logic in0_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule

(* blackbox *)
module math_fpowi_in_f32_ui64_out_f32 (
  input  logic [31:0] in0, input logic in0_valid,
  input  logic [63:0] in1, input logic in1_valid,
  input  logic out0_ready,
  output logic in0_ready, output logic in1_ready,
  output logic [31:0] out0, output logic out0_valid
); endmodule
EOS
}

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
  if [[ -f "$fp_prims_default" ]]; then
    echo "$fp_prims_default"
    return
  fi
  fp_auto_tmp="$(mktemp /tmp/circt_fp_prims_auto_XXXXXX.sv)"
  emit_builtin_fp_prims >"$fp_auto_tmp"
  echo "$fp_auto_tmp"
}

fp_prims="$(resolve_fp_prims "$input")"

is_filelist=0
case "$input" in
  *.f|*.svf|*.lst) is_filelist=1 ;;
esac

tmp_ys="$(mktemp /tmp/ts_yosys_il_XXXXXX.ys)"
cleanup() {
  rm -f "$tmp_ys"
  if [[ -n "$fp_auto_tmp" ]]; then
    rm -f "$fp_auto_tmp"
  fi
}
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
