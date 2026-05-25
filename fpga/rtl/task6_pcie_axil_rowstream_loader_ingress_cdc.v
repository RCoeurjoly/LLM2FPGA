`timescale 1ns/1ps
// SPDX-License-Identifier: MIT

`default_nettype none

module task6_pcie_axil_rowstream_loader_ingress_cdc #(
    parameter integer COMMAND_WIDTH = 208,
    parameter integer COMMAND_DATA_LSB = 80
) (
    input wire pcie_clk,
    input wire pcie_rst_n,
    input wire rowstream_clk,
    input wire rowstream_rst_n,

    input wire [31:0] s_axi_awaddr,
    input wire        s_axi_awvalid,
    output wire       s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0]  s_axi_wstrb,
    input wire        s_axi_wvalid,
    output wire       s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire       s_axi_bvalid,
    input wire        s_axi_bready,
    input wire [31:0] s_axi_araddr,
    input wire        s_axi_arvalid,
    output wire       s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire       s_axi_rvalid,
    input wire        s_axi_rready,
    output wire [1:0] s_axi_rresp,

    output reg [COMMAND_WIDTH - 1:0] rowstream_command_payload_o,
    output reg                       rowstream_command_event_o,
    output reg                       rowstream_status_clear_o,

    input wire        rowstream_calib_complete_i,
    input wire        rowstream_boot_done_i,
    input wire [31:0] rowstream_ddr_debug1_i,
    input wire        rowstream_loader_done_i,
    input wire        rowstream_loader_error_i,
    input wire        rowstream_loader_last_accepted_i,
    input wire        rowstream_loader_last_magic_ok_i,
    input wire [7:0]  rowstream_loader_last_opcode_i,
    input wire [1:0]  rowstream_loader_last_chunk_i,
    input wire [31:0] rowstream_loader_command_payload_addr_i,
    input wire [31:0] rowstream_loader_wait_cycles_i,
    input wire [511:0] rowstream_loader_read_data_i,

    output reg [511:0] rowstream_top1_hidden_vector_o,
    output reg         rowstream_top1_start_o,
    output reg         rowstream_top1_status_clear_o,
    input wire         rowstream_top1_busy_i,
    input wire         rowstream_top1_done_i,
    input wire         rowstream_top1_error_i,
    input wire [31:0]  rowstream_top1_token_i,
    input wire [31:0]  rowstream_top1_score_q024_i,
    input wire [31:0]  rowstream_top1_rows_scanned_i,
    input wire [31:0]  rowstream_top1_cycle_count_i
);
    wire [COMMAND_WIDTH - 1:0] pcie_command_payload;
    wire pcie_command_event;
    wire pcie_status_clear;
    wire [511:0] pcie_top1_hidden_vector;
    wire pcie_top1_start;
    wire pcie_top1_status_clear;

    reg req_toggle_pcie_q;
    reg clear_toggle_pcie_q;
    reg top1_start_toggle_pcie_q;
    reg top1_clear_toggle_pcie_q;
    reg [COMMAND_WIDTH - 1:0] payload_hold_pcie_q;
    reg [511:0] top1_hidden_hold_pcie_q;

    reg [2:0] req_sync_row_q;
    reg req_seen_row_q;
    reg [2:0] clear_sync_row_q;
    reg clear_seen_row_q;
    reg [2:0] top1_start_sync_row_q;
    reg top1_start_seen_row_q;
    reg [2:0] top1_clear_sync_row_q;
    reg top1_clear_seen_row_q;

    reg [2:0] calib_complete_sync_pcie_q;
    reg [2:0] boot_done_sync_pcie_q;
    reg [2:0] loader_done_sync_pcie_q;
    reg [2:0] loader_error_sync_pcie_q;
    reg [2:0] loader_accepted_sync_pcie_q;
    reg [2:0] loader_magic_ok_sync_pcie_q;
    reg [7:0] loader_opcode_pcie_q;
    reg [1:0] loader_chunk_pcie_q;
    reg [31:0] loader_addr_pcie_q;
    reg [31:0] loader_wait_pcie_q;
    reg [31:0] ddr_debug1_pcie_q;
    reg [511:0] loader_read_data_pcie_q;
    reg [2:0] top1_busy_sync_pcie_q;
    reg [2:0] top1_done_sync_pcie_q;
    reg [2:0] top1_error_sync_pcie_q;
    reg [31:0] top1_token_pcie_q;
    reg [31:0] top1_score_pcie_q;
    reg [31:0] top1_rows_pcie_q;
    reg [31:0] top1_cycles_pcie_q;

    task6_pcie_axil_rowstream_loader_ingress #(
        .COMMAND_WIDTH(COMMAND_WIDTH),
        .COMMAND_DATA_LSB(COMMAND_DATA_LSB)
    ) ingress (
        .clk(pcie_clk),
        .rst_n(pcie_rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_rresp(s_axi_rresp),
        .command_payload_o(pcie_command_payload),
        .command_event_o(pcie_command_event),
        .calib_complete_i(calib_complete_sync_pcie_q[2]),
        .boot_done_i(boot_done_sync_pcie_q[2]),
        .ddr_debug1_i(ddr_debug1_pcie_q),
        .loader_done_i(loader_done_sync_pcie_q[2]),
        .loader_error_i(loader_error_sync_pcie_q[2]),
        .loader_last_accepted_i(loader_accepted_sync_pcie_q[2]),
        .loader_last_magic_ok_i(loader_magic_ok_sync_pcie_q[2]),
        .loader_last_opcode_i(loader_opcode_pcie_q),
        .loader_last_chunk_i(loader_chunk_pcie_q),
        .loader_command_payload_addr_i(loader_addr_pcie_q),
        .loader_wait_cycles_i(loader_wait_pcie_q),
        .loader_read_data_i(loader_read_data_pcie_q),
        .status_clear_pulse_o(pcie_status_clear),
        .top1_hidden_vector_o(pcie_top1_hidden_vector),
        .top1_start_pulse_o(pcie_top1_start),
        .top1_status_clear_pulse_o(pcie_top1_status_clear),
        .top1_busy_i(top1_busy_sync_pcie_q[2]),
        .top1_done_i(top1_done_sync_pcie_q[2]),
        .top1_error_i(top1_error_sync_pcie_q[2]),
        .top1_token_i(top1_token_pcie_q),
        .top1_score_q024_i(top1_score_pcie_q),
        .top1_rows_scanned_i(top1_rows_pcie_q),
        .top1_cycle_count_i(top1_cycles_pcie_q)
    );

    always @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            req_toggle_pcie_q <= 1'b0;
            clear_toggle_pcie_q <= 1'b0;
            top1_start_toggle_pcie_q <= 1'b0;
            top1_clear_toggle_pcie_q <= 1'b0;
            payload_hold_pcie_q <= {COMMAND_WIDTH{1'b0}};
            top1_hidden_hold_pcie_q <= 512'd0;
            calib_complete_sync_pcie_q <= 3'd0;
            boot_done_sync_pcie_q <= 3'd0;
            loader_done_sync_pcie_q <= 3'd0;
            loader_error_sync_pcie_q <= 3'd0;
            loader_accepted_sync_pcie_q <= 3'd0;
            loader_magic_ok_sync_pcie_q <= 3'd0;
            loader_opcode_pcie_q <= 8'd0;
            loader_chunk_pcie_q <= 2'd0;
            loader_addr_pcie_q <= 32'd0;
            loader_wait_pcie_q <= 32'd0;
            ddr_debug1_pcie_q <= 32'd0;
            loader_read_data_pcie_q <= 512'd0;
            top1_busy_sync_pcie_q <= 3'd0;
            top1_done_sync_pcie_q <= 3'd0;
            top1_error_sync_pcie_q <= 3'd0;
            top1_token_pcie_q <= 32'd0;
            top1_score_pcie_q <= 32'd0;
            top1_rows_pcie_q <= 32'd0;
            top1_cycles_pcie_q <= 32'd0;
        end else begin
            if (pcie_command_event) begin
                payload_hold_pcie_q <= pcie_command_payload;
                req_toggle_pcie_q <= ~req_toggle_pcie_q;
            end
            if (pcie_status_clear)
                clear_toggle_pcie_q <= ~clear_toggle_pcie_q;
            if (pcie_top1_start) begin
                top1_hidden_hold_pcie_q <= pcie_top1_hidden_vector;
                top1_start_toggle_pcie_q <= ~top1_start_toggle_pcie_q;
            end
            if (pcie_top1_status_clear)
                top1_clear_toggle_pcie_q <= ~top1_clear_toggle_pcie_q;

            calib_complete_sync_pcie_q <= {calib_complete_sync_pcie_q[1:0], rowstream_calib_complete_i};
            boot_done_sync_pcie_q <= {boot_done_sync_pcie_q[1:0], rowstream_boot_done_i};
            loader_done_sync_pcie_q <= {loader_done_sync_pcie_q[1:0], rowstream_loader_done_i};
            loader_error_sync_pcie_q <= {loader_error_sync_pcie_q[1:0], rowstream_loader_error_i};
            loader_accepted_sync_pcie_q <= {loader_accepted_sync_pcie_q[1:0], rowstream_loader_last_accepted_i};
            loader_magic_ok_sync_pcie_q <= {loader_magic_ok_sync_pcie_q[1:0], rowstream_loader_last_magic_ok_i};
            loader_opcode_pcie_q <= rowstream_loader_last_opcode_i;
            loader_chunk_pcie_q <= rowstream_loader_last_chunk_i;
            loader_addr_pcie_q <= rowstream_loader_command_payload_addr_i;
            loader_wait_pcie_q <= rowstream_loader_wait_cycles_i;
            ddr_debug1_pcie_q <= rowstream_ddr_debug1_i;
            loader_read_data_pcie_q <= rowstream_loader_read_data_i;
            top1_busy_sync_pcie_q <= {top1_busy_sync_pcie_q[1:0], rowstream_top1_busy_i};
            top1_done_sync_pcie_q <= {top1_done_sync_pcie_q[1:0], rowstream_top1_done_i};
            top1_error_sync_pcie_q <= {top1_error_sync_pcie_q[1:0], rowstream_top1_error_i};
            top1_token_pcie_q <= rowstream_top1_token_i;
            top1_score_pcie_q <= rowstream_top1_score_q024_i;
            top1_rows_pcie_q <= rowstream_top1_rows_scanned_i;
            top1_cycles_pcie_q <= rowstream_top1_cycle_count_i;
        end
    end

    always @(posedge rowstream_clk or negedge rowstream_rst_n) begin
        if (!rowstream_rst_n) begin
            req_sync_row_q <= 3'd0;
            req_seen_row_q <= 1'b0;
            clear_sync_row_q <= 3'd0;
            clear_seen_row_q <= 1'b0;
            top1_start_sync_row_q <= 3'd0;
            top1_start_seen_row_q <= 1'b0;
            top1_clear_sync_row_q <= 3'd0;
            top1_clear_seen_row_q <= 1'b0;
            rowstream_command_payload_o <= {COMMAND_WIDTH{1'b0}};
            rowstream_command_event_o <= 1'b0;
            rowstream_status_clear_o <= 1'b0;
            rowstream_top1_hidden_vector_o <= 512'd0;
            rowstream_top1_start_o <= 1'b0;
            rowstream_top1_status_clear_o <= 1'b0;
        end else begin
            req_sync_row_q <= {req_sync_row_q[1:0], req_toggle_pcie_q};
            clear_sync_row_q <= {clear_sync_row_q[1:0], clear_toggle_pcie_q};
            top1_start_sync_row_q <= {top1_start_sync_row_q[1:0], top1_start_toggle_pcie_q};
            top1_clear_sync_row_q <= {top1_clear_sync_row_q[1:0], top1_clear_toggle_pcie_q};
            rowstream_command_event_o <= 1'b0;
            rowstream_status_clear_o <= 1'b0;
            rowstream_top1_start_o <= 1'b0;
            rowstream_top1_status_clear_o <= 1'b0;

            if (req_sync_row_q[2] ^ req_seen_row_q) begin
                req_seen_row_q <= req_sync_row_q[2];
                rowstream_command_payload_o <= payload_hold_pcie_q;
                rowstream_command_event_o <= 1'b1;
            end
            if (clear_sync_row_q[2] ^ clear_seen_row_q) begin
                clear_seen_row_q <= clear_sync_row_q[2];
                rowstream_status_clear_o <= 1'b1;
            end
            if (top1_start_sync_row_q[2] ^ top1_start_seen_row_q) begin
                top1_start_seen_row_q <= top1_start_sync_row_q[2];
                rowstream_top1_hidden_vector_o <= top1_hidden_hold_pcie_q;
                rowstream_top1_start_o <= 1'b1;
            end
            if (top1_clear_sync_row_q[2] ^ top1_clear_seen_row_q) begin
                top1_clear_seen_row_q <= top1_clear_sync_row_q[2];
                rowstream_top1_status_clear_o <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
