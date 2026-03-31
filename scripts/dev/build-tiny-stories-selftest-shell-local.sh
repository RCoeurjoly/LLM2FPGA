#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-/tmp/tiny-stories-selftest-shell-local}"
MODEL_IL="${MODEL_IL:-$ROOT_DIR/result}"
EXTERNAL_MEMORY_BITS_THRESHOLD="${EXTERNAL_MEMORY_BITS_THRESHOLD:-131072}"
RUN_TO_STAGE="${RUN_TO_STAGE:-stage2}"

system="${NIX_SYSTEM:-$(nix eval --raw --impure --expr builtins.currentSystem)}"
YOSYS_OUT="${YOSYS_OUT:-$(nix eval --raw ".#packages.${system}.yosys.outPath")}"
YOSYS_SLANG_OUT="${YOSYS_SLANG_OUT:-$(nix eval --raw ".#packages.${system}.yosys-slang.outPath")}"
YOSYS_BIN="${YOSYS_BIN:-$YOSYS_OUT/bin/yosys}"
YOSYS_SLANG_SO="${YOSYS_SLANG_SO:-$YOSYS_SLANG_OUT/share/yosys/plugins/slang.so}"

if [[ -z "${MAIN_SV:-}" ]]; then
  sv_out="$(nix build .#tiny-stories-1m-sv --no-link --print-out-paths)"
  MAIN_SV="${sv_out}/sv/main.sv"
fi

mkdir -p "$OUT_DIR"

TOP_SV="$OUT_DIR/tiny-stories-selftest-top.sv"
MODEL_OPT_IL="$OUT_DIR/tiny-stories-selftest-model-opt.il"
EXTERNALIZE_YS="$OUT_DIR/externalize.ys"
EXTERNALIZE_JSON="$OUT_DIR/externalize.json"
MODEL_SHELL_IL="$OUT_DIR/tiny-stories-selftest-model-shell.il"

python3 "$ROOT_DIR/scripts/pipeline/gen_tiny_stories_selftest_top.py" \
  --main-sv "$MAIN_SV" \
  --out "$TOP_SV"

python3 "$ROOT_DIR/scripts/pipeline/externalize_large_memories.py" \
  --input "$MODEL_IL" \
  --output-script "$EXTERNALIZE_YS" \
  --output-report "$EXTERNALIZE_JSON" \
  --min-module-bits "$EXTERNAL_MEMORY_BITS_THRESHOLD"

cat > "$OUT_DIR/model-opt.ys" <<EOF
read_rtlil $MODEL_IL
hierarchy -top main -check
proc
opt_expr
opt_clean
clean
write_rtlil $MODEL_OPT_IL
EOF
"$YOSYS_BIN" -q -m "$YOSYS_SLANG_SO" -s "$OUT_DIR/model-opt.ys"

cat > "$OUT_DIR/model-shell.ys" <<EOF
read_rtlil $MODEL_OPT_IL
script $EXTERNALIZE_YS
hierarchy -top main -check
write_rtlil $MODEL_SHELL_IL
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/model-shell.ys"

cat > "$OUT_DIR/stage1.ys" <<EOF
read_rtlil $MODEL_SHELL_IL
read_slang $TOP_SV
hierarchy -top tiny_stories_selftest_top -check
synth_xilinx -family xc7 -top tiny_stories_selftest_top -noiopad -run begin:prepare
write_rtlil $OUT_DIR/stage1.il
EOF
"$YOSYS_BIN" -q -m "$YOSYS_SLANG_SO" -s "$OUT_DIR/stage1.ys"
[[ "$RUN_TO_STAGE" == "stage1" ]] && exit 0

cat > "$OUT_DIR/stage2.ys" <<EOF
read_rtlil $OUT_DIR/stage1.il
hierarchy -top tiny_stories_selftest_top -check
synth_xilinx -family xc7 -top tiny_stories_selftest_top -noiopad -run coarse:map_memory
write_rtlil $OUT_DIR/stage2.il
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage2.ys"
[[ "$RUN_TO_STAGE" == "stage2" ]] && exit 0

cat > "$OUT_DIR/stage3.ys" <<EOF
read_rtlil $OUT_DIR/stage2.il
hierarchy -top tiny_stories_selftest_top -check
opt -fast -full
write_rtlil $OUT_DIR/stage3.il
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage3.ys"
[[ "$RUN_TO_STAGE" == "stage3" ]] && exit 0

cat > "$OUT_DIR/stage4.ys" <<EOF
read_rtlil $OUT_DIR/stage3.il
hierarchy -top tiny_stories_selftest_top -check
synth_xilinx -family xc7 -top tiny_stories_selftest_top -noiopad -run map_ffram:map_ffram
write_rtlil $OUT_DIR/stage4.il
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage4.ys"
[[ "$RUN_TO_STAGE" == "stage4" ]] && exit 0

cat > "$OUT_DIR/stage5.ys" <<EOF
read_rtlil $OUT_DIR/stage4.il
hierarchy -top tiny_stories_selftest_top -check
synth_xilinx -family xc7 -top tiny_stories_selftest_top -noiopad -run fine:fine
write_rtlil $OUT_DIR/stage5.il
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage5.ys"
[[ "$RUN_TO_STAGE" == "stage5" ]] && exit 0

cat > "$OUT_DIR/stage6.ys" <<EOF
read_rtlil $OUT_DIR/stage5.il
hierarchy -top tiny_stories_selftest_top -check
synth_xilinx -family xc7 -top tiny_stories_selftest_top -noiopad -run map_cells:map_cells
write_rtlil $OUT_DIR/stage6.il
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage6.ys"
[[ "$RUN_TO_STAGE" == "stage6" ]] && exit 0

cat > "$OUT_DIR/stage7.ys" <<EOF
read_rtlil $OUT_DIR/stage6.il
hierarchy -top tiny_stories_selftest_top -check
synth_xilinx -family xc7 -top tiny_stories_selftest_top -noiopad -run map_ffs:map_ffs
write_rtlil $OUT_DIR/stage7.il
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage7.ys"
[[ "$RUN_TO_STAGE" == "stage7" ]] && exit 0

cat > "$OUT_DIR/stage8.ys" <<EOF
read_rtlil $OUT_DIR/stage7.il
hierarchy -top tiny_stories_selftest_top -check
synth_xilinx -family xc7 -top tiny_stories_selftest_top -noiopad -run map_luts:check
write_rtlil $OUT_DIR/stage8.il
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage8.ys"

python3 "$ROOT_DIR/scripts/pipeline/filter_rtlil_modules.py" \
  --input "$OUT_DIR/stage8.il" \
  --output "$OUT_DIR/stage8-stripped.il" \
  --drop-escaped-uppercase-modules

cat > "$OUT_DIR/stage9.ys" <<EOF
read_rtlil $OUT_DIR/stage8-stripped.il
write_json $OUT_DIR/tiny-stories-selftest-shell.json
EOF
"$YOSYS_BIN" -q -s "$OUT_DIR/stage9.ys"
