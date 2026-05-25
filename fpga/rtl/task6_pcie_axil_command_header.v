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
    reg [31:0] ar_count_q = 32'd0;
    reg [31:0] r_count_q = 32'd0;
    reg [31:0] aw_count_q = 32'd0;
    reg [31:0] w_count_q = 32'd0;
    reg [31:0] b_count_q = 32'd0;
    reg [31:0] last_araddr_q = 32'd0;
    reg [31:0] last_rdata_q = 32'd0;
    reg [31:0] last_awaddr_q = 32'd0;
    reg [31:0] last_wdata_q = 32'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b1;
        end else if (s_axi_awvalid) begin
            write_address <= s_axi_awaddr;
            last_awaddr_q <= s_axi_awaddr;
            aw_count_q <= aw_count_q + 32'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_wready <= 1'b0;
        end else if (!s_axi_wready && s_axi_wvalid) begin
            s_axi_wready <= 1'b1;
            last_wdata_q <= s_axi_wdata;
            w_count_q <= w_count_q + 32'd1;
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
            b_count_q <= b_count_q + 32'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
        end else if (!s_axi_arready && s_axi_arvalid) begin
            s_axi_arready <= 1'b1;
            read_address <= s_axi_araddr;
            last_araddr_q <= s_axi_araddr;
            ar_count_q <= ar_count_q + 32'd1;
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
            last_rdata_q <= mem[read_address[9:2]];
            s_axi_rvalid <= 1'b1;
            s_axi_rresp <= 2'b00;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
            r_count_q <= r_count_q + 32'd1;
        end
    end

    task6_pcie_axil_app_status_shift #(.WIDTH(384), .JTAG_CHAIN(2)) app_status_i (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ar_count_i(ar_count_q),
        .r_count_i(r_count_q),
        .aw_count_i(aw_count_q),
        .w_count_i(w_count_q),
        .b_count_i(b_count_q),
        .last_araddr_i(last_araddr_q),
        .last_rdata_i(last_rdata_q),
        .last_awaddr_i(last_awaddr_q),
        .last_wdata_i(last_wdata_q)
    );

    wire unused_wstrb = |s_axi_wstrb;
endmodule
