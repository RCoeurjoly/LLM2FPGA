# Task 6 Deep Research Prompt

I want you to do deep technical research on a recurring FPGA hardware bring-up problem in this repository:

https://github.com/RCoeurjoly/LLM2FPGA/tree/task6

This project uses an open source FPGA toolchain, not the vendor implementation flow. Please treat that as central to the investigation.

Relevant tools include, but may not be limited to:

- Yosys for synthesis
- nextpnr-xilinx for place and route
- Project X-Ray / prjxray-style bitstream database flows where applicable
- fasm / fasm2frames or related bitstream-generation tooling
- OpenXC7 / open-source Xilinx 7-series tooling
- LiteX / LitePCIe / LiteDRAM or other open-source cores if present in the repo
- Any custom scripts, constraints, generated netlists, timing reports, and bitstream packaging used by this repository

Please explicitly compare the assumptions and guarantees of this open source flow against the vendor Vivado flow where relevant. In particular, investigate whether timing closure, constraint handling, clock modeling, IO timing, DDR3 PHY calibration support, PCIe hard block integration, BEL/site placement, routing delays, bitstream feature coverage, and generated bitstreams have known limitations or caveats in the open source Xilinx flow.

Do not assume that "passes timing" in the open source flow means the same thing as "passes timing" in Vivado unless the repository/tool documentation supports that assumption.

Focus especially on commits starting from:

`fbe04ecae63274b37672a3396c2e2f6142bec2fb`

Commit metadata:

`2026-05-25T19:20:01+02:00`

`Add combined PCIe DDR3 rowstream loader bitstream`

Context:

We have been iterating on DDR3 calibration for a long time. DDR3 works standalone. PCIe works standalone. But when DDR3 is integrated with PCIe and other RTL, DDR3 calibration often fails on hardware.

The standalone DDR3 work was done in a separate local checkout at `~/UberDDR3`. That work already showed a related issue: different implementation seeds generated bitstreams that behaved differently on hardware, even before the current PCIe + DDR3 integration work in this repository. Please treat that as important evidence that the problem may not be only the PCIe integration layer.

This repository consumes that DDR3 work as a Nix input:

```nix
uberDdr3 = {
  url = "github:RCoeurjoly/UberDDR3/8e6b0bb9ed38a97505b29b28a6d2689746470e7b";
};
```

This is confusing because it breaks my mental model of RTL development.

My current mental model is:

- If RTL is correct in simulation, and ideally formal verification,
- and the PLL / clock settings are correct,
- and the design places and routes successfully,
- and it fits the target FPGA,
- and timing passes, meaning the critical paths meet the requested frequencies,
- then the generated bitstream should work on hardware.

But this project shows the opposite: the same design can work with one place-and-route seed and fail with another, even though both pass timing. DDR3 calibration may succeed for one seed and fail for another.

I want you to investigate where this mental model is incomplete or wrong.

Please research:

1. Why an FPGA bitstream can pass timing but still fail on hardware, especially for DDR3 calibration.
2. Why DDR3 memory controllers, PHYs, delay calibration, IDELAY/ODELAY, PLL/MMCM clocking, reset sequencing, placement, routing, and bank-level effects can be seed-sensitive.
3. Why integrating PCIe with DDR3 could make DDR3 calibration fail even if each subsystem works independently.
4. Whether this points to missing or insufficient constraints, such as:
   - false paths / multicycle paths used incorrectly,
   - unconstrained paths,
   - clock domain crossing constraints,
   - generated clocks,
   - async reset constraints,
   - input/output delay constraints,
   - physical placement constraints,
   - Pblocks / floorplanning,
   - pin/bank/IO standard constraints,
   - IDELAYCTRL / reference clock constraints,
   - DDR byte-lane constraints,
   - PCIe hard block or transceiver placement constraints.
5. What measurements or diagnostics should be added to stop "groping in the dark".
6. How to distinguish between:
   - a real RTL bug,
   - a CDC/reset bug,
   - a timing constraint bug,
   - a physical implementation / routing / signal integrity issue,
   - a board-level power or clock integrity issue,
   - a DDR3 controller calibration margin issue,
   - an FPGA tool or IP limitation.
7. Whether trying random implementation seeds is an acceptable engineering strategy, and if so, under what conditions. Also explain when it becomes a red flag.
8. What a systematic debug plan should look like for this repository.

Important PCIe question:

Codex has frequently asked me to reboot for each hardware test:

1. turn off laptop,
2. power-cycle the PCIe-to-Thunderbolt chassis,
3. turn on laptop again.

This is very tiring and prevents autonomous testing. I want to know whether this is really unavoidable.

Please research:

1. Whether PCIe endpoint FPGA designs normally require host reboot / chassis power cycle after each failed bitstream or PCIe test.
2. What can be reset from software on Linux:
   - PCIe function reset,
   - secondary bus reset,
   - hot reset,
   - device removal/rescan,
   - driver unbind/rebind,
   - FLR,
   - Thunderbolt authorization/rescan,
   - sysfs reset mechanisms,
   - setpci mechanisms.
3. What cannot be reliably reset from software, especially with Thunderbolt PCIe enclosures.
4. Whether FPGA reconfiguration while attached to PCIe is expected to break enumeration or leave the root complex / Thunderbolt bridge in a bad state.
5. Whether there are better workflows for autonomous testing:
   - remote-controlled AC power switch,
   - USB relay,
   - controllable ATX/bench supply,
   - PCIe PERST# control,
   - chassis power relay,
   - JTAG-only debug before PCIe enumeration,
   - embedded UART debug,
   - PCIe hotplug-compatible reset flow,
   - Linux scripts for remove/rescan/reset,
   - avoiding full laptop reboot where possible.
6. Whether the project should separate DDR3 calibration debug from PCIe enumeration debug more strongly.

Please inspect the repository structure, build scripts, constraints, RTL, generated artifacts, and commit history from `fbe04ecae63274b37672a3396c2e2f6142bec2fb` onward. Identify concrete risks in this specific project, not just generic FPGA advice.

Also inspect the referenced UberDDR3 revision, especially how its standalone DDR3 calibration designs are built, constrained, placed, routed, seeded, and measured. Compare the standalone seed sensitivity in UberDDR3 with the integrated PCIe + DDR3 failures in this repository.

Deliverables:

- A diagnosis of the likely classes of failure.
- A list of specific files/constraints/RTL areas in the repo that deserve inspection.
- A list of specific files/constraints/RTL areas in the referenced UberDDR3 revision that deserve inspection.
- A prioritized debug plan.
- A list of additional instrumentation to add.
- A checklist for validating timing constraints and CDC/reset correctness.
- A recommendation on whether seed-sweeping is reasonable here.
- A recommendation on how to reduce or eliminate manual laptop/chassis reboot cycles.
- A revised mental model for FPGA hardware correctness that accounts for simulation, formal verification, timing closure, physical implementation, board effects, protocol state, and open-source-toolchain maturity.
- Cite sources where possible, especially FPGA vendor documentation, PCIe/Linux reset documentation, DDR3 PHY/controller documentation, open-source FPGA toolchain documentation, and relevant application notes.

Additional open-source-toolchain-specific deliverables:

- Identify which parts of the design rely on yosys, nextpnr-xilinx, prjxray/OpenXC7, fasm tooling, LiteX/LitePCIe/LiteDRAM, or custom scripts.
- Identify which parts of the referenced UberDDR3 standalone DDR3 flow rely on yosys, nextpnr-xilinx, prjxray/OpenXC7, fasm tooling, or custom scripts.
- List known limitations, caveats, or immature areas of those tools for Xilinx 7-series DDR3, PCIe, clocking, IO delays, timing analysis, and bitstream generation.
- Explain how to validate whether a failure is caused by RTL, constraints, board effects, or an open-source-toolchain modeling/implementation gap.
- Recommend whether reproducing selected builds in Vivado, even temporarily, would be useful as a control experiment.
