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
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd7;
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
  localparam logic [WB_DATA_BITS - 1:0] PROBE_WRITE_PATTERN = {WB_SEL_BITS{8'ha5}};

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

  typedef enum logic [2:0] {
    READ_PROBE_RESET = 3'd0,
    READ_PROBE_WAIT_CALIB = 3'd1,
    READ_PROBE_ISSUE_WRITE = 3'd2,
    READ_PROBE_WAIT_WRITE_ACK = 3'd3,
    READ_PROBE_ISSUE_READ = 3'd4,
    READ_PROBE_WAIT_READ_ACK = 3'd5,
    READ_PROBE_DONE = 3'd6,
    READ_PROBE_ERROR = 3'd7
  } read_probe_state_t;

  read_probe_state_t read_probe_state_q;
  logic read_probe_cyc_q;
  logic read_probe_stb_q;
  logic read_probe_we_q;
  logic read_probe_done_q;
  logic read_probe_write_ack_seen_q;
  logic read_probe_read_ack_seen_q;
  logic read_probe_err_seen_q;
  logic read_probe_stall_seen_q;
  logic read_probe_mismatch_q;
  logic [31:0] read_probe_wait_cycles_q;
  logic [31:0] read_probe_data_lo_q;
  logic [31:0] read_probe_data_hi_q;

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
      read_probe_state_q <= READ_PROBE_RESET;
      read_probe_cyc_q <= 1'b0;
      read_probe_stb_q <= 1'b0;
      read_probe_we_q <= 1'b0;
      read_probe_done_q <= 1'b0;
      read_probe_write_ack_seen_q <= 1'b0;
      read_probe_read_ack_seen_q <= 1'b0;
      read_probe_err_seen_q <= 1'b0;
      read_probe_stall_seen_q <= 1'b0;
      read_probe_mismatch_q <= 1'b0;
      read_probe_wait_cycles_q <= 32'd0;
      read_probe_data_lo_q <= 32'd0;
      read_probe_data_hi_q <= 32'd0;
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

      case (read_probe_state_q)
        READ_PROBE_RESET: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_done_q <= 1'b0;
          read_probe_write_ack_seen_q <= 1'b0;
          read_probe_read_ack_seen_q <= 1'b0;
          read_probe_err_seen_q <= 1'b0;
          read_probe_stall_seen_q <= 1'b0;
          read_probe_mismatch_q <= 1'b0;
          read_probe_wait_cycles_q <= 32'd0;
          read_probe_state_q <= READ_PROBE_WAIT_CALIB;
        end

        READ_PROBE_WAIT_CALIB: begin
          if (calib_complete) begin
            read_probe_cyc_q <= 1'b1;
            read_probe_stb_q <= 1'b1;
            read_probe_we_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_ISSUE_WRITE;
          end
        end

        READ_PROBE_ISSUE_WRITE: begin
          if (wb_stall) begin
            read_probe_stall_seen_q <= 1'b1;
            read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          end else begin
            read_probe_stb_q <= 1'b0;
            read_probe_state_q <= wb_ack ? READ_PROBE_DONE : READ_PROBE_WAIT_WRITE_ACK;
          end
          if (wb_err) begin
            read_probe_err_seen_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_ERROR;
          end
          if (wb_ack) begin
            read_probe_write_ack_seen_q <= 1'b1;
            read_probe_done_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
          end
        end

        READ_PROBE_WAIT_WRITE_ACK: begin
          read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          if (wb_err) begin
            read_probe_err_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_state_q <= READ_PROBE_ERROR;
          end else if (wb_ack) begin
            read_probe_write_ack_seen_q <= 1'b1;
            read_probe_done_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_stb_q <= 1'b0;
            read_probe_we_q <= 1'b0;
            read_probe_state_q <= READ_PROBE_DONE;
          end
        end

        READ_PROBE_ISSUE_READ: begin
          read_probe_we_q <= 1'b0;
          read_probe_stb_q <= 1'b1;
          if (wb_stall) begin
            read_probe_stall_seen_q <= 1'b1;
            read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          end else begin
            read_probe_stb_q <= 1'b0;
            read_probe_state_q <= wb_ack ? READ_PROBE_DONE : READ_PROBE_WAIT_READ_ACK;
          end
          if (wb_err) begin
            read_probe_err_seen_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_ERROR;
          end
          if (wb_ack) begin
            read_probe_read_ack_seen_q <= 1'b1;
            read_probe_done_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_data_lo_q <= wb_data[31:0];
            read_probe_data_hi_q <= wb_data[63:32];
            read_probe_mismatch_q <= (wb_data != PROBE_WRITE_PATTERN);
          end
        end

        READ_PROBE_WAIT_READ_ACK: begin
          read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          if (wb_err) begin
            read_probe_err_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_state_q <= READ_PROBE_ERROR;
          end else if (wb_ack) begin
            read_probe_read_ack_seen_q <= 1'b1;
            read_probe_done_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_data_lo_q <= wb_data[31:0];
            read_probe_data_hi_q <= wb_data[63:32];
            read_probe_mismatch_q <= (wb_data != PROBE_WRITE_PATTERN);
            read_probe_state_q <= READ_PROBE_DONE;
          end
        end

        READ_PROBE_DONE: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_done_q <= 1'b1;
        end

        READ_PROBE_ERROR: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_done_q <= 1'b1;
        end

        default: read_probe_state_q <= READ_PROBE_ERROR;
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
    jtag_debug_payload[240 +: 32] = read_probe_data_lo_q;
    jtag_debug_payload[272 +: 32] = read_probe_data_hi_q;
    jtag_debug_payload[304 +: 32] = {
      21'd0,
      read_probe_mismatch_q,
      read_probe_stall_seen_q,
      read_probe_err_seen_q,
      read_probe_read_ack_seen_q,
      read_probe_write_ack_seen_q,
      read_probe_done_q,
      read_probe_cyc_q,
      read_probe_stb_q,
      read_probe_state_q
    };
    jtag_debug_payload[336 +: 32] =
      {16'd0, BYTE_LANES_NIBBLE, BA_BITS_NIBBLE, COL_BITS_NIBBLE, ROW_BITS_NIBBLE};
    jtag_debug_payload[368 +: 32] =
      {16'd0, 4'd1, 4'd0, WB_SEL_BITS_NIBBLE, WB_ADDR_BITS_NIBBLE};
    jtag_debug_payload[400 +: 32] = read_probe_wait_cycles_q;
    jtag_debug_payload[432 +: 32] = clk50_count_q;
    jtag_debug_payload[464] = SYS_RSTN;
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
    .i_wb_cyc(read_probe_cyc_q),
    .i_wb_stb(read_probe_stb_q),
    .i_wb_we(read_probe_we_q),
    .i_wb_addr('0),
    .i_wb_data(PROBE_WRITE_PATTERN),
    .i_wb_sel({WB_SEL_BITS{1'b1}}),
    .i_aux(4'd1),
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
