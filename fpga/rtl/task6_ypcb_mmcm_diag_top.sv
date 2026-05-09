`default_nettype none

module task6_ypcb_mmcm_diag_top #(
  parameter int JTAG_DEBUG_WIDTH = 512,
  parameter int JTAG_CHAIN = 1
) (
  input wire clk50,
  input wire SYS_RSTN
);
  localparam logic [31:0] MAGIC = 32'h54364d4d;
  localparam logic [7:0] VERSION = 8'd1;

  wire mmcm_a_fb;
  wire mmcm_a_locked;
  wire mmcm_a_clk100_raw;
  wire mmcm_a_clk25_raw;
  wire mmcm_a_clk25;

  wire mmcm_b_fb;
  wire mmcm_b_locked;
  wire mmcm_b_clk50_raw;
  wire mmcm_b_clk25_raw;
  wire mmcm_b_clk25;

  wire pll_fb;
  wire pll_locked;
  wire pll_clk100_raw;
  wire pll_clk25_raw;
  wire pll_clk25;

  logic [31:0] raw_count_q;
  logic [31:0] mmcm_a_count_q;
  logic [31:0] mmcm_b_count_q;
  logic [31:0] pll_count_q;
  logic [JTAG_DEBUG_WIDTH - 1:0] payload;

  always_ff @(posedge clk50) begin
    raw_count_q <= raw_count_q + 32'd1;
  end

  always_ff @(posedge mmcm_a_clk25) begin
    mmcm_a_count_q <= mmcm_a_count_q + 32'd1;
  end

  always_ff @(posedge mmcm_b_clk25) begin
    mmcm_b_count_q <= mmcm_b_count_q + 32'd1;
  end

  always_ff @(posedge pll_clk25) begin
    pll_count_q <= pll_count_q + 32'd1;
  end

  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT_F(20.000),
    .CLKIN1_PERIOD(20.000),
    .CLKOUT0_DIVIDE_F(10.000),
    .CLKOUT0_PHASE(0.000),
    .CLKOUT1_DIVIDE(40),
    .CLKOUT1_PHASE(0.000),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010)
  ) mmcm_a (
    .CLKFBOUT(mmcm_a_fb),
    .CLKFBOUTB(),
    .CLKOUT0(mmcm_a_clk100_raw),
    .CLKOUT0B(),
    .CLKOUT1(mmcm_a_clk25_raw),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .LOCKED(mmcm_a_locked),
    .CLKFBIN(mmcm_a_fb),
    .CLKIN1(clk50),
    .PWRDWN(1'b0),
    .RST(1'b0)
  );

  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT_F(12.000),
    .CLKIN1_PERIOD(20.000),
    .CLKOUT0_DIVIDE_F(12.000),
    .CLKOUT0_PHASE(0.000),
    .CLKOUT1_DIVIDE(24),
    .CLKOUT1_PHASE(0.000),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010)
  ) mmcm_b (
    .CLKFBOUT(mmcm_b_fb),
    .CLKFBOUTB(),
    .CLKOUT0(mmcm_b_clk50_raw),
    .CLKOUT0B(),
    .CLKOUT1(mmcm_b_clk25_raw),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .LOCKED(mmcm_b_locked),
    .CLKFBIN(mmcm_b_fb),
    .CLKIN1(clk50),
    .PWRDWN(1'b0),
    .RST(1'b0)
  );

  PLLE2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT(20),
    .CLKFBOUT_PHASE(0.000),
    .CLKIN1_PERIOD(20.000),
    .CLKOUT0_DIVIDE(10),
    .CLKOUT0_DUTY_CYCLE(0.500),
    .CLKOUT0_PHASE(0.000),
    .CLKOUT1_DIVIDE(40),
    .CLKOUT1_DUTY_CYCLE(0.500),
    .CLKOUT1_PHASE(0.000),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010),
    .STARTUP_WAIT("FALSE")
  ) pll_a (
    .CLKFBOUT(pll_fb),
    .CLKOUT0(pll_clk100_raw),
    .CLKOUT1(pll_clk25_raw),
    .CLKOUT2(),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .LOCKED(pll_locked),
    .CLKFBIN(pll_fb),
    .CLKIN1(clk50),
    .PWRDWN(1'b0),
    .RST(1'b0)
  );

  BUFG mmcm_a_clk25_bufg (
    .I(mmcm_a_clk25_raw),
    .O(mmcm_a_clk25)
  );

  BUFG mmcm_b_clk25_bufg (
    .I(mmcm_b_clk25_raw),
    .O(mmcm_b_clk25)
  );

  BUFG pll_clk25_bufg (
    .I(pll_clk25_raw),
    .O(pll_clk25)
  );

  always_comb begin
    payload = '0;
    payload[0 +: 32] = MAGIC;
    payload[32 +: 8] = VERSION;
    payload[40 +: 8] = {4'd0, pll_locked, mmcm_b_locked, mmcm_a_locked, SYS_RSTN};
    payload[48 +: 32] = raw_count_q;
    payload[80 +: 32] = mmcm_a_count_q;
    payload[112 +: 32] = mmcm_b_count_q;
    payload[144 +: 32] = pll_count_q;
  end

  task6_mmcm_diag_jtag_shift #(
    .WIDTH(JTAG_DEBUG_WIDTH),
    .JTAG_CHAIN(JTAG_CHAIN)
  ) jtag_debug_shift (
    .payload_i(payload)
  );
endmodule

module task6_mmcm_diag_jtag_shift #(
  parameter int WIDTH = 512,
  parameter int JTAG_CHAIN = 1
) (
  input logic [WIDTH - 1:0] payload_i
);
  logic capture;
  logic drck;
  logic reset;
  logic sel;
  logic shift;
  logic tdi;
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
    .RUNTEST(),
    .SEL(sel),
    .SHIFT(shift),
    .TCK(),
    .TDI(tdi),
    .TMS(),
    .UPDATE(),
    .TDO(tdo)
  );
endmodule

`default_nettype wire
