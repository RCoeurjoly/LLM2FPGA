// SPDX-License-Identifier: MIT
// Header-only Task 6 PCIe BAR responder.
//
// This is intentionally a near-copy of upstream pcie_7x axil_minimum with only
// BAR memory initialization changed. It is the first custom responder ladder
// gate after the known-good upstream smoke image.

module axil_minimum(
    input clk,
    input rst_n,

    input      [31:0] s_axi_awaddr,
    input             s_axi_awvalid,
    output reg        s_axi_awready,

    input      [31:0] s_axi_wdata,
    input       [3:0] s_axi_wstrb,
    input             s_axi_wvalid,
    output reg        s_axi_wready,

    output reg  [1:0] s_axi_bresp,
    output reg        s_axi_bvalid,
    input             s_axi_bready,

    input      [31:0] s_axi_araddr,
    input             s_axi_arvalid,
    output reg        s_axi_arready,

    output reg [31:0] s_axi_rdata = 0,
    output reg        s_axi_rvalid,
    input             s_axi_rready,
    output reg  [1:0] s_axi_rresp
);
    (* ram_style = "distributed" *) reg [31:0] mem [255:0];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'h12345678;
        mem[8'h00] = 32'h54365043;
        mem[8'h01] = 32'd1;
        mem[8'h02] = 32'd1;
        mem[8'h03] = 32'd0;
    end

    reg [31:0] write_address;
    reg [31:0] read_address;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b1;
        end else if (s_axi_awvalid) begin
            write_address <= s_axi_awaddr;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_wready <= 1'b0;
        end else if (!s_axi_wready && s_axi_wvalid) begin
            s_axi_wready <= 1'b1;
        end else begin
            s_axi_wready <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
        end else if (s_axi_wready && s_axi_wvalid) begin
            mem[write_address[9:2]] <= s_axi_wdata;
            s_axi_bvalid <= 1'b1;
            s_axi_bresp <= 2'b00;
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
        end else if (!s_axi_arready && s_axi_arvalid) begin
            s_axi_arready <= 1'b1;
            read_address <= s_axi_araddr;
        end else begin
            s_axi_arready <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
        end else if (s_axi_arready && s_axi_arvalid) begin
            s_axi_rdata <= mem[read_address[9:2]];
            s_axi_rvalid <= 1'b1;
            s_axi_rresp <= 2'b00;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end

    wire unused_wstrb = |s_axi_wstrb;
endmodule
