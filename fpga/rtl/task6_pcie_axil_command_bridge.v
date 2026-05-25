// SPDX-License-Identifier: MIT
// Minimal Task 6 PCIe BAR command bridge.
//
// This module deliberately uses the upstream pcie_7x example module name
// `axil_minimum` so the unmodified pcie_7x_top_aximm wrapper can instantiate
// it when this file replaces upstream axil_minimum.v in the source list.

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

    output reg [31:0] s_axi_rdata,
    output reg        s_axi_rvalid,
    input wire        s_axi_rready,
    output reg [1:0]  s_axi_rresp
);
    localparam [31:0] TASK6_PCIE_MAGIC = 32'h54365043; // T6PC
    localparam [31:0] TASK6_PCIE_VERSION = 32'd1;

    reg [31:0] write_address_q;
    reg [31:0] command_payload_q [0:6];
    reg [31:0] accepted_payload_q [0:6];
    reg [31:0] accepted_count_q;
    reg command_pending_q;
    reg command_accepted_pulse_q;
    reg command_error_q;

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

    wire write_fire = s_axi_wready && s_axi_wvalid;
    wire [9:2] write_word_addr = write_address_q[9:2];
    wire [9:2] read_word_addr = s_axi_araddr[9:2];

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b1;
            write_address_q <= 32'd0;
        end else begin
            s_axi_awready <= 1'b1;
            if (s_axi_awvalid) begin
                write_address_q <= s_axi_awaddr;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_wready <= 1'b0;
        end else begin
            s_axi_wready <= !s_axi_wready && s_axi_wvalid;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            accepted_count_q <= 32'd0;
            command_pending_q <= 1'b0;
            command_accepted_pulse_q <= 1'b0;
            command_error_q <= 1'b0;
            for (i = 0; i < 7; i = i + 1) begin
                command_payload_q[i] <= 32'd0;
                accepted_payload_q[i] <= 32'd0;
            end
        end else begin
            command_accepted_pulse_q <= 1'b0;
            if (write_fire) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                case (write_word_addr)
                    8'h08: command_error_q <= 1'b0;
                    8'h0c: command_pending_q <= 1'b0;
                    8'h10: command_payload_q[0] <= apply_wstrb(command_payload_q[0], s_axi_wdata, s_axi_wstrb);
                    8'h11: command_payload_q[1] <= apply_wstrb(command_payload_q[1], s_axi_wdata, s_axi_wstrb);
                    8'h12: command_payload_q[2] <= apply_wstrb(command_payload_q[2], s_axi_wdata, s_axi_wstrb);
                    8'h13: command_payload_q[3] <= apply_wstrb(command_payload_q[3], s_axi_wdata, s_axi_wstrb);
                    8'h14: command_payload_q[4] <= apply_wstrb(command_payload_q[4], s_axi_wdata, s_axi_wstrb);
                    8'h15: command_payload_q[5] <= apply_wstrb(command_payload_q[5], s_axi_wdata, s_axi_wstrb);
                    8'h16: command_payload_q[6] <= apply_wstrb(command_payload_q[6], s_axi_wdata, s_axi_wstrb);
                    8'h18: begin
                        if (s_axi_wdata[0]) begin
                            for (i = 0; i < 7; i = i + 1)
                                accepted_payload_q[i] <= command_payload_q[i];
                            accepted_count_q <= accepted_count_q + 32'd1;
                            command_pending_q <= 1'b1;
                            command_accepted_pulse_q <= 1'b1;
                        end
                    end
                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
        end else begin
            s_axi_arready <= !s_axi_arready && s_axi_arvalid;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 32'd0;
        end else begin
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
                case (read_word_addr)
                    8'h00: s_axi_rdata <= TASK6_PCIE_MAGIC;
                    8'h01: s_axi_rdata <= TASK6_PCIE_VERSION;
                    8'h02: s_axi_rdata <= {
                        28'd0,
                        command_error_q,
                        command_accepted_pulse_q,
                        command_pending_q,
                        rst_n
                    };
                    8'h03: s_axi_rdata <= accepted_count_q;
                    8'h10: s_axi_rdata <= command_payload_q[0];
                    8'h11: s_axi_rdata <= command_payload_q[1];
                    8'h12: s_axi_rdata <= command_payload_q[2];
                    8'h13: s_axi_rdata <= command_payload_q[3];
                    8'h14: s_axi_rdata <= command_payload_q[4];
                    8'h15: s_axi_rdata <= command_payload_q[5];
                    8'h16: s_axi_rdata <= command_payload_q[6];
                    8'h20: s_axi_rdata <= accepted_payload_q[0];
                    8'h21: s_axi_rdata <= accepted_payload_q[1];
                    8'h22: s_axi_rdata <= accepted_payload_q[2];
                    8'h23: s_axi_rdata <= accepted_payload_q[3];
                    8'h24: s_axi_rdata <= accepted_payload_q[4];
                    8'h25: s_axi_rdata <= accepted_payload_q[5];
                    8'h26: s_axi_rdata <= accepted_payload_q[6];
                    default: s_axi_rdata <= 32'hbad0_add0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
