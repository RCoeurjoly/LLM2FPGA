# Task 6 Seed20 Physical Comparison

Final classification: `pcie_primitive_delta`

## Inputs

- loader-only Yosys JSON: `/nix/store/py4i08kzsb1w2212hgk6przqblgvwfcw-task6-ypcb-pcie-uberddr3-rowstream-loader-only-yosys.json`
- full Yosys JSON: `/nix/store/pkdwpq212f6r9ypm9qph15sx321wrdm6-task6-ypcb-pcie-uberddr3-rowstream-loader-yosys.json`
- loader-only placed JSON: `/nix/store/b4cg42wml5cr61x58bl1r34brgja6k3z-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.placed.json`
- full placed JSON: `/nix/store/0f5ckl1vabsf8f0kghrb88zr0vp3kj4w-task6-ypcb-pcie-uberddr3-rowstream-loader-seed20.placed.json`
- loader-only FASM: `/nix/store/lvyzlm0phqdvmv1b53xszn546qkn505c-task6-ypcb-pcie-uberddr3-rowstream-loader-only-seed20.fasm`
- full FASM: `/nix/store/ym4zbd535gl7xq9ywkhld1g8p9npmdha-task6-ypcb-pcie-uberddr3-rowstream-loader-seed20.fasm`

## Key Counts

- PCIe primitive changed cells: `6`
- PCIe/GT FASM total added/removed: `443930` / `277517`
- DDR3 placement status: `PASS`
- DDR3 FASM status: `FAIL`

## Hardware Discipline

Run `scripts/task6/task6_pcie_user_gate.sh lifecycle <BDF>` before any BAR access. If the classification is not `pcie_ready`, stop and keep the artifact as the result.
