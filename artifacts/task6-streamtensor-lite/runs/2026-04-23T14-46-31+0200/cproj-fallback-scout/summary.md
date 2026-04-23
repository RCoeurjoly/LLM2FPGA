# Task 6 `c_proj` Fallback Scout

## Commands

- L1 candidate:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' python3 scripts/task6/find_l1_gemv_candidate.py --input /nix/store/2xz1757a13j8x630jhjy3ranvfc0lfsj-tiny-stories-1m-representative-core-v64-h4-linalg.mlir --output artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-candidate.json --lhs-shape 'tensor<1x1x16xf32>' --rhs-shape 'tensor<1x16x4xf32>' --out-shape 'tensor<1x1x4xf32>' --site-label L1-c_proj`
- L2 candidate:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' python3 scripts/task6/find_l1_gemv_candidate.py --input /nix/store/x8lnd266sjig478x9b34bmlv8p0x4m61-tiny-stories-v1k-h64-l1-linalg.mlir --output artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json --lhs-shape 'tensor<1x1x256xf32>' --rhs-shape 'tensor<1x256x64xf32>' --out-shape 'tensor<1x1x64xf32>' --site-label L2-c_proj`
- L1 weight pack:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/mkgmf27sxf4i2ar26ym2jg3wzg14bivz-python3-3.11.14-env/bin/python scripts/task6/export_weights_pack.py --model-path /nix/store/kw3s159yv90pk879nm0f7v4ikkrxz83w-tinystories-1m-hf-snapshot --output-dir artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj --module-name transformer.h.0.mlp.c_proj --vocab-size 64 --num-layers 2 --max-position-embeddings 8 --window-size 4 --hidden-size 4 --num-heads 1 --model-label tiny-stories-1m-representative-core-v64-h4`
- L2 weight pack:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/mkgmf27sxf4i2ar26ym2jg3wzg14bivz-python3-3.11.14-env/bin/python scripts/task6/export_weights_pack.py --model-path /nix/store/kw3s159yv90pk879nm0f7v4ikkrxz83w-tinystories-1m-hf-snapshot --output-dir artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj --module-name transformer.h.0.mlp.c_proj --vocab-size 1024 --num-layers 1 --max-position-embeddings 128 --window-size 64 --hidden-size 64 --num-heads 16 --model-label tiny-stories-v1k-h64-l1`
- L1 contract:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/mkgmf27sxf4i2ar26ym2jg3wzg14bivz-python3-3.11.14-env/bin/python scripts/task6/export_l1_contract.py --model-path /nix/store/kw3s159yv90pk879nm0f7v4ikkrxz83w-tinystories-1m-hf-snapshot --output-dir artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract --module-name transformer.h.0.mlp.c_proj --candidate-json artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-candidate.json --vocab-size 64 --num-layers 2 --max-position-embeddings 8 --window-size 4 --hidden-size 4 --num-heads 1 --token-id 0 --model-label tiny-stories-1m-representative-core-v64-h4`
- L2 contract:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/mkgmf27sxf4i2ar26ym2jg3wzg14bivz-python3-3.11.14-env/bin/python scripts/task6/export_l1_contract.py --model-path /nix/store/kw3s159yv90pk879nm0f7v4ikkrxz83w-tinystories-1m-hf-snapshot --output-dir artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract --module-name transformer.h.0.mlp.c_proj --candidate-json artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json --vocab-size 1024 --num-layers 1 --max-position-embeddings 128 --window-size 64 --hidden-size 64 --num-heads 16 --token-id 0 --model-label tiny-stories-v1k-h64-l1`
- L1 contract replay:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/mkgmf27sxf4i2ar26ym2jg3wzg14bivz-python3-3.11.14-env/bin/python scripts/task6/verify_l1_contract.py --contract-manifest artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json --output artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract-check.json`
- L2 contract replay:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/mkgmf27sxf4i2ar26ym2jg3wzg14bivz-python3-3.11.14-env/bin/python scripts/task6/verify_l1_contract.py --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --output artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract-check.json`
- L1 task graph:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' python3 scripts/task6/build_task_graph.py --candidate-json artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-candidate.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-1m-representative-core-v64-h4/transformer.h.0.mlp.c_proj/manifest.json --contract-manifest artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-contract/manifest.json --output artifacts/task6/streamtensor-lite/l1/representative-core-v64-h4-c_proj-task-graph.json`
- L2 task graph:
  - `/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' python3 scripts/task6/build_task_graph.py --candidate-json artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-candidate.json --weight-pack-manifest artifacts/task6/weights_pack/tiny-stories-v1k-h64-l1/transformer.h.0.mlp.c_proj/manifest.json --contract-manifest artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-contract/manifest.json --output artifacts/task6/streamtensor-lite/l2/tiny-stories-v1k-h64-l1-c_proj-task-graph.json`

## Logs

- [l1-candidate.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l1-candidate.log)
- [l1-pack.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l1-pack.log)
- [l1-contract.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l1-contract.log)
- [l1-check.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l1-check.log)
- [l1-task-graph.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l1-task-graph.log)
- [l2-candidate.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l2-candidate.log)
- [l2-pack.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l2-pack.log)
- [l2-contract.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l2-contract.log)
- [l2-check.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l2-check.log)
- [l2-task-graph.log](/home/roland/LLM2FPGA_task6_streamtensor_lite/artifacts/task6-streamtensor-lite/runs/2026-04-23T14-46-31+0200/cproj-fallback-scout/l2-task-graph.log)

## Metrics

- L1 candidate:
  - line / value:
    - `418` / `%88`
  - shape contract:
    - `tensor<1x1x16xf32>` x `tensor<1x16x4xf32>` -> `tensor<1x1x4xf32>`
  - candidate count:
    - `2`
  - wall-clock / RSS:
    - `0.07 s` / `13,272 KB`
- L1 pack:
  - weight shape:
    - `(4, 16)`
  - bias shape:
    - `(4,)`
  - wall-clock / RSS:
    - `4.69 s` / `334,732 KB`
- L1 contract:
  - activation in / out:
    - `(1, 1, 16)` / `(1, 1, 4)`
  - wall-clock / RSS:
    - `4.51 s` / `342,492 KB`
- L1 replay check:
  - max / mean absolute error:
    - `0.0` / `0.0`
  - wall-clock / RSS:
    - `1.83 s` / `226,384 KB`
- L1 task graph:
  - graph name:
    - `task6-c_proj-minimal-task-graph`
  - wall-clock / RSS:
    - `0.07 s` / `14,020 KB`
- L2 candidate:
  - line / value:
    - `412` / `%94`
  - shape contract:
    - `tensor<1x1x256xf32>` x `tensor<1x256x64xf32>` -> `tensor<1x1x64xf32>`
  - candidate count:
    - `1`
  - wall-clock / RSS:
    - `0.08 s` / `14,888 KB`
- L2 pack:
  - weight shape:
    - `(64, 256)`
  - bias shape:
    - `(64,)`
  - wall-clock / RSS:
    - `4.71 s` / `335,104 KB`
- L2 contract:
  - activation in / out:
    - `(1, 1, 256)` / `(1, 1, 64)`
  - wall-clock / RSS:
    - `4.54 s` / `342,668 KB`
- L2 replay check:
  - max / mean absolute error:
    - `0.0` / `0.0`
  - wall-clock / RSS:
    - `1.83 s` / `226,016 KB`
- L2 task graph:
  - graph name:
    - `task6-c_proj-minimal-task-graph`
  - wall-clock / RSS:
    - `0.08 s` / `13,760 KB`

## Verdict

- The reserve `mlp.c_proj` fallback boundary is real on both `L1` and `L2`.
- Both rungs preserve a clean `linalg.batch_matmul` site, external weight pack,
  module-level activation contract, and exact packed replay with
  `max_abs_error = 0.0`.
- No mapped RTL claim is made yet; this step only proves that the fallback
  boundary can reuse the existing lightweight artifact path honestly.

## Next Action

- Build the first redirected `c_proj` kernel at `L1` and judge it with the same
  fast loop: pack-backed contract, Verilator, then mapped utilization.
