`timescale 1ns/1ps
// SPDX-License-Identifier: MIT
// Task 6 PCIe BAR rowstream loopback responder.
//
// This module intentionally exposes the upstream pcie_7x example module name
// `axil_minimum` so the existing pcie_7x AXI-MM top can instantiate it when
// this file replaces upstream axil_minimum.v in the source list.

`default_nettype none

module axil_minimum(
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

    output reg [31:0] s_axi_rdata = 32'd0,
    output reg        s_axi_rvalid,
    input wire        s_axi_rready,
    output reg [1:0]  s_axi_rresp
);
    localparam [31:0] TASK6_PCIE_MAGIC = 32'h54365043; // T6PC
    localparam [31:0] TASK6_PCIE_VERSION = 32'd2;
    localparam [31:0] MAX_PAYLOAD_BYTES = 32'd3840;
    localparam [9:0]  PAYLOAD_WORD_BASE = 10'h040; // BAR offset 0x100

    (* ram_style = "distributed" *) reg [31:0] mem [0:1023];

    reg [31:0] awaddr_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        awaddr_valid_q;
    reg        wdata_valid_q;

    reg [31:0] payload_count_q;
    reg [31:0] expected_sum_q;
    reg [31:0] observed_sum_q;
    reg [31:0] observed_xor_q;
    reg [31:0] written_bytes_q;
    reg [31:0] accepted_count_q;
    reg [31:0] first_word_q;
    reg [31:0] last_word_q;
    reg [31:0] mismatch_q;
    reg        done_q;
    reg        busy_q;
    reg        error_q;

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

    function [7:0] selected_byte;
        input [31:0] word;
        input [1:0] index;
        begin
            case (index)
                2'd0: selected_byte = word[31:24];
                2'd1: selected_byte = word[23:16];
                2'd2: selected_byte = word[15:8];
                default: selected_byte = word[7:0];
            endcase
        end
    endfunction

    function [31:0] byte_sum_delta;
        input [31:0] word;
        input [3:0] strobe;
        input [31:0] byte_offset;
        input [31:0] byte_count;
        begin
            byte_sum_delta = 32'd0;
            if (strobe[3] && (byte_offset + 32'd0) < byte_count)
                byte_sum_delta = byte_sum_delta + {24'd0, selected_byte(word, 2'd0)};
            if (strobe[2] && (byte_offset + 32'd1) < byte_count)
                byte_sum_delta = byte_sum_delta + {24'd0, selected_byte(word, 2'd1)};
            if (strobe[1] && (byte_offset + 32'd2) < byte_count)
                byte_sum_delta = byte_sum_delta + {24'd0, selected_byte(word, 2'd2)};
            if (strobe[0] && (byte_offset + 32'd3) < byte_count)
                byte_sum_delta = byte_sum_delta + {24'd0, selected_byte(word, 2'd3)};
        end
    endfunction

    function [31:0] byte_count_delta;
        input [3:0] strobe;
        input [31:0] byte_offset;
        input [31:0] byte_count;
        begin
            byte_count_delta = 32'd0;
            if (strobe[3] && (byte_offset + 32'd0) < byte_count)
                byte_count_delta = byte_count_delta + 32'd1;
            if (strobe[2] && (byte_offset + 32'd1) < byte_count)
                byte_count_delta = byte_count_delta + 32'd1;
            if (strobe[1] && (byte_offset + 32'd2) < byte_count)
                byte_count_delta = byte_count_delta + 32'd1;
            if (strobe[0] && (byte_offset + 32'd3) < byte_count)
                byte_count_delta = byte_count_delta + 32'd1;
        end
    endfunction

    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            mem[i] = 32'h12345678;
        end
        payload_count_q = 32'd0;
        expected_sum_q = 32'd0;
        observed_sum_q = 32'd0;
        observed_xor_q = 32'd0;
        written_bytes_q = 32'd0;
        accepted_count_q = 32'd0;
        first_word_q = 32'd0;
        last_word_q = 32'd0;
        mismatch_q = 32'd0;
        done_q = 1'b0;
        busy_q = 1'b0;
        error_q = 1'b0;
        awaddr_valid_q = 1'b0;
        wdata_valid_q = 1'b0;
    end

    wire write_ready = awaddr_valid_q && wdata_valid_q && !s_axi_bvalid;
    wire [9:0] write_word_index = awaddr_q[11:2];
    wire [9:0] read_word_index = s_axi_araddr[11:2];
    wire payload_write = write_word_index >= PAYLOAD_WORD_BASE;
    wire [31:0] payload_byte_offset = {20'd0, write_word_index - PAYLOAD_WORD_BASE, 2'd0};

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            awaddr_valid_q <= 1'b0;
            wdata_valid_q <= 1'b0;
            payload_count_q <= 32'd0;
            expected_sum_q <= 32'd0;
            observed_sum_q <= 32'd0;
            observed_xor_q <= 32'd0;
            written_bytes_q <= 32'd0;
            accepted_count_q <= 32'd0;
            first_word_q <= 32'd0;
            last_word_q <= 32'd0;
            mismatch_q <= 32'd0;
            done_q <= 1'b0;
            busy_q <= 1'b0;
            error_q <= 1'b0;
        end else begin
            s_axi_awready <= !awaddr_valid_q;
            s_axi_wready <= !wdata_valid_q;

            if (!awaddr_valid_q && s_axi_awvalid) begin
                awaddr_q <= s_axi_awaddr;
                awaddr_valid_q <= 1'b1;
            end
            if (!wdata_valid_q && s_axi_wvalid) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                wdata_valid_q <= 1'b1;
            end

            if (write_ready) begin
                awaddr_valid_q <= 1'b0;
                wdata_valid_q <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;

                if (write_word_index == 10'h002) begin
                    if (wdata_q[0]) begin
                        done_q <= 1'b0;
                        error_q <= 1'b0;
                        mismatch_q <= 32'd0;
                    end
                end else if (write_word_index == 10'h004) begin
                    payload_count_q <= wdata_q;
                    expected_sum_q <= 32'd0;
                    observed_sum_q <= 32'd0;
                    observed_xor_q <= 32'd0;
                    written_bytes_q <= 32'd0;
                    first_word_q <= 32'd0;
                    last_word_q <= 32'd0;
                    mismatch_q <= 32'd0;
                    done_q <= 1'b0;
                    busy_q <= 1'b1;
                    error_q <= wdata_q > MAX_PAYLOAD_BYTES;
                end else if (write_word_index == 10'h005) begin
                    expected_sum_q <= wdata_q;
                end else if (write_word_index == 10'h006) begin
                    if (wdata_q[0]) begin
                        accepted_count_q <= accepted_count_q + 32'd1;
                        done_q <= 1'b1;
                        busy_q <= 1'b0;
                        mismatch_q <= {30'd0, observed_sum_q != expected_sum_q, written_bytes_q != payload_count_q};
                        error_q <= error_q || (observed_sum_q != expected_sum_q) || (written_bytes_q != payload_count_q);
                    end
                end else begin
                    mem[write_word_index] <= apply_wstrb(mem[write_word_index], wdata_q, wstrb_q);
                    if (payload_write) begin
                        last_word_q <= wdata_q;
                        if (written_bytes_q == 32'd0)
                            first_word_q <= wdata_q;
                        observed_sum_q <= observed_sum_q + byte_sum_delta(wdata_q, wstrb_q, payload_byte_offset, payload_count_q);
                        written_bytes_q <= written_bytes_q + byte_count_delta(wstrb_q, payload_byte_offset, payload_count_q);
                        if (wstrb_q == 4'hf && payload_byte_offset < payload_count_q)
                            observed_xor_q <= observed_xor_q ^ wdata_q;
                    end
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
                    10'h002: s_axi_rdata <= {28'd0, error_q, done_q, busy_q, rst_n};
                    10'h003: s_axi_rdata <= accepted_count_q;
                    10'h004: s_axi_rdata <= payload_count_q;
                    10'h005: s_axi_rdata <= expected_sum_q;
                    10'h008: s_axi_rdata <= observed_sum_q;
                    10'h009: s_axi_rdata <= observed_xor_q;
                    10'h00a: s_axi_rdata <= first_word_q;
                    10'h00b: s_axi_rdata <= last_word_q;
                    10'h00c: s_axi_rdata <= mismatch_q;
                    10'h00d: s_axi_rdata <= written_bytes_q;
                    default: s_axi_rdata <= mem[read_word_index];
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
