#!/usr/bin/env python3
"""Emit a compact OpenXC7 PCIe primitive report from a Yosys JSON netlist."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

PRIMITIVE_TYPES = {"PCIE_2_1", "GTXE2_CHANNEL", "GTXE2_COMMON"}
PCIE_KEYS = {
    "BAR0",
    "BAR1",
    "CLASS_CODE",
    "CFG_DEV_ID",
    "DEV_CAP_MAX_PAYLOAD_SUPPORTED",
    "DISABLE_LANE_REVERSAL",
    "LINK_CAP_MAX_LINK_SPEED",
    "LINK_CAP_MAX_LINK_WIDTH",
    "LINK_CTRL2_TARGET_LINK_SPEED",
    "LTSSM_MAX_LINK_WIDTH",
    "PCIE_CAP_DEVICE_PORT_TYPE",
    "PCIE_CAP_NEXTPTR",
    "PCIE_CAP_ON",
    "PCIE_REVISION",
    "PL_FAST_TRAIN",
}
GT_KEYS = {
    "ALIGN_COMMA_DOUBLE",
    "CHAN_BOND_SEQ_LEN",
    "CLK_COR_SEQ_2_USE",
    "RXBUF_EN",
    "RXCDR_CFG",
    "RXOUT_DIV",
    "RX_DATA_WIDTH",
    "TXOUT_DIV",
    "TX_DATA_WIDTH",
    "TX_POLARITY",
}


def selected_parameters(cell_type: str, params: dict[str, object]) -> dict[str, object]:
    if cell_type == "PCIE_2_1":
        keys = PCIE_KEYS
    else:
        keys = GT_KEYS
    return {key: params[key] for key in sorted(keys) if key in params}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json", type=Path, help="Yosys JSON netlist to inspect")
    parser.add_argument("--xdc", type=Path, help="Optional XDC path to include verbatim")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output")
    args = parser.parse_args()

    netlist = json.loads(args.json.read_text())
    cells = []
    for module_name, module in sorted(netlist.get("modules", {}).items()):
        for cell_name, cell in sorted((module.get("cells") or {}).items()):
            cell_type = cell.get("type")
            if cell_type not in PRIMITIVE_TYPES:
                continue
            cells.append(
                {
                    "module": module_name,
                    "cell": cell_name,
                    "type": cell_type,
                    "parameters": selected_parameters(cell_type, cell.get("parameters") or {}),
                    "attributes": cell.get("attributes") or {},
                }
            )

    report = {
        "json": str(args.json),
        "primitive_count": len(cells),
        "primitives": cells,
    }
    if args.xdc:
        report["xdc"] = {"path": str(args.xdc), "text": args.xdc.read_text()}

    print(json.dumps(report, indent=2 if args.pretty else None, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
