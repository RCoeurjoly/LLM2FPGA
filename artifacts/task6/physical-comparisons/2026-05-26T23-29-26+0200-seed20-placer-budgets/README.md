# Task 6 Seed20 Physical Comparison

Final classification: `pcie_physical_delta`

## Inputs

- loader-only Yosys JSON: `/nix/store/py4i08kzsb1w2212hgk6przqblgvwfcw-task6-ypcb-pcie-uberddr3-rowstream-loader-only-yosys.json`
- full Yosys JSON: `/nix/store/pkdwpq212f6r9ypm9qph15sx321wrdm6-task6-ypcb-pcie-uberddr3-rowstream-loader-yosys.json`
- loader-only placed JSON: `/nix/store/rvams2ak81zmpv2sk01j16mc4f0yqm52-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.placed.json`
- full placed JSON: `/nix/store/xmssks3siq2lcvh88kjsdvziaq15c61m-task6-ypcb-pcie-uberddr3-rowstream-loader-seed20-placer-budgets.placed.json`
- loader-only FASM: `/nix/store/83kvvpysc7lfbvhfgrlwcm3yhxd6bqs3-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.fasm`
- full FASM: `/nix/store/byc557j8minw4xbjh0275wicci67r5hl-task6-ypcb-pcie-uberddr3-rowstream-loader-seed20-placer-budgets.fasm`

## Key Counts

- PCIe primitive changed cells: `0`
- PCIe/GT FASM total added/removed: `443927` / `277514`
- DDR3 placement status: `PASS`
- DDR3 FASM status: `FAIL`

## Hardware Discipline

Run `scripts/task6/task6_pcie_user_gate.sh lifecycle <BDF>` before any BAR access. If the classification is not `pcie_ready`, stop and keep the artifact as the result.
