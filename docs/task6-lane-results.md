# Task 6 StreamTensor Lite Lane Results

Date opened: 2026-04-22
Branch: `task6-streamtensor-lite`

## Plan Status

| Question | Current answer | Evidence | Status |
| --- | --- | --- | --- |
| What first artifact should this lane inspect? | Representative-core artifacts, starting from `tiny-stories-1m-representative-core-v64-h4` | Shared ChatGPT plan plus lane plan | decided |
| What is the first target class? | One Linalg linear / GEMV region that can become a reused kernel boundary | Shared ChatGPT plan | decided |
| What first transformation should be implemented? | Redirect one linear / GEMV proof toward a small reused kernel with external weights | Shared ChatGPT plan | decided |
| What is the first success metric? | Move the resource signature away from `0 DSP / 0 BRAM` | Shared ChatGPT plan plus baseline summary | decided |
| What replay target is required before merge-back? | Real TinyStories baseline only after the constrained proof is structurally credible | Lane plan in `docs/task6-lane.md` | decided |

## Candidate First Experiments

| Candidate use | Input artifact | Expected benefit | Main blocker | Status |
| --- | --- | --- | --- | --- |
| Single Linalg linear / GEMV redirection | Representative-core `v64-h4` first | Prove reused-kernel direction with external weights and visible DSP use | Target region not yet selected | primary |
| Single-block task-graph proof | Representative-core `v64-h4` or next sweep point | Preserve enough context to make the linear proof believable | May be unnecessary if single-op proof is sufficient | reserve |
| Bounded activation buffering around the reused kernel | Same as above | Support the proof without generic full-model buffering work | Depends on chosen linear boundary | support-only |

## Experiment Log

| Experiment | Input artifact | Stage reached | First failing stage | Main lesson | Result |
| --- | --- | --- | --- | --- | --- |
| Lane creation and plan freeze | `task6` branch + shared ChatGPT StreamTensor-lite conversation | planning | n/a | Mission tightened to a single-Linalg-GEMV reused-kernel proof with external weights and DSP-backed intent | open |
