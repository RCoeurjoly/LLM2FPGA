{ registerModel, registerQuantizedModel, pythonWithTorch, pythonWithTinyStories
, pythonWithTinyStoriesTorchAO, torchMlir, python, tinyStories1m, matmulPy
, matmulAdapterPy, matmulSrcDir, gemv64Py, gemv64AdapterPy
, tinyStoriesTorchaoAdapterPy
, tinyStoriesRepresentativeCoreAdapterPy, tinyStoriesPt2eStaticQuantAdapterPy
, fpPrimsSv, simDir, compilePyTorch, representativeCoreSweepSpecs }:
let
  torchMlirPythonPath =
    "${torchMlir}/${python.sitePackages}:${torchMlir}/${python.sitePackages}/torch_mlir";
  mkRepresentativeCoreModel = spec:
    let
      key = spec.key;
      name = key;
      inherit (spec) profile vocabSize numLayers maxPositionEmbeddings windowSize
        hiddenSize numHeads;
    in {
      inherit name;
      value = registerModel {
        inherit key name;
        description =
          "Deterministic reduced GPT-Neo core derived from the TinyStories-1M config for fast Task 6 iteration. This representative-core sweep point is intentionally minimized and must justify itself by preserving baseline MLIR op coverage before it is trusted for Task 6 iteration decisions.";
        source = {
          type = "derived";
          base_model_id = tinyStories1m.modelId;
          inherit (tinyStories1m) revision;
          inherit profile;
          vocab_size = vocabSize;
          num_layers = numLayers;
          max_position_embeddings = maxPositionEmbeddings;
          window_size = windowSize;
          hidden_size = hiddenSize;
          num_heads = numHeads;
        };
        allowHwExterns = true;
        slangPerFileExternModules = true;
        inherit fpPrimsSv;
        torchInputBuildInputs = [ pythonWithTinyStories ];
        torchInputCommand = ''
          export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
          export TINYSTORIES_CORE_VOCAB_SIZE=${toString vocabSize}
          export TINYSTORIES_CORE_NUM_LAYERS=${toString numLayers}
          export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=${toString maxPositionEmbeddings}
          export TINYSTORIES_CORE_WINDOW_SIZE=${toString windowSize}
          export TINYSTORIES_CORE_HIDDEN_SIZE=${toString hiddenSize}
          export TINYSTORIES_CORE_NUM_HEADS=${toString numHeads}
          python ${compilePyTorch} \
            --adapter ${tinyStoriesRepresentativeCoreAdapterPy} \
            --model-path ${tinyStories1m.snapshot} \
            --out "$out" >/dev/null
        '';
      };
    };
  representativeCoreModels =
    builtins.listToAttrs (map mkRepresentativeCoreModel representativeCoreSweepSpecs);
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

  "task6-l0-gemv64" = registerModel {
    key = "task6-l0-gemv64";
    name = "task6-l0-gemv64";
    description =
      "StreamTensor-lite L0 synthetic external-weight 64x64 GEMV kernel.";
    source = {
      type = "local";
      path = "${gemv64Py}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${gemv64AdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-baseline-float" = registerModel {
    key = "tiny-stories-1m-baseline-float";
    name = "tiny-stories-1m-baseline-float";
    description =
      "Task 6 baseline TinyStories-1M path using the standard torch.export plus torch-mlir FX importer flow, with explicit float extern support and per-file slang extern import.";
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

  "tiny-stories-1m" = registerQuantizedModel {
    key = "tiny-stories-1m";
    name = "tiny-stories-1m";
    description =
      "Quantized TinyStories-1M PT2E-static experiment retained for Task 6 quantization follow-up.";
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

  "tiny-stories-1m-dynamic-int8" = registerModel {
    key = "tiny-stories-1m-dynamic-int8";
    name = "tiny-stories-1m-dynamic-int8";
    description =
      "TinyStories-1M experiment using export-friendly PT2E dynamic quantization.";
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
      "TinyStories-1M experiment using the current official TorchAO quantize_ route.";
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
} // representativeCoreModels
