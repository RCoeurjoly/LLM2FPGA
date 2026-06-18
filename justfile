set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

task6-l0:
    python3 scripts/task6/run_stage_local.py --stage l0

task6-l1:
    python3 scripts/task6/run_stage_local.py --stage l1

task6-l2:
    python3 scripts/task6/run_stage_local.py --stage l2

task6-l3:
    python3 scripts/task6/run_stage_local.py --stage l3

task6-l4:
    python3 scripts/task6/run_stage_local.py --stage l4

task6-x1:
    python3 scripts/task6/run_stage_local.py --stage x1

task6-x2:
    python3 scripts/task6/run_stage_local.py --stage x2

task6-x3:
    python3 scripts/task6/run_stage_local.py --stage x3

task6-latest-passing-milestone-bitstream:
    nix build .#latest-passing-milestone --no-link --print-out-paths

task6-latest-passing-milestone-board-gate bitstream='' model_path='' run_root='artifacts/task6/runs/task6-latest-passing-milestone' sample_count='8':
    if [ -n "{{model_path}}" ]; then if [ -n "{{bitstream}}" ]; then python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "{{bitstream}}" --model-path "{{model_path}}" --sample-count "{{sample_count}}" --json-only --run-root "{{run_root}}"; else python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "$(nix build .#latest-passing-milestone --no-link --print-out-paths)" --model-path "{{model_path}}" --sample-count "{{sample_count}}" --json-only --run-root "{{run_root}}"; fi; else if [ -n "{{bitstream}}" ]; then python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "{{bitstream}}" --skip-top1 --skip-inference --json-only --run-root "{{run_root}}"; else python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "$(nix build .#latest-passing-milestone --no-link --print-out-paths)" --skip-top1 --skip-inference --json-only --run-root "{{run_root}}"; fi; fi

task6-bottleneck-bitstream:
    nix build .#bottleneck --no-link --print-out-paths

task6-bottleneck-board-gate bitstream='' model_path='' run_root='artifacts/task6/runs/task6-bottleneck' sample_count='8':
    if [ -n "{{model_path}}" ]; then if [ -n "{{bitstream}}" ]; then python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "{{bitstream}}" --model-path "{{model_path}}" --sample-count "{{sample_count}}" --json-only --run-root "{{run_root}}"; else python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "$(nix build .#bottleneck --no-link --print-out-paths)" --model-path "{{model_path}}" --sample-count "{{sample_count}}" --json-only --run-root "{{run_root}}"; fi; else if [ -n "{{bitstream}}" ]; then python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "{{bitstream}}" --skip-top1 --skip-inference --json-only --run-root "{{run_root}}"; else python3 scripts/task6/task6_ypcb_tinystories_inference_gate.py --bitstream "$(nix build .#bottleneck --no-link --print-out-paths)" --skip-top1 --skip-inference --json-only --run-root "{{run_root}}"; fi; fi

task6-zero-to-one-inventory out-json='artifacts/zero-to-one/inventory/inventory.json':
    mkdir -p "$(dirname "{{out-json}}")"
    python3 scripts/task6/task6_zero_to_one_inventory.py --repo-root . --out-json "{{out-json}}"

task6-zero-to-one-reference-lock model_snapshot model_adapter tokenizer_vocab tokenizer_merges reference_json out_json='artifacts/zero-to-one/reference-lock.json' weight_manifests='' test_vectors='' lock_tag='zero-to-one-v1':
    set -euo pipefail
    mkdir -p "$(dirname "{{out_json}}")"
    weight_args=''
    if [[ -n "{{weight_manifests}}" ]]; then
    IFS=',' read -ra _weight_files <<< "{{weight_manifests}}"
    for _weight_file in "${_weight_files[@]}"; do
    weight_args+=" --weight-manifest ${_weight_file}"
    done
    fi
    vector_args=''
    if [[ -n "{{test_vectors}}" ]]; then
    IFS=',' read -ra _vector_files <<< "{{test_vectors}}"
    for _test_vector in "${_vector_files[@]}"; do
    vector_args+=" --test-vector ${_test_vector}"
    done
    fi
    python3 scripts/task6/task6_zero_to_one_reference_lock.py \
    --repo-root . \
    --model-snapshot "{{model_snapshot}}" \
    --model-adapter "{{model_adapter}}" \
    --tokenizer-vocab "{{tokenizer_vocab}}" \
    --tokenizer-merges "{{tokenizer_merges}}" \
    --reference-json "{{reference_json}}" \
    --out-json "{{out_json}}" \
    --lock-tag "{{lock_tag}}" \
    $weight_args \
    $vector_args

task6-zero-to-one-reference-lock-tinystories model_adapter='TinyStories/model_adapter.py' tokenizer_vocab='' tokenizer_merges='' reference_json='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json' out_json='artifacts/zero-to-one/reference-lock.json' weight_manifest='artifacts/task6/weights_pack/tiny-stories-1m-m2-block0-int8/manifest.json' test_vector='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json' lock_tag='zero-to-one-v1':
    mkdir -p "$(dirname "{{out_json}}")"
    tokenizer_vocab="{{tokenizer_vocab}}"
    tokenizer_merges="{{tokenizer_merges}}"
    if [ -z "$tokenizer_vocab$tokenizer_merges" ]; then
    if [ -n "${TASK6_TINY_STORIES_TOKENIZER_ROOT:-}" ] && [ -f "${TASK6_TINY_STORIES_TOKENIZER_ROOT}/vocab.json" ] && [ -f "${TASK6_TINY_STORIES_TOKENIZER_ROOT}/merges.txt" ]; then
    tokenizer_root="${TASK6_TINY_STORIES_TOKENIZER_ROOT}"
    elif [ -f "${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e/vocab.json" ] && [ -f "${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e/merges.txt" ]; then
    tokenizer_root="${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e"
    else
    tokenizer_root="$(nix eval --raw .#gpt-neo-tokenizer 2>/dev/null || true)"
    if [ -z "$tokenizer_root" ] || [ ! -f "$tokenizer_root/vocab.json" ] || [ ! -f "$tokenizer_root/merges.txt" ]; then
    echo "Could not resolve TinyStories tokenizer root." >&2
    echo "Set TASK6_TINY_STORIES_TOKENIZER_ROOT, provide tokenizer_vocab/tokenizer_merges, or allow nix eval access." >&2
    exit 1
    fi
    fi
    tokenizer_vocab="$tokenizer_root/vocab.json"
    tokenizer_merges="$tokenizer_root/merges.txt"
    fi
    python3 scripts/task6/task6_zero_to_one_reference_lock.py \
    --repo-root . \
    --model-adapter "{{model_adapter}}" \
    --tokenizer-vocab "$tokenizer_vocab" \
    --tokenizer-merges "$tokenizer_merges" \
    --reference-json "{{reference_json}}" \
    --weight-manifest "{{weight_manifest}}" \
    --test-vector "{{test_vector}}" \
    --out-json "{{out_json}}" \
    --lock-tag "{{lock_tag}}"

task6-zero-to-one-reference-lock-tinystories-int4 model_adapter='TinyStories/model_adapter.py' tokenizer_vocab='' tokenizer_merges='' reference_json='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json' out_json='artifacts/zero-to-one/reference-lock-int4.json' weight_manifest='artifacts/task6/weights_pack/tiny-stories-1m-m2-block0-int4/manifest.json' test_vector='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json' lock_tag='zero-to-one-int4-v1':
    mkdir -p "$(dirname "{{out_json}}")"
    tokenizer_vocab="{{tokenizer_vocab}}"
    tokenizer_merges="{{tokenizer_merges}}"
    if [ -z "$tokenizer_vocab$tokenizer_merges" ]; then
    if [ -n "${TASK6_TINY_STORIES_TOKENIZER_ROOT:-}" ] && [ -f "${TASK6_TINY_STORIES_TOKENIZER_ROOT}/vocab.json" ] && [ -f "${TASK6_TINY_STORIES_TOKENIZER_ROOT}/merges.txt" ]; then
    tokenizer_root="${TASK6_TINY_STORIES_TOKENIZER_ROOT}"
    elif [ -f "${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e/vocab.json" ] && [ -f "${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e/merges.txt" ]; then
    tokenizer_root="${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e"
    else
    tokenizer_root="$(nix eval --raw .#gpt-neo-tokenizer 2>/dev/null || true)"
    if [ -z "$tokenizer_root" ] || [ ! -f "$tokenizer_root/vocab.json" ] || [ ! -f "$tokenizer_root/merges.txt" ]; then
    echo "Could not resolve TinyStories tokenizer root." >&2
    echo "Set TASK6_TINY_STORIES_TOKENIZER_ROOT, provide tokenizer_vocab/tokenizer_merges, or allow nix eval access." >&2
    exit 1
    fi
    fi
    tokenizer_vocab="$tokenizer_root/vocab.json"
    tokenizer_merges="$tokenizer_root/merges.txt"
    fi
    python3 scripts/task6/task6_zero_to_one_reference_lock.py \
    --repo-root . \
    --model-adapter "{{model_adapter}}" \
    --tokenizer-vocab "$tokenizer_vocab" \
    --tokenizer-merges "$tokenizer_merges" \
    --reference-json "{{reference_json}}" \
    --weight-manifest "{{weight_manifest}}" \
    --test-vector "{{test_vector}}" \
    --out-json "{{out_json}}" \
    --lock-tag "{{lock_tag}}"

task6-zero-to-one-reference-lock-tinystories-ternary2 model_adapter='TinyStories/model_adapter.py' tokenizer_vocab='' tokenizer_merges='' reference_json='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json' out_json='artifacts/zero-to-one/reference-lock-ternary2.json' weight_manifest='artifacts/task6/weights_pack/tiny-stories-1m-m2-block0-ternary2/manifest.json' test_vector='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json' lock_tag='zero-to-one-ternary2-v1':
    mkdir -p "$(dirname "{{out_json}}")"
    tokenizer_vocab="{{tokenizer_vocab}}"
    tokenizer_merges="{{tokenizer_merges}}"
    if [ -z "$tokenizer_vocab$tokenizer_merges" ]; then
    if [ -n "${TASK6_TINY_STORIES_TOKENIZER_ROOT:-}" ] && [ -f "${TASK6_TINY_STORIES_TOKENIZER_ROOT}/vocab.json" ] && [ -f "${TASK6_TINY_STORIES_TOKENIZER_ROOT}/merges.txt" ]; then
    tokenizer_root="${TASK6_TINY_STORIES_TOKENIZER_ROOT}"
    elif [ -f "${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e/vocab.json" ] && [ -f "${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e/merges.txt" ]; then
    tokenizer_root="${HOME}/.cache/huggingface/hub/models--roneneldan--TinyStories-1M/snapshots/77f1b168e219585646439073245fe87e56b3023e"
    else
    tokenizer_root="$(nix eval --raw .#gpt-neo-tokenizer 2>/dev/null || true)"
    if [ -z "$tokenizer_root" ] || [ ! -f "$tokenizer_root/vocab.json" ] || [ ! -f "$tokenizer_root/merges.txt" ]; then
    echo "Could not resolve TinyStories tokenizer root." >&2
    echo "Set TASK6_TINY_STORIES_TOKENIZER_ROOT, provide tokenizer_vocab/tokenizer_merges, or allow nix eval access." >&2
    exit 1
    fi
    fi
    tokenizer_vocab="$tokenizer_root/vocab.json"
    tokenizer_merges="$tokenizer_root/merges.txt"
    fi
    python3 scripts/task6/task6_zero_to_one_reference_lock.py \
    --repo-root . \
    --model-adapter "{{model_adapter}}" \
    --tokenizer-vocab "$tokenizer_vocab" \
    --tokenizer-merges "$tokenizer_merges" \
    --reference-json "{{reference_json}}" \
    --weight-manifest "{{weight_manifest}}" \
    --test-vector "{{test_vector}}" \
    --out-json "{{out_json}}" \
    --lock-tag "{{lock_tag}}"

task6-zero-to-one-guard lock-json out-json='artifacts/zero-to-one/guard-result.json':
    mkdir -p "$(dirname "{{out-json}}")"
    python3 scripts/task6/task6_zero_to_one_guard.py --lock-json "{{lock-json}}" --out-json "{{out-json}}"

task6-zero-to-one-inference-guard lock-json out-json='artifacts/zero-to-one/inference-gate-guard.json':
    mkdir -p "$(dirname "{{out-json}}")"
    python3 scripts/task6/task6_zero_to_one_inference_gate.py \
    --lock-json "{{lock-json}}" \
    --out-json "{{out-json}}" \
    --guard-only \
    --skip-inventory

task6-zero-to-one-inference-gate lock-json out-json='artifacts/zero-to-one/inference-gate.json':
    mkdir -p "$(dirname "{{out-json}}")"
    python3 scripts/task6/task6_zero_to_one_inference_gate.py \
    --lock-json "{{lock-json}}" \
    --out-json "{{out-json}}"

task6-zero-to-one-inference-gate-simulate lock-json out-json='artifacts/zero-to-one/inference-gate-simulate.json':
    mkdir -p "$(dirname "{{out-json}}")"
    python3 scripts/task6/task6_zero_to_one_inference_gate.py \
    --lock-json "{{lock-json}}" \
    --out-json "{{out-json}}" \
    --simulate

task6-zero-to-one-m2-bram-checkpoint-hashes contract-manifest='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-one-block-contract/manifest.json' score-artifact='' quantization='int8' reference-json='artifacts/task6/parallel-hypotheses/h2-tinystories-1m-prompt-output-head-q024-reference.json' out-json='':
    score_artifact="{{score-artifact}}"
    if [ -z "$score_artifact" ]; then
    if [ "{{quantization}}" = "int8" ]; then
    score_artifact="artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-full-block-lowering-score.json"
    else
    score_artifact="artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-full-block-lowering-score-{{quantization}}.json"
    fi
    fi
    out_json="{{out-json}}"
    if [ -z "$out_json" ]; then
    if [ "{{quantization}}" = "int8" ]; then
    out_json="artifacts/zero-to-one/m2-bram-checkpoint-hashes.json"
    else
    out_json="artifacts/zero-to-one/m2-bram-checkpoint-hashes-{{quantization}}.json"
    fi
    fi
    mkdir -p "$(dirname "$out_json")"
    python3 scripts/task6/task6_zero_to_one_m2_checkpoint_hashes.py \
    --quantization "{{quantization}}" \
    --contract-manifest "{{contract-manifest}}" \
    --score-artifact "$score_artifact" \
    --reference-json "{{reference-json}}" \
    --out-json "$out_json"

task6-zero-to-one-m2-bram-proof quantization='int8' lock-json='' score-artifact='' out-json='':
    lock_json="{{lock-json}}"
    if [ -z "$lock_json" ]; then
    if [ "{{quantization}}" = "int4" ]; then
    lock_json="artifacts/zero-to-one/reference-lock-int4.json"
    just task6-zero-to-one-reference-lock-tinystories-int4 out_json="$lock_json"
    elif [ "{{quantization}}" = "ternary2" ]; then
    lock_json="artifacts/zero-to-one/reference-lock-ternary2.json"
    just task6-zero-to-one-reference-lock-tinystories-ternary2 out_json="$lock_json"
    else
    lock_json="artifacts/zero-to-one/reference-lock.json"
    just task6-zero-to-one-reference-lock-tinystories out_json="$lock_json"
    fi
    fi
    score_artifact="{{score-artifact}}"
    if [ -z "$score_artifact" ]; then
    if [ "{{quantization}}" = "int8" ]; then
    score_artifact="artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-full-block-lowering-score.json"
    else
    score_artifact="artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-full-block-lowering-score-{{quantization}}.json"
    fi
    fi
    out_json="{{out-json}}"
    if [ -z "$out_json" ]; then
    if [ "{{quantization}}" = "int8" ]; then
    out_json="artifacts/zero-to-one/m2-bram-checkpoint-hashes.json"
    else
    out_json="artifacts/zero-to-one/m2-bram-checkpoint-hashes-{{quantization}}.json"
    fi
    fi
    just task6-zero-to-one-m2-bram-checkpoint-hashes --quantization "{{quantization}}" --score-artifact "$score_artifact" --contract-manifest "artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-one-block-contract/manifest.json" --out-json "$out_json"

task6-zero-to-one-m2-bram-board-gate bdf='' tb-data-sv='' embedding-tb-data-sv='' context-tb-data-sv='' out-json='artifacts/task6/runs/m2-full-block-board-summary.json':
    if [ -z "{{bdf}}" ]; then
    echo "bdf is required for BRAM-only M2 board gate" >&2
    exit 1
    fi
    if [ -z "{{tb-data-sv}}" ]; then
    echo "--tb-data-sv is required for fixed-token BRAM-only M2 board gate" >&2
    exit 1
    fi
    if [ -z "{{embedding-tb-data-sv}}" ]; then
    echo "--embedding-tb-data-sv is required for fixed-token BRAM-only M2 board gate" >&2
    exit 1
    fi
    if [ -n "{{context-tb-data-sv}}" ]; then
    python3 scripts/task6/task6_pcie_m2_full_block_gate.py "{{bdf}}" \
    --tb-data-sv "{{tb-data-sv}}" \
    --embedding-tb-data-sv "{{embedding-tb-data-sv}}" \
    --context-tb-data-sv "{{context-tb-data-sv}}" \
    --json-out "{{out-json}}"
    else
    python3 scripts/task6/task6_pcie_m2_full_block_gate.py "{{bdf}}" \
    --tb-data-sv "{{tb-data-sv}}" \
    --embedding-tb-data-sv "{{embedding-tb-data-sv}}" \
    --json-out "{{out-json}}"
    fi

task6-zero-to-one-m2-bram-chip-pass quantization='int8' board-summary-json='artifacts/task6/runs/m2-full-block-board-summary.json' checkpoint-hash-json='' out-json='':
    board_summary_json="{{board-summary-json}}"
    checkpoint_hash_json="{{checkpoint-hash-json}}"
    if [ -z "$checkpoint_hash_json" ]; then
    score_artifact="artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-full-block-lowering-score.json"
    if [ "{{quantization}}" = "int4" ]; then
    score_artifact="artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-full-block-lowering-score-int4.json"
    elif [ "{{quantization}}" = "ternary2" ]; then
    score_artifact="artifacts/task6/parallel-hypotheses/h2-tinystories-1m-m2-full-block-lowering-score-ternary2.json"
    fi
    checkpoint_hash_json="artifacts/zero-to-one/m2-bram-checkpoint-hashes.json"
    if [ "{{quantization}}" != "int8" ]; then
    checkpoint_hash_json="artifacts/zero-to-one/m2-bram-checkpoint-hashes-{{quantization}}.json"
    fi
    just task6-zero-to-one-m2-bram-checkpoint-hashes --quantization "{{quantization}}" --score-artifact "$score_artifact" --out-json "$checkpoint_hash_json"
    fi
    if [ -z "{{out-json}}" ]; then
    python3 scripts/task6/task6_m2_bram_chip_pass_artifact.py --quantization "{{quantization}}" --board-summary-json "$board_summary_json" --checkpoint-hash-json "$checkpoint_hash_json"
    else
    python3 scripts/task6/task6_m2_bram_chip_pass_artifact.py --quantization "{{quantization}}" --board-summary-json "$board_summary_json" --checkpoint-hash-json "$checkpoint_hash_json" --out-json "{{out-json}}"
    fi

task6-zero-to-one-m2-bram-inference-proof bdf='' quantization='int8' tb-data-sv='' embedding-tb-data-sv='' context-tb-data-sv='' board-summary-json='artifacts/task6/runs/m2-full-block-board-summary.json' checkpoint-hash-json='' out-json='':
    board_summary_json="{{board-summary-json}}"
    if [ -n "{{context-tb-data-sv}}" ]; then
    just task6-zero-to-one-m2-bram-board-gate \
    bdf="{{bdf}}" \
    tb-data-sv="{{tb-data-sv}}" \
    embedding-tb-data-sv="{{embedding-tb-data-sv}}" \
    context-tb-data-sv="{{context-tb-data-sv}}" \
    out-json="$board_summary_json"
    else
    just task6-zero-to-one-m2-bram-board-gate \
    bdf="{{bdf}}" \
    tb-data-sv="{{tb-data-sv}}" \
    embedding-tb-data-sv="{{embedding-tb-data-sv}}" \
    out-json="$board_summary_json"
    fi
    # Intentionally keep out-json as a shell variable to avoid brace expansion mismatch
    if [ -z "{{out-json}}" ]; then
    just task6-zero-to-one-m2-bram-chip-pass \
    quantization="{{quantization}}" \
    board-summary-json="$board_summary_json" \
    checkpoint-hash-json="{{checkpoint-hash-json}}"
    else
    just task6-zero-to-one-m2-bram-chip-pass \
    quantization="{{quantization}}" \
    board-summary-json="$board_summary_json" \
    checkpoint-hash-json="{{checkpoint-hash-json}}" \
    out-json="{{out-json}}"
    fi

task6-zero-to-one-m2-bram-int8-proof bdf='' out-dir='artifacts/task6/runs/m2-bram-int8-proof' board-summary-json='' checkpoint-hash-json='' chip-pass-json='':
    if [ -z "{{bdf}}" ]; then
    echo "bdf is required for BRAM-only M2 int8 proof" >&2
    exit 1
    fi
    python3 scripts/task6/task6_zero_to_one_m2_bram_int8_proof.py "{{bdf}}" \
    --out-dir "{{out-dir}}" \
    --board-summary-json "{{board-summary-json}}" \
    --checkpoint-hash-json "{{checkpoint-hash-json}}" \
    --chip-pass-json "{{chip-pass-json}}"

task6-zero-to-one-unit-tests:
    python3 scripts/task6/test_task6_zero_to_one_reference_lock.py
    python3 scripts/task6/test_task6_zero_to_one_guard.py
    python3 scripts/task6/test_task6_zero_to_one_inventory.py
    python3 scripts/task6/test_task6_zero_to_one_inference_gate.py
