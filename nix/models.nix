{ registerModel, pythonWithTorch, pythonWithTinyStories, torchMlir, python
, tinyStories1mSnapshot, tinyStories1mRevision, repoRoot }: {
  matmul = registerModel {
    key = "matmul";
    name = "matmul";
    description =
      "Minimal local matmul PyTorch module used as smoke pipeline input.";
    source = {
      type = "local-python";
      entry = "${repoRoot}/src/matmul.py";
      export_script = "${repoRoot}/src/compile-pytorch.py";
    };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export MATMUL_PY=${repoRoot}/src/matmul.py
      export PYTHONPATH="${repoRoot}/src:${repoRoot}/sim:${torchMlir}/${python.sitePackages}:${torchMlir}/${python.sitePackages}/torch_mlir:''${PYTHONPATH:-}"
      python ${repoRoot}/src/compile-pytorch.py > "$out"
    '';
  };

  "tiny-stories-1m" = registerModel {
    key = "tiny-stories-1m";
    name = "tiny-stories-1m";
    description = "TinyStories-1M torch-MLIR exported in a Nix derivation.";
    source = {
      type = "huggingface-export";
      model_id = "roneneldan/TinyStories-1M";
      model_revision = tinyStories1mRevision;
      export_script = "${repoRoot}/TinyStories/compile-pytorch.py";
    };
    linalgLowering = "loops";
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export HOME="$TMPDIR"
      export HF_HOME="$TMPDIR/huggingface"
      export HF_HUB_DISABLE_TELEMETRY=1
      export TOKENIZERS_PARALLELISM=false
      export PYTHONPATH="${torchMlir}/${python.sitePackages}:${torchMlir}/${python.sitePackages}/torch_mlir:''${PYTHONPATH:-}"
      export TINYSTORIES_MODEL_PATH=${tinyStories1mSnapshot}
      export TINYSTORIES_LOCAL_ONLY=1
      export TINYSTORIES_TORCH_MLIR_OUT="$out"
      python ${repoRoot}/TinyStories/compile-pytorch.py >/dev/null
    '';
  };

  "tiny-stories-1m-quant-int8" = registerModel {
    key = "tiny-stories-1m-quant-int8";
    name = "tiny-stories-1m-quant-int8";
    description =
      "TinyStories-1M integer-only surrogate export (int8 embeddings + int8 LM head).";
    source = {
      type = "huggingface-export";
      model_id = "roneneldan/TinyStories-1M";
      model_revision = tinyStories1mRevision;
      export_script = "${repoRoot}/TinyStories/compile-pytorch.py";
      quantization = "runtime-int8";
    };
    linalgLowering = "loops";
    cfRequireNoFloat = true;
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
      python ${repoRoot}/TinyStories/compile-pytorch.py >/dev/null
    '';
  };
}
