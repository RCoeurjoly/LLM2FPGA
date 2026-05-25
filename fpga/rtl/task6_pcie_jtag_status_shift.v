// SPDX-License-Identifier: MIT
`default_nettype none

module task6_pcie_jtag_status_shift #(
    parameter integer WIDTH = 1024,
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
    input  wire [2:0]  cfg_pcie_link_state_i,
    input  wire [63:0] m_axis_rx_tdata_i,
    input  wire [7:0]  m_axis_rx_tkeep_i,
    input  wire        m_axis_rx_tlast_i,
    input  wire        m_axis_rx_tvalid_i,
    input  wire        m_axis_rx_tready_i,
    input  wire [21:0] m_axis_rx_tuser_i,
    input  wire [63:0] s_axis_tx_tdata_i,
    input  wire [7:0]  s_axis_tx_tkeep_i,
    input  wire        s_axis_tx_tlast_i,
    input  wire        s_axis_tx_tvalid_i,
    input  wire        s_axis_tx_tready_i,
    input  wire [3:0]  s_axis_tx_tuser_i,
    input  wire        tx_cfg_req_i,
    input  wire        tx_cfg_gnt_i,
    input  wire        tx_err_drop_i,
    input  wire [5:0]  tx_buf_av_i
);
    localparam [31:0] MAGIC = 32'h54365049; // T6PI
    localparam [7:0] VERSION = 8'd2;

    reg [31:0] user_clk_count_q = 32'd0;
    reg [31:0] link_up_seen_count_q = 32'd0;
    reg [31:0] user_reset_seen_count_q = 32'd0;
    reg [5:0]  last_ltssm_q = 6'd0;
    reg [15:0] last_lstatus_q = 16'd0;
    reg [31:0] rx_beat_count_q = 32'd0;
    reg [31:0] rx_packet_count_q = 32'd0;
    reg [31:0] rx_eof_count_q = 32'd0;
    reg [31:0] tx_beat_count_q = 32'd0;
    reg [31:0] tx_packet_count_q = 32'd0;
    reg [31:0] tx_eof_count_q = 32'd0;
    reg [63:0] first_rx_data_q = 64'd0;
    reg [63:0] first_tx_data_q = 64'd0;
    reg [31:0] rx_sticky_q = 32'd0;
    reg [31:0] tx_sticky_q = 32'd0;
    reg        rx_in_packet_q = 1'b0;
    reg        tx_in_packet_q = 1'b0;
    reg        first_rx_seen_q = 1'b0;
    reg        first_tx_seen_q = 1'b0;

    wire rx_live = m_axis_rx_tvalid_i && m_axis_rx_tready_i;
    wire tx_live = s_axis_tx_tvalid_i && s_axis_tx_tready_i;
    wire rx_sof = rx_live && !rx_in_packet_q;
    wire tx_sof = tx_live && !tx_in_packet_q;

    always @(posedge user_clk_i) begin
        user_clk_count_q <= user_clk_count_q + 32'd1;
        last_ltssm_q <= pl_ltssm_state_i;
        last_lstatus_q <= cfg_lstatus_i;
        if (user_lnk_up_i)
            link_up_seen_count_q <= link_up_seen_count_q + 32'd1;
        if (user_reset_i)
            user_reset_seen_count_q <= user_reset_seen_count_q + 32'd1;

        if (user_reset_i) begin
            rx_in_packet_q <= 1'b0;
            tx_in_packet_q <= 1'b0;
        end else begin
            if (rx_live) begin
                rx_beat_count_q <= rx_beat_count_q + 32'd1;
                if (rx_sof)
                    rx_packet_count_q <= rx_packet_count_q + 32'd1;
                if (m_axis_rx_tlast_i) begin
                    rx_eof_count_q <= rx_eof_count_q + 32'd1;
                    rx_in_packet_q <= 1'b0;
                end else begin
                    rx_in_packet_q <= 1'b1;
                end
                if (!first_rx_seen_q) begin
                    first_rx_seen_q <= 1'b1;
                    first_rx_data_q <= m_axis_rx_tdata_i;
                end
            end

            if (tx_live) begin
                tx_beat_count_q <= tx_beat_count_q + 32'd1;
                if (tx_sof)
                    tx_packet_count_q <= tx_packet_count_q + 32'd1;
                if (s_axis_tx_tlast_i) begin
                    tx_eof_count_q <= tx_eof_count_q + 32'd1;
                    tx_in_packet_q <= 1'b0;
                end else begin
                    tx_in_packet_q <= 1'b1;
                end
                if (!first_tx_seen_q) begin
                    first_tx_seen_q <= 1'b1;
                    first_tx_data_q <= s_axis_tx_tdata_i;
                end
            end

            if (rx_live) begin
                rx_sticky_q <= rx_sticky_q | {
                    1'b0,
                    m_axis_rx_tuser_i,
                    m_axis_rx_tkeep_i,
                    rx_sof
                };
            end
            tx_sticky_q <= tx_sticky_q | {
                10'd0,
                tx_buf_av_i,
                tx_err_drop_i,
                tx_cfg_gnt_i,
                tx_cfg_req_i,
                13'd0
            };
            if (tx_live) begin
                tx_sticky_q <= tx_sticky_q | {
                    10'd0,
                    tx_buf_av_i,
                    tx_err_drop_i,
                    tx_cfg_gnt_i,
                    tx_cfg_req_i,
                    s_axis_tx_tuser_i,
                    s_axis_tx_tkeep_i,
                    tx_sof
                };
            end
        end
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
        | ({{(WIDTH-32){1'b0}}, link_up_seen_count_q} << 360)
        | ({{(WIDTH-32){1'b0}}, rx_beat_count_q} << 392)
        | ({{(WIDTH-32){1'b0}}, rx_packet_count_q} << 424)
        | ({{(WIDTH-32){1'b0}}, rx_eof_count_q} << 456)
        | ({{(WIDTH-32){1'b0}}, rx_sticky_q} << 488)
        | ({{(WIDTH-32){1'b0}}, tx_beat_count_q} << 520)
        | ({{(WIDTH-32){1'b0}}, tx_packet_count_q} << 552)
        | ({{(WIDTH-32){1'b0}}, tx_eof_count_q} << 584)
        | ({{(WIDTH-32){1'b0}}, tx_sticky_q} << 616)
        | ({{(WIDTH-32){1'b0}}, first_rx_data_q[31:0]} << 648)
        | ({{(WIDTH-32){1'b0}}, first_rx_data_q[63:32]} << 680)
        | ({{(WIDTH-32){1'b0}}, first_tx_data_q[31:0]} << 712)
        | ({{(WIDTH-32){1'b0}}, first_tx_data_q[63:32]} << 744);

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
