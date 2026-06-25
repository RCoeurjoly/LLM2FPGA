# PT2E Integer Lowering Lab

Minimal lab for one question:

> After PT2E quantization and `convert_pt2e`, does the PyTorch graph expose
> structural integer/fixed-point linear or matmul compute before Torch-MLIR?

Current working hypothesis:

> No. The maintained PT2E path often keeps float `aten.linear` / `aten.matmul`
> compute and wraps it with quantize/dequantize, clamps, or integer range
> metadata.

## Files

- `probe_pt2e_linear.py`: exports a tiny `nn.Linear`, applies one PT2E
  quantizer, runs `prepare_pt2e` / calibration / `convert_pt2e`, and dumps the
  converted graph.
- `audit.py`: checks the dumped graph for the two relevant failure modes:
  QDQ-wrapped float compute and bare float compute.
- `test_audit.py`: tests only that core failure detector.

## Run

Use any Python environment that contains `torch`, `torchao`, and `executorch`.
In this repository the Nix 26.05 ExecuTorch survey environment is sufficient.

```bash
python3 -m unittest discover -s experiments/pt2e-integer-lowering-lab -p 'test_*.py'
python3 experiments/pt2e-integer-lowering-lab/probe_pt2e_linear.py --out-dir /tmp/pt2e-lab-xnnpack
```

Try a Cadence quantizer explicitly:

```bash
python3 experiments/pt2e-integer-lowering-lab/probe_pt2e_linear.py \
  --quantizer executorch.backends.cadence.aot.quantizer.quantizer.CadenceWith16BitLinearActivationsQuantizer \
  --out-dir /tmp/pt2e-lab-cadence-linear16
```

## Success Criterion

The report should be treated as useful only if it answers the structural
question. A graph that still contains `aten.linear`, `aten.matmul`, or `aten.mm`
on the hardware-critical path is not good enough just because tensor values are
range-limited.

## Known Results

Observed on 2026-06-25 with the Nix 26.05 ExecuTorch survey environment:

- `XNNPACKQuantizer`: `fail`, `float_linear_after_dequant`, with one
  `aten.linear`, nine `dequantize_per_tensor` occurrences, and seventeen
  `quantize_per_tensor` occurrences.
- `CadenceWith16BitLinearActivationsQuantizer`: `fail`,
  `float_linear_unquantized`, with one bare `aten.linear` and zero QDQ
  occurrences.
