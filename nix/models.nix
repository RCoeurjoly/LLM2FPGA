{ registerModel, registerQuantizedModel, pythonWithTorch, pythonWithTorchAO
, pythonWithTinyStories, pythonWithTinyStoriesTorchAO, torchMlir, python
, tinyStories1m, matmulPy
, matmulAdapterPy, matmulSrcDir, torchaoInt8DynamicLinearAdapterPy
, torchaoInt8WeightOnlyLinearAdapterPy, torchaoAttentionBlockAdapterPy
, pt2eQuantLinearAdapterPy, pt2eStaticQuantLinearAdapterPy
, pt2eStaticQuantEmbeddingAdapterPy, pt2eStaticQuantEmbeddingComposableAdapterPy
, pt2eStaticQuantLayerNormAdapterPy, pt2eStaticQuantSoftmaxAdapterPy
, pt2eStaticQuantAttentionBlockAdapterPy
, pt2eStaticQuantAttentionBlockNoSoftmaxAdapterPy
, pt2eStaticQuantAttentionBlockNoLayerNormAdapterPy
, pt2eStaticQuantAttentionSoftmaxAdapterPy
, pt2eStaticQuantAttentionValueMatmulAdapterPy
, pt2eStaticQuantMatmulX86AdapterPy, tinyStoriesTorchaoAdapterPy
, tinyStoriesPt2eStaticQuantAdapterPy, fpPrimsSv, simDir, compilePyTorch }:
let
  torchMlirPythonPath =
    "${torchMlir}/${python.sitePackages}:${torchMlir}/${python.sitePackages}/torch_mlir";
in {
  matmul = registerModel {
    key = "matmul";
    name = "matmul";
    description =
      "Minimal local matmul PyTorch module used as smoke pipeline input.";
    source = {
      type = "local";
      path = "${matmulPy}";
    };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export MATMUL_PY="${matmulPy}"
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${matmulAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-quant-linear" = registerModel {
    key = "pt2e-quant-linear";
    name = "pt2e-quant-linear";
    description =
      "Minimal local PT2E dynamic-quantized Linear reproducer for torch-mlir quantized_decomposed lowering.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eQuantLinearAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "torchao-int8-dynamic-linear" = registerModel {
    key = "torchao-int8-dynamic-linear";
    name = "torchao-int8-dynamic-linear";
    description =
      "Minimal TorchAO int8 dynamic-activation/int8-weight Linear reproducer using the officially recommended quantize_ API.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorchAO ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${torchaoInt8DynamicLinearAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "torchao-int8-weight-only-linear" = registerModel {
    key = "torchao-int8-weight-only-linear";
    name = "torchao-int8-weight-only-linear";
    description =
      "Minimal TorchAO int8 weight-only Linear reproducer using the officially recommended quantize_ API.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorchAO ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${torchaoInt8WeightOnlyLinearAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "torchao-attention-block" = registerModel {
    key = "torchao-attention-block";
    name = "torchao-attention-block";
    description =
      "Small TorchAO attention-block reproducer combining LayerNorm, dynamically quantized Linear projections, attention softmax, and output projection.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorchAO ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${torchaoAttentionBlockAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-linear" = registerModel {
    key = "pt2e-static-quant-linear";
    name = "pt2e-static-quant-linear";
    description =
      "Minimal local PT2E static-quantized Linear reproducer for torch-mlir default-variant quantized_decomposed lowering.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantLinearAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-embedding" = registerModel {
    key = "pt2e-static-quant-embedding";
    name = "pt2e-static-quant-embedding";
    description =
      "Minimal local PT2E static-quantized Embedding reproducer for probing standard quantization coverage beyond linear.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantEmbeddingAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-embedding-composable" = registerModel {
    key = "pt2e-static-quant-embedding-composable";
    name = "pt2e-static-quant-embedding-composable";
    description =
      "Minimal local PT2E static-quantized Embedding reproducer using ComposableQuantizer with EmbeddingQuantizer plus XNNPACKQuantizer.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantEmbeddingComposableAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-layer-norm" = registerModel {
    key = "pt2e-static-quant-layer-norm";
    name = "pt2e-static-quant-layer-norm";
    description =
      "Minimal local PT2E static-quantized LayerNorm reproducer for probing normalization coverage on the standard quantization path.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantLayerNormAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-softmax" = registerModel {
    key = "pt2e-static-quant-softmax";
    name = "pt2e-static-quant-softmax";
    description =
      "Minimal local PT2E static-quantized Softmax reproducer for probing attention normalization coverage on the standard quantization path.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantSoftmaxAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-attention-block" = registerModel {
    key = "pt2e-static-quant-attention-block";
    name = "pt2e-static-quant-attention-block";
    description =
      "PT2E static-quantized attention-block reproducer combining LayerNorm, attention softmax, and quantized Linear projections.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantAttentionBlockAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-attention-block-no-softmax" = registerModel {
    key = "pt2e-static-quant-attention-block-no-softmax";
    name = "pt2e-static-quant-attention-block-no-softmax";
    description =
      "PT2E static-quantized attention-block reproducer with LayerNorm but without softmax.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantAttentionBlockNoSoftmaxAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-attention-block-no-layer-norm" = registerModel {
    key = "pt2e-static-quant-attention-block-no-layer-norm";
    name = "pt2e-static-quant-attention-block-no-layer-norm";
    description =
      "PT2E static-quantized attention-block reproducer with softmax but without LayerNorm.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantAttentionBlockNoLayerNormAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-attention-softmax" = registerModel {
    key = "pt2e-static-quant-attention-softmax";
    name = "pt2e-static-quant-attention-softmax";
    description =
      "PT2E static-quantized attention-score reproducer with qk score scaling and softmax, but without LayerNorm or value matmul.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantAttentionSoftmaxAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-attention-value-matmul" = registerModel {
    key = "pt2e-static-quant-attention-value-matmul";
    name = "pt2e-static-quant-attention-value-matmul";
    description =
      "PT2E static-quantized attention-core reproducer with qk score scaling and value matmul, but without softmax or LayerNorm.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantAttentionValueMatmulAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "pt2e-static-quant-matmul-x86" = registerModel {
    key = "pt2e-static-quant-matmul-x86";
    name = "pt2e-static-quant-matmul-x86";
    description =
      "Minimal local PT2E static-quantized matmul reproducer using X86InductorQuantizer to probe an alternative standard PT2E backend path.";
    source = { type = "local"; };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${pt2eStaticQuantMatmulX86AdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m" = registerQuantizedModel {
    key = "tiny-stories-1m";
    name = "tiny-stories-1m";
    description =
      "Quantized TinyStories-1M PT2E-static experiment retained for follow-up quantization work; not the current reviewer-facing Task 3 claim.";
    source = {
      type = "huggingface";
      model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${tinyStoriesPt2eStaticQuantAdapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-baseline-float" = registerModel {
    key = "tiny-stories-1m-baseline-float";
    name = "tiny-stories-1m-baseline-float";
    description =
      "Current Task 3 reviewer-facing TinyStories-1M baseline-float path using the standard torch.export plus torch-mlir FX importer flow, with explicit float extern support and per-file slang extern import to keep Yosys from OOM-killing on the split SV bundle.";
    source = {
      type = "huggingface";
      model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${tinyStories1m.adapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-dynamic-int8" = registerModel {
    key = "tiny-stories-1m-dynamic-int8";
    name = "tiny-stories-1m-dynamic-int8";
    description =
      "TinyStories-1M experiment using export-friendly PT2E dynamic quantization to find the first standard-path failure without handwritten model rewrites.";
    source = {
      type = "huggingface";
      model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${tinyStories1m.sourceDir}/model_adapter_dynamic_quant.py \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-torchao" = registerModel {
    key = "tiny-stories-1m-torchao";
    name = "tiny-stories-1m-torchao";
    description =
      "TinyStories-1M experiment using the current official TorchAO quantize_ route: weight-only embeddings plus dynamic-activation/int8-weight linears.";
    source = {
      type = "huggingface";
      model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
    };
    torchInputBuildInputs = [ pythonWithTinyStoriesTorchAO ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${tinyStoriesTorchaoAdapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-pt2e-static" = registerQuantizedModel {
    key = "tiny-stories-1m-pt2e-static";
    name = "tiny-stories-1m-pt2e-static";
    description =
      "Historical alias of the canonical PT2E-static TinyStories-1M XNNPACK-only quantized route.";
    source = {
      type = "huggingface";
      model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${tinyStoriesPt2eStaticQuantAdapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };
}
