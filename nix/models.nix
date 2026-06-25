{ registerModel, registerLsqModel, registerQuantizedModel, pythonWithTorch, pythonWithTinyStories
, pythonWithTinyStoriesTorchAO, torchMlir, python, tinyStories1m, matmulPy
, matmulAdapterPy, matmulSrcDir, gemv64Py, gemv64AdapterPy, gemv64Int16Py
, gemv64Int16AdapterPy, task6RectGemvPy, task6RectGemvAdapterPy
, task6RectGemvPt2eStaticQuantAdapterPy
, tinyStoriesTorchaoAdapterPy, tinyStoriesRepresentativeCoreAdapterPy
, tinyStoriesRepresentativeCorePt2eStaticInt4QuantAdapterPy
, tinyStoriesRepresentativeCorePt2eStaticQuantAdapterPy
, tinyStoriesPt2eStaticQuantAdapterPy
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

  "task6-l0-gemv64-int16" = registerModel {
    key = "task6-l0-gemv64-int16";
    name = "task6-l0-gemv64-int16";
    description =
      "StreamTensor-lite L0 synthetic external-weight 64x64 GEMV kernel using int16 arithmetic.";
    source = {
      type = "local";
      path = "${gemv64Int16Py}";
    };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      python ${compilePyTorch} \
        --adapter ${gemv64Int16AdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "task6-l1-c-fc-redirect" = registerModel {
    key = "task6-l1-c-fc-redirect";
    name = "task6-l1-c-fc-redirect";
    description =
      "Task 6 L1 redirected kernel-only GEMV proof for transformer.h.0.mlp.c_fc at the selected batch_matmul site before bias-add.";
    source = {
      type = "local";
      path = "${task6RectGemvPy}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TASK6_RECT_GEMV_IN_DIM=4
      export TASK6_RECT_GEMV_OUT_DIM=16
      python ${compilePyTorch} \
        --adapter ${task6RectGemvAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "task6-l1-c-fc-redirect-lsq" = registerLsqModel {
    key = "task6-l1-c-fc-redirect-lsq";
    name = "task6-l1-c-fc-redirect-lsq";
    description =
      "Task 6 L1 redirected kernel-only GEMV proof for transformer.h.0.mlp.c_fc using the LSQ handshake lowering on the same extracted float32 contract.";
    source = {
      type = "local";
      path = "${task6RectGemvPy}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TASK6_RECT_GEMV_IN_DIM=4
      export TASK6_RECT_GEMV_OUT_DIM=16
      python ${compilePyTorch} \
        --adapter ${task6RectGemvAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "task6-l1-c-fc-redirect-pt2e-static" = registerQuantizedModel {
    key = "task6-l1-c-fc-redirect-pt2e-static";
    name = "task6-l1-c-fc-redirect-pt2e-static";
    description =
      "Task 6 L1 redirected kernel-only GEMV proof for transformer.h.0.mlp.c_fc using the PT2E-static quantized route on the same extracted representative-core contract.";
    source = {
      type = "local";
      path = "${task6RectGemvPy}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TASK6_RECT_GEMV_IN_DIM=4
      export TASK6_RECT_GEMV_OUT_DIM=16
      python ${compilePyTorch} \
        --adapter ${task6RectGemvPt2eStaticQuantAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "task6-l1-c-proj-redirect" = registerModel {
    key = "task6-l1-c-proj-redirect";
    name = "task6-l1-c-proj-redirect";
    description =
      "Task 6 L1 redirected kernel-only GEMV proof for transformer.h.0.mlp.c_proj at the selected batch_matmul site before bias-add.";
    source = {
      type = "local";
      path = "${task6RectGemvPy}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TASK6_RECT_GEMV_IN_DIM=16
      export TASK6_RECT_GEMV_OUT_DIM=4
      python ${compilePyTorch} \
        --adapter ${task6RectGemvAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "task6-l2-c-fc-redirect" = registerModel {
    key = "task6-l2-c-fc-redirect";
    name = "task6-l2-c-fc-redirect";
    description =
      "Task 6 L2 redirected kernel-only GEMV proof for tiny-stories-v1k-h64-l1 transformer.h.0.mlp.c_fc at the selected batch_matmul site before bias-add.";
    source = {
      type = "local";
      path = "${task6RectGemvPy}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TASK6_RECT_GEMV_IN_DIM=64
      export TASK6_RECT_GEMV_OUT_DIM=256
      python ${compilePyTorch} \
        --adapter ${task6RectGemvAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "task6-l2-c-fc-redirect-tile64" = registerModel {
    key = "task6-l2-c-fc-redirect-tile64";
    name = "task6-l2-c-fc-redirect-tile64";
    description =
      "Task 6 L2 redirected 64x64 GEMV tile used to test whether a sequential 4x64 output wrapper beats the monolithic 64x256 c_fc kernel on fit.";
    source = {
      type = "local";
      path = "${task6RectGemvPy}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TASK6_RECT_GEMV_IN_DIM=64
      export TASK6_RECT_GEMV_OUT_DIM=64
      python ${compilePyTorch} \
        --adapter ${task6RectGemvAdapterPy} \
        --out "$out" >/dev/null
    '';
  };

  "task6-l2-c-fc-redirect-tile64-lsq" = registerLsqModel {
    key = "task6-l2-c-fc-redirect-tile64-lsq";
    name = "task6-l2-c-fc-redirect-tile64-lsq";
    description =
      "Task 6 L2 redirected 64x64 GEMV tile using the LSQ handshake lowering on the same extracted float32 contract.";
    source = {
      type = "local";
      path = "${task6RectGemvPy}";
    };
    allowHwExterns = true;
    slangPerFileExternModules = true;
    inherit fpPrimsSv;
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export PYTHONPATH="${matmulSrcDir}:${simDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TASK6_RECT_GEMV_IN_DIM=64
      export TASK6_RECT_GEMV_OUT_DIM=64
      python ${compilePyTorch} \
        --adapter ${task6RectGemvAdapterPy} \
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

  "tiny-stories-1m-baseline-int8" = registerModel {
    key = "tiny-stories-1m-baseline-int8";
    name = "tiny-stories-1m-baseline-int8";
    description =
      "Task 6 TinyStories-1M PT2E-static int8 route, using non-LSQ lowering for current CIRCT compatibility.";
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
        --adapter ${tinyStoriesPt2eStaticQuantAdapterPy} \
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

  "tiny-stories-1m-representative-core-pt2e-static" = registerQuantizedModel {
    key = "tiny-stories-1m-representative-core-pt2e-static";
    name = "tiny-stories-1m-representative-core-pt2e-static";
    description =
      "Quantized representative-core TinyStories PT2E-static experiment kept as the minimized full-model Task 6 quantization replay surface.";
    source = {
      type = "derived";
      base_model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
      profile = "representative-core-min";
      vocab_size = 32;
      num_layers = 2;
      max_position_embeddings = 4;
      window_size = 2;
      hidden_size = 2;
      num_heads = 1;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TINYSTORIES_CORE_VOCAB_SIZE=32
      export TINYSTORIES_CORE_NUM_LAYERS=2
      export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=4
      export TINYSTORIES_CORE_WINDOW_SIZE=2
      export TINYSTORIES_CORE_HIDDEN_SIZE=2
      export TINYSTORIES_CORE_NUM_HEADS=1
      python ${compilePyTorch} \
        --adapter ${tinyStoriesRepresentativeCorePt2eStaticQuantAdapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-representative-core-pt2e-static-nolsq" = registerModel {
    inherit fpPrimsSv;
    key = "tiny-stories-1m-representative-core-pt2e-static-nolsq";
    name = "tiny-stories-1m-representative-core-pt2e-static-nolsq";
    allowHwExterns = true;
    slangPerFileExternModules = true;
    description =
      "Experimental quantized representative-core TinyStories PT2E-static replay through the default non-LSQ compiler pipeline. This exists only to test whether int8 representative-core can reach RTL/resource evidence without the current lower-cf-to-handshake=lsq blocker.";
    source = {
      type = "derived";
      base_model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
      profile = "representative-core-min";
      quantization = "pt2e-static-int8";
      lowering = "default-handshake-nolsq";
      vocab_size = 32;
      num_layers = 2;
      max_position_embeddings = 4;
      window_size = 2;
      hidden_size = 2;
      num_heads = 1;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TINYSTORIES_CORE_VOCAB_SIZE=32
      export TINYSTORIES_CORE_NUM_LAYERS=2
      export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=4
      export TINYSTORIES_CORE_WINDOW_SIZE=2
      export TINYSTORIES_CORE_HIDDEN_SIZE=2
      export TINYSTORIES_CORE_NUM_HEADS=1
      python ${compilePyTorch} \
        --adapter ${tinyStoriesRepresentativeCorePt2eStaticQuantAdapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-representative-core-pt2e-static-int4-nolsq" = registerModel {
    inherit fpPrimsSv;
    key = "tiny-stories-1m-representative-core-pt2e-static-int4-nolsq";
    name = "tiny-stories-1m-representative-core-pt2e-static-int4-nolsq";
    allowHwExterns = true;
    slangPerFileExternModules = true;
    description =
      "Experimental int4-range quantized representative-core TinyStories PT2E-static replay through the default non-LSQ compiler pipeline. This exists as a bounded kill-test for compiler-to-whole-model-RTL viability.";
    source = {
      type = "derived";
      base_model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
      profile = "representative-core-min";
      quantization = "pt2e-static-int4-range";
      lowering = "default-handshake-nolsq";
      vocab_size = 32;
      num_layers = 2;
      max_position_embeddings = 4;
      window_size = 2;
      hidden_size = 2;
      num_heads = 1;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TINYSTORIES_CORE_VOCAB_SIZE=32
      export TINYSTORIES_CORE_NUM_LAYERS=2
      export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=4
      export TINYSTORIES_CORE_WINDOW_SIZE=2
      export TINYSTORIES_CORE_HIDDEN_SIZE=2
      export TINYSTORIES_CORE_NUM_HEADS=1
      python ${compilePyTorch} \
        --adapter ${tinyStoriesRepresentativeCorePt2eStaticInt4QuantAdapterPy} \
            --model-path ${tinyStories1m.snapshot} \
            --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-representative-core-pt2e-static-w2a2-nolsq" = registerModel {
    inherit fpPrimsSv;
    key = "tiny-stories-1m-representative-core-pt2e-static-w2a2-nolsq";
    name = "tiny-stories-1m-representative-core-pt2e-static-w2a2-nolsq";
    allowHwExterns = true;
    slangPerFileExternModules = true;
    description =
      "Representative-core PT2E-static W2A2 replay through the default non-LSQ compiler pipeline. Added for milestone-path quantization sweep; useful for integer-only viability checks.";
    source = {
      type = "derived";
      base_model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
      profile = "representative-core-min";
      quantization = "pt2e-static-w2a2";
      lowering = "default-handshake-nolsq";
      vocab_size = 32;
      num_layers = 2;
      max_position_embeddings = 4;
      window_size = 2;
      hidden_size = 2;
      num_heads = 1;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TINYSTORIES_CORE_VOCAB_SIZE=32
      export TINYSTORIES_CORE_NUM_LAYERS=2
      export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=4
      export TINYSTORIES_CORE_WINDOW_SIZE=2
      export TINYSTORIES_CORE_HIDDEN_SIZE=2
      export TINYSTORIES_CORE_NUM_HEADS=1
      export TINYSTORIES_PYTORCHAO_ACTIVATION_BITS=2
      export TINYSTORIES_PYTORCHAO_WEIGHT_BITS=2
      python ${compilePyTorch} \
        --adapter ${tinyStoriesRepresentativeCorePt2eStaticQuantAdapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$out" >/dev/null
    '';
  };

  "tiny-stories-1m-representative-core-pt2e-static-w2a2-executorch-fpga-backend-nolsq" = registerModel {
    inherit fpPrimsSv;
    key = "tiny-stories-1m-representative-core-pt2e-static-w2a2-executorch-fpga-backend-nolsq";
    name = "tiny-stories-1m-representative-core-pt2e-static-w2a2-executorch-fpga-backend-nolsq";
    allowHwExterns = true;
    slangPerFileExternModules = true;
    description =
      "Representative-core PT2E-static W2A2 replay through the default non-LSQ compiler pipeline after ExecuTorch backend capture. The pipeline input is still the PT2E torch-mlir model, but the step fails fast when representative core QDQ islands are not structurally capturable.";
    source = {
      type = "derived";
      base_model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
      profile = "representative-core-min";
      quantization = "pt2e-static-w2a2-executorch-fpga-backend";
      lowering = "default-handshake-nolsq";
      vocab_size = 32;
      num_layers = 2;
      max_position_embeddings = 4;
      window_size = 2;
      hidden_size = 2;
      num_heads = 1;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      set -euo pipefail
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TINYSTORIES_CORE_VOCAB_SIZE=32
      export TINYSTORIES_CORE_NUM_LAYERS=2
      export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=4
      export TINYSTORIES_CORE_WINDOW_SIZE=2
      export TINYSTORIES_CORE_HIDDEN_SIZE=2
      export TINYSTORIES_CORE_NUM_HEADS=1
      export TINYSTORIES_PYTORCHAO_ACTIVATION_BITS=2
      export TINYSTORIES_PYTORCHAO_WEIGHT_BITS=2
      tmp_dir="$(mktemp -d)"
      export TINYSTORIES_DUMP_PT2E_QUANTIZED_GRAPH="$tmp_dir/quantized.fx.txt"
      python ${compilePyTorch} \
        --adapter ${tinyStoriesRepresentativeCorePt2eStaticQuantAdapterPy} \
        --model-path ${tinyStories1m.snapshot} \
        --out "$tmp_dir/torch.mlir" >/dev/null
      python ${./src/llm2fpga_executorch_backend/cli.py} \
        --graph "$TINYSTORIES_DUMP_PT2E_QUANTIZED_GRAPH" \
        --out-dir "$tmp_dir/llm2fpga-executorch-backend-capture" \
        --model-label tiny-stories-1m-representative-core-pt2e-static-w2a2-nolsq \
        --require-representative-core
      cp "$tmp_dir/torch.mlir" "$out"
    '';
  };

  "tiny-stories-1m-representative-core-pt2e-static-w2a2-reference-rewrite-nolsq" = registerModel {
    inherit fpPrimsSv;
    key = "tiny-stories-1m-representative-core-pt2e-static-w2a2-reference-rewrite-nolsq";
    name = "tiny-stories-1m-representative-core-pt2e-static-w2a2-reference-rewrite-nolsq";
    allowHwExterns = true;
    slangPerFileExternModules = true;
    description =
      "Representative-core PT2E-static W2A2 replay through the default non-LSQ compiler pipeline after PT2E reference_representation_rewrite. This isolates whether PyTorch's reference representation rewrite reduces QDQ before torch-mlir/CIRCT.";
    source = {
      type = "derived";
      base_model_id = tinyStories1m.modelId;
      inherit (tinyStories1m) revision;
      profile = "representative-core-min";
      quantization = "pt2e-static-w2a2-reference-rewrite";
      lowering = "default-handshake-nolsq";
      vocab_size = 32;
      num_layers = 2;
      max_position_embeddings = 4;
      window_size = 2;
      hidden_size = 2;
      num_heads = 1;
    };
    torchInputBuildInputs = [ pythonWithTinyStories ];
    torchInputCommand = ''
      export PYTHONPATH="${tinyStories1m.sourceDir}:${torchMlirPythonPath}:''${PYTHONPATH:-}"
      export TINYSTORIES_CORE_VOCAB_SIZE=32
      export TINYSTORIES_CORE_NUM_LAYERS=2
      export TINYSTORIES_CORE_MAX_POSITION_EMBEDDINGS=4
      export TINYSTORIES_CORE_WINDOW_SIZE=2
      export TINYSTORIES_CORE_HIDDEN_SIZE=2
      export TINYSTORIES_CORE_NUM_HEADS=1
      export TINYSTORIES_PYTORCHAO_ACTIVATION_BITS=2
      export TINYSTORIES_PYTORCHAO_WEIGHT_BITS=2
      export TINYSTORIES_PT2E_REFERENCE_REPRESENTATION_REWRITE=1
      python ${compilePyTorch} \
        --adapter ${tinyStoriesRepresentativeCorePt2eStaticQuantAdapterPy} \
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
