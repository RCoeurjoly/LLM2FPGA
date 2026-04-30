module task6_ypcb_litedram_init_bandwidth_probe_top #(
  parameter int JTAG_DEBUG_WIDTH = 512,
  parameter int READ_COUNT_LOG2 = 16,
  parameter int TIMEOUT_LOG2 = 28
) (
  input  wire          clk200_p,
  input  wire          clk200_n,
  input  wire          SYS_RSTN,
  output wire   [14:0] ddram_a,
  output wire    [2:0] ddram_ba,
  output wire          ddram_cas_n,
  output wire          ddram_cke,
  output wire          ddram_clk_n,
  output wire          ddram_clk_p,
  output wire          ddram_cs_n,
  inout  wire   [63:0] ddram_dq,
  inout  wire    [7:0] ddram_dqs_n,
  inout  wire    [7:0] ddram_dqs_p,
  output wire          ddram_odt,
  output wire          ddram_ras_n,
  output wire          ddram_reset_n,
  output wire          ddram_we_n
);
  localparam logic [31:0] JTAG_DEBUG_MAGIC = 32'h54364a44;
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd20;
  localparam logic [31:0] READ_COUNT_WORDS = 32'd1 << READ_COUNT_LOG2;

  typedef enum logic [2:0] {
    PROBE_RESET = 3'd0,
    PROBE_WAIT_INIT = 3'd1,
    PROBE_RUN_READS = 3'd2,
    PROBE_DONE = 3'd3,
    PROBE_ERROR = 3'd4,
    PROBE_TIMEOUT = 3'd5
  } probe_state_t;

  wire clk200;
  wire pll_locked;
  wire init_done;
  wire init_error;
  wire user_clk;
  wire user_rst;
  wire core_rst;

  logic [7:0] config_reset_count_q = 8'd0;
  logic config_reset_done;

  always_ff @(posedge clk200 or negedge SYS_RSTN) begin
    if (!SYS_RSTN)
      config_reset_count_q <= 8'd0;
    else if (!config_reset_done)
      config_reset_count_q <= config_reset_count_q + 8'd1;
  end

  assign config_reset_done = config_reset_count_q[7];
  assign core_rst = !SYS_RSTN || !config_reset_done;

  IBUFDS #(
    .DIFF_TERM("TRUE"),
    .IBUF_LOW_PWR("FALSE")
  ) clk200_ibuf (
    .I(clk200_p),
    .IB(clk200_n),
    .O(clk200)
  );

  logic [27:0] read_addr_q = 28'd0;
  logic [31:0] command_count_q = 32'd0;
  logic [31:0] response_count_q = 32'd0;
  logic [31:0] read_cycle_count_q = 32'd0;
  logic [31:0] command_stall_count_q = 32'd0;
  logic [31:0] checksum_q = 32'd0;
  logic [63:0] last_rdata_q = 64'd0;
  probe_state_t state_q = PROBE_RESET;

  wire cmd_ready;
  wire cmd_valid;
  wire rdata_valid;
  wire [63:0] rdata;
  wire outstanding_full;
  wire read_target_issued;
  wire read_target_seen;
  wire timeout_seen;

  assign read_target_issued = command_count_q >= READ_COUNT_WORDS;
  assign read_target_seen = response_count_q >= READ_COUNT_WORDS;
  assign outstanding_full =
    (command_count_q - response_count_q) >= 32'd64;
  assign timeout_seen = read_cycle_count_q[TIMEOUT_LOG2 - 1];
  assign cmd_valid =
    state_q == PROBE_RUN_READS && !read_target_issued && !outstanding_full;

  always_ff @(posedge user_clk) begin
    if (user_rst || core_rst) begin
      read_addr_q <= 28'd0;
      command_count_q <= 32'd0;
      response_count_q <= 32'd0;
      read_cycle_count_q <= 32'd0;
      command_stall_count_q <= 32'd0;
      checksum_q <= 32'd0;
      last_rdata_q <= 64'd0;
      state_q <= PROBE_RESET;
    end else begin
      unique case (state_q)
        PROBE_RESET: begin
          if (init_error)
            state_q <= PROBE_ERROR;
          else if (init_done)
            state_q <= PROBE_RUN_READS;
          else
            state_q <= PROBE_WAIT_INIT;
        end
        PROBE_WAIT_INIT: begin
          if (init_error)
            state_q <= PROBE_ERROR;
          else if (init_done)
            state_q <= PROBE_RUN_READS;
        end
        PROBE_RUN_READS: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
          else if (read_target_seen)
            state_q <= PROBE_DONE;
        end
        default: begin
          state_q <= state_q;
        end
      endcase

      if (state_q == PROBE_RUN_READS) begin
        if (cmd_valid && cmd_ready) begin
          command_count_q <= command_count_q + 32'd1;
          read_addr_q <= read_addr_q + 28'd1;
        end else if (cmd_valid && !cmd_ready) begin
          command_stall_count_q <= command_stall_count_q + 32'd1;
        end

        if (rdata_valid) begin
          response_count_q <= response_count_q + 32'd1;
          last_rdata_q <= rdata;
          checksum_q <= checksum_q ^ rdata[31:0] ^ rdata[63:32];
        end
      end
    end
  end

  logic [JTAG_DEBUG_WIDTH - 1:0] jtag_debug_payload;
  wire [15:0] status_bits;

  assign status_bits = {
    5'd0,
    timeout_seen,
    read_target_seen,
    read_target_issued,
    outstanding_full,
    rdata_valid,
    cmd_ready,
    user_rst,
    pll_locked,
    init_error,
    init_done,
    SYS_RSTN
  };

  always_comb begin
    jtag_debug_payload = '0;
    jtag_debug_payload[0 +: 32] = JTAG_DEBUG_MAGIC;
    jtag_debug_payload[32 +: 8] = JTAG_DEBUG_VERSION;
    jtag_debug_payload[40 +: 8] = {5'd0, state_q};
    jtag_debug_payload[48 +: 16] = status_bits;
    jtag_debug_payload[64 +: 32] = read_cycle_count_q;
    jtag_debug_payload[96 +: 32] = command_count_q;
    jtag_debug_payload[128 +: 32] = response_count_q;
    jtag_debug_payload[160 +: 32] = command_stall_count_q;
    jtag_debug_payload[192 +: 32] = checksum_q;
    jtag_debug_payload[224 +: 64] = last_rdata_q;
    jtag_debug_payload[288 +: 28] = read_addr_q;
    jtag_debug_payload[320 +: 32] = READ_COUNT_WORDS;
  end

  ypcb_litedram_core core (
    .clk(clk200),
    .rst(core_rst),
    .ddram_a(ddram_a),
    .ddram_ba(ddram_ba),
    .ddram_cas_n(ddram_cas_n),
    .ddram_cke(ddram_cke),
    .ddram_clk_n(ddram_clk_n),
    .ddram_clk_p(ddram_clk_p),
    .ddram_cs_n(ddram_cs_n),
    .ddram_dq(ddram_dq),
    .ddram_dqs_n(ddram_dqs_n),
    .ddram_dqs_p(ddram_dqs_p),
    .ddram_odt(ddram_odt),
    .ddram_ras_n(ddram_ras_n),
    .ddram_reset_n(ddram_reset_n),
    .ddram_we_n(ddram_we_n),
    .init_done(init_done),
    .init_error(init_error),
    .pll_locked(pll_locked),
    .user_clk(user_clk),
    .user_rst(user_rst),
    .user_port_native_0_cmd_addr(read_addr_q),
    .user_port_native_0_cmd_ready(cmd_ready),
    .user_port_native_0_cmd_valid(cmd_valid),
    .user_port_native_0_cmd_we(1'b0),
    .user_port_native_0_rdata_data(rdata),
    .user_port_native_0_rdata_ready(1'b1),
    .user_port_native_0_rdata_valid(rdata_valid),
    .user_port_native_0_wdata_data(64'd0),
    .user_port_native_0_wdata_ready(),
    .user_port_native_0_wdata_valid(1'b0),
    .user_port_native_0_wdata_we(8'd0),
    .user_port_axi_0_araddr(31'd0),
    .user_port_axi_0_arburst(2'd0),
    .user_port_axi_0_arid(4'd0),
    .user_port_axi_0_arlen(8'd0),
    .user_port_axi_0_arready(),
    .user_port_axi_0_arsize(3'd0),
    .user_port_axi_0_arvalid(1'b0),
    .user_port_axi_0_awaddr(31'd0),
    .user_port_axi_0_awburst(2'd0),
    .user_port_axi_0_awid(4'd0),
    .user_port_axi_0_awlen(8'd0),
    .user_port_axi_0_awready(),
    .user_port_axi_0_awsize(3'd0),
    .user_port_axi_0_awvalid(1'b0),
    .user_port_axi_0_bid(),
    .user_port_axi_0_bready(1'b1),
    .user_port_axi_0_bresp(),
    .user_port_axi_0_bvalid(),
    .user_port_axi_0_rdata(),
    .user_port_axi_0_rid(),
    .user_port_axi_0_rlast(),
    .user_port_axi_0_rready(1'b1),
    .user_port_axi_0_rresp(),
    .user_port_axi_0_rvalid(),
    .user_port_axi_0_wdata(64'd0),
    .user_port_axi_0_wlast(1'b0),
    .user_port_axi_0_wready(),
    .user_port_axi_0_wstrb(8'd0),
    .user_port_axi_0_wvalid(1'b0),
    .wb_ctrl_ack(),
    .wb_ctrl_adr(30'd0),
    .wb_ctrl_bte(2'd0),
    .wb_ctrl_cti(3'd0),
    .wb_ctrl_cyc(1'b0),
    .wb_ctrl_dat_r(),
    .wb_ctrl_dat_w(32'd0),
    .wb_ctrl_err(),
    .wb_ctrl_sel(4'd0),
    .wb_ctrl_stb(1'b0),
    .wb_ctrl_we(1'b0)
  );

  task6_litedram_probe_jtag_debug_shift #(
    .WIDTH(JTAG_DEBUG_WIDTH),
    .JTAG_CHAIN(1)
  ) jtag_debug_shift (
    .payload_i(jtag_debug_payload)
  );
endmodule

module task6_litedram_probe_jtag_debug_shift #(
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
