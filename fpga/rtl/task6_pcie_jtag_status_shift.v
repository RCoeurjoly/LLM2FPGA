// SPDX-License-Identifier: MIT
`default_nettype none

module task6_pcie_jtag_status_shift #(
    parameter integer WIDTH = 512,
    parameter integer JTAG_CHAIN = 1
) (
    input  wire        user_clk_i,
    input  wire        sys_rst_n_i,
    input  wire        pipe_mmcm_lock_i,
    input  wire        user_reset_i,
    input  wire        user_lnk_up_i,
    input  wire [5:0]  pl_ltssm_state_i,
    input  wire [4:0]  gt_reset_fsm_i,
    input  wire [7:0]  cfg_bus_number_i,
    input  wire [4:0]  cfg_device_number_i,
    input  wire [2:0]  cfg_function_number_i,
    input  wire [15:0] cfg_status_i,
    input  wire [15:0] cfg_command_i,
    input  wire [15:0] cfg_dstatus_i,
    input  wire [15:0] cfg_dcommand_i,
    input  wire [15:0] cfg_lstatus_i,
    input  wire [15:0] cfg_lcommand_i,
    input  wire [15:0] cfg_dcommand2_i,
    input  wire [2:0]  cfg_pcie_link_state_i
);
    localparam [31:0] MAGIC = 32'h54365049; // T6PI
    localparam [7:0] VERSION = 8'd1;

    reg [31:0] user_clk_count_q = 32'd0;
    reg [31:0] link_up_seen_count_q = 32'd0;
    reg [31:0] user_reset_seen_count_q = 32'd0;
    reg [5:0]  last_ltssm_q = 6'd0;
    reg [15:0] last_lstatus_q = 16'd0;

    always @(posedge user_clk_i) begin
        user_clk_count_q <= user_clk_count_q + 32'd1;
        last_ltssm_q <= pl_ltssm_state_i;
        last_lstatus_q <= cfg_lstatus_i;
        if (user_lnk_up_i)
            link_up_seen_count_q <= link_up_seen_count_q + 32'd1;
        if (user_reset_i)
            user_reset_seen_count_q <= user_reset_seen_count_q + 32'd1;
    end

    wire [31:0] flags_word = {
        16'd0,
        cfg_bus_number_i != 8'd0,
        cfg_lstatus_i != 16'd0,
        cfg_command_i[2],
        cfg_command_i[1],
        cfg_command_i[0],
        cfg_pcie_link_state_i,
        gt_reset_fsm_i[1:0],
        user_lnk_up_i,
        user_reset_i,
        pipe_mmcm_lock_i,
        sys_rst_n_i
    };

    wire [WIDTH - 1:0] payload_fixed;
    assign payload_fixed = '0
        | ({{(WIDTH-32){1'b0}}, MAGIC} << 0)
        | ({{(WIDTH-8){1'b0}}, VERSION} << 32)
        | ({{(WIDTH-32){1'b0}}, flags_word} << 40)
        | ({{(WIDTH-32){1'b0}}, user_clk_count_q} << 72)
        | ({{(WIDTH-32){1'b0}}, {16'd0, gt_reset_fsm_i, pl_ltssm_state_i, 5'd0}} << 104)
        | ({{(WIDTH-32){1'b0}}, {16'd0, cfg_pcie_link_state_i, cfg_function_number_i, cfg_device_number_i, cfg_bus_number_i}} << 136)
        | ({{(WIDTH-32){1'b0}}, {16'd0, cfg_status_i}} << 168)
        | ({{(WIDTH-32){1'b0}}, {cfg_dstatus_i, cfg_command_i}} << 200)
        | ({{(WIDTH-32){1'b0}}, {cfg_lstatus_i, cfg_dcommand_i}} << 232)
        | ({{(WIDTH-32){1'b0}}, {cfg_dcommand2_i, cfg_lcommand_i}} << 264)
        | ({{(WIDTH-32){1'b0}}, {last_lstatus_q, last_ltssm_q, 10'd0}} << 296)
        | ({{(WIDTH-32){1'b0}}, user_reset_seen_count_q} << 328)
        | ({{(WIDTH-32){1'b0}}, link_up_seen_count_q} << 360);

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

    wire unused_runtest = runtest;
    wire unused_tck = tck;
    wire unused_tms = tms;
    wire unused_update = update;
endmodule

`default_nettype wire
