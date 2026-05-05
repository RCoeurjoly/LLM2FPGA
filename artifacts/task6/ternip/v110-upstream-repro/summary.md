# v110 Ternip upstream reproduction gate

## Hypothesis

The Ternip lane can start from pinned, open-source upstream sources that are
compatible with the Task 6/NLNet open-tooling constraint.

## Source commit

- Source/config commit: `54079f8`
- Flake target: `.#task6-ternip-upstream-repro`

## Result

- Status: `PASS_SOURCE_PINNED`
- Result path: `/nix/store/bhm046jvrq9x43w3pm12ja0abgm2bl74-task6-ternip-upstream-repro`

Pinned sources:

```text
Ternip:
  repo:   https://github.com/sifferman/ternip
  commit: 7573c17dbed8f01e7d9e07e59a863376426a5489
  hash:   sha256-ERtufGKw75r22GcBKNpPcpXRU+qW+S2L25jRwwwWWpE=
  license: BSD-3-Clause

BaseJump STL:
  repo:   https://github.com/bespoke-silicon-group/basejump_stl
  commit: a43571d2eaaae2dda7c10490e8350dfdac7da878
  hash:   sha256-7/u2qBhd4qNwQI/KUe+Ka+i6cz2/ZJkphBXjRKduf+4=
```

## Decision

Promote the Ternip lane to the reduced open-source elaboration gate.

Next command:

```bash
nix build .#task6-ternip-reduced-elab-json -L
```

Do not create a YPCB bitstream until reduced elaboration and synthesis have
recorded plausible resources.
