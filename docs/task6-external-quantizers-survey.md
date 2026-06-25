# Task 6 External Quantizer Survey

Date: 2026-06-23

This note tracks how the papers in `deliverables/1a-survey.org` handle
quantization, with emphasis on external PyTorch-adjacent quantizers. The goal is
to avoid treating labels such as `W4A8` or `W8A8` as evidence that a hardware
path is actually consuming packed integers.

## Executive Summary

The surveyed FPGA LLM papers mostly do **not** use PyTorch PT2E quantization as
their deployable backend. The recurring pattern is:

- use an external quantizer or model format to produce quantized model artifacts;
- pack those artifacts into a hardware-specific memory layout;
- implement dequantize/requantize or integer/fixed-point arithmetic explicitly
  in the accelerator.

The common external quantizers/formats found in this survey are:

| Quantizer or format | Survey occurrences | Common scheme | Notes |
| --- | ---: | --- | --- |
| SmoothQuant | 3 explicit | W8A8 | Used by FlightLLM, LoopLynx, and the Allo/spatial acceleration work. |
| torch-int | 1 explicit | W8A8 runtime kernels | Used by LoopLynx because PyTorch pseudo-int8 did not fully exploit GPU int8 performance. |
| AWQ / AutoAWQ | 1 explicit | INT4 weight-only with scales/zeros | Used by On-Device Qwen2.5; packed qweights/scales/zeros are dequantized before FP32 MACs. |
| GGML / llama.cpp quantization | 2 explicit | Q8_0, Q3_K/Q8_K-style BFP | Used by HLSTransform and SECDA-LLM style flows. Strong artifact story, but not PyTorch-native. |
| Native ternary / BitNet / MatMul-free | several | 1.58-bit or ternary weights | Usually not an external PTQ backend; the model architecture/training already assumes ternary weights. |
| PyTorch PT2E custom quantizer | 0 explicit in surveyed FPGA papers | backend-defined | Relevant to us, but not the dominant path in these papers. |

PyTorch's own current PT2E documentation is consistent with this: the flow needs
a backend-specific `Quantizer`, then `prepare_pt2e`, calibration/training, and
`convert_pt2e`. PyTorch says backend developers can write their own quantizer,
and the converted model contains integer computations only where possible. This
means "I want W4A8" is not enough; there must be a backend contract that maps
Q/DQ to deployable integer or fixed-point kernels.

## Paper-by-Paper Matrix

| ID | Paper/system | External quantizer or source format | Scheme claimed | Real integer artifact evidence | PyTorch relevance | Task 6 read |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | TeLLMe | No external quantizer identified; uses ternary/BitNet-style model assumptions | 1.58-bit weights, 8-bit activations | Hardware has quant/dequant unit and ternary table-lookup matmul | Not PyTorch quantization | Good architecture reference, not a PTQ backend. |
| 2 | KV260 tiled MatMul / TMMA | Unclear; paper says quantized DistilBERT and custom `FPGAQuantizedLinear` | Not clearly specified in paper text | Weak; wrapper/offload evidence, not full quantizer evidence | PyTorch wrapper, not PT2E | Treat as offload integration, not quantizer reference. |
| 3 | TerEffic | Native ternary MatMul-free model family | Ternary weights | Strong at hardware level, but assumes ternary model | Not PyTorch quantization | Useful if adopting native ternary models, not for post-training quantizing GPT-like weights. |
| 4 | MEADOW | No external quantizer found in paper text | Weight packing/indexing, encoded weights | Packing/indexing evidence, but not external quantizer evidence | Not PyTorch quantization | Memory compression/packing reference, not quantizer backend. |
| 5 | FlightLLM | SmoothQuant | W8A8 / mixed precision plus sparsity | Accelerator supports mixed precision and compressed sparse formats | SmoothQuant is PyTorch ecosystem adjacent; not PT2E | Strong evidence that an external quantizer is used before hardware mapping. |
| 6 | SECDA-LLM | llama.cpp / GGUF / GGML formats | Q3_K weights, Q8_K inputs, BFP superblocks | Strong: paper names GGML `MatMul_Q3_K_Q8_K` and superblock metadata | Not PyTorch-native | Very relevant artifact model: packed weights + scales + exact kernel contract. |
| 7 | MatMul-free LM | Native model design; ternary weights and modified layers | Ternary / matmul-free | Strong for that architecture, not PTQ | Not PyTorch quantization | Not applicable unless changing the model family. |
| 8 | LoopLynx | SmoothQuant plus torch-int | W8A8 | Strong warning: paper states PyTorch pseudo-int8 was insufficient and uses torch-int | Highly relevant to PyTorch trap | Best cautionary source for fake/pseudo int8 vs real kernel backend. |
| 9 | MASE | Own compiler/data-format search, not an external quantizer | MX / microscaling mixed precision, average 4-bit | Strong co-design evidence, but custom compiler path | PyTorch input possible, but quantizer is MASE-specific | Closest surveyed work to "make your own quantizer/compiler backend." |
| 10 | On-Device Qwen2.5 | AWQ / AutoAWQ | INT4/INT3-capable, implemented with INT4 qweights | Strong packed qweights/scales/zeros evidence; MACs are FP32 after dequant | PyTorch/HF-adjacent through AutoAWQ | Useful external quantizer, but beware: memory is INT4, compute is dequantized FP32. |
| 11 | HLSTransform | llama2.c / GGML-style Q8_0 | INT8 weights | Strong formula and Q8_0 reference; integer-only calculations claimed for FPGA path | Not PyTorch-native | Good simple symmetric quantization reference. |
| 12 | Allo / spatial acceleration | SmoothQuant for GPT2; other quantization frameworks supported | BERT W4A8, GPT W8A8 | Strong for SmoothQuant W8A8 GPT2 import; W4A8 BERT backend less explicit | PyTorch quantized model outputs used as oracle; not PT2E backend | Useful model-artifact import pattern. |
| 13 | AccLLM | Not verified in this pass | Sparse/quantized | Insufficient public quantizer detail in local survey | Unknown | Reference-only until quantizer artifacts are identified. |
| 14 | MLIR/CIRCT HLS demo | None | N/A | Not an LLM quantization paper | PyTorch compiler route | Methodology only. |
| 15 | StreamTensor | No quantizer backend described | W4A8 in evaluation | Packing/widening evidence; no calibration/backend algorithm found | PyTorch input via Torch-MLIR, but quantizer absent | Do not treat StreamTensor W4A8 as solved quantization. |
| 16 | FAST-Prefill | Not verified in this pass | Sparse attention focus | Quantizer not central in local survey | Unknown | Not a quantizer reference. |
| 17 | FlexLLM | Not verified in this pass | Stage-customized quantized inference | Needs paper-level follow-up | Unknown | Potentially relevant; unverified. |
| 18 | SkipOPU | Not verified in this pass | Dynamic compute allocation | Quantizer not central in local survey | Unknown | Not a quantizer reference. |
| 19 | Memory pipeline disaggregation | Not verified in this pass | System-level memory pipeline | Quantizer not central in local survey | Unknown | Not a quantizer reference. |
| 20 | LLM-driven DSE | None identified | N/A | DSE method, not quantizer | No | Irrelevant to backend selection. |
| 21 | XtraMAC | No model quantizer; datapath supports mixed precision | Mixed integer/FP MAC formats | Strong MAC artifact, no quantizer algorithm | No | Compute primitive reference only. |
| 22 | SpecMamba | Not verified in this pass | Custom Mamba accelerator | Quantizer detail unknown | Unknown | Follow-up only if Mamba path matters. |
| 23 | TeLLMe v2 | Native ternary/table-lookup approach | 1.58-bit weights, 8-bit activations | Similar to TeLLMe; no external PTQ backend identified | No | Native ternary reference. |
| 24 | LUT-LLM | Vector quantization / LUT computation, not verified as PyTorch external quantizer | Vector-quantized/table lookup | Needs paper-level follow-up | Unknown | Relevant conceptually, unverified. |
| 25 | CGLA LLM | Not verified in this pass | Unknown | Quantizer detail unknown | Unknown | Not usable yet. |
| 26 | PD-Swap | Not verified in this pass | Generic quantized edge LLM | Quantizer detail unknown | Unknown | Not usable yet. |
| 27 | N:M sparse/quantized co-design | Withdrawn | 4-bit + sparsity claims | Do not rely on it | No | Exclude from decisions. |

## External Quantizers and What They Actually Provide

### SmoothQuant

SmoothQuant is the most common external quantizer in the surveyed FPGA LLM
papers. FlightLLM compares against GPUs using vLLM and SmoothQuant. LoopLynx
uses SmoothQuant W8A8 for GPT-2 and explicitly notes that PyTorch pseudo-int8
was not enough for GPU performance, so the GPU baseline used `torch-int`.
The spatial acceleration work exports a GPT2 W8A8 model from SmoothQuant and
uses it for its on-board GPT accelerator.

Implication for Task 6: SmoothQuant is the strongest W8A8 candidate if the goal
is a known LLM PTQ flow. It still requires us to define the hardware artifact:
activation scale policy, weight layout, accumulator width, and requantization.

### torch-int

`torch-int` appears as a runtime/kernel companion to SmoothQuant in LoopLynx.
Its importance is conceptual: the authors did not trust PyTorch pseudo-int8 as a
performance backend. They used another library to obtain real int8 execution on
GPU.

Implication for Task 6: PyTorch Q/DQ in a graph is not enough. We need a backend
that consumes those Q/DQ nodes into integer/fixed-point hardware.

### AWQ / AutoAWQ

On-Device Qwen2.5 uses AWQ and AutoAWQ. The paper describes per-channel scaling
based on activation distributions, group sharing of scale parameters, and packed
`qweights`, scales, and zeros. The hardware unpacks INT4 qweights and zeros, but
then dequantizes to FP32 before MAC because the KV260 platform path did not
support lower-precision floating-point MACs.

Implication for Task 6: AWQ is attractive as an external PyTorch/HuggingFace
quantizer because it emits concrete qweight/scale/zero artifacts. However, the
surveyed FPGA use is **weight compression**, not integer-only W4A8 compute.

### llama.cpp / GGML / GGUF-style Quantization

SECDA-LLM and HLSTransform are the clearest examples of adopting a non-PyTorch
model artifact format. SECDA-LLM targets GGML's `MatMul_Q3_K_Q8_K` kernel:
3-bit BFP weights and 8-bit BFP inputs stored in superblocks with scale metadata.
HLSTransform uses a Q8_0-like symmetric section-wise int8 quantization from the
GGML/llama2.c lineage and claims integer-only FPGA calculations for the quantized
weights.

Implication for Task 6: This is less PyTorch-native, but it has the best
"artifact contract" shape: bytes, scales, block sizes, and kernels are explicit.

### Native Ternary / BitNet / MatMul-Free

TeLLMe, TeLLMe v2, TerEffic, and MatMul-free LM style work do not solve
post-training quantization for an ordinary TinyStories/GPT-style checkpoint.
They depend on a model family trained or architected for ternary weights.

Implication for Task 6: Useful if we are willing to change the model family; not
useful as an external quantizer backend for the current model.

### PyTorch PT2E / TorchAO

The surveyed FPGA papers do not appear to use PT2E as the deployment quantizer.
Still, PyTorch's current PT2E/TorchAO stack is directly relevant to us:

- PT2E quantization requires a backend-specific `Quantizer`.
- The official tutorial shows export -> `prepare_pt2e` -> calibrate/train ->
  `convert_pt2e` -> lowering.
- The quantizer is where backend capability and user quantization intent meet.
- TorchAO separates algorithms/flows, quantized tensor subclasses, primitive
  ops/kernels, and low-level dtypes.

Implication for Task 6: a real PyTorch route likely means writing an
`LLM2FPGAQuantizer` or consuming TorchAO-exported quantized tensor artifacts,
not just selecting a dtype label.

## Popularity Summary

Among the surveyed papers with explicit external quantizer evidence:

| Rank | External quantizer family | Count | Why it matters |
| ---: | --- | ---: | --- |
| 1 | SmoothQuant | 3 | Most common W8A8 LLM PTQ choice in the FPGA LLM survey. |
| 2 | GGML / llama.cpp formats | 2 | Strongest concrete packed-artifact story; less PyTorch-native. |
| 3 | AWQ / AutoAWQ | 1 | Strong PyTorch/HF-adjacent weight-only INT4 compression path. |
| 4 | torch-int | 1 | Not a quantizer alone, but explicit evidence that PyTorch pseudo-int8 is not enough. |

Scheme popularity:

| Scheme | Survey signal | Notes |
| --- | --- | --- |
| W8A8 | Strong | SmoothQuant-heavy; common for GPT-style FPGA comparisons. |
| W4A8 | Medium | Often analyzed or used for BERT/spatial designs; fewer papers identify a reusable quantizer backend. |
| INT4 weight-only | Medium | AWQ/AutoAWQ path; may dequantize before MAC. |
| Qx_K / BFP block formats | Medium | Strong in llama.cpp/GGML-derived flows. |
| Ternary / 1.58-bit | Strong as architecture trend | Usually native-model, not post-training quantization backend. |

## Recommendation for Task 6

Do not start with "W4A8" as a compiler annotation. Start with a model artifact
contract and choose a quantizer that can produce it.

Recommended investigation order:

1. **SmoothQuant W8A8**: most common in surveyed FPGA LLM work, closest to the
   W8A8 claims in LoopLynx/FlightLLM/Allo. Use it to establish real activation
   and weight scales and Q/DQ boundaries.
2. **AutoAWQ INT4 weight path**: good packed artifact story for weights, but
   accept that the surveyed FPGA implementation dequantizes to FP32. Use it only
   if weight memory is the first bottleneck.
3. **llama.cpp/GGUF Q8_0 or Qx_K**: best for explicit byte-level contracts, but
   requires stepping away from PyTorch-native export unless we build a converter.
4. **PyTorch PT2E/TorchAO custom backend**: long-term clean route. Requires a
   backend-specific quantizer and a lowering from quantized ops/tensor subclasses
   to the LLM2FPGA artifact/kernel contract.

Acceptance checklist for any quantizer:

- It emits integer payloads, not just fake-quantized float tensors.
- The artifact includes scale, zero-point, group size, axis, signedness, and
  packing order.
- The hardware accumulator and requantization rule are specified.
- There is a CPU oracle that consumes the exact same packed bytes.
- The compiler/hardware path proves that no float matmul is left in the claimed
  quantized kernel, unless the decision is explicitly "weight-compression only."
- DQD boundaries are named: every dequantize must be intentional, not accidental.

## Sources

- Local survey: `deliverables/1a-survey.org`.
- PyTorch PT2E quantization tutorial:
  https://docs.pytorch.org/ao/stable/pt2e_quantization/pt2e_quant_ptq.html
- TorchAO quantization overview:
  https://docs.pytorch.org/ao/stable/quantization_overview.html
- FlightLLM:
  https://arxiv.org/pdf/2401.03868
- LoopLynx:
  https://arxiv.org/pdf/2504.09561
- Understanding the Potential of FPGA-Based Spatial Acceleration for Large
  Language Model Inference:
  https://arxiv.org/pdf/2312.15159
- On-Device Qwen2.5:
  https://arxiv.org/pdf/2504.17376
- HLSTransform:
  https://arxiv.org/pdf/2405.00738
- SECDA-LLM:
  https://arxiv.org/pdf/2408.00462
- TeLLMe:
  https://arxiv.org/pdf/2504.16266
- StreamTensor:
  https://arxiv.org/pdf/2509.13694
