#!/usr/bin/env python3
from pathlib import Path
import sys


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
        print(line.replace("clk50", "clk_50"))


if __name__ == "__main__":
    main()
