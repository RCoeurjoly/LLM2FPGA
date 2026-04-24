# PT2E-Static L1 Extracted Parity

## Commands

```bash
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-pt2e-static-torch --no-link --print-out-paths -L |& tee artifacts/task6/runs/2026-04-24T13-02-11+0200/pt2e-static-l1-extracted-parity/quantized-torch.log
/usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' nix build .#task6-l1-c-fc-redirect-torch --no-link --print-out-paths -L |& tee artifacts/task6/runs/2026-04-24T13-02-11+0200/pt2e-static-l1-extracted-parity/float-torch.log
PYTHONPATH="/home/roland/LLM2FPGA_task6_streamtensor_lite/src:${PYTHONPATH:-}" TASK6_RECT_GEMV_IN_DIM=4 TASK6_RECT_GEMV_OUT_DIM=16 /usr/bin/time -f 'ELAPSED=%e RSS_KB=%M' /nix/store/mkgmf27sxf4i2ar26ym2jg3wzg14bivz-python3-3.11.14-env/bin/python - <<'PY' |& tee artifacts/task6/runs/2026-04-24T13-02-11+0200/pt2e-static-l1-extracted-parity/inspection.log
import torch
from task6_rect_gemv_pt2e_static_quant_adapter import build_model, example_inputs
from torch.ao.quantization import move_exported_model_to_eval
from torch.ao.quantization.quantize_pt2e import convert_pt2e, prepare_pt2e
from torch.ao.quantization.quantizer.xnnpack_quantizer import XNNPACKQuantizer, get_symmetric_quantization_config

model = build_model(None)
inputs = tuple(example_inputs())
exported = torch.export.export(model, inputs, strict=False)
quantizer = XNNPACKQuantizer().set_global(get_symmetric_quantization_config(is_dynamic=False))
prepared = prepare_pt2e(exported.module(), quantizer)
print(prepared.graph)
with torch.no_grad():
    prepared(*inputs)
quantized = convert_pt2e(prepared)
move_exported_model_to_eval(quantized)
print(quantized.graph)
reexported = torch.export.export(quantized, inputs, strict=False)
print(reexported.graph)
PY
```

## Outputs

- quantized extracted-op `torch`:
  - `/nix/store/qfamvz0l8b6axi8pr7snnxm61y5yfp31-task6-l1-c-fc-redirect-pt2e-static-torch.mlir`
- frozen float `L1` `torch` reference:
  - `/nix/store/zbg1drcqw0a1w77pww3nv8xq3whvqg5p-task6-l1-c-fc-redirect-torch.mlir`
- logs:
  - `./quantized-torch.log`
  - `./float-torch.log`
  - `./inspection.log`
  - `./compare.log`

## Metrics

- quantized extracted-op `torch` build:
  - `ELAPSED=4.61`
  - `RSS_KB=276,128`
- frozen float `L1` `torch` build:
  - `ELAPSED=4.24`
  - `RSS_KB=276,464`
- local PT2E inspection:
  - `ELAPSED=2.26`
  - `RSS_KB=341,772`
- exported `torch` MLIR comparison:
  - quantized size: `299` bytes
  - float size: `299` bytes
  - identical SHA-256:
    - `f72bdc8d20105e9b8ee048aec691ee16839eee7d9020ce7e18330b1590810d9b`
  - `TORCH_EXPORT_IDENTICAL=1`

## Structural Note

- On this minimal external-weight GEMV surface, PT2E-static does not insert any
  quant/dequant structure.
- The prepared graph, converted graph, and re-exported graph all remain a plain
  float `aten.matmul.default` over the original external `activation` and
  `weight` placeholders.
- So this is not merely "quantized but later optimized away in MLIR"; the
  quantized route is already a no-op at the PyTorch export surface.

## Verdict

`reject-quant-noop`

- The direct `L1` extracted-op parity slice does not yield a surviving
  quantized kernel.
- PT2E-static on the external-weight `4 x 16` GEMV is byte-identical to the
  frozen float `torch` export.
- That means there is no reason to widen this exact route onto `L2` or to start
  a low-bit kernel from it.

## Next Action

- Keep the broader `tiny-stories-1m` PT2E-static full-model route only as a
  reference surface.
- Do not widen `task6-l1-c-fc-redirect-pt2e-static` to heavier stages or `L2`.
- Any further quantization work now needs a new extracted-op hypothesis that can
  actually survive externalized weights without collapsing back to float.
