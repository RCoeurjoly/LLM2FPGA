#!/usr/bin/env python3
"""Hold LiteDRAM native write data until DFI write-data enable consumes it."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path)
    return parser.parse_args()


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one {description}, found {count}")
    return text.replace(old, new, 1)


def replace_duplicate_assigns(
    text: str, old_rhs: str, new_rhs: str, description: str
) -> str:
    """Replace duplicated DFI aggregate assigns with one held-data assignment."""

    lines = text.splitlines(keepends=True)
    rewritten: list[str] = []
    assignments: list[str] = []
    for line in lines:
        if old_rhs in line:
            assignments.append(line.replace(old_rhs, new_rhs))
            continue
        rewritten.append(line)

    if len(assignments) != 4:
        raise SystemExit(f"expected four {description}, found {len(assignments)}")
    if len(set(assignments)) != 1:
        raise SystemExit(f"{description} were not identical after replacement")

    insert_at = 0
    for index, line in enumerate(lines):
        if old_rhs in line:
            insert_at = len(
                [candidate for candidate in lines[:index] if old_rhs not in candidate]
            )
            break
    rewritten.insert(insert_at, assignments[0])
    return "".join(rewritten)


def main() -> None:
    args = parse_args()
    text = args.rtl.read_text()

    text = replace_once(
        text,
        "reg   [575:0] main_litedramcore_interface_wdata = 576'd0;\n"
        "reg    [71:0] main_litedramcore_interface_wdata_we = 72'd0;\n",
        "reg   [575:0] main_litedramcore_interface_wdata = 576'd0;\n"
        "reg    [71:0] main_litedramcore_interface_wdata_we = 72'd0;\n"
        "reg   [575:0] task6_native_wdata_hold = 576'd0;\n"
        "reg    [71:0] task6_native_wdata_we_hold = 72'd0;\n",
        "native write-data declaration block",
    )

    text = replace_duplicate_assigns(
        text,
        "= main_litedramcore_interface_wdata;",
        "= task6_native_wdata_hold;",
        "DFI wrdata assignments",
    )

    text = replace_duplicate_assigns(
        text,
        "= (~main_litedramcore_interface_wdata_we);",
        "= (~task6_native_wdata_we_hold);",
        "DFI wrdata-mask assignments",
    )

    hold_block = """always @(posedge sys_clk) begin
    if (sys_rst) begin
        task6_native_wdata_hold <= 576'd0;
        task6_native_wdata_we_hold <= 72'd0;
    end else if ((main_user_port_wdata_valid & builder_new_master_wdata_ready1)) begin
        task6_native_wdata_hold <= main_user_port_wdata_payload_data;
        task6_native_wdata_we_hold <= main_user_port_wdata_payload_we;
    end
end
assign main_user_port_rdata_payload_data = main_litedramcore_interface_rdata;
"""
    text = replace_once(
        text,
        "assign main_user_port_rdata_payload_data = main_litedramcore_interface_rdata;\n",
        hold_block,
        "native write-data hold insertion point",
    )

    args.rtl.write_text(text)


if __name__ == "__main__":
    main()
