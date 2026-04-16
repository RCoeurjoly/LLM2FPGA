# Task 6 MoE Feasibility

## Baseline anchor

Reference bundle:

- [artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization](../artifacts/task6/baselines/tiny-stories-1m-baseline-float-selftest-all-memory-utilization)

Baseline summary from the copied bundle:

- LUTs: 40,416,086 / 298,600 = 13,535.19%
- FFs: 58,072,527 / 597,200 = 9,724.13%
- BRAM36: 0 / 955
- DSP: 0 / 1920

Inference for this repo:

- the current failure is an all-weights-in-logic problem, not a BRAM or DSP
  saturation problem
- MoE only helps Task 6 if it reduces the amount of parameter state that must
  be resident on chip at one time

## Gating verdict: TinyStories-1M to MoE

Verdict: TinyStories-to-MoE is not a meaningful direct Task 6 adaptation. Treat
it as a different model-family experiment.

Why:

- the current repo path treats TinyStories-1M as a dense
  `AutoModelForCausalLM` checkpoint through the standard
  [`torch.export` -> `torch-mlir` flow](../scripts/compile-pytorch.py)
- MoE conversion from a dense checkpoint is described in the literature as
  sparse upcycling, meaning MoE layers are constructed from a dense checkpoint
  and then trained further, not toggled on at inference time
- Hugging Face's Qwen2MoE docs describe the released MoE model as upcycled from
  a dense Qwen model, which matches that framing

For Task 6, that means a TinyStories-to-MoE path would require model surgery
plus retraining or fine-tuning before export. That is not the same question as
"can this existing TinyStories-1M checkpoint be made smaller in this FPGA
pipeline?"

## Candidate path if MoE is tested anyway

Candidate existing small PyTorch MoE model:

- [`rohitnagareddy/AdbhutMOE`](https://huggingface.co/rohitnagareddy/AdbhutMOE)

Why this is the least-bad MoE pipeline candidate:

- it is explicitly small: 15.7M parameters
- it is documented as a PyTorch + Transformers causal LM
- it uses a compact Mixtral-style setup: 4 layers, hidden size 256, 4
  attention heads, 8 experts per layer, 2 active experts per token
- it is small enough to exercise routing behavior without jumping straight to a
  multi-billion-parameter MoE checkpoint

Important limitation versus the TinyStories-1M baseline:

- this candidate is not smaller than TinyStories-1M in total parameters
- its only plausible FPGA benefit is a smaller active expert footprint, not a
  smaller total weight set

## Resource story by path

| Path | Comparison basis | Expected benefit | Main costs / risks | Verdict |
| --- | --- | --- | --- | --- |
| Adapt TinyStories-1M into MoE | TinyStories-1M baseline + MoE papers | Only helps if inactive experts stop being resident on chip | Requires upcycling/retraining, router insertion, expert partitioning, token-to-expert dispatch, extra memory traffic | Reject as the primary Task 6 path |
| Try a small existing MoE model | Existing MoE checkpoint vs baseline board constraints | Could reduce active expert footprint if experts are stored off chip or banked outside the synthesized hot path | Router top-k, gather/scatter, merge logic, irregular control, likely compiler friction, and more total weights than TinyStories-1M | Viable only as a narrow feasibility probe |

## Expected FPGA benefit and likely costs

Expected benefit mechanism:

- primary MoE advantage is that only a subset of experts is active per token
- official MoE model docs describe this as a large gap between total parameters
  and active parameters per token
- for this repo, that helps only if non-selected experts are not synthesized
  into LUT/FF fabric at the same time

Inference for this repo:

- if the current flow still materializes every expert weight into emitted SV and
  Yosys logic, MoE does not solve the copied baseline problem
- in that case MoE increases control complexity while preserving or worsening
  the dominant on-chip residency issue
- MoE becomes more credible only when paired with DDR3 or another explicit
  expert-externalization plan

Likely costs:

- router MLP, softmax, and top-k selection
- token regrouping into per-expert batches, then merge-back
- extra control and buffering around sparse dispatch
- irregular expert memory movement if experts are externalized
- frontend/compiler risk from index-heavy routing ops that are less regular than
  the current dense TinyStories path

## Final recommendation

Final recommendation: `try existing MoE model`

Interpretation:

- reject TinyStories-to-MoE adaptation as a meaningful Task 6 reduction path
- if MoE is explored at all, use one small existing checkpoint such as
  `rohitnagareddy/AdbhutMOE` as a narrow pipeline feasibility probe
- keep MoE alive only if it quickly pairs with DDR3 or another concrete expert
  externalization mechanism; otherwise it is weaker than the direct
  quantization, external-memory, handshake, and RTL-simplification tracks

## Primary sources

- TinyStories-1M model card:
  <https://huggingface.co/roneneldan/TinyStories-1M>
- Sparse Upcycling: Training Mixture-of-Experts from Dense Checkpoints:
  <https://arxiv.org/abs/2212.05055>
- Qwen2MoE documentation:
  <https://huggingface.co/docs/transformers/model_doc/qwen2_moe>
- OLMoE documentation:
  <https://huggingface.co/docs/transformers/model_doc/olmoe>
- AdbhutMOE model card:
  <https://huggingface.co/rohitnagareddy/AdbhutMOE>
