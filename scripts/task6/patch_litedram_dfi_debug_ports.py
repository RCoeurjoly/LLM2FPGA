#!/usr/bin/env python3
"""Add narrow DFI write-data debug ports to generated LiteDRAM RTL."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    text = args.rtl.read_text()

    port_tail = re.compile(r"(    input  wire\s+wb_ctrl_we)(\n\);)")
    new_ports = """\\1,
    output wire    [3:0] debug_dfi_wrdata_en,
    output wire   [63:0] debug_dfi_wrdata_word4,
    output wire    [7:0] debug_dfi_wrdata_word4_mask
);"""
    text, count = port_tail.subn(new_ports, text, count=1)
    if count != 1:
        raise SystemExit("could not find LiteDRAM core port tail")

    debug_assigns = """
//------------------------------------------------------------------------------
// Task 6 debug taps
//------------------------------------------------------------------------------

assign debug_dfi_wrdata_en = {
    main_a7ddrphy_dfi_p3_wrdata_en,
    main_a7ddrphy_dfi_p2_wrdata_en,
    main_a7ddrphy_dfi_p1_wrdata_en,
    main_a7ddrphy_dfi_p0_wrdata_en
};
assign debug_dfi_wrdata_word4 = {
    main_a7ddrphy_dfi_p3_wrdata[143:128],
    main_a7ddrphy_dfi_p2_wrdata[143:128],
    main_a7ddrphy_dfi_p1_wrdata[143:128],
    main_a7ddrphy_dfi_p0_wrdata[143:128]
};
assign debug_dfi_wrdata_word4_mask = {
    main_a7ddrphy_dfi_p3_wrdata_mask[17:16],
    main_a7ddrphy_dfi_p2_wrdata_mask[17:16],
    main_a7ddrphy_dfi_p1_wrdata_mask[17:16],
    main_a7ddrphy_dfi_p0_wrdata_mask[17:16]
};
"""
    marker = "\nendmodule\n"
    marker_index = text.rfind(marker)
    if marker_index == -1:
        raise SystemExit("could not find LiteDRAM core endmodule marker")
    text = text[:marker_index] + debug_assigns + text[marker_index:]

    args.rtl.write_text(text)


if __name__ == "__main__":
    main()
