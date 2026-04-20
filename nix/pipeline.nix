{ pkgs, mlir, circt, yosysPkg, yosysSlang, torchMlir, python, pipelineScripts }:
let
  stageNames = [
    "torch"
    "linalg"
    "cf"
    "handshake"
    "hs-ext"
    "hw0"
    "hw"
    "hw-clean"
    "sv"
    "il"
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
      pkgs.runCommand "${name}-torch.mlir" {
        buildInputs = torchInputBuildInputs;
      } ''
        set -euo pipefail
        ${torchInputCommand}
      ''
    else
      throw
      "registerModel(${name}): provide torchMlirInput or torchInputCommand";

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

  mkHandshakeDerivation = { name, cf }:
    pkgs.runCommand "${name}-handshake.mlir" {
      buildInputs = [ mlir circt ];
    } ''
      ${pkgs.bash}/bin/bash ${pipelineScripts}/cf_to_handshake.sh \
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

  mkPipeline = { name, torch, allowHwExterns ? false, fpPrimsSv ? null
    , slangPerFileExternModules ? false }:
    let
      self = {
        inherit torch;
        linalg = mkLinalgDerivation {
          inherit name;
          inherit (self) torch;
        };
        cf = mkCfDerivation {
          inherit name;
          inherit (self) linalg;
        };
        handshake = mkHandshakeDerivation {
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
      };
    in self;

  mkPipelineStagePackages = name: pipeline:
    builtins.listToAttrs (map (stage: {
      name = "${name}-${stage}";
      value = builtins.getAttr stage pipeline;
    }) stageNames);

  registerModel = { name, torchMlirInput ? null, torchInputCommand ? null
    , torchInputBuildInputs ? [ ], allowHwExterns ? false, fpPrimsSv ? null
    , slangPerFileExternModules ? false }:
    let
      torch = mkTorchInput {
        inherit name torchMlirInput torchInputCommand torchInputBuildInputs;
      };
    in {
      pipeline = mkPipeline {
        inherit name torch allowHwExterns fpPrimsSv slangPerFileExternModules;
      };
    };

  pipelineStagePackagesFromRegistry = registry:
    pkgs.lib.concatMapAttrs
    (name: model: mkPipelineStagePackages name model.pipeline) registry;
in {
  inherit registerModel;
  inherit pipelineStagePackagesFromRegistry;
}
