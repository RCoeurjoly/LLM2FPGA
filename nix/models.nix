{ registerModel
, pythonWithTorch
, torchMlir
, python
, tinyStories1mTorchInput
, repoRoot
}:
{
  matmul = registerModel {
    key = "matmul";
    name = "matmul";
    description = "Minimal local matmul PyTorch module used as smoke pipeline input.";
    source = {
      type = "local-python";
      entry = "${repoRoot}/src/matmul.py";
      export_script = "${repoRoot}/src/compile-pytorch.py";
    };
    torchInputBuildInputs = [ pythonWithTorch ];
    torchInputCommand = ''
      export MATMUL_PY=${repoRoot}/src/matmul.py
      export PYTHONPATH="${repoRoot}/src:${repoRoot}/sim:${torchMlir}/${python.sitePackages}:''${PYTHONPATH:-}"
      python ${repoRoot}/src/compile-pytorch.py > "$out"
    '';
  };

  "tiny-stories-1m" = registerModel {
    key = "tiny-stories-1m";
    name = "tiny-stories-1m";
    description = "Frozen TinyStories-1M torch-MLIR artifact (local, not committed).";
    source = {
      type = "local-frozen-mlir";
      upstream = "roneneldan/TinyStories-1M";
      artifact = "${repoRoot}/TinyStories/tinystories_1m_torch.mlir";
    };
    torchMlirInput = tinyStories1mTorchInput;
  };
}
