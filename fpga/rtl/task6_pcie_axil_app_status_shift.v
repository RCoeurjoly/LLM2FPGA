// SPDX-License-Identifier: MIT
`default_nettype none

module task6_pcie_axil_app_status_shift #(
    parameter integer WIDTH = 384,
    parameter integer JTAG_CHAIN = 2
) (
    input wire        clk_i,
    input wire        rst_n_i,
    input wire [31:0] ar_count_i,
    input wire [31:0] r_count_i,
    input wire [31:0] aw_count_i,
    input wire [31:0] w_count_i,
    input wire [31:0] b_count_i,
    input wire [31:0] last_araddr_i,
    input wire [31:0] last_rdata_i,
    input wire [31:0] last_awaddr_i,
    input wire [31:0] last_wdata_i
);
    localparam [31:0] MAGIC = 32'h54365041; // T6PA
    localparam [7:0] VERSION = 8'd1;

    reg [31:0] clk_count_q = 32'd0;
    always @(posedge clk_i) begin
        clk_count_q <= clk_count_q + 32'd1;
    end

    wire [31:0] flags_word = {31'd0, rst_n_i};
    wire [WIDTH - 1:0] payload_fixed;
    assign payload_fixed = '0
        | ({{(WIDTH-32){1'b0}}, MAGIC} << 0)
        | ({{(WIDTH-8){1'b0}}, VERSION} << 32)
        | ({{(WIDTH-32){1'b0}}, flags_word} << 40)
        | ({{(WIDTH-32){1'b0}}, clk_count_q} << 72)
        | ({{(WIDTH-32){1'b0}}, ar_count_i} << 104)
        | ({{(WIDTH-32){1'b0}}, r_count_i} << 136)
        | ({{(WIDTH-32){1'b0}}, aw_count_i} << 168)
        | ({{(WIDTH-32){1'b0}}, w_count_i} << 200)
        | ({{(WIDTH-32){1'b0}}, b_count_i} << 232)
        | ({{(WIDTH-32){1'b0}}, last_araddr_i} << 264)
        | ({{(WIDTH-32){1'b0}}, last_rdata_i} << 296)
        | ({{(WIDTH-32){1'b0}}, last_awaddr_i} << 328)
        | ({{(WIDTH-32){1'b0}}, last_wdata_i} << 360);

    wire capture;
    wire drck;
    wire reset;
    wire runtest;
    wire sel;
    wire shift;
    wire tck;
    wire tdi;
    wire tms;
    wire update;
    wire tdo;
    reg [WIDTH - 1:0] shift_q = {WIDTH{1'b0}};

    assign tdo = shift_q[0];

    always @(posedge drck or posedge reset) begin
        if (reset)
            shift_q <= {WIDTH{1'b0}};
        else if (sel && capture)
            shift_q <= payload_fixed;
        else if (sel && shift)
            shift_q <= {tdi, shift_q[WIDTH - 1:1]};
    end

    BSCANE2 #(
        .DISABLE_JTAG("FALSE"),
        .JTAG_CHAIN(JTAG_CHAIN)
    ) bscan (
        .CAPTURE(capture),
        .DRCK(drck),
        .RESET(reset),
        .RUNTEST(runtest),
        .SEL(sel),
        .SHIFT(shift),
        .TCK(tck),
        .TDI(tdi),
        .TMS(tms),
        .UPDATE(update),
        .TDO(tdo)
    );

    wire unused_tck = tck;
    wire unused_tms = tms;
    wire unused_update = update;
    wire unused_runtest = runtest;
endmodule

`default_nettype wire
