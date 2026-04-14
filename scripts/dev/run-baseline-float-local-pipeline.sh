#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

show_usage() {
  cat <<'EOF'
usage: run-baseline-float-local-pipeline.sh [--out-dir <dir>] [--stop-after <stage>]

Runs the TinyStories baseline-float Task 3 path locally, using the repo pipeline
scripts but allowing local tool overrides for fast patch bisects.

Stages:
  torch -> linalg -> cf -> cf-stats -> handshake -> hs-ext -> hw0 -> hw
  -> hw-clean -> sv -> il -> yosys-stat

Useful overrides:
  TORCH_MLIR_OPT   Local torch-mlir-opt to test
  CIRCT_OPT        Local circt-opt to test
  MLIR_OPT         mlir-opt to use (defaults to PATH)
  YOSYS_BIN        yosys to use (defaults to PATH)
  YOSYS_SLANG_SO   yosys-slang plugin path
  MODEL_PATH       TinyStories snapshot path
  PYTHON_BIN       Python with torch + transformers
  TORCH_MLIR_PYTHONPATH
                   torch_mlir Python import path

Typical usage:
  nix develop
  TORCH_MLIR_OPT=/home/roland/torch-mlir/build-local-devshell-2/bin/torch-mlir-opt \
    scripts/dev/run-baseline-float-local-pipeline.sh --stop-after il

  CIRCT_OPT=/home/roland/circt/build-local-23/bin/circt-opt \
    scripts/dev/run-baseline-float-local-pipeline.sh --stop-after sv
EOF
}

usage() {
  show_usage >&2
  exit 1
}

stop_after="yosys-stat"
out_dir="/tmp/tiny-stories-1m-baseline-float-local"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ "$#" -ge 2 ]] || usage
      out_dir="$2"
      shift 2
      ;;
    --stop-after)
      [[ "$#" -ge 2 ]] || usage
      stop_after="$2"
      shift 2
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

valid_stage=false
for stage in torch linalg cf cf-stats handshake hs-ext hw0 hw hw-clean sv il yosys-stat; do
  if [[ "$stage" == "$stop_after" ]]; then
    valid_stage=true
    break
  fi
done
if [[ "$valid_stage" != true ]]; then
  echo "invalid --stop-after stage: $stop_after" >&2
  usage
fi

stage_index() {
  case "$1" in
    torch) echo 1 ;;
    linalg) echo 2 ;;
    cf) echo 3 ;;
    cf-stats) echo 4 ;;
    handshake) echo 5 ;;
    hs-ext) echo 6 ;;
    hw0) echo 7 ;;
    hw) echo 8 ;;
    hw-clean) echo 9 ;;
    sv) echo 10 ;;
    il) echo 11 ;;
    yosys-stat) echo 12 ;;
    *)
      echo "unknown stage: $1" >&2
      exit 1
      ;;
  esac
}

needs_stage() {
  local stage="$1"
  [[ "$(stage_index "$stage")" -le "$(stage_index "$stop_after")" ]]
}

resolve_flake_path() {
  local ref="$1"
  nix build --print-out-paths --no-link "$ref"
}

prefer_path() {
  local candidate="$1"
  if [[ -n "$candidate" && -e "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

python_pkg="$(resolve_flake_path '.#python-with-tiny-stories')"
torch_mlir_pkg="$(resolve_flake_path '.#torch-mlir')"
yosys_slang_pkg=""
if needs_stage il; then
  yosys_slang_pkg="$(resolve_flake_path '.#yosys-slang')"
fi

python_bin="${PYTHON_BIN:-$python_pkg/bin/python}"
model_path="${MODEL_PATH:-$(resolve_flake_path '.#tiny-stories-1m-snapshot')}"

nix_torch_mlir_pythonpath="$torch_mlir_pkg/python-packages/torch_mlir"
local_torch_mlir_pythonpath="/home/roland/torch-mlir/python"
default_torch_mlir_pythonpath="$nix_torch_mlir_pythonpath"
if [[ -d "$local_torch_mlir_pythonpath" ]]; then
  default_torch_mlir_pythonpath="$local_torch_mlir_pythonpath:$nix_torch_mlir_pythonpath"
fi
torch_mlir_pythonpath="${TORCH_MLIR_PYTHONPATH:-$default_torch_mlir_pythonpath}"

torch_mlir_opt="${TORCH_MLIR_OPT:-}"
if [[ -z "$torch_mlir_opt" ]]; then
  torch_mlir_opt="$(prefer_path /home/roland/torch-mlir/build-local-devshell-2/bin/torch-mlir-opt || command -v torch-mlir-opt || true)"
fi
mlir_opt="${MLIR_OPT:-$(command -v mlir-opt || true)}"
circt_opt="${CIRCT_OPT:-}"
if [[ -z "$circt_opt" ]]; then
  circt_opt="$(prefer_path /home/roland/circt/build-local-23/bin/circt-opt || command -v circt-opt || true)"
fi
yosys_bin="${YOSYS_BIN:-$(command -v yosys || true)}"
yosys_slang_so="${YOSYS_SLANG_SO:-}"
if needs_stage il && [[ -z "$yosys_slang_so" ]]; then
  yosys_slang_so="$yosys_slang_pkg/share/yosys/plugins/slang.so"
fi
fp_prims_sv="${FP_PRIMS_SV:-$REPO_ROOT/rtl/fp/circt_fp_primitives.sv}"

require_executable() {
  local path="$1"
  [[ -x "$path" ]] || {
    echo "required executable not found: $path" >&2
    echo "run inside 'nix develop' and/or set the corresponding override env var" >&2
    exit 1
  }
}

require_path() {
  local path="$1"
  [[ -e "$path" ]] || {
    echo "required path not found: $path" >&2
    exit 1
  }
}

require_executable "$python_bin"
require_path "$model_path"

if needs_stage linalg; then
  require_executable "$torch_mlir_opt"
fi
if needs_stage cf; then
  require_executable "$mlir_opt"
fi
if needs_stage handshake; then
  require_executable "$circt_opt"
fi
if needs_stage sv; then
  require_path "$fp_prims_sv"
fi
if needs_stage il; then
  require_executable "$yosys_bin"
  require_path "$yosys_slang_so"
fi

mkdir -p "$out_dir"

torch_out="$out_dir/torch.mlir"
linalg_out="$out_dir/linalg.mlir"
cf_out="$out_dir/cf.mlir"
cf_stats_out="$out_dir/cf.stats"
handshake_out="$out_dir/handshake.mlir"
hs_ext_out="$out_dir/hs-ext.mlir"
hw0_out="$out_dir/hw0.mlir"
hw_out="$out_dir/hw.mlir"
hw_clean_out="$out_dir/hw-clean.mlir"
sv_out="$out_dir/sv"
il_out="$out_dir/design.il"
yosys_stat_out="$out_dir/yosys-stat.json"

cat >"$out_dir/toolchain.env" <<EOF
PYTHON_BIN=$python_bin
MODEL_PATH=$model_path
TORCH_MLIR_PYTHONPATH=$torch_mlir_pythonpath
TORCH_MLIR_OPT=$torch_mlir_opt
MLIR_OPT=$mlir_opt
CIRCT_OPT=$circt_opt
YOSYS_BIN=$yosys_bin
YOSYS_SLANG_SO=$yosys_slang_so
FP_PRIMS_SV=$fp_prims_sv
STOP_AFTER=$stop_after
EOF

run_stage() {
  local stage="$1"
  shift
  echo "[local-pipeline] stage=$stage"
  "$@"
  echo "$stage" >"$out_dir/last-stage.txt"
  if [[ "$stage" == "$stop_after" ]]; then
    echo "[local-pipeline] stopped after $stage"
    exit 0
  fi
}

compile_torch_stage() {
  env \
    PYTHONPATH="$torch_mlir_pythonpath${PYTHONPATH:+:$PYTHONPATH}" \
    "$python_bin" "$REPO_ROOT/scripts/compile-pytorch.py" \
    --adapter "$REPO_ROOT/TinyStories/model_adapter.py" \
    --model-path "$model_path" \
    --out "$torch_out" >/dev/null
}

run_stage torch compile_torch_stage

run_stage linalg \
  "$REPO_ROOT/scripts/pipeline/torch_to_linalg.sh" \
  "$torch_mlir_opt" "$torch_out" "$linalg_out"

run_stage cf \
  "$REPO_ROOT/scripts/pipeline/linalg_to_cf.sh" \
  "$mlir_opt" "$linalg_out" "$cf_out"

run_stage cf-stats \
  "$REPO_ROOT/scripts/pipeline/cf_stats.sh" \
  "$mlir_opt" "$cf_out" "$cf_stats_out"

run_stage handshake \
  "$REPO_ROOT/scripts/pipeline/cf_to_handshake.sh" \
  "$circt_opt" "$mlir_opt" "$cf_out" "$handshake_out"

run_stage hs-ext \
  "$REPO_ROOT/scripts/pipeline/handshake_to_hs_ext.sh" \
  "$circt_opt" "$handshake_out" "$hs_ext_out"

run_stage hw0 \
  "$REPO_ROOT/scripts/pipeline/hs_ext_to_hw0.sh" \
  "$circt_opt" "$hs_ext_out" "$hw0_out"

run_stage hw \
  "$REPO_ROOT/scripts/pipeline/hw0_to_hw.sh" \
  "$circt_opt" "$hw0_out" "$hw_out"

run_stage hw-clean \
  "$REPO_ROOT/scripts/pipeline/hw_to_hw_clean.sh" \
  "$circt_opt" "$hw_out" "$hw_clean_out"

run_stage sv env \
  ALLOW_HW_EXTERNS=1 \
  FP_PRIMS_SV="$fp_prims_sv" \
  "$REPO_ROOT/scripts/pipeline/hw_clean_to_sv.sh" \
  "$circt_opt" "$hw_clean_out" "$sv_out"

run_stage il env \
  YOSYS_SLANG_PER_FILE_EXTERNS=1 \
  "$REPO_ROOT/scripts/pipeline/sv_to_il.sh" \
  "$yosys_bin" "$yosys_slang_so" "$sv_out/sources.f" "$il_out"

run_stage yosys-stat env \
  YOSYS_SLANG_PER_FILE_EXTERNS=1 \
  "$REPO_ROOT/scripts/pipeline/sv_to_yosys_stat.sh" \
  "$yosys_bin" "$yosys_slang_so" "$sv_out/sources.f" "$yosys_stat_out"

echo "[local-pipeline] completed: $out_dir"
