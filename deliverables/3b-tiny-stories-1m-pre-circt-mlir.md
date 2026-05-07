# Deliverable 3b: tiny<sub>stories1m</sub>.mlir before CIRCT

Reference:

- docs/project-plan<sub>v2</sub>.org:215

Definition:

- 3b) tiny<sub>stories1m</sub>.mlir, just before consumption by CIRCT

Gate:

``` bash
nix build .#tiny-stories-1m-baseline-float-hw-clean -L
```

Artifact:

- `/nix/store/...-tiny-stories-1m-baseline-float-hw-clean.mlir`

Note:

- For the current Task 3 branch review route, 3b is taken to be the
  `baseline-float` MLIR artifact immediately before SystemVerilog
  emission.
