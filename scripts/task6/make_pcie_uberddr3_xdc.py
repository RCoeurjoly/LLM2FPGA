#!/usr/bin/env python3
from pathlib import Path
import re
import sys


PCIE_UBERDDR3_BYTE_LANES = 2
PCIE_UBERDDR3_DQ_BITS = PCIE_UBERDDR3_BYTE_LANES * 8


def adapt_ddr_line_for_pcie_top(line: str) -> str | None:
    """Map the 64-bit standalone DDR constraints onto the combined DDR top."""

    dq_match = re.search(r"ddram_dq\[(\d+)\]", line)
    if dq_match and int(dq_match.group(1)) >= PCIE_UBERDDR3_DQ_BITS:
        return None

    dqs_match = re.search(r"ddram_dqs_([pn])\[(\d+)\]", line)
    if dqs_match and int(dqs_match.group(2)) >= PCIE_UBERDDR3_BYTE_LANES:
        return None

    return line


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_pcie_uberddr3_xdc.py <pcie.xdc> <ddr.xdc>")

    pcie = Path(sys.argv[1]).read_text()
    ddr = Path(sys.argv[2]).read_text()
    print(pcie)
    print("\n# DDR3 constraints for combined PCIe + rowstream loader top")
    for line in ddr.splitlines():
        if "SYS_RSTN" in line:
            continue
        mapped = adapt_ddr_line_for_pcie_top(line.replace("clk50", "clk_50"))
        if mapped is not None:
            print(mapped)


if __name__ == "__main__":
    main()
