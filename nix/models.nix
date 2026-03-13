{ registerModel, pythonWithTorch, pythonWithTinyStories, torchMlir, python
, tinyStories1mSnapshot, tinyStories1mRevision, matmulPy, matmulCompilePy
, matmulSrcDir, simDir, tinyStoriesCompilePy }: {
  matmul = registerModel {
    key = "matmul";
    name = "matmul";
    description =
      "Minimal local matmul PyTorch module used as smoke pipeline input.";
    source = {
      type = "local-python";
      entry = "${matmulPy}";
      export_script = "${matmulCompilePy}";
    };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export MATMUL_PY=${matmulPy}
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlir}/${python.sitePackages}:${torchMlir}/${python.sitePackages}/torch_mlir:''${PYTHONPATH:-}"
      python ${matmulCompilePy} > "$out"
    '';
  };

  "tiny-stories-1m-quant-int8" = registerModel {
    key = "tiny-stories-1m-quant-int8";
    name = "tiny-stories-1m-quant-int8";
    description =
      "TinyStories-1M full-quantized integer-only export (no dequant fallback).";
    source = {
      type = "huggingface-export";
      model_id = "roneneldan/TinyStories-1M";
      model_revision = tinyStories1mRevision;
      export_script = "${tinyStoriesCompilePy}";
      quantization = "runtime-int8";
    };
    linalgLowering = "loops";
    cfRequireNoFloat = true;
    handshakeUseLsq = true;
    useSplitSvForIl = true;
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export HOME="$TMPDIR"
      export HF_HOME="$TMPDIR/huggingface"
      export HF_HUB_DISABLE_TELEMETRY=1
      export TOKENIZERS_PARALLELISM=false
      export PYTHONPATH="${torchMlir}/${python.sitePackages}:${torchMlir}/${python.sitePackages}/torch_mlir:''${PYTHONPATH:-}"
      export TINYSTORIES_MODEL_PATH=${tinyStories1mSnapshot}
      export TINYSTORIES_LOCAL_ONLY=1
      export TINYSTORIES_QUANTIZATION=runtime-int8
      export TINYSTORIES_TORCH_MLIR_OUT="$out"
      python ${tinyStoriesCompilePy} >/dev/null
    '';
  };
}
