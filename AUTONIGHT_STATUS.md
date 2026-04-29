# AUTONIGHT_STATUS

## Last iteration
No overnight iteration has completed yet.

## Current best evidence
- v1k bounded int8 L2 MLP/residual-add slice is board validated.
- v4k bounded MLP/residual RTL replay passes.
- vocab memory score indicates v4k can continue on-chip; full vocab/output projection needs external-memory or streaming planning.

## Accepted/promoted changes
None yet in this overnight session.

## Rejected attempts
None yet in this overnight session.

## Commands run
None yet in this overnight session.

## Files changed
None yet in this overnight session.

## Open risks
- v4k embedding/lm_head not yet synthesized.
- multi-sample quantization not yet calibrated.
- attention not yet scored.
- full output-head streaming/DDR3 plan not yet concrete.

## Next recommended step
Start with a small v4k on-chip tied vocab/output-head score or prototype.
