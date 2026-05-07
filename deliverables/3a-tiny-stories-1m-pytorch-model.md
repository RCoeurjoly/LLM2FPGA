# Deliverable 3a: TinyStories-1M PyTorch model

Reference:

- docs/project-plan<sub>v2</sub>.org:214

Definition:

- 3a) TinyStories-1M PyTorch model

Gate:

``` bash
nix build .#tiny-stories-1m-snapshot -L
```

Artifact:

- `result/config.json`
- `result/pytorch_model.bin`

Note:

- Pinned snapshot of `roneneldan/TinyStories-1M` used as the Task 3
  input model.
