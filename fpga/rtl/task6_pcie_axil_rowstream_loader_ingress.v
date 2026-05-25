`timescale 1ns/1ps
// SPDX-License-Identifier: MIT
// Task 6 PCIe BAR ingress for the DDR3 rowstream loader command contract.

`default_nettype none

module task6_pcie_axil_rowstream_loader_ingress #(
    parameter [31:0] TASK6_PCIE_MAGIC = 32'h54365043,
    parameter [31:0] TASK6_PCIE_VERSION = 32'd3,
    parameter [31:0] LOADER_COMMAND_MAGIC = 32'h33445244,
    parameter integer COMMAND_WIDTH = 192,
    parameter integer COMMAND_DATA_LSB = 64
) (
    input wire clk,
    input wire rst_n,

    input wire [31:0] s_axi_awaddr,
    input wire        s_axi_awvalid,
    output reg        s_axi_awready,

    input wire [31:0] s_axi_wdata,
    input wire [3:0]  s_axi_wstrb,
    input wire        s_axi_wvalid,
    output reg        s_axi_wready,

    output reg [1:0]  s_axi_bresp,
    output reg        s_axi_bvalid,
    input wire        s_axi_bready,

    input wire [31:0] s_axi_araddr,
    input wire        s_axi_arvalid,
    output reg        s_axi_arready,

    output reg [31:0] s_axi_rdata,
    output reg        s_axi_rvalid,
    input wire        s_axi_rready,
    output reg [1:0]  s_axi_rresp,

    output reg [COMMAND_WIDTH - 1:0] command_payload_o,
    output reg         command_event_o,

    input wire         boot_done_i,
    input wire         loader_done_i,
    input wire         loader_error_i,
    input wire         loader_last_accepted_i,
    input wire         loader_last_magic_ok_i,
    input wire [7:0]   loader_last_opcode_i,
    input wire [1:0]   loader_last_chunk_i,
    input wire [31:0]  loader_command_payload_addr_i,
    input wire [31:0]  loader_wait_cycles_i,
    input wire [511:0] loader_read_data_i,
    output reg         status_clear_pulse_o
);
    localparam [1:0] EVENT_IDLE = 2'd0;
    localparam [1:0] EVENT_ISSUE = 2'd1;
    localparam [1:0] EVENT_GAP = 2'd2;
    localparam [1:0] EVENT_REARM = 2'd3;

    reg [31:0] awaddr_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        awaddr_valid_q;
    reg        wdata_valid_q;

    reg [31:0] command_magic_q;
    reg [7:0]  command_opcode_q;
    reg [1:0]  command_chunk_q;
    reg [31:0] command_addr_q;
    reg [31:0] command_data_q [0:3];
    reg [31:0] accepted_count_q;
    reg        doorbell_error_q;
    reg        loader_done_seen_q;
    reg        loader_error_seen_q;
    reg        loader_accepted_seen_q;
    reg        loader_magic_ok_seen_q;
    reg [1:0]  event_state_q;

    reg        last_write_valid_q;
    reg [9:0]  last_write_word_index_q;
    reg [31:0] last_wdata_q;
    reg [3:0]  last_wstrb_q;

    integer i;

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobe;
        begin
            apply_wstrb = old_value;
            if (strobe[0]) apply_wstrb[7:0] = new_value[7:0];
            if (strobe[1]) apply_wstrb[15:8] = new_value[15:8];
            if (strobe[2]) apply_wstrb[23:16] = new_value[23:16];
            if (strobe[3]) apply_wstrb[31:24] = new_value[31:24];
        end
    endfunction

    function [COMMAND_WIDTH - 1:0] pack_command_payload;
        input [31:0] magic;
        input [7:0] opcode;
        input [1:0] chunk;
        input [31:0] addr;
        input [31:0] data0;
        input [31:0] data1;
        input [31:0] data2;
        input [31:0] data3;
        begin
            pack_command_payload = {COMMAND_WIDTH{1'b0}};
            pack_command_payload[0 +: 32] = magic;
            pack_command_payload[32 +: 8] = opcode;
            pack_command_payload[40 +: 2] = chunk;
            pack_command_payload[48 +: 32] = addr;
            pack_command_payload[COMMAND_DATA_LSB +: 128] = {data3, data2, data1, data0};
        end
    endfunction

    wire write_ready = awaddr_valid_q && wdata_valid_q && !s_axi_bvalid;
    wire aw_fire = s_axi_awready && s_axi_awvalid;
    wire w_fire = s_axi_wready && s_axi_wvalid;
    wire [9:0] write_word_index = awaddr_q[11:2];
    wire [9:0] read_word_index = s_axi_araddr[11:2];
    wire duplicate_write = last_write_valid_q &&
        last_write_word_index_q == write_word_index &&
        last_wdata_q == wdata_q &&
        last_wstrb_q == wstrb_q;
    wire event_active = event_state_q != EVENT_IDLE;

    initial begin
        s_axi_rdata = 32'd0;
        command_payload_o = {COMMAND_WIDTH{1'b0}};
        command_event_o = 1'b0;
        status_clear_pulse_o = 1'b0;
        command_magic_q = LOADER_COMMAND_MAGIC;
        command_opcode_q = 8'd0;
        command_chunk_q = 2'd0;
        command_addr_q = 32'd0;
        accepted_count_q = 32'd0;
        doorbell_error_q = 1'b0;
        loader_done_seen_q = 1'b0;
        loader_error_seen_q = 1'b0;
        loader_accepted_seen_q = 1'b0;
        loader_magic_ok_seen_q = 1'b0;
        event_state_q = EVENT_IDLE;
        awaddr_valid_q = 1'b0;
        wdata_valid_q = 1'b0;
        last_write_valid_q = 1'b0;
        last_write_word_index_q = 10'd0;
        last_wdata_q = 32'd0;
        last_wstrb_q = 4'd0;
        for (i = 0; i < 4; i = i + 1)
            command_data_q[i] = 32'd0;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            awaddr_valid_q <= 1'b0;
            wdata_valid_q <= 1'b0;
            command_magic_q <= LOADER_COMMAND_MAGIC;
            command_opcode_q <= 8'd0;
            command_chunk_q <= 2'd0;
            command_addr_q <= 32'd0;
            accepted_count_q <= 32'd0;
            doorbell_error_q <= 1'b0;
            loader_done_seen_q <= 1'b0;
            loader_error_seen_q <= 1'b0;
            loader_accepted_seen_q <= 1'b0;
            loader_magic_ok_seen_q <= 1'b0;
            event_state_q <= EVENT_IDLE;
            command_payload_o <= {COMMAND_WIDTH{1'b0}};
            command_event_o <= 1'b0;
            last_write_valid_q <= 1'b0;
            last_write_word_index_q <= 10'd0;
            last_wdata_q <= 32'd0;
            last_wstrb_q <= 4'd0;
            for (i = 0; i < 4; i = i + 1)
                command_data_q[i] <= 32'd0;
        end else begin
            command_event_o <= 1'b0;
            status_clear_pulse_o <= 1'b0;
            if (loader_done_i)
                loader_done_seen_q <= 1'b1;
            if (loader_error_i)
                loader_error_seen_q <= 1'b1;
            if (loader_last_accepted_i)
                loader_accepted_seen_q <= 1'b1;
            if (loader_last_magic_ok_i)
                loader_magic_ok_seen_q <= 1'b1;

            s_axi_awready <= !awaddr_valid_q && !write_ready && !s_axi_bvalid;
            s_axi_wready <= !wdata_valid_q && !write_ready && !s_axi_bvalid;

            if (event_state_q == EVENT_ISSUE) begin
                command_event_o <= 1'b1;
                event_state_q <= EVENT_GAP;
            end else if (event_state_q == EVENT_GAP) begin
                event_state_q <= EVENT_REARM;
            end else if (event_state_q == EVENT_REARM) begin
                command_event_o <= 1'b1;
                event_state_q <= EVENT_IDLE;
            end

            if (aw_fire) begin
                awaddr_q <= s_axi_awaddr;
                awaddr_valid_q <= 1'b1;
            end
            if (w_fire) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                wdata_valid_q <= 1'b1;
            end

            if (write_ready) begin
                awaddr_valid_q <= 1'b0;
                wdata_valid_q <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                last_write_valid_q <= 1'b1;
                last_write_word_index_q <= write_word_index;
                last_wdata_q <= wdata_q;
                last_wstrb_q <= wstrb_q;

                if (duplicate_write) begin
                end else begin
                    case (write_word_index)
                        10'h002: begin
                            if (wdata_q[0]) begin
                                doorbell_error_q <= 1'b0;
                                loader_done_seen_q <= 1'b0;
                                loader_error_seen_q <= 1'b0;
                                loader_accepted_seen_q <= 1'b0;
                                loader_magic_ok_seen_q <= 1'b0;
                                status_clear_pulse_o <= 1'b1;
                            end
                        end
                        10'h004: command_magic_q <= apply_wstrb(command_magic_q, wdata_q, wstrb_q);
                        10'h005: begin
                            if (wstrb_q[0])
                                command_opcode_q <= wdata_q[7:0];
                            if (wstrb_q[1])
                                command_chunk_q <= wdata_q[9:8];
                        end
                        10'h006: command_addr_q <= apply_wstrb(command_addr_q, wdata_q, wstrb_q);
                        10'h008: command_data_q[0] <= apply_wstrb(command_data_q[0], wdata_q, wstrb_q);
                        10'h009: command_data_q[1] <= apply_wstrb(command_data_q[1], wdata_q, wstrb_q);
                        10'h00a: command_data_q[2] <= apply_wstrb(command_data_q[2], wdata_q, wstrb_q);
                        10'h00b: command_data_q[3] <= apply_wstrb(command_data_q[3], wdata_q, wstrb_q);
                        10'h00c: begin
                            if (wdata_q[0]) begin
                                if (event_active) begin
                                    doorbell_error_q <= 1'b1;
                                end else begin
                                    command_payload_o <= pack_command_payload(
                                        command_magic_q,
                                        command_opcode_q,
                                        command_chunk_q,
                                        command_addr_q,
                                        command_data_q[0],
                                        command_data_q[1],
                                        command_data_q[2],
                                        command_data_q[3]
                                    );
                                    event_state_q <= EVENT_ISSUE;
                                    accepted_count_q <= accepted_count_q + 32'd1;
                                end
                            end
                        end
                        default: begin
                        end
                    endcase
                end
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 32'd0;
        end else begin
            s_axi_arready <= !s_axi_rvalid;
            if (!s_axi_rvalid && s_axi_arvalid) begin
                case (read_word_index)
                    10'h000: s_axi_rdata <= TASK6_PCIE_MAGIC;
                    10'h001: s_axi_rdata <= TASK6_PCIE_VERSION;
                    10'h002: s_axi_rdata <= {26'd0, boot_done_i, doorbell_error_q, loader_error_seen_q, loader_done_seen_q, event_active, rst_n};
                    10'h003: s_axi_rdata <= accepted_count_q;
                    10'h004: s_axi_rdata <= command_magic_q;
                    10'h005: s_axi_rdata <= {22'd0, command_chunk_q, command_opcode_q};
                    10'h006: s_axi_rdata <= command_addr_q;
                    10'h008: s_axi_rdata <= command_data_q[0];
                    10'h009: s_axi_rdata <= command_data_q[1];
                    10'h00a: s_axi_rdata <= command_data_q[2];
                    10'h00b: s_axi_rdata <= command_data_q[3];
                    10'h00d: s_axi_rdata <= {27'd0, loader_accepted_seen_q, loader_magic_ok_seen_q, loader_error_seen_q, loader_done_seen_q, boot_done_i};
                    10'h00e: s_axi_rdata <= {22'd0, loader_last_chunk_i, loader_last_opcode_i};
                    10'h00f: s_axi_rdata <= loader_command_payload_addr_i;
                    10'h010: s_axi_rdata <= loader_wait_cycles_i;
                    10'h011: s_axi_rdata <= loader_read_data_i[31:0];
                    10'h012: s_axi_rdata <= loader_read_data_i[63:32];
                    10'h013: s_axi_rdata <= loader_read_data_i[95:64];
                    10'h014: s_axi_rdata <= loader_read_data_i[127:96];
                    default: s_axi_rdata <= 32'd0;
                endcase
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
