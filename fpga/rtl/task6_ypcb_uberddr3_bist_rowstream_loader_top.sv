`default_nettype none

module task6_ypcb_uberddr3_bist_rowstream_loader_top #(
  parameter int JTAG_DEBUG_WIDTH = 512,
  parameter int JTAG_CHAIN = 1,
  parameter int JTAG_COMMAND_CHAIN = 2,
  parameter int PROBE_BYTE = 165,
  parameter int BYTE_LANES = 8,
  parameter int DISABLE_JTAG_DEBUG_SHIFT = (BYTE_LANES == 1),
  parameter int BOOT_ISOLATE_UNTIL_CALIB = 0,
  parameter int PLL_CLKOUT0_DIVIDE = 3,
  parameter int PLL_CLKOUT1_DIVIDE = 3,
  parameter int PLL_CLKOUT2_DIVIDE = 12,
  parameter int CONTROLLER_CLK_PERIOD_PS = 12_000,
  parameter int DDR3_CLK_PERIOD_PS = 3_000,
  parameter bit DLL_OFF_PARAM = 1'b1,
  parameter int SPEED_BIN_PARAM = 0,
  parameter int SDRAM_CAPACITY_PARAM = 5,
  parameter bit BIST_TEST_DATAMASK = 1'b1
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
`ifdef TASK6_PCIE_ROWSTREAM_INGRESS_PORTS
  , input  wire [JTAG_COMMAND_WIDTH - 1:0] pcie_command_payload_i
  , input  wire                             pcie_command_event_i
  , input  wire                             pcie_status_clear_i
  , output wire                             pcie_controller_clk_o
  , output wire                             pcie_controller_rst_n_o
  , output wire                             pcie_boot_done_o
  , output wire                             pcie_loader_done_o
  , output wire                             pcie_loader_error_o
  , output wire                             pcie_loader_last_accepted_o
  , output wire                             pcie_loader_last_magic_ok_o
  , output wire [7:0]                       pcie_loader_last_opcode_o
  , output wire [1:0]                       pcie_loader_last_chunk_o
  , output wire [31:0]                      pcie_loader_command_payload_addr_o
  , output wire [31:0]                      pcie_loader_wait_cycles_o
  , output wire [511:0]                     pcie_loader_read_data_o
`endif
);
  localparam logic [31:0] JTAG_DEBUG_MAGIC = 32'h54364a44;
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd63;
  localparam int JTAG_COMMAND_WIDTH = 208;
  localparam logic [31:0] LOADER_COMMAND_MAGIC = 32'h33445244;
  localparam logic [7:0] LOADER_OP_WRITE_CHUNK = 8'h01;
  localparam logic [7:0] LOADER_OP_READ_BEAT = 8'h02;
  localparam logic [7:0] LOADER_OP_WRITE_LOWBYTE = 8'h03;
  localparam logic [7:0] LOADER_OP_READ_LOWBYTE = 8'h04;
  localparam logic [7:0] LOADER_OP_WRITE_DENSE_BYTE = 8'h05;
  localparam logic [7:0] LOADER_OP_READ_DENSE_BEAT = 8'h06;
  localparam logic [7:0] LOADER_OP_RUN_AUTOPROBE = 8'h07;
  localparam logic [7:0] LOADER_OP_WRITE_DENSE_FILL = 8'h08;
  localparam logic [7:0] LOADER_OP_RUN_FULLBEAT = 8'h09;
  localparam logic [7:0] LOADER_OP_RUN_HARDCODED_AUTOPROBE = 8'h0a;
  localparam logic [7:0] LOADER_OP_RUN_HARDCODED_SINGLEBYTE = 8'h0b;
  localparam logic [7:0] LOADER_OP_ECHO_CHUNK = 8'h0c;
  localparam logic [7:0] LOADER_OP_RUN_HOST_FULLBEAT = 8'h0d;
  localparam logic [7:0] LOADER_OP_RUN_RTL_BURST = 8'h0e;
  localparam logic [7:0] LOADER_OP_LOAD_PACKET_BEAT = 8'h0f;
  localparam logic [7:0] LOADER_OP_RUN_HOST_PACKET = 8'h10;
  localparam int ROW_BITS = 15;
  localparam int COL_BITS = 10;
  localparam int BA_BITS = 3;
  localparam int WB_ADDR_BITS = ROW_BITS + COL_BITS + BA_BITS - 3;
  localparam int WB_DATA_BITS = 8 * BYTE_LANES * 8;
  localparam int WB_SEL_BITS = WB_DATA_BITS / 8;
  localparam logic [3:0] ROW_BITS_NIBBLE = ROW_BITS % 16;
  localparam logic [3:0] COL_BITS_NIBBLE = COL_BITS % 16;
  localparam logic [3:0] BA_BITS_NIBBLE = BA_BITS % 16;
  localparam logic [3:0] BYTE_LANES_NIBBLE = BYTE_LANES % 16;
  localparam logic [3:0] WB_ADDR_BITS_NIBBLE = WB_ADDR_BITS % 16;
  localparam logic [3:0] WB_SEL_BITS_NIBBLE = WB_SEL_BITS % 16;
  localparam logic [7:0] PROBE_BYTE_VALUE = PROBE_BYTE[7:0];
  localparam logic [15:0] LOADER_HOST_FULLBEAT_COMMAND_COOLDOWN = 16'h3fff;

  function automatic logic [7:0] hardcoded_probe_value(
    input logic [1:0] selector
  );
    begin
      case (selector)
        2'd0: hardcoded_probe_value = 8'h00;
        2'd1: hardcoded_probe_value = 8'hff;
        2'd2: hardcoded_probe_value = 8'ha5;
        default: hardcoded_probe_value = 8'h5a;
      endcase
    end
  endfunction

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
    .CLKOUT0_DIVIDE(PLL_CLKOUT0_DIVIDE),
    .CLKOUT0_DUTY_CYCLE(0.500),
    .CLKOUT0_PHASE(0.000),
    .CLKOUT1_DIVIDE(PLL_CLKOUT1_DIVIDE),
    .CLKOUT1_DUTY_CYCLE(0.500),
    .CLKOUT1_PHASE(90.000),
    .CLKOUT2_DIVIDE(PLL_CLKOUT2_DIVIDE),
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
    READ_PROBE_RESET = 3'd0,
    READ_PROBE_WAIT_CALIB = 3'd1,
    READ_PROBE_ISSUE_WRITE = 3'd2,
    READ_PROBE_WAIT_WRITE_ACK = 3'd3,
    READ_PROBE_WAIT_WRITE_DRAIN = 3'd4,
    READ_PROBE_NEXT_WRITE = 3'd5,
    READ_PROBE_ISSUE_READ = 3'd6,
    READ_PROBE_WAIT_READ_ACK = 3'd7,
    READ_PROBE_NEXT_READ = 4'd8,
    READ_PROBE_DONE = 4'd9,
    LOADER_ISSUE = 4'd10,
    LOADER_WAIT_ACK = 4'd11,
    LOADER_ERROR = 4'd12,
    LOADER_WRITE_DRAIN = 4'd13,
    LOADER_COMMAND_COOLDOWN = 4'd14,
    LOADER_BURST_NEXT = 4'd15
  } read_probe_state_t;

  typedef enum logic [1:0] {
    FULLBEAT_PHASE_NONE = 2'd0,
    FULLBEAT_PHASE_WRITE = 2'd1,
    FULLBEAT_PHASE_READ = 2'd2
  } fullbeat_phase_t;

  read_probe_state_t read_probe_state_q;
  logic read_probe_cyc_q;
  logic read_probe_stb_q;
  logic read_probe_we_q;
  logic read_probe_done_q;
  logic read_probe_write_ack_seen_q;
  logic read_probe_read_ack_seen_q;
  logic read_probe_err_seen_q;
  logic read_probe_stall_seen_q;
  logic [WB_DATA_BITS - 1:0] read_probe_data_q;
  logic [7:0] read_probe_expected_byte_q;
  logic [9:0] read_probe_write_drain_q;
  logic [31:0] read_probe_wait_cycles_q;
  logic [1:0] read_probe_write_index_q;
  logic [2:0] read_probe_read_index_q;
  logic [5:0] read_probe_stream_base_q;
  logic [31:0] read_probe_stream_bytes_q;
  logic [3:0] read_probe_stream_valid_q;
  logic [3:0] read_probe_stream_mismatch_q;
  logic [WB_ADDR_BITS - 1:0] read_probe_addr;
  logic [5:0] read_probe_write_addr;
  logic [5:0] read_probe_read_addr;
  logic [7:0] read_probe_write_byte;
  logic [1:0] read_probe_capture_index;
  logic [7:0] read_probe_capture_byte;
  logic [JTAG_COMMAND_WIDTH - 1:0] jtag_command_payload_from_shift;
  logic jtag_command_event_from_shift;
  logic [15:0] jtag_command_count;
`ifdef TASK6_PCIE_ROWSTREAM_INGRESS_PORTS
  wire [JTAG_COMMAND_WIDTH - 1:0] jtag_command_payload =
    pcie_command_event_i ? pcie_command_payload_i : jtag_command_payload_from_shift;
  wire jtag_command_event = pcie_command_event_i | jtag_command_event_from_shift;
  logic pcie_loader_done_sticky_q;
  logic pcie_loader_error_sticky_q;
  logic pcie_loader_last_accepted_sticky_q;
  logic pcie_loader_last_magic_ok_sticky_q;
`else
  wire [JTAG_COMMAND_WIDTH - 1:0] jtag_command_payload = jtag_command_payload_from_shift;
  wire jtag_command_event = jtag_command_event_from_shift;
`endif
  logic [15:0] read_probe_run_count_q;
  logic [WB_ADDR_BITS - 1:0] loader_addr_q;
  logic [WB_DATA_BITS - 1:0] loader_write_data_q;
  logic [WB_DATA_BITS - 1:0] loader_read_data_q;
  logic [WB_SEL_BITS - 1:0] loader_sel_q;
  logic loader_done_q;
  logic loader_error_q;
  logic loader_write_ack_seen_q;
  logic loader_read_ack_seen_q;
  logic loader_stall_seen_q;
  logic [31:0] loader_wait_cycles_q;
  logic [31:0] loader_command_payload_addr_q;
  logic [7:0] loader_last_opcode_q;
  logic [1:0] loader_last_chunk_q;
  logic [1:0] loader_read_chunk_q;
  logic loader_last_magic_ok_q;
  logic loader_last_accepted_q;
  logic loader_dense_write_seen_q;
  logic [15:0] loader_dense_write_addr_q;
  logic [5:0] loader_dense_write_lane_q;
  logic [7:0] loader_dense_write_data_q;
  logic [15:0] loader_dense_write_sel_low_q;
  logic [7:0] loader_lowbyte_write_data_q;
  logic [7:0] loader_lowbyte_read_data_q;
  logic [7:0] loader_lowbyte_addr_q;
  logic loader_lowbyte_read_seen_q;
  logic loader_lowbyte_write_seen_q;
  logic loader_fullbeat_read_after_write_q;
  logic loader_fullbeat_compare_active_q;
  logic loader_fullbeat_done_q;
  logic [15:0] loader_command_cooldown_q;
  logic loader_burst_active_q;
  logic loader_burst_read_phase_q;
  logic [7:0] loader_burst_count_q;
  logic [7:0] loader_burst_index_q;
  logic [7:0] loader_burst_mismatch_count_q;
  logic [7:0] loader_burst_first_mismatch_q;
  logic [WB_ADDR_BITS - 1:0] loader_burst_base_addr_q;
  logic loader_burst_packet_mode_q;
  logic [WB_DATA_BITS - 1:0] loader_packet_data_q [0:3];
  logic loader_packet_write_ack_seen_q;
  logic loader_packet_read_ack_seen_q;
  logic [7:0] loader_packet_write_ack_index_q;
  logic [WB_ADDR_BITS - 1:0] loader_packet_write_ack_addr_q;
  logic [WB_DATA_BITS - 1:0] loader_packet_write_ack_data_q;
  logic [WB_SEL_BITS - 1:0] loader_packet_write_ack_sel_q;
  logic [WB_ADDR_BITS - 1:0] loader_packet_read_ack_addr_q;
  logic [WB_DATA_BITS - 1:0] loader_packet_read_ack_data_q;
  logic [6:0] loader_fullbeat_mismatch_count_q;
  logic [WB_ADDR_BITS - 1:0] loader_fullbeat_addr_q;
  logic [7:0] loader_fullbeat_expected_base_q;
  logic [31:0] loader_fullbeat_write_echo_q;
  logic [3:0] loader_debug_state;
  logic [31:0] loader_fullbeat_issue_cycle_q;
  logic [3:0] loader_fullbeat_last_write_ack_delta_q;
  logic [3:0] loader_fullbeat_last_read_ack_delta_q;
  logic [31:0] loader_standalone_read_issue_cycle_q;
  logic [3:0] loader_standalone_read_ack_delta_q;
  logic [WB_ADDR_BITS - 1:0] loader_standalone_read_request_addr_q;
  logic [WB_ADDR_BITS - 1:0] loader_standalone_read_ack_addr_q;
  logic [7:0] loader_standalone_read_ack_opcode_q;
  fullbeat_phase_t loader_fullbeat_issue_phase_q;
  logic [127:0] loader_fullbeat_last_issue_data_q;
  logic [$clog2(WB_SEL_BITS) - 1:0] loader_lowbyte_index_q;
  logic read_probe_single_q;
  logic read_probe_is_loader_beat;
  logic [WB_ADDR_BITS - 1:0] wb_addr_to_controller;
  logic [WB_DATA_BITS - 1:0] wb_data_to_controller;
  logic [WB_SEL_BITS - 1:0] wb_sel_to_controller;

  wire [31:0] jtag_command_magic = jtag_command_payload[0 +: 32];
  wire [7:0] jtag_command_opcode = jtag_command_payload[32 +: 8];
  wire [1:0] jtag_command_chunk = jtag_command_payload[40 +: 2];
  wire [31:0] jtag_command_addr = jtag_command_payload[48 +: 32];
  wire [7:0] jtag_command_data_byte = jtag_command_payload[80 +: 8];
  wire [2:0] jtag_command_packet_count = jtag_command_addr[31:29];
  wire [WB_ADDR_BITS - 1:0] jtag_command_addr_low16 =
    {{(WB_ADDR_BITS - 16){1'b0}}, jtag_command_addr[15:0]};
  wire [WB_ADDR_BITS - 1:0] jtag_command_addr_full =
    jtag_command_addr[WB_ADDR_BITS - 1:0];
  wire jtag_command_magic_ok = jtag_command_magic == LOADER_COMMAND_MAGIC;
  wire [WB_ADDR_BITS - 1:0] jtag_command_lowbyte_addr =
    jtag_command_addr[WB_ADDR_BITS + $clog2(WB_SEL_BITS) - 1:$clog2(WB_SEL_BITS)];
  wire [$clog2(WB_SEL_BITS) - 1:0] jtag_command_lowbyte_index =
    jtag_command_addr[$clog2(WB_SEL_BITS) - 1:0];
  wire [WB_SEL_BITS - 1:0] jtag_command_lowbyte_sel =
    {{(WB_SEL_BITS - 1){1'b0}}, 1'b1} << jtag_command_lowbyte_index;
  wire [WB_ADDR_BITS - 1:0] jtag_command_dense_addr =
    {{(WB_ADDR_BITS - 10){1'b0}}, jtag_command_addr[15:6]};
  wire [WB_SEL_BITS - 1:0] jtag_command_dense_sel =
    {{(WB_SEL_BITS - 1){1'b0}}, 1'b1} << jtag_command_addr[5:0];
  logic [WB_DATA_BITS - 1:0] jtag_command_dense_data;
  logic [WB_DATA_BITS - 1:0] jtag_command_lowbyte_data;
  logic [WB_DATA_BITS - 1:0] jtag_command_fullbeat_data;
  logic [WB_DATA_BITS - 1:0] jtag_command_chunk_data;
  logic [WB_DATA_BITS - 1:0] loader_fullbeat_expected_data;
  logic [6:0] loader_fullbeat_mismatch_count;

  function automatic logic [WB_DATA_BITS - 1:0] generated_burst_fullbeat(
    input logic [7:0] beat_index
  );
    logic [WB_DATA_BITS - 1:0] value;
    begin
      value = '0;
      for (int lane = 0; lane < WB_SEL_BITS; lane = lane + 1)
        value[lane * 8 +: 8] = 8'h40 + beat_index + lane[7:0];
      generated_burst_fullbeat = value;
    end
  endfunction

  function automatic [3:0] clamp_delta4(
    input logic [31:0] issue_cycle,
    input logic [31:0] ack_cycle
  );
    logic [31:0] delta;
    begin
      delta = ack_cycle - issue_cycle;
      clamp_delta4 = delta > 32'd15 ? 4'hf : delta[3:0];
    end
  endfunction

  always_comb begin
    jtag_command_dense_data = '0;
    jtag_command_dense_data[jtag_command_addr[5:0] * 8 +: 8] =
      jtag_command_data_byte;
  end

  always_comb begin
    jtag_command_lowbyte_data = '0;
    jtag_command_lowbyte_data[jtag_command_lowbyte_index * 8 +: 8] =
      jtag_command_data_byte;
  end

  always_comb begin
    jtag_command_chunk_data = jtag_command_payload[80 +: WB_DATA_BITS];
  end

  always_comb begin
    jtag_command_fullbeat_data = '0;
    for (int lane = 0; lane < WB_SEL_BITS; lane = lane + 1)
      jtag_command_fullbeat_data[lane * 8 +: 8] = jtag_command_data_byte + lane[7:0];
  end

  always_comb begin
    if (loader_burst_active_q && loader_burst_packet_mode_q) begin
      loader_fullbeat_expected_data = loader_write_data_q;
    end else if (loader_burst_active_q) begin
      loader_fullbeat_expected_data = generated_burst_fullbeat(loader_burst_index_q);
    end else begin
      loader_fullbeat_expected_data = '0;
      for (int lane = 0; lane < WB_SEL_BITS; lane = lane + 1)
        loader_fullbeat_expected_data[lane * 8 +: 8] =
          loader_fullbeat_expected_base_q + lane[7:0];
    end
  end

  always_comb begin
    loader_fullbeat_mismatch_count = 7'd0;
    for (int lane = 0; lane < WB_SEL_BITS; lane = lane + 1) begin
      if (wb_data[lane * 8 +: 8] != loader_fullbeat_expected_data[lane * 8 +: 8])
        loader_fullbeat_mismatch_count = loader_fullbeat_mismatch_count + 7'd1;
    end
  end

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

  initial begin
    if (
      BYTE_LANES != 1 &&
      BYTE_LANES != 2 &&
      BYTE_LANES != 4 &&
      BYTE_LANES != 8
    ) begin
      $error("BYTE_LANES must be 1, 2, 4, or 8");
      $finish;
    end
  end
  logic jtag_command_accept_phase_q;

  assign read_probe_read_addr =
    read_probe_single_q ? read_probe_stream_base_q :
    read_probe_stream_base_q +
    {4'd0, read_probe_read_index_q == 3'd4 ? 2'd3 : read_probe_read_index_q[1:0]};
  assign read_probe_write_addr =
    read_probe_stream_base_q + {4'd0, read_probe_write_index_q};
  assign read_probe_addr =
    {{(WB_ADDR_BITS - 6) {1'b0}},
     read_probe_we_q ? read_probe_write_addr : read_probe_read_addr};
  assign read_probe_write_byte =
    read_probe_single_q ? read_probe_expected_byte_q :
    read_probe_expected_byte_q + read_probe_stream_base_q +
    {6'd0, read_probe_write_index_q};
  assign read_probe_capture_index =
    read_probe_single_q ? 2'd0 : read_probe_read_index_q[1:0] - 2'd1;
  assign read_probe_capture_byte =
    read_probe_single_q ? wb_data[7:0] :
    read_probe_capture_index == 2'd3 ? wb_data[31:24] : wb_data[7:0];
  assign read_probe_is_loader_beat =
    read_probe_state_q == LOADER_ISSUE || read_probe_state_q == LOADER_WAIT_ACK;
  assign wb_addr_to_controller =
    read_probe_is_loader_beat ? loader_addr_q : read_probe_addr;
  assign wb_data_to_controller =
    read_probe_is_loader_beat ? loader_write_data_q : {WB_SEL_BITS{read_probe_write_byte}};
  assign wb_sel_to_controller =
    read_probe_is_loader_beat ? loader_sel_q : {WB_SEL_BITS{1'b1}};
  assign loader_debug_state =
    read_probe_state_q == LOADER_ISSUE ? 4'd2 :
    read_probe_state_q == LOADER_WAIT_ACK ? 4'd3 :
    read_probe_state_q == LOADER_ERROR ? 4'd4 :
    read_probe_state_q == LOADER_WRITE_DRAIN ? 4'd5 :
    read_probe_done_q ? 4'd1 :
    read_probe_state_q;

  always_ff @(posedge controller_clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count_q <= 32'd0;
      calib_seen_cycle_q <= 32'd0;
      wb_ack_count_q <= 32'd0;
      wb_err_count_q <= 32'd0;
      wb_stall_count_q <= 32'd0;
      calib_seen_q <= 1'b0;
      jtag_command_accept_phase_q <= 1'b0;
      read_probe_state_q <= READ_PROBE_RESET;
      read_probe_cyc_q <= 1'b0;
      read_probe_stb_q <= 1'b0;
      read_probe_we_q <= 1'b0;
      read_probe_done_q <= 1'b0;
      read_probe_write_ack_seen_q <= 1'b0;
      read_probe_read_ack_seen_q <= 1'b0;
      read_probe_err_seen_q <= 1'b0;
      read_probe_stall_seen_q <= 1'b0;
      read_probe_data_q <= '0;
      read_probe_expected_byte_q <= PROBE_BYTE_VALUE;
      read_probe_write_drain_q <= 10'd0;
      read_probe_wait_cycles_q <= 32'd0;
      read_probe_write_index_q <= 2'd0;
      read_probe_read_index_q <= 3'd0;
      read_probe_stream_base_q <= 6'd0;
      read_probe_stream_bytes_q <= '0;
      read_probe_stream_valid_q <= 4'd0;
      read_probe_stream_mismatch_q <= 4'd0;
      read_probe_run_count_q <= 16'd0;
      loader_addr_q <= '0;
      loader_write_data_q <= '0;
      loader_read_data_q <= '0;
      loader_sel_q <= '0;
      loader_lowbyte_index_q <= '0;
      loader_done_q <= 1'b0;
      loader_error_q <= 1'b0;
      loader_write_ack_seen_q <= 1'b0;
      loader_read_ack_seen_q <= 1'b0;
      loader_stall_seen_q <= 1'b0;
      loader_wait_cycles_q <= 32'd0;
      loader_command_payload_addr_q <= 32'd0;
      loader_last_opcode_q <= 8'd0;
      loader_last_chunk_q <= 2'd0;
      loader_read_chunk_q <= 2'd0;
      loader_last_magic_ok_q <= 1'b0;
      loader_last_accepted_q <= 1'b0;
      loader_dense_write_seen_q <= 1'b0;
      loader_dense_write_addr_q <= 16'd0;
      loader_dense_write_lane_q <= 6'd0;
      loader_dense_write_data_q <= 8'd0;
      loader_dense_write_sel_low_q <= 16'd0;
      loader_lowbyte_write_data_q <= 8'd0;
      loader_lowbyte_read_data_q <= 8'd0;
      loader_lowbyte_addr_q <= 8'd0;
      loader_lowbyte_read_seen_q <= 1'b0;
      loader_lowbyte_write_seen_q <= 1'b0;
      loader_fullbeat_read_after_write_q <= 1'b0;
      loader_fullbeat_compare_active_q <= 1'b0;
      loader_fullbeat_done_q <= 1'b0;
      loader_command_cooldown_q <= 16'd0;
      loader_burst_active_q <= 1'b0;
      loader_burst_read_phase_q <= 1'b0;
      loader_burst_count_q <= 8'd0;
      loader_burst_index_q <= 8'd0;
      loader_burst_mismatch_count_q <= 8'd0;
      loader_burst_first_mismatch_q <= 8'hff;
      loader_burst_base_addr_q <= '0;
      loader_burst_packet_mode_q <= 1'b0;
      loader_packet_data_q[0] <= '0;
      loader_packet_data_q[1] <= '0;
      loader_packet_data_q[2] <= '0;
      loader_packet_data_q[3] <= '0;
      loader_packet_write_ack_seen_q <= 1'b0;
      loader_packet_read_ack_seen_q <= 1'b0;
      loader_packet_write_ack_index_q <= 8'd0;
      loader_packet_write_ack_addr_q <= '0;
      loader_packet_write_ack_data_q <= '0;
      loader_packet_write_ack_sel_q <= '0;
      loader_packet_read_ack_addr_q <= '0;
      loader_packet_read_ack_data_q <= '0;
      loader_fullbeat_mismatch_count_q <= 7'd0;
      loader_fullbeat_addr_q <= '0;
      loader_fullbeat_expected_base_q <= 8'd0;
      loader_fullbeat_write_echo_q <= 32'd0;
      loader_fullbeat_issue_cycle_q <= 32'd0;
      loader_fullbeat_last_write_ack_delta_q <= 4'd0;
      loader_fullbeat_last_read_ack_delta_q <= 4'd0;
      loader_standalone_read_issue_cycle_q <= 32'd0;
      loader_standalone_read_ack_delta_q <= 4'd0;
      loader_standalone_read_request_addr_q <= '0;
      loader_standalone_read_ack_addr_q <= '0;
      loader_standalone_read_ack_opcode_q <= 8'd0;
      loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
      loader_fullbeat_last_issue_data_q <= '0;
      read_probe_single_q <= 1'b0;
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

      if (jtag_command_event)
        jtag_command_accept_phase_q <= ~jtag_command_accept_phase_q;

`ifdef TASK6_PCIE_ROWSTREAM_INGRESS_PORTS
      if (pcie_status_clear_i) begin
        pcie_loader_done_sticky_q <= 1'b0;
        pcie_loader_error_sticky_q <= 1'b0;
        pcie_loader_last_accepted_sticky_q <= 1'b0;
        pcie_loader_last_magic_ok_sticky_q <= 1'b0;
      end else begin
        if (loader_done_q)
          pcie_loader_done_sticky_q <= 1'b1;
        if (loader_error_q)
          pcie_loader_error_sticky_q <= 1'b1;
        if (loader_last_accepted_q)
          pcie_loader_last_accepted_sticky_q <= 1'b1;
        if (loader_last_magic_ok_q)
          pcie_loader_last_magic_ok_sticky_q <= 1'b1;
      end
`endif
      loader_done_q <= 1'b0;
      loader_last_accepted_q <= 1'b0;

      if (
        jtag_command_event && !jtag_command_accept_phase_q && read_probe_done_q &&
        jtag_command_magic_ok && calib_complete && debug1[4:0] == 5'd23
      ) begin
        loader_last_opcode_q <= jtag_command_opcode;
        loader_last_chunk_q <= jtag_command_chunk;
        loader_command_payload_addr_q <= jtag_command_addr;
        loader_last_magic_ok_q <= 1'b1;
        loader_last_accepted_q <= 1'b1;
        read_probe_done_q <= 1'b0;
        loader_error_q <= 1'b0;
        loader_stall_seen_q <= 1'b0;
        loader_wait_cycles_q <= 32'd0;
        loader_fullbeat_read_after_write_q <= 1'b0;
        loader_fullbeat_compare_active_q <= 1'b0;
        loader_burst_active_q <= 1'b0;
        loader_burst_read_phase_q <= 1'b0;
        loader_burst_packet_mode_q <= 1'b0;
        loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
        if (jtag_command_opcode == LOADER_OP_ECHO_CHUNK && jtag_command_chunk == 2'd0) begin
          loader_read_data_q <= jtag_command_chunk_data;
          loader_done_q <= 1'b1;
          read_probe_done_q <= 1'b1;
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_state_q <= READ_PROBE_DONE;
        end else if (jtag_command_opcode == LOADER_OP_RUN_HOST_FULLBEAT && jtag_command_chunk == 2'd0 && WB_SEL_BITS <= 16) begin
          loader_addr_q <= jtag_command_addr_low16;
          loader_write_data_q <= jtag_command_chunk_data;
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          loader_fullbeat_read_after_write_q <= 1'b1;
          loader_fullbeat_compare_active_q <= 1'b0;
          loader_fullbeat_done_q <= 1'b0;
          loader_fullbeat_mismatch_count_q <= 7'd0;
          loader_fullbeat_addr_q <= jtag_command_addr_full;
          loader_burst_base_addr_q <= jtag_command_addr_full;
          loader_fullbeat_expected_base_q <= jtag_command_data_byte;
          loader_fullbeat_write_echo_q <= jtag_command_chunk_data[0 +: 32];
          loader_fullbeat_issue_cycle_q <= 32'd0;
          loader_fullbeat_last_write_ack_delta_q <= 4'd0;
          loader_fullbeat_last_read_ack_delta_q <= 4'd0;
          loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
          loader_fullbeat_last_issue_data_q <= '0;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_LOAD_PACKET_BEAT && jtag_command_chunk == 2'd0 && WB_SEL_BITS <= 16) begin
          loader_packet_data_q[jtag_command_addr[1:0]] <= jtag_command_chunk_data;
          loader_read_data_q <= jtag_command_chunk_data;
          loader_done_q <= 1'b1;
          read_probe_done_q <= 1'b1;
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_state_q <= READ_PROBE_DONE;
        end else if (jtag_command_opcode == LOADER_OP_RUN_HOST_PACKET && jtag_command_chunk == 2'd0 && WB_SEL_BITS <= 16) begin
          loader_addr_q <= jtag_command_addr_full;
          loader_write_data_q <= loader_packet_data_q[0];
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          loader_fullbeat_read_after_write_q <= 1'b1;
          loader_fullbeat_compare_active_q <= 1'b0;
          loader_fullbeat_done_q <= 1'b0;
          loader_fullbeat_mismatch_count_q <= 7'd0;
          loader_fullbeat_addr_q <= jtag_command_addr_full;
          loader_burst_base_addr_q <= jtag_command_addr_full;
          loader_fullbeat_expected_base_q <= 8'h00;
          loader_fullbeat_write_echo_q <= loader_packet_data_q[0][0 +: 32];
          loader_fullbeat_issue_cycle_q <= 32'd0;
          loader_fullbeat_last_write_ack_delta_q <= 4'd0;
          loader_fullbeat_last_read_ack_delta_q <= 4'd0;
          loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
          loader_fullbeat_last_issue_data_q <= '0;
          loader_burst_active_q <= 1'b1;
          loader_burst_packet_mode_q <= 1'b1;
          loader_burst_read_phase_q <= 1'b0;
          loader_burst_count_q <= jtag_command_packet_count == 3'd0 ? 8'd0 :
            (jtag_command_packet_count > 3'd4 ? 8'd3 : {5'd0, jtag_command_packet_count} - 8'd1);
          loader_burst_index_q <= 8'd0;
          loader_burst_mismatch_count_q <= 8'd0;
          loader_burst_first_mismatch_q <= 8'hff;
          loader_packet_write_ack_seen_q <= 1'b0;
          loader_packet_read_ack_seen_q <= 1'b0;
          loader_packet_write_ack_index_q <= 8'd0;
          loader_packet_write_ack_addr_q <= '0;
          loader_packet_write_ack_data_q <= '0;
          loader_packet_write_ack_sel_q <= '0;
          loader_packet_read_ack_addr_q <= '0;
          loader_packet_read_ack_data_q <= '0;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_RUN_RTL_BURST && jtag_command_chunk == 2'd0 && WB_SEL_BITS <= 16) begin
          loader_addr_q <= jtag_command_addr_low16;
          loader_write_data_q <= generated_burst_fullbeat(8'd0);
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          loader_fullbeat_read_after_write_q <= 1'b1;
          loader_fullbeat_compare_active_q <= 1'b0;
          loader_fullbeat_done_q <= 1'b0;
          loader_fullbeat_mismatch_count_q <= 7'd0;
          loader_fullbeat_addr_q <= jtag_command_addr_low16;
          loader_burst_base_addr_q <= jtag_command_addr_low16;
          loader_fullbeat_expected_base_q <= 8'h40;
          loader_fullbeat_write_echo_q <= jtag_command_chunk_data[0 +: 32];
          loader_fullbeat_issue_cycle_q <= 32'd0;
          loader_fullbeat_last_write_ack_delta_q <= 4'd0;
          loader_fullbeat_last_read_ack_delta_q <= 4'd0;
          loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
          loader_fullbeat_last_issue_data_q <= '0;
          loader_burst_active_q <= 1'b1;
          loader_burst_packet_mode_q <= 1'b0;
          loader_burst_read_phase_q <= 1'b0;
          loader_burst_count_q <= jtag_command_data_byte == 8'd0 ? 8'd0 : jtag_command_data_byte - 8'd1;
          loader_burst_index_q <= 8'd0;
          loader_burst_mismatch_count_q <= 8'd0;
          loader_burst_first_mismatch_q <= 8'hff;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_WRITE_CHUNK && jtag_command_chunk == 2'd0 && WB_SEL_BITS <= 16) begin
          loader_addr_q <= jtag_command_addr[WB_ADDR_BITS - 1:0];
          loader_write_data_q <= jtag_command_chunk_data;
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_READ_BEAT && jtag_command_chunk == 2'd0) begin
          loader_addr_q <= jtag_command_addr[WB_ADDR_BITS - 1:0];
          loader_standalone_read_request_addr_q <= jtag_command_addr[WB_ADDR_BITS - 1:0];
          loader_standalone_read_issue_cycle_q <= 32'd0;
          loader_standalone_read_ack_delta_q <= 4'd0;
          loader_standalone_read_ack_addr_q <= '0;
          loader_standalone_read_ack_opcode_q <= 8'd0;
          loader_read_chunk_q <= 2'd0;
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b0;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_WRITE_LOWBYTE) begin
          loader_addr_q <= jtag_command_lowbyte_addr;
          loader_write_data_q <= {WB_SEL_BITS{jtag_command_data_byte}};
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          loader_lowbyte_index_q <= jtag_command_lowbyte_index;
          loader_lowbyte_addr_q <= jtag_command_addr[7:0];
          loader_lowbyte_write_data_q <= jtag_command_data_byte;
          loader_lowbyte_write_seen_q <= 1'b1;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_READ_LOWBYTE) begin
          loader_addr_q <= jtag_command_lowbyte_addr;
          loader_lowbyte_index_q <= jtag_command_lowbyte_index;
          loader_lowbyte_addr_q <= jtag_command_addr[7:0];
          loader_read_chunk_q <= 2'd0;
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b0;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_WRITE_DENSE_BYTE) begin
          loader_addr_q <= jtag_command_dense_addr;
          loader_write_data_q <= jtag_command_dense_data;
          loader_sel_q <= jtag_command_dense_sel;
          loader_dense_write_seen_q <= 1'b1;
          loader_dense_write_addr_q <= jtag_command_dense_addr[15:0];
          loader_dense_write_lane_q <= jtag_command_addr[5:0];
          loader_dense_write_data_q <= jtag_command_data_byte;
          loader_dense_write_sel_low_q <= jtag_command_dense_sel[15:0];
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_READ_DENSE_BEAT) begin
          loader_addr_q <= jtag_command_addr[WB_ADDR_BITS - 1:0];
          loader_read_chunk_q <= 2'd0;
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b0;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_RUN_AUTOPROBE) begin
          read_probe_expected_byte_q <= jtag_command_data_byte;
          read_probe_stream_base_q <= jtag_command_addr[5:0];
          read_probe_write_drain_q <= 10'd0;
          read_probe_wait_cycles_q <= 32'd0;
          read_probe_write_index_q <= 2'd0;
          read_probe_read_index_q <= 3'd0;
          read_probe_stream_bytes_q <= '0;
          read_probe_stream_valid_q <= 4'd0;
          read_probe_stream_mismatch_q <= 4'd0;
          read_probe_write_ack_seen_q <= 1'b0;
          read_probe_read_ack_seen_q <= 1'b0;
          read_probe_err_seen_q <= 1'b0;
          read_probe_stall_seen_q <= 1'b0;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= READ_PROBE_ISSUE_WRITE;
        end else if (jtag_command_opcode == LOADER_OP_RUN_HARDCODED_AUTOPROBE) begin
          read_probe_expected_byte_q <= PROBE_BYTE_VALUE;
          read_probe_stream_base_q <= jtag_command_addr[5:0];
          read_probe_write_drain_q <= 10'd0;
          read_probe_wait_cycles_q <= 32'd0;
          read_probe_write_index_q <= 2'd0;
          read_probe_read_index_q <= 3'd0;
          read_probe_stream_bytes_q <= '0;
          read_probe_stream_valid_q <= 4'd0;
          read_probe_stream_mismatch_q <= 4'd0;
          read_probe_write_ack_seen_q <= 1'b0;
          read_probe_read_ack_seen_q <= 1'b0;
          read_probe_err_seen_q <= 1'b0;
          read_probe_stall_seen_q <= 1'b0;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= READ_PROBE_ISSUE_WRITE;
        end else if (jtag_command_opcode == LOADER_OP_RUN_HARDCODED_SINGLEBYTE) begin
          read_probe_single_q <= 1'b1;
          read_probe_expected_byte_q <= hardcoded_probe_value(jtag_command_addr[9:8]);
          read_probe_stream_base_q <= jtag_command_addr[5:0];
          read_probe_write_drain_q <= 10'd0;
          read_probe_wait_cycles_q <= 32'd0;
          read_probe_write_index_q <= 2'd0;
          read_probe_read_index_q <= 3'd0;
          read_probe_stream_bytes_q <= '0;
          read_probe_stream_valid_q <= 4'd0;
          read_probe_stream_mismatch_q <= 4'd0;
          read_probe_write_ack_seen_q <= 1'b0;
          read_probe_read_ack_seen_q <= 1'b0;
          read_probe_err_seen_q <= 1'b0;
          read_probe_stall_seen_q <= 1'b0;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= READ_PROBE_ISSUE_WRITE;
        end else if (jtag_command_opcode == LOADER_OP_WRITE_DENSE_FILL) begin
          loader_addr_q <= jtag_command_addr[WB_ADDR_BITS - 1:0];
          loader_write_data_q <= {WB_SEL_BITS{jtag_command_data_byte}};
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          loader_dense_write_seen_q <= 1'b1;
          loader_dense_write_addr_q <= jtag_command_addr[15:0];
          loader_dense_write_lane_q <= 6'd0;
          loader_dense_write_data_q <= jtag_command_data_byte;
          loader_dense_write_sel_low_q <= 16'hffff;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else if (jtag_command_opcode == LOADER_OP_RUN_FULLBEAT) begin
          loader_addr_q <= jtag_command_addr_low16;
          loader_write_data_q <= jtag_command_fullbeat_data;
          loader_sel_q <= {WB_SEL_BITS{1'b1}};
          loader_fullbeat_read_after_write_q <= 1'b1;
          loader_fullbeat_compare_active_q <= 1'b0;
          loader_fullbeat_done_q <= 1'b0;
          loader_fullbeat_mismatch_count_q <= 7'd0;
          loader_fullbeat_addr_q <= jtag_command_addr_low16;
          loader_fullbeat_expected_base_q <= jtag_command_data_byte;
          loader_fullbeat_write_echo_q <= jtag_command_fullbeat_data[0 +: 32];
          loader_fullbeat_issue_cycle_q <= 32'd0;
          loader_fullbeat_last_write_ack_delta_q <= 4'd0;
          loader_fullbeat_last_read_ack_delta_q <= 4'd0;
          loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
          loader_fullbeat_last_issue_data_q <= '0;
      read_probe_single_q <= 1'b0;
          read_probe_cyc_q <= 1'b1;
          read_probe_stb_q <= 1'b1;
          read_probe_we_q <= 1'b1;
          read_probe_state_q <= LOADER_ISSUE;
        end else begin
          loader_error_q <= 1'b1;
          read_probe_state_q <= LOADER_ERROR;
        end
      end else if (
        jtag_command_event && !jtag_command_accept_phase_q && read_probe_done_q
      ) begin
        loader_last_opcode_q <= jtag_command_opcode;
        loader_last_chunk_q <= jtag_command_chunk;
        loader_command_payload_addr_q <= jtag_command_addr;
        loader_last_magic_ok_q <= 1'b0;
        wb_ack_count_q <= 32'd0;
        wb_err_count_q <= 32'd0;
        wb_stall_count_q <= 32'd0;
        read_probe_state_q <= READ_PROBE_RESET;
        read_probe_cyc_q <= 1'b0;
        read_probe_stb_q <= 1'b0;
        read_probe_we_q <= 1'b0;
        read_probe_done_q <= 1'b0;
        read_probe_write_ack_seen_q <= 1'b0;
        read_probe_read_ack_seen_q <= 1'b0;
        read_probe_err_seen_q <= 1'b0;
        read_probe_stall_seen_q <= 1'b0;
        read_probe_data_q <= '0;
        read_probe_expected_byte_q <= PROBE_BYTE_VALUE;
        read_probe_stream_base_q <= (read_probe_run_count_q[5:0] + 6'd1) << 2;
        read_probe_write_drain_q <= 10'd0;
        read_probe_wait_cycles_q <= 32'd0;
        read_probe_write_index_q <= 2'd0;
        read_probe_read_index_q <= 3'd0;
        read_probe_stream_bytes_q <= '0;
        read_probe_stream_valid_q <= 4'd0;
        read_probe_stream_mismatch_q <= 4'd0;
        read_probe_run_count_q <= read_probe_run_count_q + 16'd1;
      end else begin
        case (read_probe_state_q)
        READ_PROBE_RESET: begin
          read_probe_single_q <= 1'b0;
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_done_q <= 1'b0;
          read_probe_write_ack_seen_q <= 1'b0;
          read_probe_read_ack_seen_q <= 1'b0;
          read_probe_err_seen_q <= 1'b0;
          read_probe_stall_seen_q <= 1'b0;
          read_probe_write_drain_q <= 10'd0;
          read_probe_wait_cycles_q <= 32'd0;
          read_probe_write_index_q <= 2'd0;
          read_probe_read_index_q <= 3'd0;
          read_probe_stream_bytes_q <= '0;
          read_probe_stream_valid_q <= 4'd0;
          read_probe_stream_mismatch_q <= 4'd0;
          read_probe_state_q <= READ_PROBE_WAIT_CALIB;
        end

        READ_PROBE_WAIT_CALIB: begin
          if (calib_complete) begin
            if (BOOT_ISOLATE_UNTIL_CALIB != 0) begin
              read_probe_cyc_q <= 1'b0;
              read_probe_stb_q <= 1'b0;
              read_probe_we_q <= 1'b0;
              read_probe_done_q <= 1'b1;
              read_probe_state_q <= READ_PROBE_DONE;
            end else begin
              read_probe_cyc_q <= 1'b1;
              read_probe_stb_q <= 1'b1;
              read_probe_we_q <= 1'b1;
              read_probe_state_q <= READ_PROBE_ISSUE_WRITE;
            end
          end
        end

        READ_PROBE_ISSUE_WRITE: begin
          if (wb_stall) begin
            read_probe_stall_seen_q <= 1'b1;
            read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          end else begin
            read_probe_stb_q <= 1'b0;
            read_probe_state_q <= wb_ack ? READ_PROBE_ISSUE_READ : READ_PROBE_WAIT_WRITE_ACK;
          end
          if (wb_err) begin
            read_probe_err_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_DONE;
          end
          if (wb_ack) begin
            read_probe_write_ack_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_stb_q <= 1'b0;
            read_probe_we_q <= 1'b0;
            read_probe_write_drain_q <= 10'd0;
            read_probe_state_q <= READ_PROBE_WAIT_WRITE_DRAIN;
          end
        end

        READ_PROBE_WAIT_WRITE_ACK: begin
          read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          if (wb_err) begin
            read_probe_err_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_DONE;
          end else if (wb_ack) begin
            read_probe_write_ack_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_stb_q <= 1'b0;
            read_probe_we_q <= 1'b0;
            read_probe_write_drain_q <= 10'd0;
            read_probe_state_q <= READ_PROBE_WAIT_WRITE_DRAIN;
          end
        end

        READ_PROBE_WAIT_WRITE_DRAIN: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          if (read_probe_write_drain_q == 10'h3ff) begin
            read_probe_state_q <= READ_PROBE_NEXT_WRITE;
          end else begin
            read_probe_write_drain_q <= read_probe_write_drain_q + 10'd1;
          end
        end

        READ_PROBE_NEXT_WRITE: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          if (read_probe_single_q || read_probe_write_index_q == 2'd3) begin
            read_probe_read_index_q <= 3'd0;
            read_probe_cyc_q <= 1'b1;
            read_probe_stb_q <= 1'b1;
            read_probe_we_q <= 1'b0;
            read_probe_state_q <= READ_PROBE_ISSUE_READ;
          end else begin
            read_probe_write_index_q <= read_probe_write_index_q + 2'd1;
            read_probe_cyc_q <= 1'b1;
            read_probe_stb_q <= 1'b1;
            read_probe_we_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_ISSUE_WRITE;
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
            read_probe_cyc_q <= 1'b0;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_DONE;
          end
          if (wb_ack) begin
            read_probe_read_ack_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_data_q <= wb_data;
            if (read_probe_single_q || read_probe_read_index_q != 3'd0) begin
              read_probe_stream_bytes_q[read_probe_capture_index * 8 +: 8] <=
                read_probe_capture_byte;
              read_probe_stream_valid_q[read_probe_capture_index] <= 1'b1;
              read_probe_stream_mismatch_q[read_probe_capture_index] <=
                read_probe_capture_byte !=
                (read_probe_expected_byte_q +
                 (read_probe_single_q ? 8'd0 : read_probe_stream_base_q) +
                 (read_probe_single_q ? 8'd0 : {6'd0, read_probe_capture_index}));
            end
            read_probe_state_q <= READ_PROBE_NEXT_READ;
          end
        end

        READ_PROBE_WAIT_READ_ACK: begin
          read_probe_wait_cycles_q <= read_probe_wait_cycles_q + 32'd1;
          if (wb_err) begin
            read_probe_err_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_DONE;
          end else if (wb_ack) begin
            read_probe_read_ack_seen_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_data_q <= wb_data;
            if (read_probe_single_q || read_probe_read_index_q != 3'd0) begin
              read_probe_stream_bytes_q[read_probe_capture_index * 8 +: 8] <=
                read_probe_capture_byte;
              read_probe_stream_valid_q[read_probe_capture_index] <= 1'b1;
              read_probe_stream_mismatch_q[read_probe_capture_index] <=
                read_probe_capture_byte !=
                (read_probe_expected_byte_q +
                 (read_probe_single_q ? 8'd0 : read_probe_stream_base_q) +
                 (read_probe_single_q ? 8'd0 : {6'd0, read_probe_capture_index}));
            end
            read_probe_state_q <= READ_PROBE_NEXT_READ;
          end
        end

        READ_PROBE_NEXT_READ: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          if (read_probe_single_q || read_probe_read_index_q == 3'd4) begin
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_DONE;
          end else begin
            read_probe_read_index_q <= read_probe_read_index_q + 3'd1;
            read_probe_cyc_q <= 1'b1;
            read_probe_stb_q <= 1'b1;
            read_probe_we_q <= 1'b0;
            read_probe_state_q <= READ_PROBE_ISSUE_READ;
          end
        end

        READ_PROBE_DONE: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_done_q <= 1'b1;
        end

        LOADER_ISSUE: begin
          if (read_probe_is_loader_beat && !read_probe_we_q && !wb_stall) begin
            loader_standalone_read_issue_cycle_q <= cycle_count_q;
          end
          if (
            read_probe_is_loader_beat &&
            !wb_stall &&
            loader_fullbeat_issue_phase_q == FULLBEAT_PHASE_NONE &&
            (loader_fullbeat_read_after_write_q || loader_fullbeat_compare_active_q)
          ) begin
            loader_fullbeat_issue_phase_q <=
              loader_fullbeat_read_after_write_q ? FULLBEAT_PHASE_WRITE : FULLBEAT_PHASE_READ;
            loader_fullbeat_issue_cycle_q <= cycle_count_q;
            loader_fullbeat_last_issue_data_q <= wb_data_to_controller[127:0];
          end
          if (wb_stall) begin
            loader_stall_seen_q <= 1'b1;
            loader_wait_cycles_q <= loader_wait_cycles_q + 32'd1;
          end else begin
            read_probe_stb_q <= 1'b0;
            read_probe_state_q <= wb_ack ? READ_PROBE_DONE : LOADER_WAIT_ACK;
          end
          if (wb_err) begin
            loader_error_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_stb_q <= 1'b0;
            read_probe_we_q <= 1'b0;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= LOADER_ERROR;
            loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
          end
          if (wb_ack) begin
            read_probe_cyc_q <= 1'b0;
            read_probe_stb_q <= 1'b0;
            if (read_probe_we_q) begin
              loader_write_ack_seen_q <= 1'b1;
              if (loader_burst_active_q && loader_burst_packet_mode_q) begin
                loader_packet_write_ack_seen_q <= 1'b1;
                loader_packet_write_ack_index_q <= loader_burst_index_q;
                loader_packet_write_ack_addr_q <= loader_addr_q;
                loader_packet_write_ack_data_q <= wb_data_to_controller;
                loader_packet_write_ack_sel_q <= wb_sel_to_controller;
              end
              if (loader_fullbeat_issue_phase_q == FULLBEAT_PHASE_WRITE) begin
                loader_fullbeat_last_write_ack_delta_q <=
                  clamp_delta4(loader_fullbeat_issue_cycle_q, cycle_count_q);
                loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
              end
              read_probe_write_drain_q <= 10'd0;
              read_probe_state_q <= LOADER_WRITE_DRAIN;
            end else begin
              loader_read_ack_seen_q <= 1'b1;
              loader_read_data_q <= wb_data;
              if (loader_burst_active_q && loader_burst_packet_mode_q) begin
                loader_packet_read_ack_seen_q <= 1'b1;
                loader_packet_read_ack_addr_q <= loader_addr_q;
                loader_packet_read_ack_data_q <= wb_data;
              end
              loader_standalone_read_ack_addr_q <= loader_addr_q;
              loader_standalone_read_ack_opcode_q <= loader_last_opcode_q;
              loader_standalone_read_ack_delta_q <=
                clamp_delta4(loader_standalone_read_issue_cycle_q, cycle_count_q);
              if (loader_last_opcode_q == LOADER_OP_READ_LOWBYTE) begin
                loader_lowbyte_read_data_q <= wb_data[loader_lowbyte_index_q * 8 +: 8];
                loader_lowbyte_read_seen_q <= 1'b1;
              end
              if (loader_fullbeat_issue_phase_q == FULLBEAT_PHASE_READ) begin
                loader_fullbeat_last_read_ack_delta_q <=
                  clamp_delta4(loader_fullbeat_issue_cycle_q, cycle_count_q);
                loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
              end
              if (loader_fullbeat_compare_active_q) begin
                loader_fullbeat_done_q <= 1'b1;
                loader_fullbeat_mismatch_count_q <= loader_fullbeat_mismatch_count;
                loader_fullbeat_compare_active_q <= 1'b0;
                if (loader_burst_active_q && loader_fullbeat_mismatch_count != 7'd0) begin
                  loader_burst_mismatch_count_q <= loader_burst_mismatch_count_q + 8'd1;
                  if (loader_burst_first_mismatch_q == 8'hff)
                    loader_burst_first_mismatch_q <= loader_burst_index_q;
                end
              end
              if (loader_burst_active_q) begin
                read_probe_state_q <= LOADER_BURST_NEXT;
              end else if (loader_last_opcode_q == LOADER_OP_RUN_HOST_FULLBEAT) begin
                loader_command_cooldown_q <= LOADER_HOST_FULLBEAT_COMMAND_COOLDOWN;
                read_probe_state_q <= LOADER_COMMAND_COOLDOWN;
              end else begin
                loader_done_q <= 1'b1;
                read_probe_done_q <= 1'b1;
                read_probe_state_q <= READ_PROBE_DONE;
              end
            end
          end
        end

        LOADER_WAIT_ACK: begin
          loader_wait_cycles_q <= loader_wait_cycles_q + 32'd1;
          if (wb_err) begin
            loader_error_q <= 1'b1;
            read_probe_cyc_q <= 1'b0;
            read_probe_stb_q <= 1'b0;
            read_probe_we_q <= 1'b0;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= LOADER_ERROR;
            loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
          end else if (wb_ack) begin
            read_probe_cyc_q <= 1'b0;
            if (read_probe_we_q) begin
              loader_write_ack_seen_q <= 1'b1;
              if (loader_burst_active_q && loader_burst_packet_mode_q) begin
                loader_packet_write_ack_seen_q <= 1'b1;
                loader_packet_write_ack_index_q <= loader_burst_index_q;
                loader_packet_write_ack_addr_q <= loader_addr_q;
                loader_packet_write_ack_data_q <= wb_data_to_controller;
                loader_packet_write_ack_sel_q <= wb_sel_to_controller;
              end
              if (loader_fullbeat_issue_phase_q == FULLBEAT_PHASE_WRITE) begin
                loader_fullbeat_last_write_ack_delta_q <=
                  clamp_delta4(loader_fullbeat_issue_cycle_q, cycle_count_q);
                loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
              end
              read_probe_write_drain_q <= 10'd0;
              read_probe_state_q <= LOADER_WRITE_DRAIN;
            end else begin
              loader_read_ack_seen_q <= 1'b1;
              loader_read_data_q <= wb_data;
              if (loader_burst_active_q && loader_burst_packet_mode_q) begin
                loader_packet_read_ack_seen_q <= 1'b1;
                loader_packet_read_ack_addr_q <= loader_addr_q;
                loader_packet_read_ack_data_q <= wb_data;
              end
              loader_standalone_read_ack_addr_q <= loader_addr_q;
              loader_standalone_read_ack_opcode_q <= loader_last_opcode_q;
              loader_standalone_read_ack_delta_q <=
                clamp_delta4(loader_standalone_read_issue_cycle_q, cycle_count_q);
              if (loader_last_opcode_q == LOADER_OP_READ_LOWBYTE) begin
                loader_lowbyte_read_data_q <= wb_data[loader_lowbyte_index_q * 8 +: 8];
                loader_lowbyte_read_seen_q <= 1'b1;
              end
              if (loader_fullbeat_issue_phase_q == FULLBEAT_PHASE_READ) begin
                loader_fullbeat_last_read_ack_delta_q <=
                  clamp_delta4(loader_fullbeat_issue_cycle_q, cycle_count_q);
                loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
              end
              if (loader_fullbeat_compare_active_q) begin
                loader_fullbeat_done_q <= 1'b1;
                loader_fullbeat_mismatch_count_q <= loader_fullbeat_mismatch_count;
                loader_fullbeat_compare_active_q <= 1'b0;
                if (loader_burst_active_q && loader_fullbeat_mismatch_count != 7'd0) begin
                  loader_burst_mismatch_count_q <= loader_burst_mismatch_count_q + 8'd1;
                  if (loader_burst_first_mismatch_q == 8'hff)
                    loader_burst_first_mismatch_q <= loader_burst_index_q;
                end
              end
              if (loader_burst_active_q) begin
                read_probe_state_q <= LOADER_BURST_NEXT;
              end else if (loader_last_opcode_q == LOADER_OP_RUN_HOST_FULLBEAT) begin
                loader_command_cooldown_q <= LOADER_HOST_FULLBEAT_COMMAND_COOLDOWN;
                read_probe_state_q <= LOADER_COMMAND_COOLDOWN;
              end else begin
                loader_done_q <= 1'b1;
                read_probe_done_q <= 1'b1;
                read_probe_state_q <= READ_PROBE_DONE;
              end
            end
          end
        end

        LOADER_WRITE_DRAIN: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          loader_wait_cycles_q <= loader_wait_cycles_q + 32'd1;
          if (read_probe_write_drain_q == 10'h3ff) begin
            if (loader_fullbeat_read_after_write_q) begin
              loader_fullbeat_read_after_write_q <= 1'b0;
              loader_fullbeat_compare_active_q <= 1'b1;
              loader_addr_q <= loader_fullbeat_addr_q;
              loader_sel_q <= {WB_SEL_BITS{1'b1}};
              read_probe_cyc_q <= 1'b1;
              read_probe_stb_q <= 1'b1;
              read_probe_we_q <= 1'b0;
              read_probe_state_q <= LOADER_ISSUE;
            end else begin
              loader_done_q <= 1'b1;
              read_probe_done_q <= 1'b1;
              read_probe_state_q <= READ_PROBE_DONE;
            end
          end else begin
            read_probe_write_drain_q <= read_probe_write_drain_q + 10'd1;
          end
        end

        LOADER_BURST_NEXT: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          loader_wait_cycles_q <= loader_wait_cycles_q + 32'd1;
          if (loader_burst_index_q == loader_burst_count_q) begin
            loader_burst_active_q <= 1'b0;
            loader_done_q <= 1'b1;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_DONE;
          end else begin
            loader_burst_index_q <= loader_burst_index_q + 8'd1;
            loader_addr_q <= loader_burst_base_addr_q + {{(WB_ADDR_BITS - 8){1'b0}}, loader_burst_index_q + 8'd1};
            loader_fullbeat_addr_q <= loader_burst_base_addr_q + {{(WB_ADDR_BITS - 8){1'b0}}, loader_burst_index_q + 8'd1};
            loader_write_data_q <= loader_burst_packet_mode_q ?
              loader_packet_data_q[loader_burst_index_q[1:0] + 2'd1] :
              generated_burst_fullbeat(loader_burst_index_q + 8'd1);
            loader_sel_q <= {WB_SEL_BITS{1'b1}};
            loader_fullbeat_expected_base_q <= 8'h40 + loader_burst_index_q + 8'd1;
            loader_fullbeat_read_after_write_q <= 1'b1;
            loader_fullbeat_compare_active_q <= 1'b0;
            loader_fullbeat_issue_phase_q <= FULLBEAT_PHASE_NONE;
            read_probe_cyc_q <= 1'b1;
            read_probe_stb_q <= 1'b1;
            read_probe_we_q <= 1'b1;
            read_probe_state_q <= LOADER_ISSUE;
          end
        end

        LOADER_COMMAND_COOLDOWN: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          loader_wait_cycles_q <= loader_wait_cycles_q + 32'd1;
          if (loader_command_cooldown_q == 16'd0) begin
            loader_done_q <= 1'b1;
            read_probe_done_q <= 1'b1;
            read_probe_state_q <= READ_PROBE_DONE;
          end else begin
            loader_command_cooldown_q <= loader_command_cooldown_q - 16'd1;
          end
        end

        LOADER_ERROR: begin
          read_probe_cyc_q <= 1'b0;
          read_probe_stb_q <= 1'b0;
          read_probe_we_q <= 1'b0;
          read_probe_done_q <= 1'b1;
        end

        default: read_probe_state_q <= READ_PROBE_DONE;
        endcase
      end
    end
  end

  logic [JTAG_DEBUG_WIDTH - 1:0] jtag_debug_payload;
  localparam int JTAG_BOOT_DEBUG_WIDTH = 336;
  logic [JTAG_BOOT_DEBUG_WIDTH - 1:0] jtag_boot_debug_payload;

  assign jtag_boot_debug_payload = jtag_debug_payload[JTAG_BOOT_DEBUG_WIDTH - 1:0];

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
    jtag_debug_payload[240 +: 32] =
      read_probe_done_q &&
      (loader_last_opcode_q == LOADER_OP_RUN_RTL_BURST ||
       loader_last_opcode_q == LOADER_OP_RUN_HOST_PACKET) ?
      {loader_burst_first_mismatch_q, loader_burst_mismatch_count_q, loader_burst_count_q, loader_burst_index_q} :
      read_probe_done_q && loader_last_opcode_q == LOADER_OP_RUN_FULLBEAT ?
      loader_read_data_q[31:0] :
      read_probe_done_q && loader_last_opcode_q == LOADER_OP_RUN_HARDCODED_SINGLEBYTE ?
      {8'd0, read_probe_expected_byte_q, read_probe_stream_mismatch_q,
       read_probe_stream_valid_q, read_probe_stream_bytes_q[7:0]} :
      read_probe_done_q &&
      (loader_last_opcode_q == LOADER_OP_WRITE_LOWBYTE ||
       loader_last_opcode_q == LOADER_OP_READ_LOWBYTE) ?
      {loader_lowbyte_addr_q, loader_lowbyte_write_data_q,
       loader_lowbyte_read_data_q, 6'd0, loader_lowbyte_read_seen_q,
       loader_lowbyte_write_seen_q} :
      read_probe_done_q ? loader_read_data_q[31:0] : read_probe_data_q[31:0];
    jtag_debug_payload[272 +: 32] =
      {jtag_command_count[7:0], loader_last_opcode_q,
       6'd0, loader_last_chunk_q, loader_last_magic_ok_q, loader_last_accepted_q};
    jtag_debug_payload[304 +: 32] = {
      7'd0,
      loader_fullbeat_mismatch_count_q,
      loader_fullbeat_done_q,
      read_probe_done_q && (read_probe_stream_mismatch_q != 4'd0),
      read_probe_stall_seen_q,
      read_probe_err_seen_q,
      read_probe_read_ack_seen_q,
      read_probe_write_ack_seen_q,
      read_probe_done_q,
      loader_stall_seen_q,
      loader_error_q,
      loader_read_ack_seen_q,
      loader_write_ack_seen_q,
      loader_done_q,
      read_probe_cyc_q,
      read_probe_stb_q,
      loader_debug_state
    };
    jtag_debug_payload[336 +: 128] = loader_last_opcode_q == LOADER_OP_RUN_HOST_PACKET ?
      loader_packet_write_ack_data_q[0 +: 128] : loader_read_data_q[0 +: 128];
    jtag_debug_payload[464] = loader_last_opcode_q == LOADER_OP_RUN_HOST_PACKET ?
      loader_packet_write_ack_seen_q :
      loader_last_opcode_q == LOADER_OP_READ_BEAT ?
      loader_read_ack_seen_q : loader_fullbeat_done_q;
    jtag_debug_payload[465 +: 7] = loader_last_opcode_q == LOADER_OP_RUN_HOST_PACKET ?
      {loader_packet_write_ack_index_q[5:0], loader_packet_read_ack_seen_q} :
      loader_last_opcode_q == LOADER_OP_READ_BEAT ?
      loader_standalone_read_ack_opcode_q[6:0] : loader_fullbeat_mismatch_count_q;
    jtag_debug_payload[472 +: 24] = loader_last_opcode_q == LOADER_OP_RUN_RTL_BURST ?
      {8'd0, loader_burst_mismatch_count_q, loader_burst_first_mismatch_q} :
      loader_last_opcode_q == LOADER_OP_RUN_HOST_PACKET ?
      loader_packet_write_ack_addr_q[23:0] :
      loader_last_opcode_q == LOADER_OP_READ_BEAT ?
      loader_standalone_read_ack_addr_q[23:0] :
      loader_fullbeat_addr_q[23:0];
    jtag_debug_payload[496 +: 8] = loader_last_opcode_q == LOADER_OP_RUN_RTL_BURST ?
      loader_burst_count_q :
      loader_last_opcode_q == LOADER_OP_RUN_HOST_PACKET ?
      loader_packet_write_ack_sel_q[7:0] :
      loader_last_opcode_q == LOADER_OP_READ_BEAT ?
      loader_standalone_read_request_addr_q[7:0] : loader_fullbeat_expected_base_q;
    jtag_debug_payload[504 +: 4] = loader_last_opcode_q == LOADER_OP_READ_BEAT ?
      loader_standalone_read_ack_delta_q : loader_fullbeat_last_write_ack_delta_q;
    jtag_debug_payload[508 +: 4] = loader_fullbeat_last_read_ack_delta_q;
    if (!read_probe_done_q)
      jtag_debug_payload[240 +: 32] = read_probe_stream_bytes_q;
  end

  ddr3_top #(
    .CONTROLLER_CLK_PERIOD(CONTROLLER_CLK_PERIOD_PS),
    .DDR3_CLK_PERIOD(DDR3_CLK_PERIOD_PS),
    .ROW_BITS(ROW_BITS),
    .COL_BITS(COL_BITS),
    .BA_BITS(BA_BITS),
    .BYTE_LANES(BYTE_LANES),
    .AUX_WIDTH(4),
    .WB2_ADDR_BITS(7),
    .WB2_DATA_BITS(32),
    .DUAL_RANK_DIMM(0),
    .SPEED_BIN(SPEED_BIN_PARAM),
    .SDRAM_CAPACITY(SDRAM_CAPACITY_PARAM),
    .TRCD(13_750),
    .TRP(13_750),
    .TRAS(35_000),
    .ODELAY_SUPPORTED(0),
    .SECOND_WISHBONE(0),
    .DLL_OFF(DLL_OFF_PARAM),
    .WB_ERROR(0),
    .BIST_MODE(1),
    .BIST_TEST_DATAMASK(BIST_TEST_DATAMASK),
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
    .i_wb_addr(wb_addr_to_controller),
    .i_wb_data(wb_data_to_controller),
    .i_wb_sel(wb_sel_to_controller),
    .i_aux(read_probe_we_q ? 4'd0 : 4'd1),
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
    .io_ddr3_dq(ddram_dq[BYTE_LANES * 8 - 1:0]),
    .io_ddr3_dqs(ddram_dqs_p[BYTE_LANES - 1:0]),
    .io_ddr3_dqs_n(ddram_dqs_n[BYTE_LANES - 1:0]),
    .o_ddr3_dm(ddr3_dm_w),
    .o_ddr3_odt(ddr3_odt_w),
    .o_calib_complete(calib_complete),
    .o_debug1(debug1),
    .i_user_self_refresh(1'b0),
    .uart_tx(uart_tx)
  );

  generate
    if (!DISABLE_JTAG_DEBUG_SHIFT) begin : g_debug_shift_enabled
      task6_uberddr3_jtag_debug_shift #(
        .WIDTH(JTAG_DEBUG_WIDTH),
        .JTAG_CHAIN(JTAG_CHAIN),
        .DISABLE_JTAG(DISABLE_JTAG_DEBUG_SHIFT)
      ) jtag_debug_shift (
        .payload_i(jtag_debug_payload)
      );
    end else begin : g_debug_boot_status_enabled
      task6_uberddr3_jtag_debug_shift #(
        .WIDTH(JTAG_BOOT_DEBUG_WIDTH),
        .JTAG_CHAIN(JTAG_CHAIN),
        .DISABLE_JTAG(1'b0)
      ) jtag_debug_shift (
        .payload_i(jtag_boot_debug_payload)
      );
    end
  endgenerate

  task6_uberddr3_loader_jtag_command_shift #(
    .WIDTH(JTAG_COMMAND_WIDTH),
    .JTAG_CHAIN(JTAG_COMMAND_CHAIN)
  ) jtag_command_shift (
    .controller_clk_i(controller_clk),
    .rst_ni(rst_n),
    .payload_o(jtag_command_payload_from_shift),
    .event_o(jtag_command_event_from_shift),
    .command_count_o(jtag_command_count)
  );

`ifdef TASK6_PCIE_ROWSTREAM_INGRESS_PORTS
  assign pcie_controller_clk_o = controller_clk;
  assign pcie_controller_rst_n_o = rst_n;
  assign pcie_boot_done_o = read_probe_done_q;
  assign pcie_loader_done_o = pcie_loader_done_sticky_q;
  assign pcie_loader_error_o = pcie_loader_error_sticky_q;
  assign pcie_loader_last_accepted_o = pcie_loader_last_accepted_sticky_q;
  assign pcie_loader_last_magic_ok_o = pcie_loader_last_magic_ok_sticky_q;
  assign pcie_loader_last_opcode_o = loader_last_opcode_q;
  assign pcie_loader_last_chunk_o = loader_last_chunk_q;
  assign pcie_loader_command_payload_addr_o = loader_command_payload_addr_q;
  assign pcie_loader_wait_cycles_o = loader_wait_cycles_q;
  assign pcie_loader_read_data_o = {{(512 - WB_DATA_BITS){1'b0}}, loader_read_data_q};
`endif
endmodule

module task6_uberddr3_loader_jtag_command_shift #(
  parameter int WIDTH = 16,
  parameter int JTAG_CHAIN = 2
) (
  input  logic        controller_clk_i,
  input  logic        rst_ni,
  output logic [WIDTH - 1:0] payload_o,
  output logic        event_o,
  output logic [15:0] command_count_o
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
  logic [WIDTH - 1:0] payload_tck_q;
  logic [WIDTH - 1:0] payload_meta_q;
  logic [WIDTH - 1:0] payload_sync_q;
  logic toggle_tck_q;
  logic toggle_meta_q;
  logic toggle_sync_q;
  logic toggle_seen_q;

  assign tdo = shift_q[0];

  always_ff @(posedge drck or posedge reset) begin
    if (reset) begin
      shift_q <= '0;
    end else begin
      if (sel && capture)
        shift_q <= payload_tck_q;
      else if (sel && shift)
        shift_q <= {tdi, shift_q[WIDTH - 1:1]};
    end
  end

  always_ff @(posedge tck or posedge reset) begin
    if (reset) begin
      payload_tck_q <= '0;
      toggle_tck_q <= 1'b0;
    end else if (sel && update) begin
        payload_tck_q <= shift_q;
        toggle_tck_q <= ~toggle_tck_q;
    end
  end

  always_ff @(posedge controller_clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      toggle_meta_q <= 1'b0;
      toggle_sync_q <= 1'b0;
      toggle_seen_q <= 1'b0;
      payload_meta_q <= '0;
      payload_sync_q <= '0;
      payload_o <= '0;
      event_o <= 1'b0;
      command_count_o <= 16'd0;
    end else begin
      payload_meta_q <= payload_tck_q;
      payload_sync_q <= payload_meta_q;
      toggle_meta_q <= toggle_tck_q;
      toggle_sync_q <= toggle_meta_q;
      event_o <= toggle_sync_q ^ toggle_seen_q;
      if (toggle_sync_q ^ toggle_seen_q) begin
        toggle_seen_q <= toggle_sync_q;
        payload_o <= payload_sync_q;
        command_count_o <= command_count_o + 16'd1;
      end
    end
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

module task6_uberddr3_jtag_debug_shift #(
  parameter int WIDTH = 512,
  parameter int JTAG_CHAIN = 1,
  parameter bit DISABLE_JTAG = 0
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

  generate
    if (DISABLE_JTAG) begin : g_jtag_debug_shift_disabled
      BSCANE2 #(
        .DISABLE_JTAG("TRUE"),
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
    end else begin : g_jtag_debug_shift_enabled
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
    end
  endgenerate
endmodule

`default_nettype wire
