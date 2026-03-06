{ pkgs, mlir, circt, yosysPkg, yosysSlang, torchMlir, python, pipelineScripts
, fpPrimsSv ? null }:
let
  stageMap = [
    {
      pkg = "torch";
      attr = "torch";
    }
    {
      pkg = "linalg";
      attr = "linalg";
    }
    {
      pkg = "cf";
      attr = "cf";
    }
    {
      pkg = "cf-stats";
      attr = "cfStats";
    }
    {
      pkg = "handshake";
      attr = "handshake";
    }
    {
      pkg = "hs-ext";
      attr = "hsExt";
    }
    {
      pkg = "hw0";
      attr = "hw0";
    }
    {
      pkg = "hw";
      attr = "hw";
    }
    {
      pkg = "hw-clean";
      attr = "hwClean";
    }
    {
      pkg = "sv";
      attr = "sv";
    }
    {
      pkg = "il";
      attr = "il";
    }
    {
      pkg = "yosys-stat";
      attr = "yosysStat";
    }
  ];

  mkTorchDerivation = { name, torchMlirInput }:
    pkgs.runCommand "${name}-torch.mlir" { } ''
      cp ${torchMlirInput} "$out"
    '';

  mkLinalgDerivation = { name, torch }:
    pkgs.runCommand "${name}-linalg.mlir" { buildInputs = [ torchMlir ]; } ''
      if [ -x "${torchMlir}/bin/torch-mlir-opt" ]; then
        export TORCH_MLIR_OPT=${torchMlir}/bin/torch-mlir-opt
      elif [ -x "${torchMlir}/${python.sitePackages}/torch_mlir/_mlir_libs/torch-mlir-opt" ]; then
        export TORCH_MLIR_OPT=${torchMlir}/${python.sitePackages}/torch_mlir/_mlir_libs/torch-mlir-opt
      elif [ -x "${torchMlir}/${python.sitePackages}/torch_mlir/torch_mlir/_mlir_libs/torch-mlir-opt" ]; then
        export TORCH_MLIR_OPT=${torchMlir}/${python.sitePackages}/torch_mlir/torch_mlir/_mlir_libs/torch-mlir-opt
      else
        echo "Unable to locate torch-mlir-opt in ${torchMlir}" >&2
        exit 1
      fi
      ${pkgs.bash}/bin/bash ${pipelineScripts}/torch_to_linalg.sh ${torch} "$out"
    '';

  mkCfDerivation = { name, linalg, linalgLowering ? "affine"
    , cfRequireNoFloat ? false }:
    pkgs.runCommand "${name}-cf.mlir" { buildInputs = [ mlir ]; } ''
      export MLIR_OPT=${mlir}/bin/mlir-opt
      export LINALG_LOWERING=${linalgLowering}
      export CF_REQUIRE_NO_FLOAT=${if cfRequireNoFloat then "1" else "0"}
      ${pkgs.bash}/bin/bash ${pipelineScripts}/linalg_to_cf.sh ${linalg} "$out"
    '';

  mkCfStatsDerivation = { name, cf }:
    pkgs.runCommand "${name}-cf.stats" { buildInputs = [ mlir ]; } ''
      export MLIR_OPT=${mlir}/bin/mlir-opt
      ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_stats.sh ${cf} "$out"
    '';

  mkHandshakeDerivation =
    { name, cf, handshakeInsertBuffers ? true, circtPkg ? circt }:
    pkgs.runCommand "${name}-handshake.mlir" {
      buildInputs = [ mlir circtPkg ];
    } ''
      export MLIR_OPT=${mlir}/bin/mlir-opt
      export CIRCT_OPT=${circtPkg}/bin/circt-opt
      if [ "${if handshakeInsertBuffers then "1" else "0"}" = "1" ]; then
        export HANDSHAKE_INSERT_BUFFERS=1
      else
        export HANDSHAKE_INSERT_BUFFERS=0
      fi
      ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_to_handshake.sh ${cf} "$out"
    '';

  mkHsExtDerivation = { name, handshake, circtPkg ? circt }:
    pkgs.runCommand "${name}-hs-ext.mlir" { buildInputs = [ circtPkg ]; } ''
      export CIRCT_OPT=${circtPkg}/bin/circt-opt
      ${pkgs.bash}/bin/bash ${pipelineScripts}/handshake_to_hs_ext.sh ${handshake} "$out"
    '';

  mkHw0Derivation = { name, hsExt, circtPkg ? circt }:
    pkgs.runCommand "${name}-hw0.mlir" {
      buildInputs = [ circtPkg pkgs.perl ];
    } ''
      export CIRCT_OPT=${circtPkg}/bin/circt-opt
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hs_ext_to_hw0.sh ${hsExt} "$out"
    '';

  mkHwDerivation = { name, hw0, circtPkg ? circt }:
    pkgs.runCommand "${name}-hw.mlir" { buildInputs = [ circtPkg ]; } ''
      export CIRCT_OPT=${circtPkg}/bin/circt-opt
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hw0_to_hw.sh ${hw0} "$out"
    '';

  mkHwCleanDerivation = { name, hw, circtPkg ? circt }:
    pkgs.runCommand "${name}-hw-clean.mlir" { buildInputs = [ circtPkg ]; } ''
      export CIRCT_OPT=${circtPkg}/bin/circt-opt
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hw_to_hw_clean.sh ${hw} "$out"
    '';

  mkSvDerivation = { name, hwClean, circtPkg ? circt }:
    pkgs.runCommand "${name}.sv" { buildInputs = [ circtPkg ]; } ''
      export CIRCT_OPT=${circtPkg}/bin/circt-opt
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hw_clean_to_sv.sh ${hwClean} "$out"
    '';

  mkIlDerivation = { name, sv }:
    pkgs.runCommand "${name}.il" { buildInputs = [ yosysPkg ]; } ''
      export YOSYS=${yosysPkg}/bin/yosys
      export YOSYS_SLANG_SO=${yosysSlang}/share/yosys/plugins/slang.so
      ${pkgs.lib.optionalString (fpPrimsSv != null) ''
        export FP_PRIMS_SV=${fpPrimsSv}
      ''}
      ${pkgs.bash}/bin/bash ${pipelineScripts}/sv_to_il.sh ${sv} "$out"
    '';

  mkYosysStatDerivation = { name, sv }:
    pkgs.runCommand "${name}-yosys.stat" { buildInputs = [ yosysPkg ]; } ''
      export YOSYS=${yosysPkg}/bin/yosys
      export YOSYS_SLANG_SO=${yosysSlang}/share/yosys/plugins/slang.so
      ${pkgs.lib.optionalString (fpPrimsSv != null) ''
        export FP_PRIMS_SV=${fpPrimsSv}
      ''}
      ${pkgs.bash}/bin/bash ${pipelineScripts}/sv_to_yosys_stat.sh ${sv} "$out"
    '';

  mkPipeline = { name, torchMlirInput, linalgLowering ? "affine"
    , cfRequireNoFloat ? false, handshakeInsertBuffers ? true
    , circtPkg ? circt }: rec {
      torch = mkTorchDerivation { inherit name torchMlirInput; };
      linalg = mkLinalgDerivation { inherit name torch; };
      cf = mkCfDerivation {
        inherit name linalg linalgLowering cfRequireNoFloat;
      };
      cfStats = mkCfStatsDerivation { inherit name cf; };
      handshake = mkHandshakeDerivation {
        inherit name cf handshakeInsertBuffers circtPkg;
      };
      hsExt = mkHsExtDerivation { inherit name handshake circtPkg; };
      hw0 = mkHw0Derivation { inherit name hsExt circtPkg; };
      hw = mkHwDerivation { inherit name hw0 circtPkg; };
      hwClean = mkHwCleanDerivation { inherit name hw circtPkg; };
      sv = mkSvDerivation { inherit name hwClean circtPkg; };
      il = mkIlDerivation { inherit name sv; };
      yosysStat = mkYosysStatDerivation { inherit name sv; };
    };

  stagePathsForPipeline = pipeline:
    builtins.listToAttrs (map (stage: {
      name = stage.pkg;
      value = "${builtins.getAttr stage.attr pipeline}";
    }) stageMap);

  mkPipelineStagePackages = name: pipeline:
    builtins.listToAttrs (map (stage: {
      name = "${name}-${stage.pkg}";
      value = builtins.getAttr stage.attr pipeline;
    }) stageMap);

  mkModelMetadata = modelKey: model:
    pkgs.writeText "${modelKey}-pipeline-metadata.json" (builtins.toJSON {
      model = {
        key = modelKey;
        inherit (model)
          name description source linalgLowering cfRequireNoFloat
          handshakeInsertBuffers;
      };
      artifacts = stagePathsForPipeline model.pipeline;
    });

  registerModel = { name, key ? name, description ? ""
    , source ? { type = "local"; }, torchMlirInput ? null
    , torchInputCommand ? null, torchInputBuildInputs ? [ ]
    , linalgLowering ? "affine", cfRequireNoFloat ? false
    , handshakeInsertBuffers ? true, circtPkg ? circt
    }:
    let
      validatedSource = if (source.type or "") == "huggingface"
      && (!(source ? model_id) || !(source ? revision)) then
        throw
        "registerModel(${name}): HuggingFace sources must pin source.model_id and source.revision"
      else
        source;
      resolvedTorchInput = if torchMlirInput != null then
        torchMlirInput
      else if torchInputCommand != null then
        pkgs.runCommand "${name}-torch-input.mlir" {
          buildInputs = torchInputBuildInputs;
        } ''
          set -euo pipefail
          ${torchInputCommand}
        ''
      else
        throw
        "registerModel(${name}): provide torchMlirInput or torchInputCommand";
      pipeline = mkPipeline {
        inherit name linalgLowering cfRequireNoFloat handshakeInsertBuffers
          circtPkg;
        torchMlirInput = resolvedTorchInput;
      };
      model = {
        inherit key name description linalgLowering cfRequireNoFloat
          handshakeInsertBuffers;
        source = validatedSource;
        torchInput = resolvedTorchInput;
        inherit pipeline;
      };
      metadata = mkModelMetadata key model;
    in model // { inherit metadata; };

  modelPipelinesFromRegistry = registry:
    pkgs.lib.mapAttrs (_: model: model.pipeline) registry;

  pipelineStagePackagesFromRegistry = registry:
    pkgs.lib.concatMapAttrs
    (name: model: mkPipelineStagePackages name model.pipeline) registry;

  metadataPackagesFromRegistry = registry:
    pkgs.lib.mapAttrs' (name: model:
      pkgs.lib.nameValuePair "${name}-pipeline-metadata" model.metadata)
    registry;

  registryIndexPackage = registry:
    pkgs.writeText "model-registry.json" (builtins.toJSON (pkgs.lib.mapAttrs
      (name: model: {
        inherit (model)
          name description source linalgLowering cfRequireNoFloat
          handshakeInsertBuffers;
        packages = builtins.listToAttrs (map (stage: {
          name = stage.pkg;
          value = "${name}-${stage.pkg}";
        }) stageMap);
      }) registry));
in {
  inherit registerModel;
  inherit modelPipelinesFromRegistry;
  inherit pipelineStagePackagesFromRegistry;
  inherit metadataPackagesFromRegistry;
  inherit registryIndexPackage;
}
