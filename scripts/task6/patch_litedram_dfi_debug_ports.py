#!/usr/bin/env python3
"""Patch generated LiteDRAM RTL for Task 6 native write-data bring-up."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path)
    return parser.parse_args()


def replace_repeated_assigns(
    text: str,
    old_assign: str,
    new_assign: str,
    label: str,
) -> str:
    count = text.count(old_assign)
    if count != 4:
        raise SystemExit(f"expected four LiteDRAM {label} assigns, found {count}")
    text = text.replace(old_assign, new_assign, 1)
    text = text.replace(old_assign, "", 3)
    return text


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

    old_wdata_assign = (
        "assign {main_litedramcore_dfi_p3_wrdata, main_litedramcore_dfi_p2_wrdata, "
        "main_litedramcore_dfi_p1_wrdata, main_litedramcore_dfi_p0_wrdata} = "
        "main_litedramcore_interface_wdata;"
    )
    new_wdata_assign = (
        "assign {main_litedramcore_dfi_p3_wrdata, main_litedramcore_dfi_p2_wrdata, "
        "main_litedramcore_dfi_p1_wrdata, main_litedramcore_dfi_p0_wrdata} = "
        "task6_native_wdf_select_native ? task6_native_wdf_data_out : "
        "main_litedramcore_interface_wdata;"
    )
    text = replace_repeated_assigns(
        text,
        old_wdata_assign,
        new_wdata_assign,
        "interface wrdata",
    )

    old_mask_assign = (
        "assign {main_litedramcore_dfi_p3_wrdata_mask, main_litedramcore_dfi_p2_wrdata_mask, "
        "main_litedramcore_dfi_p1_wrdata_mask, main_litedramcore_dfi_p0_wrdata_mask} = "
        "(~main_litedramcore_interface_wdata_we);"
    )
    new_mask_assign = (
        "assign {main_litedramcore_dfi_p3_wrdata_mask, main_litedramcore_dfi_p2_wrdata_mask, "
        "main_litedramcore_dfi_p1_wrdata_mask, main_litedramcore_dfi_p0_wrdata_mask} = "
        "task6_native_wdf_select_native ? (~task6_native_wdf_we_out) : "
        "(~main_litedramcore_interface_wdata_we);"
    )
    text = replace_repeated_assigns(
        text,
        old_mask_assign,
        new_mask_assign,
        "interface wrdata mask",
    )

    debug_assigns = """
//------------------------------------------------------------------------------
// Task 6 native write-data FIFO and debug taps
//------------------------------------------------------------------------------

reg  [575:0] task6_native_wdf_data_fifo [0:31];
reg   [71:0] task6_native_wdf_we_fifo [0:31];
reg    [4:0] task6_native_wdf_wr_ptr = 5'd0;
reg    [4:0] task6_native_wdf_rd_ptr = 5'd0;
reg    [5:0] task6_native_wdf_level = 6'd0;
reg    [7:0] task6_native_wdf_push_count = 8'd0;
reg    [7:0] task6_native_wdf_pop_count = 8'd0;
reg    [7:0] task6_native_wdf_slave_event_count = 8'd0;
reg    [7:0] task6_native_wdf_master_event_count = 8'd0;

wire         task6_native_wdf_empty = (task6_native_wdf_level == 6'd0);
wire         task6_native_wdf_push =
    main_user_port_wdata_valid & main_user_port_wdata_ready;
wire         task6_native_wdf_select_native =
    main_litedramcore_sel &
    (~main_litedramcore_ext_dfi_sel);
wire         task6_native_wdf_slave_event =
    (main_litedramcore_slave_p0_wrdata_en |
     main_litedramcore_slave_p1_wrdata_en |
     main_litedramcore_slave_p2_wrdata_en |
     main_litedramcore_slave_p3_wrdata_en);
wire         task6_native_wdf_master_event =
    (main_a7ddrphy_dfi_p0_wrdata_en |
     main_a7ddrphy_dfi_p1_wrdata_en |
     main_a7ddrphy_dfi_p2_wrdata_en |
     main_a7ddrphy_dfi_p3_wrdata_en);
wire         task6_native_wdf_pop =
    task6_native_wdf_select_native & task6_native_wdf_slave_event;

wire [575:0] task6_native_wdf_data_out =
    (task6_native_wdf_empty & task6_native_wdf_push) ?
        main_user_port_wdata_payload_data :
        task6_native_wdf_data_fifo[task6_native_wdf_rd_ptr];
wire  [71:0] task6_native_wdf_we_out =
    (task6_native_wdf_empty & task6_native_wdf_push) ?
        main_user_port_wdata_payload_we :
        task6_native_wdf_we_fifo[task6_native_wdf_rd_ptr];

always @(posedge sys_clk) begin
    if (sys_rst) begin
        task6_native_wdf_wr_ptr <= 5'd0;
        task6_native_wdf_rd_ptr <= 5'd0;
        task6_native_wdf_level <= 6'd0;
        task6_native_wdf_push_count <= 8'd0;
        task6_native_wdf_pop_count <= 8'd0;
        task6_native_wdf_slave_event_count <= 8'd0;
        task6_native_wdf_master_event_count <= 8'd0;
    end else begin
        if (task6_native_wdf_push) begin
            task6_native_wdf_data_fifo[task6_native_wdf_wr_ptr] <=
                main_user_port_wdata_payload_data;
            task6_native_wdf_we_fifo[task6_native_wdf_wr_ptr] <=
                main_user_port_wdata_payload_we;
            task6_native_wdf_wr_ptr <= task6_native_wdf_wr_ptr + 1'd1;
            task6_native_wdf_push_count <= task6_native_wdf_push_count + 1'd1;
        end
        if (task6_native_wdf_pop) begin
            task6_native_wdf_rd_ptr <= task6_native_wdf_rd_ptr + 1'd1;
            task6_native_wdf_pop_count <= task6_native_wdf_pop_count + 1'd1;
        end
        if (task6_native_wdf_slave_event) begin
            task6_native_wdf_slave_event_count <=
                task6_native_wdf_slave_event_count + 1'd1;
        end
        if (task6_native_wdf_master_event) begin
            task6_native_wdf_master_event_count <=
                task6_native_wdf_master_event_count + 1'd1;
        end
        case ({task6_native_wdf_push, task6_native_wdf_pop})
            2'b10: task6_native_wdf_level <= task6_native_wdf_level + 1'd1;
            2'b01: task6_native_wdf_level <= task6_native_wdf_level - 1'd1;
            default: task6_native_wdf_level <= task6_native_wdf_level;
        endcase
    end
end

assign debug_dfi_wrdata_en = {main_a7ddrphy_dfi_p3_wrdata_en, main_a7ddrphy_dfi_p2_wrdata_en, main_a7ddrphy_dfi_p1_wrdata_en, main_a7ddrphy_dfi_p0_wrdata_en};
assign debug_dfi_wrdata_word4 = {24'd0, task6_native_wdf_push_count, task6_native_wdf_pop_count, task6_native_wdf_master_event_count, task6_native_wdf_slave_event_count, 2'd0, task6_native_wdf_level};
assign debug_dfi_wrdata_word4_mask = {
    (task6_native_wdf_push_count != 8'd0),
    (task6_native_wdf_pop_count != 8'd0),
    (task6_native_wdf_level != 6'd0),
    task6_native_wdf_push,
    task6_native_wdf_pop,
    task6_native_wdf_slave_event,
    task6_native_wdf_master_event,
    task6_native_wdf_select_native
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
