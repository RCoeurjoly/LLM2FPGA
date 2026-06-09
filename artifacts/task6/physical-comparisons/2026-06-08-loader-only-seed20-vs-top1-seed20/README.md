# Task 6 Seed20 Physical Comparison

Final classification: `pcie_physical_delta`

## Inputs

- loader-only Yosys JSON: `/nix/store/py4i08kzsb1w2212hgk6przqblgvwfcw-task6-ypcb-pcie-uberddr3-rowstream-loader-only-yosys.json`
- full Yosys JSON: `/nix/store/sj8jgcbbm0nhizqir9wfksfir13vnz6r-task6-ypcb-pcie-uberddr3-rowstream-loader-only-top1-yosys.json`
- loader-only placed JSON: `/nix/store/rvams2ak81zmpv2sk01j16mc4f0yqm52-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.placed.json`
- full placed JSON: `/nix/store/ywjwwwv5zn4rlhi7sq7vvii70gxqpssw-task6-ypcb-pcie-uberddr3-rowstream-loader-only-top1-seed20.placed.json`
- loader-only FASM: `/nix/store/83kvvpysc7lfbvhfgrlwcm3yhxd6bqs3-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.fasm`
- full FASM: `/nix/store/nvgy78n6n4k405z4lwr8qsjb8sy6vl9a-task6-ypcb-pcie-uberddr3-rowstream-loader-only-top1-seed20.fasm`

## Key Counts

- PCIe primitive changed cells: `0`
- PCIe/GT FASM total added/removed: `456173` / `275508`
- DDR3 placement status: `PASS`
- DDR3 FASM status: `FAIL`

## Hardware Discipline

Run `scripts/task6/task6_pcie_user_gate.sh lifecycle <BDF>` before any BAR access. If the classification is not `pcie_ready`, stop and keep the artifact as the result.
