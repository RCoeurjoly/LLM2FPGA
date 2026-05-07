# Deliverable 3e: synthesis resource report and bottleneck report

Reference:

- docs/project-plan<sub>v2</sub>.org:218

Definition:

- 3e) synthesis resource report + bottleneck report

Gate:

``` bash
nix build .#tiny-stories-1m-baseline-float-selftest-all-memory-utilization -L
cat result/summary.txt
```

# How to reproduce

From a checkout of this repo, run the gate command above. Nix builds the
toolchain and all needed inputs through the flake, then leaves a
`result` symlink in the repo root.

The command is expected to finish with a resource report, not a final
FPGA bitstream. If it succeeds, inspect `result/summary.txt` first.

Target name breakdown:

- `tiny-stories-1m`: the model under test.
- `baseline-float`: floating-point baseline, not a quantized model.
- `selftest`: wraps the design in a top-level test shell.
- `all-memory`: blackboxes all oversized Handshake memory modules found
  in the model, treating them as external-memory candidates. In this
  target, oversized means at least 128 kbits per Handshake memory
  module. The use of Handshake dialect is one of the biggest burdens in
  the current pipeline and removing it is a goal of task 6.
- `utilization`: produces a Yosys-based FPGA resource estimate, not a
  bitstream.

# What this command does

This builds the TinyStories-1M baseline-float pipeline through RTLIL,
wraps it in the TinyStories self-test shell, externalizes oversized
Handshake memory modules as external-storage candidates, runs staged
Yosys/Xilinx mapping, writes JSON, and derives utilization numbers from
that JSON.

The command produces a `result` symlink with:

- `summary.txt`: human-readable resource summary
- `summary.json`: same summary in JSON form
- `stat.json`: leaf-cell counts used to produce the summary

The main output is `summary.txt`. The most important line is `clb_luts`,
because LUTs are the resource that most clearly exceeds the target FPGA.
`summary.json` is the same data for scripts. `stat.json` is lower-level
Yosys data used to make the summary.

This is not a nextpnr-xilinx place-and-route utilization report. It is a
Yosys estimate. nextpnr-xilinx was attempted, but it runs out of memory
on this route and does not produce a final PnR result.

Result:

The conclusion from task 3 is that we have to work on resource
minimization next.

With the current pipeline, even after externalizing oversized handshake
memory modules as external storage candidates, the shell design for tiny
stories 1M does not fit in the target FPGA.

The resource utilization report is a Yosys estimate for this shell
design, because nextpnr-xilinx was attempted as the main path and failed
with OOM on this design.

Since the design is about 141x bigger (in terms of LUTs) than the target
FPGA, the next task should be task 6 and not task 4.

Task 6 (see project plan) is about resource minimization. Some paths
that could be taken, learned from executing task 3 are:

- Use board memory more directly. This gate already externalizes
  oversized handshake memory modules as external storage candidates.
- Use a MLIR dialect other than handshake. The handshake dialect
  (<https://circt.llvm.org/docs/Dialects/Handshake/>) uses a lot of
  resources in this pipeline.

# Note about resource utilization report

At first, I tried to do place and route with nextpnr-xilinx on this
shell design, but it exited with out of memory errors.

I created some patches to try to fix that, but I discarded them after
finding out that the shell design was about 141x bigger than the target
FPGA, which is already the largest supported FPGA, so it seems
unreasonable to me to expect nextpnr-xilinx to support that design.
