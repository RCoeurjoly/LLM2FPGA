`default_nettype none

module task6_ypcb_uberddr3_bist_top #(
  parameter int JTAG_DEBUG_WIDTH = 512,
  parameter int JTAG_CHAIN = 1
) (
  input  wire        clk50,
  input  wire        SYS_RSTN,
  output wire [14:0] ddram_a,
  output wire  [2:0] ddram_ba,
  output wire        ddram_cas_n,
  output wire        ddram_cke,
  output wire        ddram_clk_n,
  output wire        ddram_clk_p,
  output wire        ddram_cs_n,
  inout  wire [63:0] ddram_dq,
  inout  wire  [7:0] ddram_dqs_n,
  inout  wire  [7:0] ddram_dqs_p,
  output wire        ddram_odt,
  output wire        ddram_ras_n,
  output wire        ddram_reset_n,
  output wire        ddram_we_n
);
  localparam logic [31:0] JTAG_DEBUG_MAGIC = 32'h54364a44;
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd3;
  localparam int ROW_BITS = 15;
  localparam int COL_BITS = 10;
  localparam int BA_BITS = 3;
  localparam int BYTE_LANES = 8;
  localparam int WB_ADDR_BITS = ROW_BITS + COL_BITS + BA_BITS - 3;
  localparam int WB_DATA_BITS = 8 * BYTE_LANES * 8;
  localparam int WB_SEL_BITS = WB_DATA_BITS / 8;
  localparam logic [3:0] ROW_BITS_NIBBLE = ROW_BITS % 16;
  localparam logic [3:0] COL_BITS_NIBBLE = COL_BITS % 16;
  localparam logic [3:0] BA_BITS_NIBBLE = BA_BITS % 16;
  localparam logic [3:0] BYTE_LANES_NIBBLE = BYTE_LANES % 16;
  localparam logic [3:0] WB_ADDR_BITS_NIBBLE = WB_ADDR_BITS % 16;
  localparam logic [3:0] WB_SEL_BITS_NIBBLE = WB_SEL_BITS % 16;
  localparam int PROBE_BEATS = 4;

  wire controller_clk;
  wire ddr3_clk;
  wire ddr3_clk_90;
  wire ref_clk;
  wire clk100_raw;
  wire clk100_90_raw;
  wire clk25_raw;
  wire clk200_raw;
  wire pll_clkfb;
  wire mmcm_locked;
  wire rst_n;
  logic [31:0] clk50_count_q;

  always_ff @(posedge clk50) begin
    clk50_count_q <= clk50_count_q + 32'd1;
  end

  PLLE2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT(20),
    .CLKFBOUT_PHASE(0.000),
    .CLKIN1_PERIOD(20.000),
    .CLKOUT0_DIVIDE(10),
    .CLKOUT0_DUTY_CYCLE(0.500),
    .CLKOUT0_PHASE(0.000),
    .CLKOUT1_DIVIDE(10),
    .CLKOUT1_DUTY_CYCLE(0.500),
    .CLKOUT1_PHASE(90.000),
    .CLKOUT2_DIVIDE(40),
    .CLKOUT2_DUTY_CYCLE(0.500),
    .CLKOUT2_PHASE(0.000),
    .CLKOUT3_DIVIDE(5),
    .CLKOUT3_DUTY_CYCLE(0.500),
    .CLKOUT3_PHASE(0.000),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010),
    .STARTUP_WAIT("FALSE")
  ) clock_pll (
    .CLKFBOUT(pll_clkfb),
    .CLKOUT0(clk100_raw),
    .CLKOUT1(clk100_90_raw),
    .CLKOUT2(clk25_raw),
    .CLKOUT3(clk200_raw),
    .CLKOUT4(),
    .CLKOUT5(),
    .LOCKED(mmcm_locked),
    .CLKFBIN(pll_clkfb),
    .CLKIN1(clk50),
    .PWRDWN(1'b0),
    .RST(1'b0)
  );

  BUFG clk100_bufg (
    .I(clk100_raw),
    .O(ddr3_clk)
  );

  BUFG clk100_90_bufg (
    .I(clk100_90_raw),
    .O(ddr3_clk_90)
  );

  BUFG clk25_bufg (
    .I(clk25_raw),
    .O(controller_clk)
  );

  BUFG clk200_bufg (
    .I(clk200_raw),
    .O(ref_clk)
  );

  assign rst_n = mmcm_locked;

  wire wb_stall;
  wire wb_ack;
  wire wb_err;
  wire [WB_DATA_BITS - 1:0] wb_data;
  wire [3:0] wb_aux;
  wire wb2_stall;
  wire wb2_ack;
  wire [31:0] wb2_data;
  wire [0:0] ddr3_clk_p_w;
  wire [0:0] ddr3_clk_n_w;
  wire [0:0] ddr3_cke_w;
  wire [0:0] ddr3_cs_n_w;
  wire [0:0] ddr3_odt_w;
  wire [BYTE_LANES - 1:0] ddr3_dm_w;
  wire calib_complete;
  wire [31:0] debug1;
  wire uart_tx;

  typedef enum logic [3:0] {
    PROBE_RESET = 4'd0,
    PROBE_WAIT_CALIB = 4'd1,
    PROBE_WRITE_ISSUE = 4'd2,
    PROBE_WRITE_WAIT = 4'd3,
    PROBE_READ_ISSUE = 4'd4,
    PROBE_READ_WAIT = 4'd5,
    PROBE_DONE = 4'd6,
    PROBE_FAIL = 4'd7
  } probe_state_t;

  probe_state_t probe_state_q;
  logic probe_cyc_q;
  logic probe_stb_q;
  logic probe_we_q;
  logic [WB_ADDR_BITS - 1:0] probe_addr_q;
  logic [WB_DATA_BITS - 1:0] probe_data_q;
  logic [3:0] probe_index_q;
  logic [31:0] probe_mismatch_count_q;
  logic [31:0] probe_first_mismatch_addr_q;
  logic [31:0] probe_expected_lo_q;
  logic [31:0] probe_observed_lo_q;
  logic probe_done_q;
  logic probe_pass_q;
  logic probe_fail_q;

  function automatic logic [WB_DATA_BITS - 1:0] probe_pattern(input logic [WB_ADDR_BITS - 1:0] addr);
    logic [WB_DATA_BITS - 1:0] value;
    logic [7:0] byte_value;
    int byte_index;
    begin
      value = '0;
      for (byte_index = 0; byte_index < WB_SEL_BITS; byte_index = byte_index + 1) begin
        byte_value = ((byte_index * 8'h25) ^ (addr[7:0] * 8'h5d) ^ 8'ha6) + byte_index;
        value[8 * byte_index +: 8] = byte_value;
      end
      probe_pattern = value;
    end
  endfunction

  function automatic logic [31:0] probe_pattern_lo(input logic [WB_ADDR_BITS - 1:0] addr);
    logic [31:0] value;
    logic [7:0] byte_value;
    int byte_index;
    begin
      value = 32'd0;
      for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
        byte_value = ((byte_index * 8'h25) ^ (addr[7:0] * 8'h5d) ^ 8'ha6) + byte_index;
        value[8 * byte_index +: 8] = byte_value;
      end
      probe_pattern_lo = value;
    end
  endfunction

  assign ddram_clk_p = ddr3_clk_p_w[0];
  assign ddram_clk_n = ddr3_clk_n_w[0];
  assign ddram_cke = ddr3_cke_w[0];
  assign ddram_cs_n = ddr3_cs_n_w[0];
  assign ddram_odt = ddr3_odt_w[0];

  logic [31:0] cycle_count_q;
  logic [31:0] calib_seen_cycle_q;
  logic [31:0] wb_ack_count_q;
  logic [31:0] wb_err_count_q;
  logic [31:0] wb_stall_count_q;
  logic calib_seen_q;

  always_ff @(posedge controller_clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count_q <= 32'd0;
      calib_seen_cycle_q <= 32'd0;
      wb_ack_count_q <= 32'd0;
      wb_err_count_q <= 32'd0;
      wb_stall_count_q <= 32'd0;
      calib_seen_q <= 1'b0;
      probe_state_q <= PROBE_RESET;
      probe_cyc_q <= 1'b0;
      probe_stb_q <= 1'b0;
      probe_we_q <= 1'b0;
      probe_addr_q <= '0;
      probe_data_q <= '0;
      probe_index_q <= 4'd0;
      probe_mismatch_count_q <= 32'd0;
      probe_first_mismatch_addr_q <= 32'd0;
      probe_expected_lo_q <= 32'd0;
      probe_observed_lo_q <= 32'd0;
      probe_done_q <= 1'b0;
      probe_pass_q <= 1'b0;
      probe_fail_q <= 1'b0;
    end else begin
      cycle_count_q <= cycle_count_q + 32'd1;
      if (calib_complete && !calib_seen_q) begin
        calib_seen_q <= 1'b1;
        calib_seen_cycle_q <= cycle_count_q;
      end
      if (wb_ack)
        wb_ack_count_q <= wb_ack_count_q + 32'd1;
      if (wb_err)
        wb_err_count_q <= wb_err_count_q + 32'd1;
      if (wb_stall)
        wb_stall_count_q <= wb_stall_count_q + 32'd1;

      case (probe_state_q)
        PROBE_RESET: begin
          probe_cyc_q <= 1'b0;
          probe_stb_q <= 1'b0;
          probe_we_q <= 1'b0;
          probe_addr_q <= '0;
          probe_data_q <= '0;
          probe_index_q <= 4'd0;
          probe_mismatch_count_q <= 32'd0;
          probe_first_mismatch_addr_q <= 32'd0;
          probe_expected_lo_q <= 32'd0;
          probe_observed_lo_q <= 32'd0;
          probe_done_q <= 1'b0;
          probe_pass_q <= 1'b0;
          probe_fail_q <= 1'b0;
          probe_state_q <= PROBE_WAIT_CALIB;
        end

        PROBE_WAIT_CALIB: begin
          if (calib_complete) begin
            probe_index_q <= 4'd0;
            probe_state_q <= PROBE_WRITE_ISSUE;
          end
        end

        PROBE_WRITE_ISSUE: begin
          probe_cyc_q <= 1'b1;
          probe_stb_q <= 1'b1;
          probe_we_q <= 1'b1;
          probe_addr_q <= {{(WB_ADDR_BITS - 4){1'b0}}, probe_index_q};
          probe_data_q <= probe_pattern({{(WB_ADDR_BITS - 4){1'b0}}, probe_index_q});
          if (!wb_stall) begin
            probe_stb_q <= 1'b0;
            probe_state_q <= wb_ack ? ((probe_index_q == PROBE_BEATS - 1) ? PROBE_READ_ISSUE : PROBE_WRITE_ISSUE) : PROBE_WRITE_WAIT;
            if (wb_ack) begin
              probe_index_q <= (probe_index_q == PROBE_BEATS - 1) ? 4'd0 : probe_index_q + 4'd1;
            end
          end
        end

        PROBE_WRITE_WAIT: begin
          probe_cyc_q <= 1'b1;
          probe_stb_q <= 1'b0;
          probe_we_q <= 1'b1;
          if (wb_err) begin
            probe_fail_q <= 1'b1;
            probe_done_q <= 1'b1;
            probe_state_q <= PROBE_FAIL;
          end else if (wb_ack) begin
            probe_cyc_q <= 1'b0;
            probe_index_q <= (probe_index_q == PROBE_BEATS - 1) ? 4'd0 : probe_index_q + 4'd1;
            probe_state_q <= (probe_index_q == PROBE_BEATS - 1) ? PROBE_READ_ISSUE : PROBE_WRITE_ISSUE;
          end
        end

        PROBE_READ_ISSUE: begin
          probe_cyc_q <= 1'b1;
          probe_stb_q <= 1'b1;
          probe_we_q <= 1'b0;
          probe_addr_q <= {{(WB_ADDR_BITS - 4){1'b0}}, probe_index_q};
          probe_data_q <= '0;
          if (!wb_stall) begin
            probe_stb_q <= 1'b0;
            probe_state_q <= PROBE_READ_WAIT;
          end
        end

        PROBE_READ_WAIT: begin
          probe_cyc_q <= 1'b1;
          probe_stb_q <= 1'b0;
          probe_we_q <= 1'b0;
          if (wb_err) begin
            probe_fail_q <= 1'b1;
            probe_done_q <= 1'b1;
            probe_state_q <= PROBE_FAIL;
          end else if (wb_ack) begin
            probe_cyc_q <= 1'b0;
            if (wb_data != probe_pattern({{(WB_ADDR_BITS - 4){1'b0}}, probe_index_q})) begin
              probe_mismatch_count_q <= probe_mismatch_count_q + 32'd1;
              if (!probe_fail_q) begin
                probe_fail_q <= 1'b1;
                probe_first_mismatch_addr_q <= {{(32 - 4){1'b0}}, probe_index_q};
                probe_expected_lo_q <= probe_pattern_lo({{(WB_ADDR_BITS - 4){1'b0}}, probe_index_q});
                probe_observed_lo_q <= wb_data[31:0];
              end
            end
            if (probe_index_q == PROBE_BEATS - 1) begin
              probe_done_q <= 1'b1;
              probe_pass_q <= !probe_fail_q && (wb_data == probe_pattern({{(WB_ADDR_BITS - 4){1'b0}}, probe_index_q}));
              probe_state_q <= (!probe_fail_q && (wb_data == probe_pattern({{(WB_ADDR_BITS - 4){1'b0}}, probe_index_q}))) ? PROBE_DONE : PROBE_FAIL;
            end else begin
              probe_index_q <= probe_index_q + 4'd1;
              probe_state_q <= PROBE_READ_ISSUE;
            end
          end
        end

        PROBE_DONE: begin
          probe_cyc_q <= 1'b0;
          probe_stb_q <= 1'b0;
          probe_we_q <= 1'b0;
          probe_done_q <= 1'b1;
          probe_pass_q <= 1'b1;
        end

        PROBE_FAIL: begin
          probe_cyc_q <= 1'b0;
          probe_stb_q <= 1'b0;
          probe_done_q <= 1'b1;
          probe_fail_q <= 1'b1;
        end

        default: probe_state_q <= PROBE_FAIL;
      endcase
    end
  end

  logic [JTAG_DEBUG_WIDTH - 1:0] jtag_debug_payload;

  always_comb begin
    jtag_debug_payload = '0;
    jtag_debug_payload[0 +: 32] = JTAG_DEBUG_MAGIC;
    jtag_debug_payload[32 +: 8] = JTAG_DEBUG_VERSION;
    jtag_debug_payload[40 +: 8] = {
      1'b0,
      uart_tx,
      wb2_ack,
      wb2_stall,
      wb_err,
      wb_ack,
      calib_seen_q,
      calib_complete
    };
    jtag_debug_payload[47] = mmcm_locked;
    jtag_debug_payload[48 +: 32] = cycle_count_q;
    jtag_debug_payload[80 +: 32] = calib_seen_cycle_q;
    jtag_debug_payload[112 +: 32] = debug1;
    jtag_debug_payload[144 +: 32] = wb_ack_count_q;
    jtag_debug_payload[176 +: 32] = wb_err_count_q;
    jtag_debug_payload[208 +: 32] = wb_stall_count_q;
    jtag_debug_payload[240 +: 32] = wb_data[31:0];
    jtag_debug_payload[272 +: 32] = wb_data[63:32];
    jtag_debug_payload[304 +: 32] =
      {16'd0, probe_state_q, probe_index_q, 5'd0, probe_fail_q, probe_pass_q, probe_done_q};
    jtag_debug_payload[336 +: 32] =
      {16'd0, BYTE_LANES_NIBBLE, BA_BITS_NIBBLE, COL_BITS_NIBBLE, ROW_BITS_NIBBLE};
    jtag_debug_payload[368 +: 32] =
      {16'd0, 4'd1, 4'd0, WB_SEL_BITS_NIBBLE, WB_ADDR_BITS_NIBBLE};
    jtag_debug_payload[400 +: 32] = probe_mismatch_count_q;
    jtag_debug_payload[432 +: 32] = probe_first_mismatch_addr_q;
    jtag_debug_payload[464 +: 32] = probe_expected_lo_q;
    jtag_debug_payload[496 +: 16] = probe_observed_lo_q[15:0];
    jtag_debug_payload[511] = SYS_RSTN;
  end

  ddr3_top #(
    .CONTROLLER_CLK_PERIOD(40_000),
    .DDR3_CLK_PERIOD(10_000),
    .ROW_BITS(ROW_BITS),
    .COL_BITS(COL_BITS),
    .BA_BITS(BA_BITS),
    .BYTE_LANES(BYTE_LANES),
    .AUX_WIDTH(4),
    .WB2_ADDR_BITS(7),
    .WB2_DATA_BITS(32),
    .DUAL_RANK_DIMM(0),
    .SPEED_BIN(0),
    .SDRAM_CAPACITY(5),
    .TRCD(13_750),
    .TRP(13_750),
    .TRAS(35_000),
    .ODELAY_SUPPORTED(0),
    .SECOND_WISHBONE(0),
    .DLL_OFF(1),
    .WB_ERROR(0),
    .BIST_MODE(1),
    .ECC_ENABLE(0)
  ) uberddr3 (
    .i_controller_clk(controller_clk),
    .i_ddr3_clk(ddr3_clk),
    .i_ref_clk(ref_clk),
    .i_ddr3_clk_90(ddr3_clk_90),
    .i_rst_n(rst_n),
    .i_wb_cyc(probe_cyc_q),
    .i_wb_stb(probe_stb_q),
    .i_wb_we(probe_we_q),
    .i_wb_addr(probe_addr_q),
    .i_wb_data(probe_data_q),
    .i_wb_sel({WB_SEL_BITS{1'b1}}),
    .i_aux({3'd0, probe_we_q}),
    .o_wb_stall(wb_stall),
    .o_wb_ack(wb_ack),
    .o_wb_err(wb_err),
    .o_wb_data(wb_data),
    .o_aux(wb_aux),
    .i_wb2_cyc(1'b0),
    .i_wb2_stb(1'b0),
    .i_wb2_we(1'b0),
    .i_wb2_addr(7'd0),
    .i_wb2_data(32'd0),
    .i_wb2_sel(4'd0),
    .o_wb2_stall(wb2_stall),
    .o_wb2_ack(wb2_ack),
    .o_wb2_data(wb2_data),
    .o_ddr3_clk_p(ddr3_clk_p_w),
    .o_ddr3_clk_n(ddr3_clk_n_w),
    .o_ddr3_reset_n(ddram_reset_n),
    .o_ddr3_cke(ddr3_cke_w),
    .o_ddr3_cs_n(ddr3_cs_n_w),
    .o_ddr3_ras_n(ddram_ras_n),
    .o_ddr3_cas_n(ddram_cas_n),
    .o_ddr3_we_n(ddram_we_n),
    .o_ddr3_addr(ddram_a),
    .o_ddr3_ba_addr(ddram_ba),
    .io_ddr3_dq(ddram_dq),
    .io_ddr3_dqs(ddram_dqs_p),
    .io_ddr3_dqs_n(ddram_dqs_n),
    .o_ddr3_dm(ddr3_dm_w),
    .o_ddr3_odt(ddr3_odt_w),
    .o_calib_complete(calib_complete),
    .o_debug1(debug1),
    .i_user_self_refresh(1'b0),
    .uart_tx(uart_tx)
  );

  task6_uberddr3_jtag_debug_shift #(
    .WIDTH(JTAG_DEBUG_WIDTH),
    .JTAG_CHAIN(JTAG_CHAIN)
  ) jtag_debug_shift (
    .payload_i(jtag_debug_payload)
  );
endmodule

module task6_uberddr3_jtag_debug_shift #(
  parameter int WIDTH = 512,
  parameter int JTAG_CHAIN = 1
) (
  input logic [WIDTH - 1:0] payload_i
);
  logic capture;
  logic drck;
  logic reset;
  logic runtest;
  logic sel;
  logic shift;
  logic tck;
  logic tdi;
  logic tms;
  logic update;
  logic tdo;
  logic [WIDTH - 1:0] shift_q;

  assign tdo = shift_q[0];

  always_ff @(posedge drck or posedge reset) begin
    if (reset)
      shift_q <= '0;
    else if (sel && capture)
      shift_q <= payload_i;
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
endmodule

`default_nettype wire
