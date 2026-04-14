{ pkgs, mlir, circt, yosysPkg, yosysSlang, torchMlir, python, pipelineScripts }:
let
  stageNames = [
    "torch"
    "linalg"
    "cf"
    "cf-stats"
    "handshake"
    "hs-ext"
    "hw0"
    "hw"
    "hw-clean"
    "sv"
    "il"
    "yosys-stat"
  ];

  torchMlirOpt = let
    candidates = [
      "${torchMlir}/bin/torch-mlir-opt"
      "${torchMlir}/${python.sitePackages}/torch_mlir/_mlir_libs/torch-mlir-opt"
      "${torchMlir}/${python.sitePackages}/torch_mlir/torch_mlir/_mlir_libs/torch-mlir-opt"
    ];
    matches = builtins.filter builtins.pathExists candidates;
  in if matches == [ ] then
    throw "Unable to locate torch-mlir-opt in ${torchMlir}"
  else
    builtins.head matches;

  mkTorchInput = { name, torchMlirInput ? null, torchInputCommand ? null
    , torchInputBuildInputs ? [ ] }:
    if torchMlirInput != null then
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

  mkTorchDerivation = { name, torchMlirInput }:
    pkgs.runCommand "${name}-torch.mlir" { } ''
      cp ${torchMlirInput} "$out"
    '';

  mkLinalgDerivation = { name, torch }:
    pkgs.runCommand "${name}-linalg.mlir" { buildInputs = [ torchMlir ]; } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/torch_to_linalg.sh \
        ${torchMlirOpt} ${torch} "$out"
    '';

  mkCfDerivation = { name, linalg }:
    pkgs.runCommand "${name}-cf.mlir" { buildInputs = [ mlir ]; } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/linalg_to_cf.sh \
        ${mlir}/bin/mlir-opt ${linalg} "$out"
    '';

  mkCfStatsDerivation = { name, cf }:
    pkgs.runCommand "${name}-cf.stats" { buildInputs = [ mlir ]; } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_stats.sh \
        ${mlir}/bin/mlir-opt ${cf} "$out"
    '';

  mkHandshakeDerivation = { name, cf }:
    pkgs.runCommand "${name}-handshake.mlir" {
      buildInputs = [ mlir circt ];
    } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_to_handshake.sh \
        ${circt}/bin/circt-opt ${mlir}/bin/mlir-opt ${cf} "$out"
    '';

  mkHandshakeLsqDerivation = { name, cf }:
    pkgs.runCommand "${name}-handshake.mlir" {
      buildInputs = [ mlir circt ];
    } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_to_handshake_lsq.sh \
        ${circt}/bin/circt-opt ${mlir}/bin/mlir-opt ${cf} "$out"
    '';

  mkHsExtDerivation = { name, handshake }:
    pkgs.runCommand "${name}-hs-ext.mlir" { buildInputs = [ circt ]; } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/handshake_to_hs_ext.sh \
        ${circt}/bin/circt-opt ${handshake} "$out"
    '';

  mkHw0Derivation = { name, hsExt }:
    pkgs.runCommand "${name}-hw0.mlir" { buildInputs = [ circt ]; } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hs_ext_to_hw0.sh \
        ${circt}/bin/circt-opt ${hsExt} "$out"
    '';

  mkHwDerivation = { name, hw0 }:
    pkgs.runCommand "${name}-hw.mlir" { buildInputs = [ circt ]; } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hw0_to_hw.sh \
        ${circt}/bin/circt-opt ${hw0} "$out"
    '';

  mkHwCleanDerivation = { name, hw }:
    pkgs.runCommand "${name}-hw-clean.mlir" { buildInputs = [ circt ]; } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hw_to_hw_clean.sh \
        ${circt}/bin/circt-opt ${hw} "$out"
    '';

  mkSvDerivation = { name, hwClean, allowHwExterns ? false, fpPrimsSv ? null }:
    pkgs.runCommand "${name}-sv" { buildInputs = [ circt python ]; } ''
      ${pkgs.lib.optionalString allowHwExterns ''
        export ALLOW_HW_EXTERNS=1
      ''}
      ${pkgs.lib.optionalString (fpPrimsSv != null) ''
        export FP_PRIMS_SV=${fpPrimsSv}
      ''}
      ${pkgs.bash}/bin/bash ${pipelineScripts}/hw_clean_to_sv.sh \
        ${circt}/bin/circt-opt ${hwClean} "$out"
    '';

  mkIlDerivation = { name, sv, slangPerFileExternModules ? false }:
    pkgs.runCommand "${name}.il" { buildInputs = [ yosysPkg ]; } ''
      ${pkgs.lib.optionalString slangPerFileExternModules ''
        export YOSYS_SLANG_PER_FILE_EXTERNS=1
      ''}
      ${pkgs.bash}/bin/bash ${pipelineScripts}/sv_to_il.sh \
        ${yosysPkg}/bin/yosys \
        ${yosysSlang}/share/yosys/plugins/slang.so \
        ${sv}/sources.f "$out"
    '';

  mkYosysStatDerivation = { name, sv, slangPerFileExternModules ? false }:
    pkgs.runCommand "${name}-yosys.stat" {
      buildInputs = [ yosysPkg python ];
    } ''
      ${pkgs.lib.optionalString slangPerFileExternModules ''
        export YOSYS_SLANG_PER_FILE_EXTERNS=1
      ''}
      ${pkgs.bash}/bin/bash ${pipelineScripts}/sv_to_yosys_stat.sh \
        ${yosysPkg}/bin/yosys \
        ${yosysSlang}/share/yosys/plugins/slang.so \
        ${sv}/sources.f "$out"
    '';

  mkBasePipeline = { name, torchMlirInput, handshakeFromCf
    , allowHwExterns ? false, fpPrimsSv ? null
    , slangPerFileExternModules ? false }:
    let
      self = {
        torch = mkTorchDerivation { inherit name torchMlirInput; };
        linalg = mkLinalgDerivation {
          inherit name;
          inherit (self) torch;
        };
        cf = mkCfDerivation {
          inherit name;
          inherit (self) linalg;
        };
        "cf-stats" = mkCfStatsDerivation {
          inherit name;
          inherit (self) cf;
        };
        handshake = handshakeFromCf {
          inherit name;
          inherit (self) cf;
        };
        "hs-ext" = mkHsExtDerivation {
          inherit name;
          inherit (self) handshake;
        };
        hw0 = mkHw0Derivation {
          inherit name;
          hsExt = self."hs-ext";
        };
        hw = mkHwDerivation {
          inherit name;
          inherit (self) hw0;
        };
        "hw-clean" = mkHwCleanDerivation {
          inherit name;
          inherit (self) hw;
        };
        sv = mkSvDerivation {
          inherit name;
          hwClean = self."hw-clean";
          inherit allowHwExterns fpPrimsSv;
        };
        il = mkIlDerivation {
          inherit name;
          inherit (self) sv;
          inherit slangPerFileExternModules;
        };
        "yosys-stat" = mkYosysStatDerivation {
          inherit name;
          inherit (self) sv;
          inherit slangPerFileExternModules;
        };
      };
    in self;

  mkPipeline = { name, torchMlirInput, allowHwExterns ? false, fpPrimsSv ? null
    , slangPerFileExternModules ? false }:
    mkBasePipeline {
      inherit name torchMlirInput allowHwExterns fpPrimsSv
        slangPerFileExternModules;
      handshakeFromCf = mkHandshakeDerivation;
    };

  mkQuantizedPipeline = { name, torchMlirInput, allowHwExterns ? false
    , fpPrimsSv ? null, slangPerFileExternModules ? false }:
    mkBasePipeline {
      inherit name torchMlirInput allowHwExterns fpPrimsSv
        slangPerFileExternModules;
      handshakeFromCf = mkHandshakeLsqDerivation;
    };

  publicStageNamesForModel = modelKey:
    if modelKey == "tiny-stories-1m" then
      builtins.filter (stage: stage != "yosys-stat") stageNames
    else
      stageNames;

  stagePathsForPipeline = publicStageNames: pipeline:
    builtins.listToAttrs (map (stage: {
      name = stage;
      value = "${builtins.getAttr stage pipeline}";
    }) publicStageNames);

  mkPipelineStagePackages = publicStageNames: name: pipeline:
    builtins.listToAttrs (map (stage: {
      name = "${name}-${stage}";
      value = builtins.getAttr stage pipeline;
    }) publicStageNames);

  mkModelMetadata = modelKey: model:
    let publicStageNames = publicStageNamesForModel modelKey;
    in pkgs.writeText "${modelKey}-pipeline-metadata.json" (builtins.toJSON {
      model = {
        inherit modelKey;
        inherit (model) name description source;
      };
      artifacts = stagePathsForPipeline publicStageNames model.pipeline;
    });

  registerPipelineModel = { pipelineFactory, name, key ? name, description ? ""
    , source ? { type = "local"; }, torchMlirInput ? null
    , torchInputCommand ? null, torchInputBuildInputs ? [ ]
    , allowHwExterns ? false, fpPrimsSv ? null
    , slangPerFileExternModules ? false }:
    let
      resolvedTorchInput = mkTorchInput {
        inherit name torchMlirInput torchInputCommand torchInputBuildInputs;
      };
      normalizedSource =
        if source ? type then source else source // { type = "local"; };
      pipeline = pipelineFactory {
        inherit name;
        torchMlirInput = resolvedTorchInput;
        inherit allowHwExterns fpPrimsSv slangPerFileExternModules;
      };
      model = {
        inherit key name description;
        source = normalizedSource;
        torchInput = resolvedTorchInput;
        inherit pipeline;
      };
      metadata = mkModelMetadata key model;
    in model // { inherit metadata; };

  registerModel = args:
    registerPipelineModel (args // { pipelineFactory = mkPipeline; });

  registerQuantizedModel = args:
    registerPipelineModel (args // { pipelineFactory = mkQuantizedPipeline; });

  modelPipelinesFromRegistry = registry:
    pkgs.lib.mapAttrs (_: model: model.pipeline) registry;

  pipelineStagePackagesFromRegistry = registry:
    pkgs.lib.concatMapAttrs (name: model:
      mkPipelineStagePackages (publicStageNamesForModel name) name
      model.pipeline) registry;

  metadataPackagesFromRegistry = registry:
    pkgs.lib.mapAttrs' (name: model:
      pkgs.lib.nameValuePair "${name}-pipeline-metadata" model.metadata)
    registry;

  registryIndexPackage = registry:
    pkgs.writeText "model-registry.json" (builtins.toJSON (pkgs.lib.mapAttrs
      (name: model:
        let publicStageNames = publicStageNamesForModel name;
        in {
          inherit (model) name description source;
          packages = builtins.listToAttrs (map (stage: {
            name = stage;
            value = "${name}-${stage}";
          }) publicStageNames);
        }) registry));
in {
  inherit registerModel;
  inherit registerQuantizedModel;
  inherit modelPipelinesFromRegistry;
  inherit pipelineStagePackagesFromRegistry;
  inherit metadataPackagesFromRegistry;
  inherit registryIndexPackage;
}
