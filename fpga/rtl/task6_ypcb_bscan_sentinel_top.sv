module task6_ypcb_bscan_sentinel_top #(
  parameter int JTAG_DEBUG_WIDTH = 1024,
  parameter int JTAG_CHAIN = 1
) (
  input wire SYS_RSTN
);
  localparam logic [31:0] JTAG_DEBUG_MAGIC = 32'h54364a44;
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd1;

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
  logic [JTAG_DEBUG_WIDTH - 1:0] shift_q;
  logic [31:0] tck_count_q = 32'd0;
  logic [31:0] capture_count_q = 32'd0;
  logic [31:0] update_count_q = 32'd0;
  logic [JTAG_DEBUG_WIDTH - 1:0] payload;

  assign tdo = shift_q[0];

  always_ff @(posedge tck) begin
    tck_count_q <= tck_count_q + 32'd1;
    if (sel && capture)
      capture_count_q <= capture_count_q + 32'd1;
    if (sel && update)
      update_count_q <= update_count_q + 32'd1;
  end

  always_comb begin
    payload = '0;
    payload[0 +: 32] = JTAG_DEBUG_MAGIC;
    payload[32 +: 8] = JTAG_DEBUG_VERSION;
    payload[40 +: 8] = {7'd0, SYS_RSTN};
    payload[64 +: 32] = tck_count_q;
    payload[96 +: 32] = capture_count_q;
    payload[128 +: 32] = update_count_q;
    payload[160 +: 32] = 32'h11111111;
    payload[192 +: 32] = 32'h22222222;
    payload[224 +: 32] = 32'h33333333;
    payload[256 +: 32] = 32'h44444444;
    payload[288 +: 32] = 32'h55555555;
    payload[320 +: 32] = 32'ha5a55a5a;
    payload[352 +: 32] = 32'h5a5aa5a5;
    payload[384 +: 32] = 32'hdeadbeef;
  end

  always_ff @(posedge drck or posedge reset) begin
    if (reset)
      shift_q <= '0;
    else if (sel && capture)
      shift_q <= payload;
    else if (sel && shift)
      shift_q <= {tdi, shift_q[JTAG_DEBUG_WIDTH - 1:1]};
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
  wire unused_tms = tms;
endmodule
