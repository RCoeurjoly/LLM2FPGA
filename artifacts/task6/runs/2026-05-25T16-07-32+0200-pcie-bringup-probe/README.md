# PCIe Bring-Up Probe

- port BDF: `0000:41:00.0`
- endpoint BDF: `not provided`
- capture time: `2026-05-25T16:07:33+02:00`

Inspect:

- `boltctl.log`
- `lspci-Dnn.log`
- `lspci-tv.log`
- `lspci-port-vvv.log`
- `dmesg-pcie-filtered.log`
- `bar-smoke.log` when an endpoint BDF was provided

Gate interpretation:

- Endpoint present in `lspci -Dnn`: proceed to BAR smoke.
- Port has `PresDet+` and trained link but no endpoint: focus on endpoint config-space/TLP behavior.
- No presence or no link: focus on reset, refclk, lane pins, chassis slot behavior, and flash boot state.
