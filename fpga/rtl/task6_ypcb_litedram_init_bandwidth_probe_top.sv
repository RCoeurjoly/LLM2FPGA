module task6_ypcb_litedram_init_bandwidth_probe_top #(
  parameter int JTAG_DEBUG_WIDTH = 4672,
  parameter int READ_COUNT_LOG2 = 16,
  parameter int CAL_COUNT_LOG2 = 5,
  parameter int TIMEOUT_LOG2 = 28,
  parameter int WB_TIMEOUT_LOG2 = 20,
  parameter bit DFII_DISABLE_WRITE_COMMAND = 1'b0,
  parameter bit DFII_PHASE_MATRIX_ONLY = 1'b0,
  parameter bit DFII_SOURCE_COMMAND_MATRIX_ONLY = 1'b0,
  parameter bit DFII_SOURCE_ORDER_MATRIX_ONLY = 1'b0,
  parameter bit DFII_HALF_ORDER_MATRIX_ONLY = 1'b0,
  parameter bit DFII_DISPLACEMENT_PROBE_ONLY = 1'b0,
  parameter bit DFII_CSR_ECHO_PROBE_ONLY = 1'b0,
  parameter bit DFII_WBITSLIP_SWEEP_ONLY = 1'b0,
  parameter bit DFII_RBITSLIP_SWEEP_ONLY = 1'b0,
  parameter bit DFII_EDGE_MAP_PROBE_ONLY = 1'b0,
  parameter bit DFII_EDGE_COMP_PROBE_ONLY = 1'b0,
  parameter bit DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY = 1'b0,
  parameter int DFII_SOURCE_COMMAND_READ_PHASE = 2,
  parameter int DFII_SOURCE_ORDER_SOURCE_PHASE = 0,
  parameter int DFII_SOURCE_ORDER_WRITE_PHASE = 0,
  parameter int DFII_SOURCE_ORDER_READ_PHASE = 2
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
  inout  wire   [71:0] ddram_dq,
  inout  wire    [8:0] ddram_dqs_n,
  inout  wire    [8:0] ddram_dqs_p,
  output wire          ddram_odt,
  output wire          ddram_ras_n,
  output wire          ddram_reset_n,
  output wire          ddram_we_n
);
  localparam logic [31:0] JTAG_DEBUG_MAGIC = 32'h54364a44;
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd77;
  // v53 fixed the DFII CSR layout for the 72-bit no-ODELAY PHY. v54 restores a
  // non-overlapping DFII-first JTAG payload so board evidence is not decoded as
  // stale native-chunk fields. v55 keeps that payload stable for low-rate PHY
  // A/B testing. v56 adds a compact DFII column-address association sweep.
  // v57 adds a no-write discriminator flag for command reachability tests.
  // v58 adds an autonomous write-source/read-phase matrix for DFII association.
  // v59 decouples write-source phase from write-command phase.
  // v60 maps source-phase-0 byte tags through DFII write/read ordering.
  // v61 maps low/high 72-bit half tags, including the ninth byte lane.
  // v62 writes a dense low/high lane-tag pattern for read-capture mapping.
  // v63 reads back DFII wrdata CSRs before DRAM commands to prove CSR order.
  // v64 sweeps write-bitslip pulses before the dense displacement probe.
  // v65 sweeps read-bitslip pulses before the dense displacement probe.
  // v66 writes tagged bytes across all DFI phases/halves in one BL8 stream.
  // v67 fixes the DFII rddata CSR base so probes read rddata4..0, not wrdata0.
  // v68 tests the v67 lane association with a compensated write-source map.
  // v69 locates lane7's source. v70 retests the compensated map. v71 drives
  // the whole compensated write pattern on every DFI source phase. v72 prunes
  // that to only lane7's source-phase ambiguity. v73 keeps the v70 source map
  // but uses the repeatable lane7 locator value to split map vs value behavior.
  // v74 restores the v69 word4 filler to test DFII final-word packing/enables.
  // v75 keeps only the lane7/lane8 final-word bytes and drops filler bytes.
  // v76 keeps those final-word bytes on phase 0 only to test phase scope.
  // v77 sweeps final-word variants in one routed image at separate columns.
  localparam int CAL_BYTE_LANES = 8;
  localparam int PHASE_CANDIDATES = 16;
  localparam int DFII_ADDR_SLOTS = 4;
  localparam int DFII_CSR_WORDS_PER_PHASE = 5;
  localparam int DFII_RDDATA_WORDS = 20;
  localparam int DFII_CSR_PHASE_STRIDE = 14;
  localparam int NATIVE_BEATS = 8;
  localparam logic [31:0] READ_COUNT_WORDS = 32'd1 << READ_COUNT_LOG2;
  localparam logic [31:0] CAL_COUNT_WORDS = 32'd1 << CAL_COUNT_LOG2;
  localparam logic [31:0] WRITE_DRAIN_CYCLES = 32'd10_000;
  localparam logic [31:0] CAL_WRITE_DRAIN_CYCLES = 32'd1_000;
  localparam logic [31:0] WRITE_DATA_AHEAD_LIMIT = 32'd16;
  localparam int READBACK_SAMPLE_COUNT = 8;
  localparam int BYTE_DIAG_SAMPLE_COUNT = 8;
  localparam logic [31:0] READBACK_SAMPLE_COUNT_WORDS = 32'd8;
  localparam logic [31:0] BYTE_DIAG_WORDS = 32'd8;
  localparam logic [24:0] BYTE_DIAG_BASE_ADDR = 25'h0_1000;
  localparam logic [1:0] DFII_PATTERN_MODE_UNIFORM = 2'd0;
  localparam logic [1:0] DFII_PATTERN_MODE_PHASE = 2'd1;
  localparam logic [1:0] DFII_PATTERN_MODE_RAMP = 2'd2;
  localparam logic [1:0] DFII_PATTERN_MODE_ASSOC = 2'd3;
  localparam logic [7:0] DFII_EDGE_COMP_LANE7_TAG = 8'hA0;

  localparam logic [29:0] WB_ADDR_INIT_DONE = 30'h000;
  localparam logic [29:0] WB_ADDR_INIT_ERROR = 30'h001;
  localparam logic [29:0] WB_ADDR_DDRPHY_RST = 30'h200;
  localparam logic [29:0] WB_ADDR_DDRPHY_DLY_SEL = 30'h201;
  localparam logic [29:0] WB_ADDR_DDRPHY_RDLY_DQ_RST = 30'h205;
  localparam logic [29:0] WB_ADDR_DDRPHY_RDLY_DQ_INC = 30'h206;
  localparam logic [29:0] WB_ADDR_DDRPHY_RDLY_DQ_BITSLIP_RST = 30'h207;
  localparam logic [29:0] WB_ADDR_DDRPHY_RDLY_DQ_BITSLIP = 30'h208;
  localparam logic [29:0] WB_ADDR_DDRPHY_WDLY_DQ_BITSLIP_RST = 30'h209;
  localparam logic [29:0] WB_ADDR_DDRPHY_WDLY_DQ_BITSLIP = 30'h20a;
  localparam logic [29:0] WB_ADDR_DDRPHY_RDPHASE = 30'h20b;
  localparam logic [29:0] WB_ADDR_DDRPHY_WRPHASE = 30'h20c;
  localparam logic [29:0] WB_ADDR_DFII_CONTROL = 30'h400;
  localparam logic [29:0] WB_ADDR_PI0_COMMAND = 30'h401;
  localparam logic [29:0] WB_ADDR_PI0_COMMAND_ISSUE = 30'h402;
  localparam logic [29:0] WB_ADDR_PI0_ADDRESS = 30'h403;
  localparam logic [29:0] WB_ADDR_PI0_BADDRESS = 30'h404;
  localparam logic [29:0] WB_ADDR_PI0_WRDATA = 30'h405;
  localparam logic [29:0] WB_ADDR_PI0_RDDATA = 30'h40a;
  localparam logic [29:0] WB_ADDR_PI2_COMMAND = 30'h41d;
  localparam logic [29:0] WB_ADDR_PI2_COMMAND_ISSUE = 30'h41e;
  localparam logic [29:0] WB_ADDR_PI2_ADDRESS = 30'h41f;
  localparam logic [29:0] WB_ADDR_PI2_BADDRESS = 30'h420;
  localparam logic [29:0] WB_ADDR_PI2_RDDATA = 30'h426;
  localparam logic [29:0] WB_ADDR_PI3_COMMAND = 30'h42b;
  localparam logic [29:0] WB_ADDR_PI3_COMMAND_ISSUE = 30'h42c;
  localparam logic [29:0] WB_ADDR_PI3_ADDRESS = 30'h42d;
  localparam logic [29:0] WB_ADDR_PI3_BADDRESS = 30'h42e;
  localparam logic [29:0] WB_ADDR_PI3_WRDATA = 30'h42f;

  localparam logic [31:0] DFII_CONTROL_SEL = 32'h0000_0001;
  localparam logic [31:0] DFII_CONTROL_CKE = 32'h0000_0002;
  localparam logic [31:0] DFII_CONTROL_ODT = 32'h0000_0004;
  localparam logic [31:0] DFII_CONTROL_RESET_N = 32'h0000_0008;
  localparam logic [31:0] DFII_COMMAND_CS = 32'h0000_0001;
  localparam logic [31:0] DFII_COMMAND_WE = 32'h0000_0002;
  localparam logic [31:0] DFII_COMMAND_CAS = 32'h0000_0004;
  localparam logic [31:0] DFII_COMMAND_RAS = 32'h0000_0008;
  localparam logic [31:0] DFII_COMMAND_WRDATA = 32'h0000_0010;
  localparam logic [31:0] DFII_COMMAND_RDDATA = 32'h0000_0020;
  localparam logic [31:0] DFII_COMMAND_MRS =
    DFII_COMMAND_RAS | DFII_COMMAND_CAS | DFII_COMMAND_WE | DFII_COMMAND_CS;
  localparam logic [31:0] DFII_COMMAND_ZQ =
    DFII_COMMAND_WE | DFII_COMMAND_CS;
  localparam logic [31:0] DFII_CONTROL_SOFTWARE_RESET_RELEASE =
    DFII_CONTROL_ODT | DFII_CONTROL_RESET_N;
  localparam logic [31:0] DFII_CONTROL_SOFTWARE_CKE =
    DFII_CONTROL_CKE | DFII_CONTROL_ODT | DFII_CONTROL_RESET_N;
  localparam logic [31:0] DFII_CONTROL_HARDWARE = DFII_CONTROL_SEL;
  localparam logic [7:0] INIT_STEP_DONE_MARKER = 8'd32;

  typedef enum logic [4:0] {
    PROBE_RESET = 5'd0,
    PROBE_WAIT_INIT = 5'd1,
    PROBE_CAL_CONFIG = 5'd2,
    PROBE_CAL_RUN_WRITES = 5'd3,
    PROBE_CAL_WRITE_DRAIN = 5'd4,
    PROBE_CAL_RUN_READS = 5'd5,
    PROBE_CAL_APPLY_BEST = 5'd6,
    PROBE_CAL_NEXT_LANE = 5'd7,
    PROBE_RUN_WRITES = 5'd8,
    PROBE_WRITE_DRAIN = 5'd9,
    PROBE_RUN_READS = 5'd10,
    PROBE_DONE = 5'd11,
    PROBE_ERROR = 5'd12,
    PROBE_TIMEOUT = 5'd13,
    PROBE_DFII_RUN = 5'd14,
    PROBE_DFII_DONE = 5'd15,
    PROBE_DFII_RESTART = 5'd16,
    PROBE_BYTE_CLEAR_WRITES = 5'd17,
    PROBE_BYTE_MASK_WRITES = 5'd18,
    PROBE_BYTE_WRITE_DRAIN = 5'd19,
    PROBE_BYTE_RUN_READS = 5'd20,
    PROBE_PHASE_CONFIG = 5'd21,
    PROBE_PHASE_RUN_WRITES = 5'd22,
    PROBE_PHASE_WRITE_DRAIN = 5'd23,
    PROBE_PHASE_RUN_READS = 5'd24,
    PROBE_PHASE_APPLY_BEST = 5'd25,
    PROBE_DFII_WBITSLIP_CONFIG = 5'd26
  } probe_state_t;

  typedef enum logic [3:0] {
    INIT_RESET = 4'd0,
    INIT_START_WAIT = 4'd1,
    INIT_RUN_STEP = 4'd2,
    INIT_WB_WAIT = 4'd3,
    INIT_DELAY = 4'd4,
    INIT_DONE = 4'd5,
    INIT_ERROR = 4'd6
  } init_state_t;

  typedef enum logic [3:0] {
    CAL_CFG_IDLE = 4'd0,
    CAL_CFG_RUN_STEP = 4'd1,
    CAL_CFG_WB_WAIT = 4'd2,
    CAL_CFG_DONE = 4'd3,
    CAL_CFG_ERROR = 4'd4
  } cal_config_state_t;

  typedef enum logic [2:0] {
    DFII_SEQ_IDLE = 3'd0,
    DFII_SEQ_RUN_STEP = 3'd1,
    DFII_SEQ_WB_WAIT = 3'd2,
    DFII_SEQ_DELAY = 3'd3,
    DFII_SEQ_DONE = 3'd4,
    DFII_SEQ_ERROR = 3'd5
  } dfii_seq_state_t;

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

  function automatic logic [63:0] pattern64_for_addr(input logic [24:0] addr);
    logic [31:0] x;
    begin
      x = {7'd0, addr};
      pattern64_for_addr = {
        (32'hc0de_0000 ^ x ^ (x << 7)),
        (32'h1357_9bdf ^ ~x ^ (x << 13))
      };
    end
  endfunction

  function automatic logic [575:0] pattern_for_addr(input logic [24:0] addr);
    logic [63:0] base;
    begin
      base = pattern64_for_addr(addr);
      for (int chunk_idx = 0; chunk_idx < 9; chunk_idx++)
        pattern_for_addr[chunk_idx * 64 +: 64] =
          base ^ {8{8'h10 + chunk_idx[7:0]}};
    end
  endfunction

  logic [24:0] read_addr_q = 25'd0;
  logic [24:0] compare_addr_q = 25'd0;
  logic [31:0] command_count_q = 32'd0;
  logic [31:0] response_count_q = 32'd0;
  logic [31:0] write_command_count_q = 32'd0;
  logic [31:0] write_data_count_q = 32'd0;
  logic [31:0] write_drain_count_q = 32'd0;
  logic [31:0] read_cycle_count_q = 32'd0;
  logic [31:0] command_stall_count_q = 32'd0;
  logic [31:0] checksum_q = 32'd0;
  logic [63:0] last_rdata_q = 64'd0;
  logic [31:0] mismatch_count_q = 32'd0;
  logic [27:0] first_mismatch_addr_q = 28'd0;
  logic [63:0] first_expected_q = 64'd0;
  logic [63:0] first_actual_q = 64'd0;
  logic [575:0] first_expected_full_q = 576'd0;
  logic [575:0] first_actual_full_q = 576'd0;
  logic [8:0] first_chunk_mismatch_q = 9'd0;
  logic [63:0] sample_rdata_q [0:READBACK_SAMPLE_COUNT - 1];
  logic [7:0] sample_valid_count_q = 8'd0;
  logic [63:0] byte_diag_rdata_q [0:BYTE_DIAG_SAMPLE_COUNT - 1];
  logic [7:0] byte_diag_valid_count_q = 8'd0;
  probe_state_t state_q = PROBE_RESET;
  init_state_t init_state_q = INIT_RESET;
  cal_config_state_t cal_config_state_q = CAL_CFG_IDLE;

  logic [7:0] init_step_q = 8'd0;
  logic [31:0] init_delay_q = 32'd0;
  logic [31:0] wb_ack_count_q = 32'd0;
  logic [31:0] wb_wait_count_q = 32'd0;
  logic [WB_TIMEOUT_LOG2 - 1:0] wb_timeout_count_q = '0;
  logic [15:0] last_wb_addr_q = 16'd0;
  logic [31:0] last_wb_data_q = 32'd0;
  logic init_seq_error_q = 1'b0;
  logic wb_error_seen_q = 1'b0;
  logic wb_timeout_seen_q = 1'b0;

  logic wb_ctrl_cyc_q = 1'b0;
  logic wb_ctrl_stb_q = 1'b0;
  logic wb_ctrl_we_q = 1'b0;
  logic [29:0] wb_ctrl_adr_q = 30'd0;
  logic [31:0] wb_ctrl_dat_w_q = 32'd0;
  wire wb_ctrl_ack;
  wire wb_ctrl_err;
  wire [31:0] wb_ctrl_dat_r;

  logic cal_wb_ctrl_cyc_q = 1'b0;
  logic cal_wb_ctrl_stb_q = 1'b0;
  logic cal_wb_ctrl_we_q = 1'b0;
  logic [29:0] cal_wb_ctrl_adr_q = 30'd0;
  logic [31:0] cal_wb_ctrl_dat_w_q = 32'd0;
  logic [WB_TIMEOUT_LOG2 - 1:0] cal_wb_timeout_count_q = '0;
  logic [31:0] cal_wb_ack_count_q = 32'd0;
  logic [31:0] cal_wb_wait_count_q = 32'd0;
  logic [15:0] cal_last_wb_addr_q = 16'd0;
  logic [31:0] cal_last_wb_data_q = 32'd0;
  logic cal_wb_error_seen_q = 1'b0;
  logic cal_wb_timeout_seen_q = 1'b0;

  logic dfii_wb_ctrl_cyc_q = 1'b0;
  logic dfii_wb_ctrl_stb_q = 1'b0;
  logic dfii_wb_ctrl_we_q = 1'b0;
  logic [29:0] dfii_wb_ctrl_adr_q = 30'd0;
  logic [31:0] dfii_wb_ctrl_dat_w_q = 32'd0;
  logic [WB_TIMEOUT_LOG2 - 1:0] dfii_wb_timeout_count_q = '0;
  logic [31:0] dfii_wb_ack_count_q = 32'd0;
  logic [31:0] dfii_wb_wait_count_q = 32'd0;
  logic [15:0] dfii_last_wb_addr_q = 16'd0;
  logic [31:0] dfii_last_wb_data_q = 32'd0;
  logic [31:0] dfii_last_read_data_q = 32'd0;
  logic dfii_wb_error_seen_q = 1'b0;
  logic dfii_wb_timeout_seen_q = 1'b0;
  logic dfii_failed_q = 1'b0;
  logic dfii_done_q = 1'b0;
  logic dfii_final_q = 1'b0;
  logic dfii_phasecmd_sweep_q = 1'b0;
  logic dfii_assoc_sweep_q = 1'b0;
  logic dfii_addr_sweep_q = 1'b0;
  logic [1:0] dfii_pattern_mode_q = DFII_PATTERN_MODE_RAMP;
  logic [3:0] dfii_phasecmd_index_q = 4'd0;
  logic [3:0] dfii_assoc_index_q = 4'd0;
  logic [1:0] dfii_addr_index_q = 2'd0;
  dfii_seq_state_t dfii_seq_state_q = DFII_SEQ_IDLE;
  logic [7:0] dfii_step_q = 8'd0;
  logic [31:0] dfii_delay_q = 32'd0;
  logic [31:0] dfii_rddata_q [0:DFII_RDDATA_WORDS - 1];
  logic [DFII_RDDATA_WORDS - 1:0] dfii_word_mismatch_q = '0;
  logic [15:0] dfii_mode_mismatch_q [0:2];
  logic [15:0] dfii_phasecmd_mismatch_q [0:15];
  logic [15:0] dfii_assoc_nonzero_mask_q [0:15];
  logic [15:0] dfii_assoc_match_mask_q [0:15];
  logic [3:0] dfii_half_nonzero_high_q [0:15];
  logic [3:0] dfii_half_low_match_high_q [0:15];
  logic [15:0] dfii_half_high_match_low_q [0:15];
  logic [3:0] dfii_half_high_match_high_q [0:15];
  logic [15:0] dfii_addr_mismatch_mask_q [0:DFII_ADDR_SLOTS - 1];
  logic [15:0] dfii_addr_nonzero_mask_q [0:DFII_ADDR_SLOTS - 1];
  logic [15:0] dfii_addr_match_mask_q [0:DFII_ADDR_SLOTS - 1];

  logic [2:0] cal_bitslip_q = 3'd0;
  logic [2:0] cal_wbitslip_q = 3'd0;
  logic [4:0] cal_delay_q = 5'd0;
  logic [2:0] cal_lane_q = 3'd0;
  logic [2:0] selected_bitslip_q = 3'd0;
  logic [2:0] selected_wbitslip_q = 3'd0;
  logic [4:0] selected_delay_q = 5'd0;
  logic [2:0] best_bitslip_q = 3'd0;
  logic [2:0] best_wbitslip_q = 3'd0;
  logic [4:0] best_delay_q = 5'd0;
  logic [31:0] best_mismatch_count_q = 32'hffff_ffff;
  logic [31:0] cal_candidates_tested_q = 32'd0;
  logic [7:0] cal_config_step_q = 8'd0;
  logic [4:0] cal_delay_pulse_q = 5'd0;
  logic [2:0] cal_bitslip_pulse_q = 3'd0;
  logic [2:0] cal_wbitslip_pulse_q = 3'd0;
  logic [31:0] cal_last_mismatch_count_q = 32'd0;
  logic [2:0] lane_selected_bitslip_q [0:CAL_BYTE_LANES - 1];
  logic [2:0] lane_selected_wbitslip_q [0:CAL_BYTE_LANES - 1];
  logic [4:0] lane_selected_delay_q [0:CAL_BYTE_LANES - 1];
  logic [2:0] lane_selected_logical_byte_q [0:CAL_BYTE_LANES - 1];
  logic [2:0] lane_best_bitslip_q [0:CAL_BYTE_LANES - 1];
  logic [2:0] lane_best_wbitslip_q [0:CAL_BYTE_LANES - 1];
  logic [4:0] lane_best_delay_q [0:CAL_BYTE_LANES - 1];
  logic [2:0] lane_best_logical_byte_q [0:CAL_BYTE_LANES - 1];
  logic [31:0] lane_best_mismatch_count_q [0:CAL_BYTE_LANES - 1];
  logic [31:0] cal_byte_mismatch_count_q [0:CAL_BYTE_LANES - 1];
  logic [1:0] phase_rd_q = 2'd0;
  logic [1:0] phase_wr_q = 2'd0;
  logic [1:0] phase_best_rd_q = 2'd0;
  logic [1:0] phase_best_wr_q = 2'd0;
  logic [31:0] phase_best_mismatch_count_q = 32'hffff_ffff;
  logic [31:0] phase_candidates_tested_q = 32'd0;
  logic [31:0] phase_mismatch_count_q [0:PHASE_CANDIDATES - 1];

  logic init_step_is_delay;
  logic [29:0] init_step_wb_addr;
  logic [31:0] init_step_wb_data;
  logic [31:0] init_step_delay;
  logic [29:0] cal_step_wb_addr;
  logic [31:0] cal_step_wb_data;
  logic dfii_step_is_delay;
  logic dfii_step_is_read;
  logic [29:0] dfii_step_wb_addr;
  logic [31:0] dfii_step_wb_data;
  logic [31:0] dfii_step_delay;

  wire cmd_ready;
  wire cmd_valid;
  wire cmd_we;
  wire [24:0] cmd_addr;
  wire wdata_ready;
  wire wdata_valid;
  wire [575:0] wdata;
  wire [71:0] wdata_we;
  wire rdata_valid;
  wire [575:0] rdata;
  wire outstanding_full;
  wire read_target_issued;
  wire read_target_seen;
  wire write_data_target_seen;
  wire write_command_target_seen;
  wire write_drain_done;
  wire timeout_seen;
  wire cal_mode;
  wire cal_config_done;
  wire cal_config_failed;
  wire cal_config_active;
  wire cal_apply_state;
  wire cal_last_candidate;
  wire cal_candidate_success;
  wire cal_lane_last;
  wire cal_candidate_better;
  wire cal_write_state;
  wire cal_read_state;
  wire phase_mode;
  wire phase_config_active;
  wire phase_apply_state;
  wire phase_write_state;
  wire phase_read_state;
  wire phase_last_candidate;
  wire phase_candidate_better;
  wire byte_diag_clear_state;
  wire byte_diag_mask_state;
  wire byte_diag_write_state;
  wire byte_diag_read_state;
  wire byte_diag_mode;
  wire write_state;
  wire read_state;
  wire [31:0] active_target_words;
  wire [31:0] active_write_drain_cycles;
  wire [31:0] next_mismatch_count;
  wire [31:0] lane_best_mismatch_next;
  wire [2:0] lane_best_bitslip_next;
  wire [2:0] lane_best_wbitslip_next;
  wire [4:0] lane_best_delay_next;
  wire [2:0] lane_best_logical_byte_next;
  wire [3:0] phase_candidate_index;
  wire [3:0] phase_best_index;
  wire [31:0] phase_mismatch_next;
  wire [31:0] phase_best_mismatch_next;
  wire [1:0] phase_best_rd_next;
  wire [1:0] phase_best_wr_next;
  logic [CAL_BYTE_LANES - 1:0] byte_response_mismatch;
  logic [31:0] cal_byte_mismatch_next [0:CAL_BYTE_LANES - 1];
  logic [31:0] cal_candidate_min_mismatch;
  logic [2:0] cal_candidate_min_byte;
  wire [2:0] cal_config_bitslip;
  wire [2:0] cal_config_wbitslip;
  wire [4:0] cal_config_delay;
  wire [31:0] cal_config_lane_mask;
  wire [29:0] wb_ctrl_adr_mux;
  wire [31:0] wb_ctrl_dat_w_mux;
  wire wb_ctrl_cyc_mux;
  wire wb_ctrl_stb_mux;
  wire wb_ctrl_we_mux;
  wire dfii_seq_running;
  wire [4:0] dfii_wrdata_index;
  wire [4:0] dfii_wrdata_write_index;
  wire [4:0] dfii_rddata_index;
  wire [1:0] dfii_active_pattern_mode;
  wire [1:0] dfii_write_command_phase;
  wire [1:0] dfii_read_command_phase;
  wire dfii_phase_matrix_mode;
  wire dfii_source_command_matrix_mode;
  wire dfii_source_order_matrix_mode;
  wire dfii_half_order_matrix_mode;
  wire dfii_displacement_probe_mode;
  wire dfii_csr_echo_probe_mode;
  wire dfii_wbitslip_sweep_mode;
  wire dfii_rbitslip_sweep_mode;
  wire dfii_edge_map_probe_mode;
  wire dfii_edge_comp_probe_mode;
  wire dfii_edge_lane7_locator_probe_mode;
  wire dfii_bitslip_sweep_mode;
  wire dfii_wide_word_mode;
  wire [1:0] dfii_matrix_source_phase;
  wire [3:0] dfii_result_slot;
  wire [7:0] dfii_source_order_tag;
  wire [7:0] dfii_half_low_tag;
  wire [7:0] dfii_half_high_tag;
  wire [4:0] dfii_wrdata_index20;
  wire [4:0] dfii_rddata_index20;
  wire [4:0] dfii_read_store_index;
  wire [7:0] dfii_seq_done_step;
  wire [4:0] dfii_csr_echo_read_index20;
  wire [31:0] cal_candidate_score;
  logic [31:0] dfii_candidate_error_count;
  logic [15:0] dfii_assoc_nonzero_mask_next;
  logic [15:0] dfii_assoc_match_mask_next;
  logic [15:0] dfii_phase_matrix_nonzero_mask_next;
  logic [15:0] dfii_phase_matrix_match_mask_next;
  logic [DFII_RDDATA_WORDS - 1:0] dfii_half_nonzero_mask_next;
  logic [DFII_RDDATA_WORDS - 1:0] dfii_half_low_match_mask_next;
  logic [DFII_RDDATA_WORDS - 1:0] dfii_half_high_match_mask_next;
  logic [15:0] dfii_addr_nonzero_mask_next;
  logic [15:0] dfii_addr_match_mask_next;
  logic [63:0] dfii_addr_column_payload;
  logic [63:0] dfii_addr_mismatch_payload;
  logic [63:0] dfii_addr_nonzero_payload;
  logic [63:0] dfii_addr_match_payload;
  logic [63:0] dfii_half_nonzero_high_payload;
  logic [63:0] dfii_half_low_match_high_payload;
  logic [255:0] dfii_half_high_match_low_payload;
  logic [63:0] dfii_half_high_match_high_payload;
  wire init_seq_done;
  wire init_seq_running;
  wire response_mismatch;
  wire lane_response_mismatch;
  wire [8:0] response_chunk_mismatch;
  wire [575:0] expected_rdata;
  wire mismatch_seen;

  function automatic logic [7:0] select_byte(
    input logic [575:0] value,
    input logic [2:0] lane
  );
    begin
      unique case (lane)
        3'd0: select_byte = value[7:0];
        3'd1: select_byte = value[15:8];
        3'd2: select_byte = value[23:16];
        3'd3: select_byte = value[31:24];
        3'd4: select_byte = value[39:32];
        3'd5: select_byte = value[47:40];
        3'd6: select_byte = value[55:48];
        default: select_byte = value[63:56];
      endcase
    end
  endfunction

  function automatic logic [63:0] select_lane_burst(
    input logic [575:0] value,
    input logic [2:0] lane
  );
    begin
      select_lane_burst = 64'd0;
      for (int beat_idx = 0; beat_idx < NATIVE_BEATS; beat_idx++) begin
        unique case (lane)
          3'd0: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 0 +: 8];
          3'd1: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 8 +: 8];
          3'd2: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 16 +: 8];
          3'd3: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 24 +: 8];
          3'd4: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 32 +: 8];
          3'd5: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 40 +: 8];
          3'd6: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 48 +: 8];
          3'd7: select_lane_burst[beat_idx * 8 +: 8] =
            value[beat_idx * 72 + 56 +: 8];
          default: select_lane_burst[beat_idx * 8 +: 8] = 8'd0;
        endcase
      end
    end
  endfunction

  function automatic logic [575:0] byte_diag_word(input logic [3:0] lane);
    begin
      unique case (lane)
        3'd0: byte_diag_word = {512'd0, 64'h0000_0000_0000_00a0};
        3'd1: byte_diag_word = {512'd0, 64'h0000_0000_0000_a100};
        3'd2: byte_diag_word = {512'd0, 64'h0000_0000_00a2_0000};
        3'd3: byte_diag_word = {512'd0, 64'h0000_0000_a300_0000};
        3'd4: byte_diag_word = {512'd0, 64'h0000_00a4_0000_0000};
        3'd5: byte_diag_word = {512'd0, 64'h0000_a500_0000_0000};
        3'd6: byte_diag_word = {512'd0, 64'h00a6_0000_0000_0000};
        default: byte_diag_word = {512'd0, 64'ha700_0000_0000_0000};
      endcase
    end
  endfunction

  function automatic logic [71:0] byte_diag_we_mask(input logic [3:0] lane);
    begin
      unique case (lane)
        3'd0: byte_diag_we_mask = 72'd1;
        3'd1: byte_diag_we_mask = 72'd2;
        3'd2: byte_diag_we_mask = 72'd4;
        3'd3: byte_diag_we_mask = 72'd8;
        3'd4: byte_diag_we_mask = 72'd16;
        3'd5: byte_diag_we_mask = 72'd32;
        3'd6: byte_diag_we_mask = 72'd64;
        3'd7: byte_diag_we_mask = 72'd128;
        default: byte_diag_we_mask = 72'd256;
      endcase
    end
  endfunction

  function automatic logic [29:0] dfii_pi_wrdata_addr(
    input logic [1:0] phase,
    input logic [1:0] word
  );
    logic [2:0] csr_word;
    begin
      // Match LiteX CONFIG_CSR_ORDERING_BIG buffer order for 144-bit DFII CSRs.
      // The v53 probe still compares the lower 128 bits and leaves the 9th
      // byte-lane half-word at the generated CSR word 0.
      csr_word = 3'd4 - {1'b0, word};
      dfii_pi_wrdata_addr = WB_ADDR_PI0_WRDATA +
        {25'd0, phase, 3'd0} +
        {26'd0, phase, 2'd0} +
        {27'd0, phase, 1'd0} +
        {27'd0, csr_word};
    end
  endfunction

  function automatic logic [29:0] dfii_pi_wrdata_addr5(
    input logic [1:0] phase,
    input logic [2:0] word
  );
    begin
      dfii_pi_wrdata_addr5 =
        word == 3'd4 ?
        (WB_ADDR_PI0_WRDATA +
         {25'd0, phase, 3'd0} +
         {26'd0, phase, 2'd0} +
         {27'd0, phase, 1'd0}) :
        dfii_pi_wrdata_addr(phase, word[1:0]);
    end
  endfunction

  function automatic logic [29:0] dfii_pi_offset(input logic [1:0] phase);
    begin
      dfii_pi_offset =
        {25'd0, phase, 3'd0} +
        {26'd0, phase, 2'd0} +
        {27'd0, phase, 1'd0};
    end
  endfunction

  function automatic logic [29:0] dfii_pi_command_addr(input logic [1:0] phase);
    begin
      dfii_pi_command_addr = WB_ADDR_PI0_COMMAND + dfii_pi_offset(phase);
    end
  endfunction

  function automatic logic [29:0] dfii_pi_command_issue_addr(
    input logic [1:0] phase
  );
    begin
      dfii_pi_command_issue_addr =
        WB_ADDR_PI0_COMMAND_ISSUE + dfii_pi_offset(phase);
    end
  endfunction

  function automatic logic [29:0] dfii_pi_address_addr(input logic [1:0] phase);
    begin
      dfii_pi_address_addr = WB_ADDR_PI0_ADDRESS + dfii_pi_offset(phase);
    end
  endfunction

  function automatic logic [29:0] dfii_pi_baddress_addr(input logic [1:0] phase);
    begin
      dfii_pi_baddress_addr = WB_ADDR_PI0_BADDRESS + dfii_pi_offset(phase);
    end
  endfunction

  function automatic logic [29:0] dfii_pi_rddata_addr(
    input logic [1:0] phase,
    input logic [1:0] word
  );
    logic [2:0] csr_word;
    begin
      // Match LiteX CONFIG_CSR_ORDERING_BIG buffer order for 144-bit DFII CSRs.
      csr_word = 3'd4 - {1'b0, word};
      dfii_pi_rddata_addr = WB_ADDR_PI0_RDDATA +
        {25'd0, phase, 3'd0} +
        {26'd0, phase, 2'd0} +
        {27'd0, phase, 1'd0} +
        {27'd0, csr_word};
    end
  endfunction

  function automatic logic [29:0] dfii_pi_rddata_addr5(
    input logic [1:0] phase,
    input logic [2:0] word
  );
    begin
      dfii_pi_rddata_addr5 =
        word == 3'd4 ?
        (WB_ADDR_PI0_RDDATA +
         {25'd0, phase, 3'd0} +
         {26'd0, phase, 2'd0} +
         {27'd0, phase, 1'd0}) :
        dfii_pi_rddata_addr(phase, word[1:0]);
    end
  endfunction

  function automatic logic [1:0] dfii_index20_phase(
    input logic [4:0] index
  );
    begin
      if (index < 5'd5)
        dfii_index20_phase = 2'd0;
      else if (index < 5'd10)
        dfii_index20_phase = 2'd1;
      else if (index < 5'd15)
        dfii_index20_phase = 2'd2;
      else
        dfii_index20_phase = 2'd3;
    end
  endfunction

  function automatic logic [2:0] dfii_index20_word(
    input logic [4:0] index
  );
    begin
      if (index < 5'd5)
        dfii_index20_word = index[2:0];
      else if (index < 5'd10)
        dfii_index20_word = index - 5'd5;
      else if (index < 5'd15)
        dfii_index20_word = index - 5'd10;
      else
        dfii_index20_word = index - 5'd15;
    end
  endfunction

  function automatic logic [31:0] dfii_assoc_signature(
    input logic [3:0] source
  );
    begin
      dfii_assoc_signature = {
        4'ha, source,
        4'hb, source,
        4'hc, source,
        4'hd, source
      };
    end
  endfunction

  function automatic logic [31:0] dfii_phase_source_pattern(
    input logic [1:0] source_phase,
    input logic [1:0] word
  );
    logic [7:0] base;
    begin
      base = 8'h10 + {2'd0, source_phase, 4'd0} + {4'd0, word, 2'd0};
      dfii_phase_source_pattern = {
        base,
        base + 8'd1,
        base + 8'd2,
        base + 8'd3
      };
    end
  endfunction

  function automatic logic [7:0] dfii_source_order_tag_byte(
    input logic [3:0] slot
  );
    begin
      dfii_source_order_tag_byte = 8'h80 + {4'd0, slot};
    end
  endfunction

  function automatic logic [31:0] dfii_source_order_word(
    input logic [3:0] slot,
    input logic [1:0] word
  );
    logic [7:0] tag;
    begin
      tag = dfii_source_order_tag_byte(slot);
      dfii_source_order_word = 32'd0;
      if (word == slot[3:2]) begin
        unique case (slot[1:0])
          2'd0: dfii_source_order_word = {24'd0, tag};
          2'd1: dfii_source_order_word = {16'd0, tag, 8'd0};
          2'd2: dfii_source_order_word = {8'd0, tag, 16'd0};
          default: dfii_source_order_word = {tag, 24'd0};
        endcase
      end
    end
  endfunction

  function automatic logic [7:0] dfii_half_order_low_tag_byte(
    input logic [3:0] slot
  );
    begin
      dfii_half_order_low_tag_byte = 8'h90 + {4'd0, slot};
    end
  endfunction

  function automatic logic [7:0] dfii_half_order_high_tag_byte(
    input logic [3:0] slot
  );
    begin
      dfii_half_order_high_tag_byte = 8'ha0 + {4'd0, slot};
    end
  endfunction

  function automatic logic [3:0] dfii_half_order_lane(
    input logic [3:0] slot
  );
    begin
      unique case (slot)
        4'd0, 4'd1, 4'd2, 4'd3, 4'd4,
        4'd5, 4'd6, 4'd7, 4'd8:
          dfii_half_order_lane = slot;
        4'd9, 4'd10:
          dfii_half_order_lane = 4'd7;
        4'd11, 4'd12, 4'd15:
          dfii_half_order_lane = 4'd8;
        default:
          dfii_half_order_lane = 4'd0;
      endcase
    end
  endfunction

  function automatic logic dfii_half_order_low_enabled(
    input logic [3:0] slot
  );
    begin
      dfii_half_order_low_enabled =
        slot <= 4'd9 || slot == 4'd11 || slot == 4'd13 || slot == 4'd15;
    end
  endfunction

  function automatic logic dfii_half_order_high_enabled(
    input logic [3:0] slot
  );
    begin
      dfii_half_order_high_enabled =
        slot <= 4'd8 || slot == 4'd10 || slot == 4'd12 ||
        slot == 4'd14 || slot == 4'd15;
    end
  endfunction

  function automatic logic [2:0] dfii_half_order_low_word(
    input logic [3:0] lane
  );
    begin
      unique case (lane)
        4'd0, 4'd1, 4'd2, 4'd3: dfii_half_order_low_word = 3'd0;
        4'd4, 4'd5, 4'd6, 4'd7: dfii_half_order_low_word = 3'd1;
        default: dfii_half_order_low_word = 3'd2;
      endcase
    end
  endfunction

  function automatic logic [1:0] dfii_half_order_low_byte(
    input logic [3:0] lane
  );
    begin
      unique case (lane)
        4'd0, 4'd4, 4'd8: dfii_half_order_low_byte = 2'd0;
        4'd1, 4'd5: dfii_half_order_low_byte = 2'd1;
        4'd2, 4'd6: dfii_half_order_low_byte = 2'd2;
        default: dfii_half_order_low_byte = 2'd3;
      endcase
    end
  endfunction

  function automatic logic [2:0] dfii_half_order_high_word(
    input logic [3:0] lane
  );
    begin
      unique case (lane)
        4'd0, 4'd1, 4'd2: dfii_half_order_high_word = 3'd2;
        4'd3, 4'd4, 4'd5, 4'd6: dfii_half_order_high_word = 3'd3;
        default: dfii_half_order_high_word = 3'd4;
      endcase
    end
  endfunction

  function automatic logic [1:0] dfii_half_order_high_byte(
    input logic [3:0] lane
  );
    begin
      unique case (lane)
        4'd0, 4'd4, 4'd8: dfii_half_order_high_byte = 2'd1;
        4'd1, 4'd5: dfii_half_order_high_byte = 2'd2;
        4'd2: dfii_half_order_high_byte = 2'd3;
        4'd3, 4'd7: dfii_half_order_high_byte = 2'd0;
        default: dfii_half_order_high_byte = 2'd3;
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_place_byte(
    input logic [7:0] tag,
    input logic [1:0] byte_index
  );
    begin
      unique case (byte_index)
        2'd0: dfii_place_byte = {24'd0, tag};
        2'd1: dfii_place_byte = {16'd0, tag, 8'd0};
        2'd2: dfii_place_byte = {8'd0, tag, 16'd0};
        default: dfii_place_byte = {tag, 24'd0};
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_half_order_word(
    input logic [3:0] slot,
    input logic [2:0] word
  );
    logic [3:0] lane;
    begin
      lane = dfii_half_order_lane(slot);
      dfii_half_order_word = 32'd0;
      if (dfii_half_order_low_enabled(slot) &&
          word == dfii_half_order_low_word(lane))
        dfii_half_order_word =
          dfii_half_order_word |
          dfii_place_byte(
            dfii_half_order_low_tag_byte(slot),
            dfii_half_order_low_byte(lane)
          );
      if (dfii_half_order_high_enabled(slot) &&
          word == dfii_half_order_high_word(lane))
        dfii_half_order_word =
          dfii_half_order_word |
          dfii_place_byte(
            dfii_half_order_high_tag_byte(slot),
            dfii_half_order_high_byte(lane)
          );
    end
  endfunction

  function automatic logic [31:0] dfii_displacement_word(
    input logic [2:0] word
  );
    begin
      unique case (word)
        3'd0:
          dfii_displacement_word =
            dfii_place_byte(8'h10, 2'd0) |
            dfii_place_byte(8'h11, 2'd1) |
            dfii_place_byte(8'h12, 2'd2) |
            dfii_place_byte(8'h13, 2'd3);
        3'd1:
          dfii_displacement_word =
            dfii_place_byte(8'h14, 2'd0) |
            dfii_place_byte(8'h15, 2'd1) |
            dfii_place_byte(8'h16, 2'd2) |
            dfii_place_byte(8'h17, 2'd3);
        3'd2:
          dfii_displacement_word =
            dfii_place_byte(8'h18, 2'd0) |
            dfii_place_byte(8'h20, 2'd1) |
            dfii_place_byte(8'h21, 2'd2) |
            dfii_place_byte(8'h22, 2'd3);
        3'd3:
          dfii_displacement_word =
            dfii_place_byte(8'h23, 2'd0) |
            dfii_place_byte(8'h24, 2'd1) |
            dfii_place_byte(8'h25, 2'd2) |
            dfii_place_byte(8'h26, 2'd3);
        3'd4:
          dfii_displacement_word =
            dfii_place_byte(8'h27, 2'd0) |
            dfii_place_byte(8'h28, 2'd1) |
            dfii_place_byte(8'h2a, 2'd2) |
            dfii_place_byte(8'h2b, 2'd3);
        default:
          dfii_displacement_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [7:0] dfii_edge_map_tag(
    input logic [1:0] phase,
    input logic high_half,
    input logic [3:0] lane
  );
    begin
      dfii_edge_map_tag =
        8'h10 + {phase, 5'd0} + (high_half ? 8'h10 : 8'h00) +
        {4'd0, lane};
    end
  endfunction

  function automatic logic [31:0] dfii_edge_map_word(
    input logic [1:0] phase,
    input logic [2:0] word
  );
    begin
      unique case (word)
        3'd0:
          dfii_edge_map_word =
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd0), 2'd0) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd1), 2'd1) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd2), 2'd2) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd3), 2'd3);
        3'd1:
          dfii_edge_map_word =
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd4), 2'd0) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd5), 2'd1) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd6), 2'd2) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd7), 2'd3);
        3'd2:
          dfii_edge_map_word =
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b0, 4'd8), 2'd0) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd0), 2'd1) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd1), 2'd2) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd2), 2'd3);
        3'd3:
          dfii_edge_map_word =
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd3), 2'd0) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd4), 2'd1) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd5), 2'd2) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd6), 2'd3);
        3'd4:
          dfii_edge_map_word =
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd7), 2'd0) |
            dfii_place_byte(dfii_edge_map_tag(phase, 1'b1, 4'd8), 2'd1) |
            dfii_place_byte(8'hc0 | {6'd0, phase}, 2'd2) |
            dfii_place_byte(8'hd0 | {6'd0, phase}, 2'd3);
        default:
          dfii_edge_map_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [7:0] dfii_edge_comp_tag(
    input logic [3:0] lane
  );
    begin
      dfii_edge_comp_tag =
        (lane == 4'd7) ? DFII_EDGE_COMP_LANE7_TAG : (8'h90 + {4'd0, lane});
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_write_word(
    input logic [1:0] phase,
    input logic [2:0] word,
    input logic [1:0] variant
  );
    begin
      dfii_edge_comp_write_word = 32'd0;
      unique case ({phase, word})
        5'b00_000:
          dfii_edge_comp_write_word =
            dfii_place_byte(dfii_edge_comp_tag(4'd0), 2'd0) |
            dfii_place_byte(dfii_edge_comp_tag(4'd1), 2'd1) |
            dfii_place_byte(dfii_edge_comp_tag(4'd2), 2'd2) |
            dfii_place_byte(dfii_edge_comp_tag(4'd3), 2'd3);
        5'b00_001:
          dfii_edge_comp_write_word =
            dfii_place_byte(dfii_edge_comp_tag(4'd4), 2'd0) |
            dfii_place_byte(dfii_edge_comp_tag(4'd5), 2'd1) |
            dfii_place_byte(dfii_edge_comp_tag(4'd6), 2'd2) |
            dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd3);
        5'b00_010:
          dfii_edge_comp_write_word =
            dfii_place_byte(dfii_edge_comp_tag(4'd8), 2'd0);
        5'b00_100:
          dfii_edge_comp_write_word =
            (variant == 2'd3) ? 32'd0 :
            dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) |
            ((variant == 2'd2) ? 32'd0 :
             dfii_place_byte(dfii_edge_comp_tag(4'd8), 2'd1));
        5'b01_100:
          dfii_edge_comp_write_word =
            (variant == 2'd0) ?
            (dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) |
             dfii_place_byte(dfii_edge_comp_tag(4'd8), 2'd1)) :
            (variant == 2'd2) ?
            dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) :
            32'd0;
        5'b10_100:
          dfii_edge_comp_write_word =
            (variant == 2'd0) ?
            (dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) |
             dfii_place_byte(dfii_edge_comp_tag(4'd8), 2'd1)) :
            (variant == 2'd2) ?
            dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) :
            32'd0;
        5'b11_100:
          dfii_edge_comp_write_word =
            (variant == 2'd0) ?
            (dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) |
             dfii_place_byte(dfii_edge_comp_tag(4'd8), 2'd1)) :
            (variant == 2'd2) ?
            dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) :
            32'd0;
        default:
          dfii_edge_comp_write_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_read_word(
    input logic [2:0] word,
    input logic [1:0] variant
  );
    begin
      unique case (word)
        3'd0:
          dfii_edge_comp_read_word =
            dfii_place_byte(dfii_edge_comp_tag(4'd0), 2'd0) |
            dfii_place_byte(dfii_edge_comp_tag(4'd1), 2'd1) |
            dfii_place_byte(dfii_edge_comp_tag(4'd2), 2'd2) |
            dfii_place_byte(dfii_edge_comp_tag(4'd3), 2'd3);
        3'd1:
          dfii_edge_comp_read_word =
            dfii_place_byte(dfii_edge_comp_tag(4'd4), 2'd0) |
            dfii_place_byte(dfii_edge_comp_tag(4'd5), 2'd1) |
            dfii_place_byte(dfii_edge_comp_tag(4'd6), 2'd2) |
            dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd3);
        3'd2:
          dfii_edge_comp_read_word =
            dfii_place_byte(dfii_edge_comp_tag(4'd8), 2'd0) |
            dfii_place_byte(dfii_edge_comp_tag(4'd0), 2'd1) |
            dfii_place_byte(dfii_edge_comp_tag(4'd1), 2'd2) |
            dfii_place_byte(dfii_edge_comp_tag(4'd2), 2'd3);
        3'd3:
          dfii_edge_comp_read_word =
            dfii_place_byte(dfii_edge_comp_tag(4'd3), 2'd0) |
            dfii_place_byte(dfii_edge_comp_tag(4'd4), 2'd1) |
            dfii_place_byte(dfii_edge_comp_tag(4'd5), 2'd2) |
            dfii_place_byte(dfii_edge_comp_tag(4'd6), 2'd3);
        3'd4:
          dfii_edge_comp_read_word =
            (variant == 2'd2) ?
            dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) :
            (dfii_place_byte(dfii_edge_comp_tag(4'd7), 2'd0) |
             dfii_place_byte(dfii_edge_comp_tag(4'd8), 2'd1));
        default:
          dfii_edge_comp_read_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [7:0] dfii_lane7_locator_tag(
    input logic [4:0] candidate
  );
    begin
      dfii_lane7_locator_tag = 8'hA0 + {3'd0, candidate};
    end
  endfunction

  function automatic logic [31:0] dfii_lane7_locator_write_word(
    input logic [1:0] phase,
    input logic [2:0] word
  );
    begin
      dfii_lane7_locator_write_word =
        dfii_edge_comp_write_word(phase, word, 2'd0);
      unique case ({phase, word})
        5'b00_001:
          dfii_lane7_locator_write_word =
            dfii_edge_comp_write_word(phase, word, 2'd0) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd0), 2'd3);
        5'b00_100:
          dfii_lane7_locator_write_word =
            dfii_place_byte(dfii_lane7_locator_tag(5'd1), 2'd0) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd5), 2'd1) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd9), 2'd2) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd13), 2'd3);
        5'b01_100:
          dfii_lane7_locator_write_word =
            dfii_place_byte(dfii_lane7_locator_tag(5'd2), 2'd0) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd6), 2'd1) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd10), 2'd2) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd14), 2'd3);
        5'b10_100:
          dfii_lane7_locator_write_word =
            dfii_place_byte(dfii_lane7_locator_tag(5'd3), 2'd0) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd7), 2'd1) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd11), 2'd2) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd15), 2'd3);
        5'b11_100:
          dfii_lane7_locator_write_word =
            dfii_place_byte(dfii_lane7_locator_tag(5'd4), 2'd0) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd8), 2'd1) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd12), 2'd2) |
            dfii_place_byte(dfii_lane7_locator_tag(5'd16), 2'd3);
        default:
          dfii_lane7_locator_write_word =
            dfii_edge_comp_write_word(phase, word, 2'd0);
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_lane7_locator_expected_word(
    input logic [2:0] word
  );
    begin
      dfii_lane7_locator_expected_word = dfii_edge_comp_read_word(word, 2'd0);
      unique case (word)
        3'd1:
          dfii_lane7_locator_expected_word =
            dfii_edge_comp_read_word(word, 2'd0) & 32'h00ff_ffff;
        3'd4:
          dfii_lane7_locator_expected_word =
            dfii_edge_comp_read_word(word, 2'd0) & 32'hffff_ff00;
        default:
          dfii_lane7_locator_expected_word =
            dfii_edge_comp_read_word(word, 2'd0);
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_csr_echo_word(
    input logic [1:0] phase,
    input logic [2:0] word
  );
    logic [7:0] base;
    begin
      base = 8'h10 + {1'b0, phase, 5'd0} + {3'd0, word, 2'd0};
      if (word == 3'd4) begin
        dfii_csr_echo_word =
          dfii_place_byte(base, 2'd0) |
          dfii_place_byte(base + 8'd1, 2'd1);
      end else begin
        dfii_csr_echo_word =
          dfii_place_byte(base, 2'd0) |
          dfii_place_byte(base + 8'd1, 2'd1) |
          dfii_place_byte(base + 8'd2, 2'd2) |
          dfii_place_byte(base + 8'd3, 2'd3);
      end
    end
  endfunction

  function automatic logic dfii_word_has_tag(
    input logic [31:0] value,
    input logic [7:0] tag
  );
    begin
      dfii_word_has_tag =
        value[7:0] == tag ||
        value[15:8] == tag ||
        value[23:16] == tag ||
        value[31:24] == tag;
    end
  endfunction

  function automatic logic [31:0] dfii_addr_column(
    input logic [1:0] slot
  );
    begin
      unique case (slot)
        2'd0: dfii_addr_column = 32'h0000_0000;
        2'd1: dfii_addr_column = 32'h0000_0008;
        2'd2: dfii_addr_column = 32'h0000_0040;
        default: dfii_addr_column = 32'h0000_0100;
      endcase
    end
  endfunction

  function automatic logic [15:0] dfii_addr_column16(
    input logic [1:0] slot
  );
    begin
      dfii_addr_column16 = dfii_addr_column(slot);
    end
  endfunction

  function automatic logic [31:0] dfii_addr_pattern_tag(
    input logic [1:0] slot
  );
    logic [7:0] tag;
    begin
      tag = 8'h40 + {6'd0, slot};
      dfii_addr_pattern_tag = {tag, tag, tag, tag};
    end
  endfunction

  function automatic logic [31:0] dfii_pattern_word_for_mode(
    input logic [4:0] index,
    input logic [1:0] mode
  );
    logic [3:0] idx;
    logic [1:0] phase;
    begin
      idx = index[3:0];
      phase = index[3:2];
      unique case (mode)
        DFII_PATTERN_MODE_UNIFORM: begin
          dfii_pattern_word_for_mode = 32'ha55a_3cc3;
        end
        DFII_PATTERN_MODE_PHASE: begin
          dfii_pattern_word_for_mode = {
            2'd0, phase, 4'h8,
            2'd0, phase, 4'h4,
            2'd0, phase, 4'h2,
            2'd0, phase, 4'h1
          };
        end
        DFII_PATTERN_MODE_ASSOC: begin
          dfii_pattern_word_for_mode =
            (idx == dfii_assoc_index_q) ?
            dfii_assoc_signature(dfii_assoc_index_q) : 32'd0;
        end
        default: begin
          dfii_pattern_word_for_mode = {
            idx, 4'h8,
            idx, 4'h4,
            idx, 4'h2,
            idx, 4'h1
          };
        end
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_pattern_word(input logic [4:0] index);
    logic [3:0] idx;
    logic [1:0] phase;
    logic [7:0] tag;
    logic [31:0] base_pattern;
    begin
      idx = index[3:0];
      phase = index[3:2];
      unique case (dfii_active_pattern_mode)
        DFII_PATTERN_MODE_UNIFORM: begin
          base_pattern = 32'ha55a_3cc3;
        end
        DFII_PATTERN_MODE_PHASE: begin
          base_pattern = {
            2'd0, phase, 4'h8,
            2'd0, phase, 4'h4,
            2'd0, phase, 4'h2,
            2'd0, phase, 4'h1
          };
        end
        DFII_PATTERN_MODE_ASSOC: begin
          base_pattern = (idx == dfii_assoc_index_q) ?
            {4'ha, dfii_assoc_index_q,
             4'hb, dfii_assoc_index_q,
             4'hc, dfii_assoc_index_q,
             4'hd, dfii_assoc_index_q} :
            32'd0;
        end
        default: begin
          base_pattern = {
            idx, 4'h8,
            idx, 4'h4,
            idx, 4'h2,
            idx, 4'h1
          };
        end
      endcase
      tag = 8'h40 + {6'd0, dfii_addr_index_q};
      dfii_pattern_word =
        dfii_addr_sweep_q ?
        (base_pattern ^ {tag, tag, tag, tag}) :
        base_pattern;
    end
  endfunction

  function automatic logic [3:0] popcount8(input logic [7:0] value);
    begin
      popcount8 = 4'd0;
      for (int bit_idx = 0; bit_idx < 8; bit_idx++)
        popcount8 = popcount8 + {3'd0, value[bit_idx]};
    end
  endfunction

  function automatic logic [7:0] byte_from_word(
    input logic [31:0] value,
    input logic [1:0] byte_index
  );
    begin
      unique case (byte_index)
        2'd0: byte_from_word = value[7:0];
        2'd1: byte_from_word = value[15:8];
        2'd2: byte_from_word = value[23:16];
        default: byte_from_word = value[31:24];
      endcase
    end
  endfunction

  function automatic logic [7:0] dfii_pattern_byte(
    input logic [1:0] phase,
    input logic [3:0] byte_index
  );
    logic [4:0] word_index;
    begin
      word_index = {1'b0, phase, byte_index[3:2]};
      dfii_pattern_byte =
        byte_from_word(dfii_pattern_word(word_index), byte_index[1:0]);
    end
  endfunction

  function automatic logic [7:0] dfii_actual_byte(
    input logic [1:0] phase,
    input logic [3:0] byte_index
  );
    logic [3:0] word_index;
    begin
      word_index = {phase, byte_index[3:2]};
      dfii_actual_byte =
        byte_from_word(dfii_rddata_q[word_index], byte_index[1:0]);
    end
  endfunction

  assign cal_write_state = state_q == PROBE_CAL_RUN_WRITES;
  assign cal_read_state = state_q == PROBE_CAL_RUN_READS;
  assign phase_write_state = state_q == PROBE_PHASE_RUN_WRITES;
  assign phase_read_state = state_q == PROBE_PHASE_RUN_READS;
  assign phase_mode =
    state_q == PROBE_PHASE_CONFIG || phase_write_state ||
    state_q == PROBE_PHASE_WRITE_DRAIN || phase_read_state ||
    state_q == PROBE_PHASE_APPLY_BEST;
  assign phase_config_active =
    state_q == PROBE_PHASE_CONFIG || state_q == PROBE_PHASE_APPLY_BEST;
  assign phase_apply_state = state_q == PROBE_PHASE_APPLY_BEST;
  assign byte_diag_clear_state = state_q == PROBE_BYTE_CLEAR_WRITES;
  assign byte_diag_mask_state = state_q == PROBE_BYTE_MASK_WRITES;
  assign byte_diag_write_state = byte_diag_clear_state || byte_diag_mask_state;
  assign byte_diag_read_state = state_q == PROBE_BYTE_RUN_READS;
  assign byte_diag_mode =
    byte_diag_write_state || byte_diag_read_state ||
    state_q == PROBE_BYTE_WRITE_DRAIN;
  assign cal_config_active =
    phase_config_active ||
    state_q == PROBE_CAL_CONFIG || state_q == PROBE_CAL_APPLY_BEST ||
    state_q == PROBE_DFII_WBITSLIP_CONFIG;
  assign cal_apply_state = state_q == PROBE_CAL_APPLY_BEST;
  assign dfii_seq_running = state_q == PROBE_DFII_RUN;
  assign cal_mode =
    state_q == PROBE_CAL_CONFIG || state_q == PROBE_CAL_RUN_WRITES ||
    state_q == PROBE_CAL_WRITE_DRAIN || state_q == PROBE_CAL_RUN_READS ||
    state_q == PROBE_CAL_APPLY_BEST;
  assign write_state =
    state_q == PROBE_RUN_WRITES || cal_write_state || phase_write_state ||
    byte_diag_write_state;
  assign read_state =
    state_q == PROBE_RUN_READS || cal_read_state || phase_read_state ||
    byte_diag_read_state;
  assign active_target_words =
    cal_mode ? CAL_COUNT_WORDS :
    (phase_mode ? CAL_COUNT_WORDS :
    (byte_diag_mode ? BYTE_DIAG_WORDS : READ_COUNT_WORDS));
  assign active_write_drain_cycles =
    (cal_mode || phase_mode) ? CAL_WRITE_DRAIN_CYCLES : WRITE_DRAIN_CYCLES;
  assign read_target_issued = command_count_q >= active_target_words;
  assign read_target_seen = response_count_q >= active_target_words;
  assign write_data_target_seen = write_data_count_q >= active_target_words;
  assign write_command_target_seen = write_command_count_q >= active_target_words;
  assign write_drain_done = write_drain_count_q == 32'd0;
  assign outstanding_full =
    (command_count_q - response_count_q) >= 32'd64;
  assign timeout_seen = read_cycle_count_q[TIMEOUT_LOG2 - 1];
  assign cmd_valid =
    (write_state && !write_command_target_seen &&
     (write_command_count_q <= write_data_count_q)) ||
    (read_state && !read_target_issued && !outstanding_full);
  assign cmd_we = write_state;
  assign cmd_addr =
    byte_diag_mode ?
      (BYTE_DIAG_BASE_ADDR +
       (cmd_we ? write_command_count_q[24:0] : read_addr_q)) :
      (cmd_we ? write_command_count_q[24:0] : read_addr_q);
  assign wdata_valid =
    write_state && !write_data_target_seen &&
    (write_data_count_q <= write_command_count_q ||
     ((write_data_count_q - write_command_count_q) < WRITE_DATA_AHEAD_LIMIT));
  assign wdata =
    byte_diag_clear_state ? 576'd0 :
    (byte_diag_mask_state ?
      byte_diag_word(write_data_count_q[2:0]) :
      pattern_for_addr(write_data_count_q[24:0]));
  assign wdata_we =
    byte_diag_mask_state ? byte_diag_we_mask(write_data_count_q[2:0]) : {72{1'b1}};
  assign expected_rdata = pattern_for_addr(compare_addr_q);
  assign lane_response_mismatch =
    select_lane_burst(rdata, cal_lane_q) !=
    select_lane_burst(expected_rdata, cal_lane_q);
  assign response_mismatch =
    read_state && !byte_diag_read_state && rdata_valid &&
    (cal_read_state ? lane_response_mismatch : rdata != expected_rdata);
  for (genvar chunk_idx = 0; chunk_idx < 9; chunk_idx++) begin : gen_response_chunk_mismatch
    assign response_chunk_mismatch[chunk_idx] =
      rdata[chunk_idx * 64 +: 64] != expected_rdata[chunk_idx * 64 +: 64];
  end
  assign next_mismatch_count =
    mismatch_count_q + (response_mismatch ? 32'd1 : 32'd0);
  assign mismatch_seen = mismatch_count_q != 32'd0;
  assign phase_candidate_index = {phase_wr_q, phase_rd_q};
  assign phase_best_index = {phase_best_wr_next, phase_best_rd_next};
  assign phase_last_candidate = phase_candidate_index == 4'hf;
  assign phase_mismatch_next = next_mismatch_count;
  assign phase_candidate_better =
    phase_mismatch_next < phase_best_mismatch_count_q;
  assign phase_best_mismatch_next =
    phase_candidate_better ? phase_mismatch_next :
    phase_best_mismatch_count_q;
  assign phase_best_rd_next =
    phase_candidate_better ? phase_rd_q : phase_best_rd_q;
  assign phase_best_wr_next =
    phase_candidate_better ? phase_wr_q : phase_best_wr_q;
  assign cal_config_done = cal_config_state_q == CAL_CFG_DONE;
  assign cal_config_failed = cal_config_state_q == CAL_CFG_ERROR;
  assign dfii_wrdata_index = dfii_step_q[4:0] - 5'd2;
  assign dfii_wrdata_write_index = {
    1'b0,
    dfii_wrdata_index[3:2],
    2'd3 - dfii_wrdata_index[1:0]
  };
  assign dfii_rddata_index = dfii_step_q[4:0] - 5'd6;
  assign dfii_wrdata_index20 = dfii_step_q[4:0] - 5'd2;
  assign dfii_rddata_index20 = dfii_step_q[4:0] - 5'd10;
  assign dfii_csr_echo_read_index20 = dfii_step_q[4:0] - 5'd22;
  assign dfii_wbitslip_sweep_mode =
    DFII_WBITSLIP_SWEEP_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_rbitslip_sweep_mode =
    DFII_RBITSLIP_SWEEP_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_edge_map_probe_mode =
    DFII_EDGE_MAP_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_edge_comp_probe_mode =
    DFII_EDGE_COMP_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_edge_lane7_locator_probe_mode =
    DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_bitslip_sweep_mode =
    dfii_wbitslip_sweep_mode || dfii_rbitslip_sweep_mode;
  assign dfii_wide_word_mode =
    dfii_half_order_matrix_mode || dfii_displacement_probe_mode ||
    dfii_csr_echo_probe_mode || dfii_edge_map_probe_mode ||
    dfii_edge_comp_probe_mode || dfii_edge_lane7_locator_probe_mode;
  assign dfii_read_store_index =
    dfii_csr_echo_probe_mode ? dfii_csr_echo_read_index20 :
    (dfii_wide_word_mode ? dfii_rddata_index20 : dfii_rddata_index);
  assign dfii_seq_done_step =
    dfii_csr_echo_probe_mode ? 8'd43 :
    (dfii_wide_word_mode ? 8'd63 : 8'd55);
  assign dfii_active_pattern_mode =
    dfii_assoc_sweep_q ? DFII_PATTERN_MODE_ASSOC :
    dfii_addr_sweep_q ? DFII_PATTERN_MODE_RAMP :
    dfii_final_q ? dfii_pattern_mode_q : DFII_PATTERN_MODE_RAMP;
  assign dfii_phase_matrix_mode =
    (DFII_PHASE_MATRIX_ONLY || DFII_SOURCE_COMMAND_MATRIX_ONLY ||
     DFII_SOURCE_ORDER_MATRIX_ONLY || DFII_HALF_ORDER_MATRIX_ONLY ||
     DFII_DISPLACEMENT_PROBE_ONLY || DFII_WBITSLIP_SWEEP_ONLY ||
     DFII_RBITSLIP_SWEEP_ONLY) &&
    dfii_phasecmd_sweep_q;
  assign dfii_source_command_matrix_mode =
    DFII_SOURCE_COMMAND_MATRIX_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_source_order_matrix_mode =
    DFII_SOURCE_ORDER_MATRIX_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_half_order_matrix_mode =
    DFII_HALF_ORDER_MATRIX_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_displacement_probe_mode =
    (DFII_DISPLACEMENT_PROBE_ONLY || DFII_WBITSLIP_SWEEP_ONLY ||
     DFII_RBITSLIP_SWEEP_ONLY) &&
    dfii_phasecmd_sweep_q;
  assign dfii_csr_echo_probe_mode =
    DFII_CSR_ECHO_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_matrix_source_phase =
    (dfii_source_order_matrix_mode || dfii_half_order_matrix_mode ||
     dfii_displacement_probe_mode || dfii_csr_echo_probe_mode ||
     dfii_edge_map_probe_mode || dfii_edge_comp_probe_mode ||
     dfii_edge_lane7_locator_probe_mode ||
     dfii_bitslip_sweep_mode) ?
    DFII_SOURCE_ORDER_SOURCE_PHASE[1:0] : dfii_phasecmd_index_q[3:2];
  assign dfii_result_slot =
    DFII_WBITSLIP_SWEEP_ONLY ? {1'b0, cal_wbitslip_q} :
    DFII_RBITSLIP_SWEEP_ONLY ? {1'b0, cal_bitslip_q} :
    dfii_phasecmd_index_q;
  assign dfii_source_order_tag =
    dfii_source_order_tag_byte(dfii_phasecmd_index_q);
  assign dfii_half_low_tag =
    dfii_half_order_low_tag_byte(dfii_phasecmd_index_q);
  assign dfii_half_high_tag =
    dfii_half_order_high_tag_byte(dfii_phasecmd_index_q);
  assign dfii_write_command_phase =
    dfii_source_command_matrix_mode ? dfii_phasecmd_index_q[1:0] :
    (dfii_source_order_matrix_mode || dfii_half_order_matrix_mode ||
     dfii_displacement_probe_mode || dfii_csr_echo_probe_mode ||
     dfii_edge_map_probe_mode || dfii_edge_comp_probe_mode ||
     dfii_edge_lane7_locator_probe_mode ||
     dfii_bitslip_sweep_mode) ?
    DFII_SOURCE_ORDER_WRITE_PHASE[1:0] :
    dfii_phasecmd_sweep_q ? dfii_phasecmd_index_q[3:2] : 2'd3;
  assign dfii_read_command_phase =
    dfii_source_command_matrix_mode ?
    DFII_SOURCE_COMMAND_READ_PHASE[1:0] :
    (dfii_source_order_matrix_mode || dfii_half_order_matrix_mode ||
     dfii_displacement_probe_mode || dfii_csr_echo_probe_mode ||
     dfii_edge_map_probe_mode || dfii_edge_comp_probe_mode ||
     dfii_edge_lane7_locator_probe_mode ||
     dfii_bitslip_sweep_mode) ?
    DFII_SOURCE_ORDER_READ_PHASE[1:0] :
    dfii_phasecmd_sweep_q ? dfii_phasecmd_index_q[1:0] : 2'd2;
  assign cal_last_candidate =
    cal_wbitslip_q == 3'd7 && cal_bitslip_q == 3'd7 &&
    cal_delay_q == 5'd31;
  assign cal_lane_last = cal_lane_q == 3'd7;
  always_comb begin
    cal_candidate_min_mismatch = 32'hffff_ffff;
    cal_candidate_min_byte = 3'd0;
    for (int byte_idx = 0; byte_idx < CAL_BYTE_LANES; byte_idx++) begin
      byte_response_mismatch[byte_idx] =
        select_lane_burst(rdata, byte_idx[2:0]) !=
        select_lane_burst(expected_rdata, byte_idx[2:0]);
      cal_byte_mismatch_next[byte_idx] =
        cal_byte_mismatch_count_q[byte_idx] +
        ((cal_read_state && rdata_valid && byte_response_mismatch[byte_idx]) ?
         32'd1 : 32'd0);
      if (cal_byte_mismatch_next[byte_idx] < cal_candidate_min_mismatch) begin
        cal_candidate_min_mismatch = cal_byte_mismatch_next[byte_idx];
        cal_candidate_min_byte = byte_idx[2:0];
      end
    end
  end

  always_comb begin
    dfii_candidate_error_count = 32'd0;
    for (int phase_idx = 0; phase_idx < 4; phase_idx++) begin
      dfii_candidate_error_count = dfii_candidate_error_count + {
        28'd0,
        popcount8(
          dfii_pattern_byte(phase_idx[1:0], {1'b0, cal_lane_q}) ^
          dfii_actual_byte(phase_idx[1:0], {1'b0, cal_lane_q})
        )
      };
      dfii_candidate_error_count = dfii_candidate_error_count + {
        28'd0,
        popcount8(
          dfii_pattern_byte(phase_idx[1:0], {1'b1, cal_lane_q}) ^
          dfii_actual_byte(phase_idx[1:0], {1'b1, cal_lane_q})
        )
      };
    end
  end

  always_comb begin
    dfii_assoc_nonzero_mask_next = 16'd0;
    dfii_assoc_match_mask_next = 16'd0;
    dfii_phase_matrix_nonzero_mask_next = 16'd0;
    dfii_phase_matrix_match_mask_next = 16'd0;
    dfii_half_nonzero_mask_next = '0;
    dfii_half_low_match_mask_next = '0;
    dfii_half_high_match_mask_next = '0;
    dfii_addr_nonzero_mask_next = 16'd0;
    dfii_addr_match_mask_next = 16'd0;
    for (int assoc_read_idx = 0; assoc_read_idx < 16; assoc_read_idx++) begin
      if (dfii_rddata_q[assoc_read_idx] != 32'd0)
        dfii_assoc_nonzero_mask_next[assoc_read_idx] = 1'b1;
      if (dfii_rddata_q[assoc_read_idx] ==
          dfii_assoc_signature(dfii_assoc_index_q))
        dfii_assoc_match_mask_next[assoc_read_idx] = 1'b1;
      if (dfii_rddata_q[assoc_read_idx] != 32'd0)
        dfii_addr_nonzero_mask_next[assoc_read_idx] = 1'b1;
      if (dfii_rddata_q[assoc_read_idx] == dfii_pattern_word(assoc_read_idx[4:0]))
        dfii_addr_match_mask_next[assoc_read_idx] = 1'b1;
      if (dfii_rddata_q[assoc_read_idx] != 32'd0)
        dfii_phase_matrix_nonzero_mask_next[assoc_read_idx] = 1'b1;
      if (dfii_source_order_matrix_mode) begin
        if (dfii_word_has_tag(dfii_rddata_q[assoc_read_idx],
                              dfii_source_order_tag))
          dfii_phase_matrix_match_mask_next[assoc_read_idx] = 1'b1;
      end else if (dfii_rddata_q[assoc_read_idx] ==
          dfii_phase_source_pattern(
            dfii_matrix_source_phase,
            assoc_read_idx[1:0]
          )) begin
        dfii_phase_matrix_match_mask_next[assoc_read_idx] = 1'b1;
      end
    end
    for (int half_read_idx = 0;
         half_read_idx < DFII_RDDATA_WORDS;
         half_read_idx++) begin
      if (dfii_rddata_q[half_read_idx] != 32'd0)
        dfii_half_nonzero_mask_next[half_read_idx] = 1'b1;
      if (dfii_word_has_tag(dfii_rddata_q[half_read_idx], dfii_half_low_tag))
        dfii_half_low_match_mask_next[half_read_idx] = 1'b1;
      if (dfii_word_has_tag(dfii_rddata_q[half_read_idx], dfii_half_high_tag))
        dfii_half_high_match_mask_next[half_read_idx] = 1'b1;
    end
  end

  always_comb begin
    dfii_addr_column_payload = 64'd0;
    dfii_addr_mismatch_payload = 64'd0;
    dfii_addr_nonzero_payload = 64'd0;
    dfii_addr_match_payload = 64'd0;
    for (int addr_idx = 0; addr_idx < DFII_ADDR_SLOTS; addr_idx++) begin
      dfii_addr_column_payload[addr_idx * 16 +: 16] =
        dfii_addr_column16(addr_idx[1:0]);
      dfii_addr_mismatch_payload[addr_idx * 16 +: 16] =
        dfii_addr_mismatch_mask_q[addr_idx];
      dfii_addr_nonzero_payload[addr_idx * 16 +: 16] =
        dfii_addr_nonzero_mask_q[addr_idx];
      dfii_addr_match_payload[addr_idx * 16 +: 16] =
        dfii_addr_match_mask_q[addr_idx];
    end
  end

  always_comb begin
    dfii_half_nonzero_high_payload = 64'd0;
    dfii_half_low_match_high_payload = 64'd0;
    dfii_half_high_match_low_payload = 256'd0;
    dfii_half_high_match_high_payload = 64'd0;
    for (int half_idx = 0; half_idx < 16; half_idx++) begin
      dfii_half_nonzero_high_payload[half_idx * 4 +: 4] =
        dfii_half_nonzero_high_q[half_idx];
      dfii_half_low_match_high_payload[half_idx * 4 +: 4] =
        dfii_half_low_match_high_q[half_idx];
      dfii_half_high_match_low_payload[half_idx * 16 +: 16] =
        dfii_half_high_match_low_q[half_idx];
      dfii_half_high_match_high_payload[half_idx * 4 +: 4] =
        dfii_half_high_match_high_q[half_idx];
    end
  end

  assign cal_candidate_score =
    dfii_seq_running ? dfii_candidate_error_count : cal_candidate_min_mismatch;
  assign cal_candidate_success = cal_candidate_score == 32'd0;
  assign cal_candidate_better =
    cal_candidate_score < lane_best_mismatch_count_q[cal_lane_q];
  assign lane_best_mismatch_next =
    cal_candidate_better ? cal_candidate_score :
    lane_best_mismatch_count_q[cal_lane_q];
  assign lane_best_bitslip_next =
    cal_candidate_better ? cal_bitslip_q :
    lane_best_bitslip_q[cal_lane_q];
  assign lane_best_wbitslip_next =
    cal_candidate_better ? cal_wbitslip_q :
    lane_best_wbitslip_q[cal_lane_q];
  assign lane_best_delay_next =
    cal_candidate_better ? cal_delay_q :
    lane_best_delay_q[cal_lane_q];
  assign lane_best_logical_byte_next =
    cal_candidate_better ?
    (dfii_seq_running ? cal_lane_q : cal_candidate_min_byte) :
    lane_best_logical_byte_q[cal_lane_q];
  assign cal_config_bitslip =
    cal_apply_state ? selected_bitslip_q : cal_bitslip_q;
  assign cal_config_wbitslip =
    cal_apply_state ? selected_wbitslip_q : cal_wbitslip_q;
  assign cal_config_delay =
    cal_apply_state ? selected_delay_q : cal_delay_q;
  assign cal_config_lane_mask =
    (DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY) ?
    32'h0000_01ff : (32'd1 << cal_lane_q);
  assign init_seq_done = init_state_q == INIT_DONE;
  assign init_seq_running =
    init_state_q != INIT_RESET && init_state_q != INIT_DONE &&
    init_state_q != INIT_ERROR;

  assign wb_ctrl_cyc_mux =
    init_seq_running ? wb_ctrl_cyc_q :
    (dfii_seq_running ? dfii_wb_ctrl_cyc_q : cal_wb_ctrl_cyc_q);
  assign wb_ctrl_stb_mux =
    init_seq_running ? wb_ctrl_stb_q :
    (dfii_seq_running ? dfii_wb_ctrl_stb_q : cal_wb_ctrl_stb_q);
  assign wb_ctrl_we_mux =
    init_seq_running ? wb_ctrl_we_q :
    (dfii_seq_running ? dfii_wb_ctrl_we_q : cal_wb_ctrl_we_q);
  assign wb_ctrl_adr_mux =
    init_seq_running ? wb_ctrl_adr_q :
    (dfii_seq_running ? dfii_wb_ctrl_adr_q : cal_wb_ctrl_adr_q);
  assign wb_ctrl_dat_w_mux =
    init_seq_running ? wb_ctrl_dat_w_q :
    (dfii_seq_running ? dfii_wb_ctrl_dat_w_q : cal_wb_ctrl_dat_w_q);

  always_comb begin
    init_step_is_delay = 1'b0;
    init_step_wb_addr = WB_ADDR_INIT_DONE;
    init_step_wb_data = 32'd0;
    init_step_delay = 32'd0;

    unique case (init_step_q)
      8'd0: begin
        init_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        init_step_wb_data = 32'h0000_0000;
      end
      8'd1: begin
        init_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        init_step_wb_data = 32'h0000_0000;
      end
      8'd2: begin
        init_step_wb_addr = WB_ADDR_DFII_CONTROL;
        init_step_wb_data = DFII_CONTROL_SOFTWARE_RESET_RELEASE;
      end
      8'd3: begin
        init_step_is_delay = 1'b1;
        init_step_delay = 32'd50_000;
      end
      8'd4: begin
        init_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        init_step_wb_data = 32'h0000_0000;
      end
      8'd5: begin
        init_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        init_step_wb_data = 32'h0000_0000;
      end
      8'd6: begin
        init_step_wb_addr = WB_ADDR_DFII_CONTROL;
        init_step_wb_data = DFII_CONTROL_SOFTWARE_CKE;
      end
      8'd7: begin
        init_step_is_delay = 1'b1;
        init_step_delay = 32'd10_000;
      end
      8'd8: begin
        init_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        init_step_wb_data = 32'h0000_0200;
      end
      8'd9: begin
        init_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        init_step_wb_data = 32'h0000_0002;
      end
      8'd10: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND;
        init_step_wb_data = DFII_COMMAND_MRS;
      end
      8'd11: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        init_step_wb_data = 32'h0000_0001;
      end
      8'd12: begin
        init_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        init_step_wb_data = 32'h0000_0000;
      end
      8'd13: begin
        init_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        init_step_wb_data = 32'h0000_0003;
      end
      8'd14: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND;
        init_step_wb_data = DFII_COMMAND_MRS;
      end
      8'd15: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        init_step_wb_data = 32'h0000_0001;
      end
      8'd16: begin
        init_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        init_step_wb_data = 32'h0000_0006;
      end
      8'd17: begin
        init_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        init_step_wb_data = 32'h0000_0001;
      end
      8'd18: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND;
        init_step_wb_data = DFII_COMMAND_MRS;
      end
      8'd19: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        init_step_wb_data = 32'h0000_0001;
      end
      8'd20: begin
        init_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        init_step_wb_data = 32'h0000_0930;
      end
      8'd21: begin
        init_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        init_step_wb_data = 32'h0000_0000;
      end
      8'd22: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND;
        init_step_wb_data = DFII_COMMAND_MRS;
      end
      8'd23: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        init_step_wb_data = 32'h0000_0001;
      end
      8'd24: begin
        init_step_is_delay = 1'b1;
        init_step_delay = 32'd200;
      end
      8'd25: begin
        init_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        init_step_wb_data = 32'h0000_0400;
      end
      8'd26: begin
        init_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        init_step_wb_data = 32'h0000_0000;
      end
      8'd27: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND;
        init_step_wb_data = DFII_COMMAND_ZQ;
      end
      8'd28: begin
        init_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        init_step_wb_data = 32'h0000_0001;
      end
      8'd29: begin
        init_step_is_delay = 1'b1;
        init_step_delay = 32'd200;
      end
      8'd30: begin
        init_step_wb_addr = WB_ADDR_DFII_CONTROL;
        init_step_wb_data = DFII_CONTROL_HARDWARE;
      end
      8'd31: begin
        init_step_wb_addr = WB_ADDR_INIT_DONE;
        init_step_wb_data = 32'h0000_0001;
      end
      default: begin
        init_step_wb_addr = WB_ADDR_INIT_DONE;
        init_step_wb_data = 32'd0;
      end
    endcase
  end

  always_comb begin
    cal_step_wb_addr = WB_ADDR_DDRPHY_DLY_SEL;
    cal_step_wb_data = 32'd0;

    if (phase_config_active) begin
      unique case (cal_config_step_q)
        8'd0: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_RDPHASE;
          cal_step_wb_data = {30'd0, phase_apply_state ? phase_best_rd_q : phase_rd_q};
        end
        8'd1: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_WRPHASE;
          cal_step_wb_data = {30'd0, phase_apply_state ? phase_best_wr_q : phase_wr_q};
        end
        default: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_WRPHASE;
          cal_step_wb_data = {30'd0, phase_apply_state ? phase_best_wr_q : phase_wr_q};
        end
      endcase
    end else begin
      unique case (cal_config_step_q)
        8'd0: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_DLY_SEL;
          cal_step_wb_data = cal_config_lane_mask;
        end
        8'd1: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_RDLY_DQ_RST;
          cal_step_wb_data = 32'h0000_0001;
        end
        8'd2: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_RDLY_DQ_BITSLIP_RST;
          cal_step_wb_data = 32'h0000_0001;
        end
        8'd3: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_WDLY_DQ_BITSLIP_RST;
          cal_step_wb_data = 32'h0000_0001;
        end
        8'd4: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_RDLY_DQ_INC;
          cal_step_wb_data = 32'h0000_0001;
        end
        8'd5: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_RDLY_DQ_BITSLIP;
          cal_step_wb_data = 32'h0000_0001;
        end
        8'd6: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_WDLY_DQ_BITSLIP;
          cal_step_wb_data = 32'h0000_0001;
        end
        8'd7: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_DLY_SEL;
          cal_step_wb_data = 32'h0000_0000;
        end
        default: begin
          cal_step_wb_addr = WB_ADDR_DDRPHY_DLY_SEL;
          cal_step_wb_data = 32'h0000_0000;
        end
      endcase
    end
  end

  always_comb begin
    dfii_step_is_delay = 1'b0;
    dfii_step_is_read = 1'b0;
    dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
    dfii_step_wb_data = 32'd0;
    dfii_step_delay = 32'd0;

    if (dfii_csr_echo_probe_mode) begin
      if (dfii_step_q == 8'd0) begin
        dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
        dfii_step_wb_data = DFII_CONTROL_SOFTWARE_CKE;
      end else if (dfii_step_q == 8'd1) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_000;
      end else if (dfii_step_q >= 8'd2 && dfii_step_q <= 8'd21) begin
        dfii_step_wb_addr = dfii_pi_wrdata_addr5(
          dfii_index20_phase(dfii_wrdata_index20),
          dfii_index20_word(dfii_wrdata_index20)
        );
        dfii_step_wb_data = dfii_csr_echo_word(
          dfii_index20_phase(dfii_wrdata_index20),
          dfii_index20_word(dfii_wrdata_index20)
        );
      end else if (dfii_step_q >= 8'd22 && dfii_step_q <= 8'd41) begin
        dfii_step_is_read = 1'b1;
        dfii_step_wb_addr = dfii_pi_wrdata_addr5(
          dfii_index20_phase(dfii_csr_echo_read_index20),
          dfii_index20_word(dfii_csr_echo_read_index20)
        );
      end else if (dfii_step_q == 8'd42) begin
        dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
        dfii_step_wb_data = DFII_CONTROL_HARDWARE;
      end
    end else if (dfii_wide_word_mode) begin
      if (dfii_step_q == 8'd0) begin
        dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
        dfii_step_wb_data = DFII_CONTROL_SOFTWARE_CKE;
      end else if (dfii_step_q == 8'd1) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_000;
      end else if (dfii_step_q >= 8'd2 && dfii_step_q <= 8'd21) begin
        dfii_step_wb_addr = dfii_pi_wrdata_addr5(
          dfii_index20_phase(dfii_wrdata_index20),
          dfii_index20_word(dfii_wrdata_index20)
        );
        dfii_step_wb_data =
          dfii_edge_lane7_locator_probe_mode ?
          dfii_lane7_locator_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20)
          ) :
          dfii_edge_comp_probe_mode ?
          dfii_edge_comp_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20),
            dfii_phasecmd_index_q[1:0]
          ) :
          dfii_edge_map_probe_mode ?
          dfii_edge_map_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20)
          ) :
          (dfii_index20_phase(dfii_wrdata_index20) ==
           dfii_matrix_source_phase) ?
          (dfii_displacement_probe_mode ?
           dfii_displacement_word(dfii_index20_word(dfii_wrdata_index20)) :
           dfii_half_order_word(
             dfii_phasecmd_index_q,
             dfii_index20_word(dfii_wrdata_index20)
           )) : 32'd0;
      end else if (dfii_step_q == 8'd22) begin
        dfii_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == 8'd23) begin
        dfii_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == 8'd24) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND;
        dfii_step_wb_data = DFII_COMMAND_RAS | DFII_COMMAND_CS;
      end else if (dfii_step_q == 8'd25) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        dfii_step_wb_data = 32'd1;
      end else if (dfii_step_q == 8'd26) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q == 8'd27) begin
        dfii_step_wb_addr = dfii_pi_address_addr(dfii_write_command_phase);
        dfii_step_wb_data =
          dfii_edge_comp_probe_mode ?
          dfii_addr_column(dfii_phasecmd_index_q[1:0]) :
          32'd0;
      end else if (dfii_step_q == 8'd28) begin
        dfii_step_wb_addr = dfii_pi_baddress_addr(dfii_write_command_phase);
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == 8'd29) begin
        dfii_step_wb_addr = dfii_pi_command_addr(dfii_write_command_phase);
        dfii_step_wb_data =
          DFII_DISABLE_WRITE_COMMAND ? 32'd0 :
          (DFII_COMMAND_CAS | DFII_COMMAND_WE | DFII_COMMAND_CS |
           DFII_COMMAND_WRDATA);
      end else if (dfii_step_q == 8'd30) begin
        dfii_step_wb_addr =
          dfii_pi_command_issue_addr(dfii_write_command_phase);
        dfii_step_wb_data = DFII_DISABLE_WRITE_COMMAND ? 32'd0 : 32'd1;
      end else if (dfii_step_q == 8'd31) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q == 8'd32) begin
        dfii_step_wb_addr = dfii_pi_address_addr(dfii_read_command_phase);
        dfii_step_wb_data =
          dfii_edge_comp_probe_mode ?
          dfii_addr_column(dfii_phasecmd_index_q[1:0]) :
          32'd0;
      end else if (dfii_step_q == 8'd33) begin
        dfii_step_wb_addr = dfii_pi_baddress_addr(dfii_read_command_phase);
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == 8'd34) begin
        dfii_step_wb_addr = dfii_pi_command_addr(dfii_read_command_phase);
        dfii_step_wb_data =
          DFII_COMMAND_CAS | DFII_COMMAND_CS | DFII_COMMAND_RDDATA;
      end else if (dfii_step_q == 8'd35) begin
        dfii_step_wb_addr =
          dfii_pi_command_issue_addr(dfii_read_command_phase);
        dfii_step_wb_data = 32'd1;
      end else if (dfii_step_q == 8'd36) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q == 8'd37) begin
        dfii_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == 8'd38) begin
        dfii_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == 8'd39) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND;
        dfii_step_wb_data =
          DFII_COMMAND_RAS | DFII_COMMAND_WE | DFII_COMMAND_CS;
      end else if (dfii_step_q == 8'd40) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        dfii_step_wb_data = 32'd1;
      end else if (dfii_step_q == 8'd41) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q >= 8'd42 && dfii_step_q <= 8'd61) begin
        dfii_step_is_read = 1'b1;
        dfii_step_wb_addr = dfii_pi_rddata_addr5(
          dfii_index20_phase(dfii_rddata_index20),
          dfii_index20_word(dfii_rddata_index20)
        );
      end else if (dfii_step_q == 8'd62) begin
        dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
        dfii_step_wb_data = DFII_CONTROL_HARDWARE;
      end
    end else begin
      unique case (dfii_step_q)
        8'd0: begin
          dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
          dfii_step_wb_data = DFII_CONTROL_SOFTWARE_CKE;
        end
        8'd1: begin
          dfii_step_is_delay = 1'b1;
          dfii_step_delay = 32'd1_000;
        end
        8'd2, 8'd3, 8'd4, 8'd5,
        8'd6, 8'd7, 8'd8, 8'd9,
        8'd10, 8'd11, 8'd12, 8'd13,
        8'd14, 8'd15, 8'd16, 8'd17: begin
          dfii_step_wb_addr = dfii_pi_wrdata_addr(
            dfii_wrdata_write_index[3:2],
            dfii_wrdata_write_index[1:0]
          );
          dfii_step_wb_data =
            dfii_source_order_matrix_mode ?
            ((dfii_wrdata_write_index[3:2] == dfii_matrix_source_phase) ?
             dfii_source_order_word(
               dfii_phasecmd_index_q,
               dfii_wrdata_write_index[1:0]
             ) : 32'd0) :
            dfii_phase_matrix_mode ?
            ((dfii_wrdata_write_index[3:2] == dfii_matrix_source_phase) ?
             dfii_phase_source_pattern(
               dfii_matrix_source_phase,
               dfii_wrdata_write_index[1:0]
             ) : 32'd0) :
            dfii_pattern_word(dfii_wrdata_write_index);
        end
        8'd18: begin
          dfii_step_wb_addr = WB_ADDR_PI0_ADDRESS;
          dfii_step_wb_data = 32'd0;
        end
        8'd19: begin
          dfii_step_wb_addr = WB_ADDR_PI0_BADDRESS;
          dfii_step_wb_data = 32'd0;
        end
        8'd20: begin
          dfii_step_wb_addr = WB_ADDR_PI0_COMMAND;
          dfii_step_wb_data = DFII_COMMAND_RAS | DFII_COMMAND_CS;
        end
        8'd21: begin
          dfii_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
          dfii_step_wb_data = 32'd1;
        end
        8'd22: begin
          dfii_step_is_delay = 1'b1;
          dfii_step_delay = 32'd1_500;
        end
        8'd23: begin
          dfii_step_wb_addr = dfii_pi_address_addr(dfii_write_command_phase);
          dfii_step_wb_data =
            dfii_addr_sweep_q ? dfii_addr_column(dfii_addr_index_q) : 32'd0;
        end
        8'd24: begin
          dfii_step_wb_addr = dfii_pi_baddress_addr(dfii_write_command_phase);
          dfii_step_wb_data = 32'd0;
        end
        8'd25: begin
          dfii_step_wb_addr = dfii_pi_command_addr(dfii_write_command_phase);
          dfii_step_wb_data =
            DFII_DISABLE_WRITE_COMMAND ? 32'd0 :
            (DFII_COMMAND_CAS | DFII_COMMAND_WE | DFII_COMMAND_CS |
             DFII_COMMAND_WRDATA);
        end
        8'd26: begin
          dfii_step_wb_addr =
            dfii_pi_command_issue_addr(dfii_write_command_phase);
          dfii_step_wb_data = DFII_DISABLE_WRITE_COMMAND ? 32'd0 : 32'd1;
        end
        8'd27: begin
          dfii_step_is_delay = 1'b1;
          dfii_step_delay = 32'd1_500;
        end
        8'd28: begin
          dfii_step_wb_addr = dfii_pi_address_addr(dfii_read_command_phase);
          dfii_step_wb_data =
            dfii_addr_sweep_q ? dfii_addr_column(dfii_addr_index_q) : 32'd0;
        end
        8'd29: begin
          dfii_step_wb_addr = dfii_pi_baddress_addr(dfii_read_command_phase);
          dfii_step_wb_data = 32'd0;
        end
        8'd30: begin
          dfii_step_wb_addr = dfii_pi_command_addr(dfii_read_command_phase);
          dfii_step_wb_data =
            DFII_COMMAND_CAS | DFII_COMMAND_CS | DFII_COMMAND_RDDATA;
        end
        8'd31: begin
          dfii_step_wb_addr =
            dfii_pi_command_issue_addr(dfii_read_command_phase);
          dfii_step_wb_data = 32'd1;
        end
        8'd32: begin
          dfii_step_is_delay = 1'b1;
          dfii_step_delay = 32'd1_500;
        end
        8'd33: begin
          dfii_step_wb_addr = WB_ADDR_PI0_ADDRESS;
          dfii_step_wb_data = 32'd0;
        end
        8'd34: begin
          dfii_step_wb_addr = WB_ADDR_PI0_BADDRESS;
          dfii_step_wb_data = 32'd0;
        end
        8'd35: begin
          dfii_step_wb_addr = WB_ADDR_PI0_COMMAND;
          dfii_step_wb_data =
            DFII_COMMAND_RAS | DFII_COMMAND_WE | DFII_COMMAND_CS;
        end
        8'd36: begin
          dfii_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
          dfii_step_wb_data = 32'd1;
        end
        8'd37: begin
          dfii_step_is_delay = 1'b1;
          dfii_step_delay = 32'd1_500;
        end
        8'd38, 8'd39, 8'd40, 8'd41,
        8'd42, 8'd43, 8'd44, 8'd45,
        8'd46, 8'd47, 8'd48, 8'd49,
        8'd50, 8'd51, 8'd52, 8'd53: begin
          dfii_step_is_read = 1'b1;
          dfii_step_wb_addr = dfii_pi_rddata_addr(
            dfii_rddata_index[3:2],
            dfii_rddata_index[1:0]
          );
        end
        8'd54: begin
          dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
          dfii_step_wb_data = DFII_CONTROL_HARDWARE;
        end
        default: begin
          dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
          dfii_step_wb_data = 32'd0;
        end
      endcase
    end
  end

  always_ff @(posedge user_clk) begin
    if (user_rst || core_rst) begin
      init_state_q <= INIT_RESET;
      init_step_q <= 8'd0;
      init_delay_q <= 32'd0;
      wb_ack_count_q <= 32'd0;
      wb_wait_count_q <= 32'd0;
      wb_timeout_count_q <= '0;
      last_wb_addr_q <= 16'd0;
      last_wb_data_q <= 32'd0;
      init_seq_error_q <= 1'b0;
      wb_error_seen_q <= 1'b0;
      wb_timeout_seen_q <= 1'b0;
      wb_ctrl_cyc_q <= 1'b0;
      wb_ctrl_stb_q <= 1'b0;
      wb_ctrl_we_q <= 1'b0;
      wb_ctrl_adr_q <= 30'd0;
      wb_ctrl_dat_w_q <= 32'd0;
    end else begin
      unique case (init_state_q)
        INIT_RESET: begin
          if (SYS_RSTN && config_reset_done && pll_locked) begin
            init_delay_q <= 32'd100_000;
            init_state_q <= INIT_START_WAIT;
          end
        end
        INIT_START_WAIT: begin
          if (init_delay_q == 32'd0)
            init_state_q <= INIT_RUN_STEP;
          else
            init_delay_q <= init_delay_q - 32'd1;
        end
        INIT_RUN_STEP: begin
          wb_timeout_count_q <= '0;
          wb_ctrl_cyc_q <= 1'b0;
          wb_ctrl_stb_q <= 1'b0;
          wb_ctrl_we_q <= 1'b0;

          if (init_step_q >= INIT_STEP_DONE_MARKER) begin
            init_state_q <= INIT_DONE;
          end else if (init_step_is_delay) begin
            init_delay_q <= init_step_delay;
            init_state_q <= INIT_DELAY;
          end else begin
            wb_ctrl_adr_q <= init_step_wb_addr;
            wb_ctrl_dat_w_q <= init_step_wb_data;
            last_wb_addr_q <= init_step_wb_addr[15:0];
            last_wb_data_q <= init_step_wb_data;
            wb_ctrl_cyc_q <= 1'b1;
            wb_ctrl_stb_q <= 1'b1;
            wb_ctrl_we_q <= 1'b1;
            init_state_q <= INIT_WB_WAIT;
          end
        end
        INIT_WB_WAIT: begin
          wb_wait_count_q <= wb_wait_count_q + 32'd1;
          if (wb_ctrl_ack) begin
            wb_ctrl_cyc_q <= 1'b0;
            wb_ctrl_stb_q <= 1'b0;
            wb_ctrl_we_q <= 1'b0;
            wb_ack_count_q <= wb_ack_count_q + 32'd1;
            if (wb_ctrl_err) begin
              wb_error_seen_q <= 1'b1;
              init_seq_error_q <= 1'b1;
              init_state_q <= INIT_ERROR;
            end else begin
              init_step_q <= init_step_q + 8'd1;
              init_state_q <= INIT_RUN_STEP;
            end
          end else begin
            wb_timeout_count_q <= wb_timeout_count_q + 1'b1;
            if (wb_timeout_count_q[WB_TIMEOUT_LOG2 - 1]) begin
              wb_ctrl_cyc_q <= 1'b0;
              wb_ctrl_stb_q <= 1'b0;
              wb_ctrl_we_q <= 1'b0;
              wb_timeout_seen_q <= 1'b1;
              init_seq_error_q <= 1'b1;
              init_state_q <= INIT_ERROR;
            end
          end
        end
        INIT_DELAY: begin
          if (init_delay_q == 32'd0) begin
            init_step_q <= init_step_q + 8'd1;
            init_state_q <= INIT_RUN_STEP;
          end else begin
            init_delay_q <= init_delay_q - 32'd1;
          end
        end
        INIT_DONE: begin
          init_state_q <= INIT_DONE;
        end
        INIT_ERROR: begin
          init_seq_error_q <= 1'b1;
          init_state_q <= INIT_ERROR;
        end
        default: begin
          init_seq_error_q <= 1'b1;
          init_state_q <= INIT_ERROR;
        end
      endcase
    end
  end

  always_ff @(posedge user_clk) begin
    if (user_rst || core_rst) begin
      dfii_seq_state_q <= DFII_SEQ_IDLE;
      dfii_step_q <= 8'd0;
      dfii_delay_q <= 32'd0;
      dfii_wb_timeout_count_q <= '0;
      dfii_wb_ack_count_q <= 32'd0;
      dfii_wb_wait_count_q <= 32'd0;
      dfii_last_wb_addr_q <= 16'd0;
      dfii_last_wb_data_q <= 32'd0;
      dfii_last_read_data_q <= 32'd0;
      dfii_wb_error_seen_q <= 1'b0;
      dfii_wb_timeout_seen_q <= 1'b0;
      dfii_failed_q <= 1'b0;
      dfii_done_q <= 1'b0;
      dfii_word_mismatch_q <= '0;
      dfii_wb_ctrl_cyc_q <= 1'b0;
      dfii_wb_ctrl_stb_q <= 1'b0;
      dfii_wb_ctrl_we_q <= 1'b0;
      dfii_wb_ctrl_adr_q <= 30'd0;
      dfii_wb_ctrl_dat_w_q <= 32'd0;
      for (int dfii_idx = 0; dfii_idx < DFII_RDDATA_WORDS; dfii_idx++)
        dfii_rddata_q[dfii_idx] <= 32'd0;
    end else if (state_q == PROBE_RESET || state_q == PROBE_WAIT_INIT ||
                 state_q == PROBE_CAL_CONFIG ||
                 state_q == PROBE_CAL_APPLY_BEST ||
                 state_q == PROBE_CAL_NEXT_LANE ||
                 state_q == PROBE_DFII_RESTART ||
                 state_q == PROBE_DFII_WBITSLIP_CONFIG) begin
      dfii_seq_state_q <= DFII_SEQ_IDLE;
      dfii_step_q <= 8'd0;
      dfii_delay_q <= 32'd0;
      dfii_wb_timeout_count_q <= '0;
      dfii_wb_ack_count_q <= 32'd0;
      dfii_wb_wait_count_q <= 32'd0;
      dfii_last_wb_addr_q <= 16'd0;
      dfii_last_wb_data_q <= 32'd0;
      dfii_last_read_data_q <= 32'd0;
      dfii_wb_error_seen_q <= 1'b0;
      dfii_wb_timeout_seen_q <= 1'b0;
      dfii_failed_q <= 1'b0;
      dfii_done_q <= 1'b0;
      dfii_word_mismatch_q <= '0;
      dfii_wb_ctrl_cyc_q <= 1'b0;
      dfii_wb_ctrl_stb_q <= 1'b0;
      dfii_wb_ctrl_we_q <= 1'b0;
      dfii_wb_ctrl_adr_q <= 30'd0;
      dfii_wb_ctrl_dat_w_q <= 32'd0;
      for (int dfii_idx = 0; dfii_idx < DFII_RDDATA_WORDS; dfii_idx++)
        dfii_rddata_q[dfii_idx] <= 32'd0;
    end else if (dfii_seq_running) begin
      unique case (dfii_seq_state_q)
        DFII_SEQ_IDLE: begin
          dfii_step_q <= 8'd0;
          dfii_delay_q <= 32'd0;
          dfii_wb_timeout_count_q <= '0;
          dfii_wb_ack_count_q <= 32'd0;
          dfii_wb_wait_count_q <= 32'd0;
          dfii_last_wb_addr_q <= 16'd0;
          dfii_last_wb_data_q <= 32'd0;
          dfii_last_read_data_q <= 32'd0;
          dfii_wb_error_seen_q <= 1'b0;
          dfii_wb_timeout_seen_q <= 1'b0;
          dfii_failed_q <= 1'b0;
          dfii_done_q <= 1'b0;
          dfii_word_mismatch_q <= '0;
          dfii_wb_ctrl_cyc_q <= 1'b0;
          dfii_wb_ctrl_stb_q <= 1'b0;
          dfii_wb_ctrl_we_q <= 1'b0;
          for (int dfii_idx = 0; dfii_idx < DFII_RDDATA_WORDS; dfii_idx++)
            dfii_rddata_q[dfii_idx] <= 32'd0;
          dfii_seq_state_q <= DFII_SEQ_RUN_STEP;
        end
        DFII_SEQ_RUN_STEP: begin
          dfii_wb_timeout_count_q <= '0;
          dfii_wb_ctrl_cyc_q <= 1'b0;
          dfii_wb_ctrl_stb_q <= 1'b0;
          dfii_wb_ctrl_we_q <= 1'b0;
          if (dfii_step_q >= dfii_seq_done_step) begin
            dfii_done_q <= 1'b1;
            dfii_seq_state_q <= DFII_SEQ_DONE;
          end else if (dfii_step_is_delay) begin
            dfii_delay_q <= dfii_step_delay;
            dfii_seq_state_q <= DFII_SEQ_DELAY;
          end else begin
            dfii_wb_ctrl_adr_q <= dfii_step_wb_addr;
            dfii_wb_ctrl_dat_w_q <= dfii_step_wb_data;
            dfii_wb_ctrl_we_q <= !dfii_step_is_read;
            dfii_last_wb_addr_q <= dfii_step_wb_addr[15:0];
            dfii_last_wb_data_q <= dfii_step_wb_data;
            dfii_wb_ctrl_cyc_q <= 1'b1;
            dfii_wb_ctrl_stb_q <= 1'b1;
            dfii_seq_state_q <= DFII_SEQ_WB_WAIT;
          end
        end
        DFII_SEQ_WB_WAIT: begin
          dfii_wb_wait_count_q <= dfii_wb_wait_count_q + 32'd1;
          if (wb_ctrl_ack) begin
            dfii_wb_ctrl_cyc_q <= 1'b0;
            dfii_wb_ctrl_stb_q <= 1'b0;
            dfii_wb_ctrl_we_q <= 1'b0;
            dfii_wb_ack_count_q <= dfii_wb_ack_count_q + 32'd1;
            if (wb_ctrl_err) begin
              dfii_wb_error_seen_q <= 1'b1;
              dfii_failed_q <= 1'b1;
              dfii_seq_state_q <= DFII_SEQ_ERROR;
            end else begin
              if (dfii_step_is_read &&
                  dfii_read_store_index < 5'd20) begin
                dfii_rddata_q[dfii_read_store_index] <= wb_ctrl_dat_r;
                dfii_last_read_data_q <= wb_ctrl_dat_r;
                if (dfii_csr_echo_probe_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_csr_echo_word(
                        dfii_index20_phase(dfii_read_store_index),
                        dfii_index20_word(dfii_read_store_index)
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_displacement_probe_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_displacement_word(
                        dfii_index20_word(dfii_read_store_index)
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_edge_map_probe_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_edge_map_word(
                        dfii_index20_phase(dfii_read_store_index),
                        dfii_index20_word(dfii_read_store_index)
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_edge_lane7_locator_probe_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_lane7_locator_expected_word(
                        dfii_index20_word(dfii_read_store_index)
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_edge_comp_probe_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_edge_comp_read_word(
                        dfii_index20_word(dfii_read_store_index),
                        dfii_phasecmd_index_q[1:0]
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_half_order_matrix_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_half_order_word(
                        dfii_phasecmd_index_q,
                        dfii_index20_word(dfii_read_store_index)
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (wb_ctrl_dat_r !=
                    dfii_pattern_word(dfii_rddata_index)) begin
                  dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end
              end
              dfii_step_q <= dfii_step_q + 8'd1;
              dfii_seq_state_q <= DFII_SEQ_RUN_STEP;
            end
          end else begin
            dfii_wb_timeout_count_q <= dfii_wb_timeout_count_q + 1'b1;
            if (dfii_wb_timeout_count_q[WB_TIMEOUT_LOG2 - 1]) begin
              dfii_wb_ctrl_cyc_q <= 1'b0;
              dfii_wb_ctrl_stb_q <= 1'b0;
              dfii_wb_ctrl_we_q <= 1'b0;
              dfii_wb_timeout_seen_q <= 1'b1;
              dfii_failed_q <= 1'b1;
              dfii_seq_state_q <= DFII_SEQ_ERROR;
            end
          end
        end
        DFII_SEQ_DELAY: begin
          if (dfii_delay_q == 32'd0) begin
            dfii_step_q <= dfii_step_q + 8'd1;
            dfii_seq_state_q <= DFII_SEQ_RUN_STEP;
          end else begin
            dfii_delay_q <= dfii_delay_q - 32'd1;
          end
        end
        DFII_SEQ_DONE: begin
          dfii_seq_state_q <= DFII_SEQ_DONE;
        end
        DFII_SEQ_ERROR: begin
          dfii_failed_q <= 1'b1;
          dfii_seq_state_q <= DFII_SEQ_ERROR;
        end
        default: begin
          dfii_failed_q <= 1'b1;
          dfii_seq_state_q <= DFII_SEQ_ERROR;
        end
      endcase
    end
  end

  always_ff @(posedge user_clk) begin
    if (user_rst || core_rst) begin
      cal_config_state_q <= CAL_CFG_IDLE;
      cal_config_step_q <= 8'd0;
      cal_delay_pulse_q <= 5'd0;
      cal_bitslip_pulse_q <= 3'd0;
      cal_wbitslip_pulse_q <= 3'd0;
      cal_wb_timeout_count_q <= '0;
      cal_wb_ack_count_q <= 32'd0;
      cal_wb_wait_count_q <= 32'd0;
      cal_last_wb_addr_q <= 16'd0;
      cal_last_wb_data_q <= 32'd0;
      cal_wb_error_seen_q <= 1'b0;
      cal_wb_timeout_seen_q <= 1'b0;
      cal_wb_ctrl_cyc_q <= 1'b0;
      cal_wb_ctrl_stb_q <= 1'b0;
      cal_wb_ctrl_we_q <= 1'b0;
      cal_wb_ctrl_adr_q <= 30'd0;
      cal_wb_ctrl_dat_w_q <= 32'd0;
    end else begin
      if (!cal_config_active) begin
        cal_config_state_q <= CAL_CFG_IDLE;
        cal_config_step_q <= 8'd0;
        cal_delay_pulse_q <= 5'd0;
        cal_bitslip_pulse_q <= 3'd0;
        cal_wbitslip_pulse_q <= 3'd0;
        cal_wb_timeout_count_q <= '0;
        cal_wb_ctrl_cyc_q <= 1'b0;
        cal_wb_ctrl_stb_q <= 1'b0;
        cal_wb_ctrl_we_q <= 1'b0;
      end else begin
        unique case (cal_config_state_q)
          CAL_CFG_IDLE: begin
            cal_config_step_q <= 8'd0;
            cal_delay_pulse_q <= 5'd0;
            cal_bitslip_pulse_q <= 3'd0;
            cal_wbitslip_pulse_q <= 3'd0;
            cal_wb_timeout_count_q <= '0;
            cal_wb_ctrl_cyc_q <= 1'b0;
            cal_wb_ctrl_stb_q <= 1'b0;
            cal_wb_ctrl_we_q <= 1'b0;
            cal_config_state_q <= CAL_CFG_RUN_STEP;
          end
          CAL_CFG_RUN_STEP: begin
            cal_wb_timeout_count_q <= '0;
            cal_wb_ctrl_cyc_q <= 1'b0;
            cal_wb_ctrl_stb_q <= 1'b0;
            cal_wb_ctrl_we_q <= 1'b0;

            if (cal_config_step_q == 8'd4 &&
                cal_delay_pulse_q >= cal_config_delay) begin
              cal_config_step_q <= 8'd5;
            end else if (cal_config_step_q == 8'd5 &&
                         cal_bitslip_pulse_q >= cal_config_bitslip) begin
              cal_config_step_q <= 8'd6;
            end else if (cal_config_step_q == 8'd6 &&
                         cal_wbitslip_pulse_q >= cal_config_wbitslip) begin
              cal_config_step_q <= 8'd7;
            end else if (phase_config_active && cal_config_step_q >= 8'd2) begin
              cal_config_state_q <= CAL_CFG_DONE;
            end else if (!phase_config_active && cal_config_step_q >= 8'd8) begin
              cal_config_state_q <= CAL_CFG_DONE;
            end else begin
              cal_wb_ctrl_adr_q <= cal_step_wb_addr;
              cal_wb_ctrl_dat_w_q <= cal_step_wb_data;
              cal_last_wb_addr_q <= cal_step_wb_addr[15:0];
              cal_last_wb_data_q <= cal_step_wb_data;
              cal_wb_ctrl_cyc_q <= 1'b1;
              cal_wb_ctrl_stb_q <= 1'b1;
              cal_wb_ctrl_we_q <= 1'b1;
              cal_config_state_q <= CAL_CFG_WB_WAIT;
            end
          end
          CAL_CFG_WB_WAIT: begin
            cal_wb_wait_count_q <= cal_wb_wait_count_q + 32'd1;
            if (wb_ctrl_ack) begin
              cal_wb_ctrl_cyc_q <= 1'b0;
              cal_wb_ctrl_stb_q <= 1'b0;
              cal_wb_ctrl_we_q <= 1'b0;
              cal_wb_ack_count_q <= cal_wb_ack_count_q + 32'd1;
              if (wb_ctrl_err) begin
                cal_wb_error_seen_q <= 1'b1;
                cal_config_state_q <= CAL_CFG_ERROR;
              end else begin
                unique case (cal_config_step_q)
                  8'd4: cal_delay_pulse_q <= cal_delay_pulse_q + 5'd1;
                  8'd5: cal_bitslip_pulse_q <= cal_bitslip_pulse_q + 3'd1;
                  8'd6: cal_wbitslip_pulse_q <= cal_wbitslip_pulse_q + 3'd1;
                  8'd7: cal_config_step_q <= 8'd8;
                  default: cal_config_step_q <= cal_config_step_q + 8'd1;
                endcase
                cal_config_state_q <= CAL_CFG_RUN_STEP;
              end
            end else begin
              cal_wb_timeout_count_q <= cal_wb_timeout_count_q + 1'b1;
              if (cal_wb_timeout_count_q[WB_TIMEOUT_LOG2 - 1]) begin
                cal_wb_ctrl_cyc_q <= 1'b0;
                cal_wb_ctrl_stb_q <= 1'b0;
                cal_wb_ctrl_we_q <= 1'b0;
                cal_wb_timeout_seen_q <= 1'b1;
                cal_config_state_q <= CAL_CFG_ERROR;
              end
            end
          end
          CAL_CFG_DONE: begin
            cal_config_state_q <= CAL_CFG_DONE;
          end
          CAL_CFG_ERROR: begin
            cal_config_state_q <= CAL_CFG_ERROR;
          end
          default: begin
            cal_config_state_q <= CAL_CFG_ERROR;
          end
        endcase
      end
    end
  end

  always_ff @(posedge user_clk) begin
    if (user_rst || core_rst) begin
      read_addr_q <= 25'd0;
      compare_addr_q <= 25'd0;
      command_count_q <= 32'd0;
      response_count_q <= 32'd0;
      write_command_count_q <= 32'd0;
      write_data_count_q <= 32'd0;
      write_drain_count_q <= 32'd0;
      read_cycle_count_q <= 32'd0;
      command_stall_count_q <= 32'd0;
      checksum_q <= 32'd0;
      last_rdata_q <= 64'd0;
      mismatch_count_q <= 32'd0;
      first_mismatch_addr_q <= 28'd0;
      first_expected_q <= 64'd0;
      first_actual_q <= 64'd0;
      first_expected_full_q <= 576'd0;
      first_actual_full_q <= 576'd0;
      first_chunk_mismatch_q <= 9'd0;
      sample_valid_count_q <= 8'd0;
      for (int sample_idx = 0; sample_idx < READBACK_SAMPLE_COUNT; sample_idx++)
        sample_rdata_q[sample_idx] <= 64'd0;
      byte_diag_valid_count_q <= 8'd0;
      for (int byte_sample_idx = 0;
           byte_sample_idx < BYTE_DIAG_SAMPLE_COUNT;
           byte_sample_idx++)
        byte_diag_rdata_q[byte_sample_idx] <= 64'd0;
      cal_bitslip_q <= 3'd0;
      cal_wbitslip_q <= 3'd0;
      cal_delay_q <= 5'd0;
      cal_lane_q <= 3'd0;
      selected_bitslip_q <= 3'd0;
      selected_wbitslip_q <= 3'd0;
      selected_delay_q <= 5'd0;
      best_bitslip_q <= 3'd0;
      best_wbitslip_q <= 3'd0;
      best_delay_q <= 5'd0;
      best_mismatch_count_q <= 32'hffff_ffff;
      cal_candidates_tested_q <= 32'd0;
      cal_last_mismatch_count_q <= 32'd0;
      phase_rd_q <= 2'd0;
      phase_wr_q <= 2'd0;
      phase_best_rd_q <= 2'd0;
      phase_best_wr_q <= 2'd0;
      phase_best_mismatch_count_q <= 32'hffff_ffff;
      phase_candidates_tested_q <= 32'd0;
      for (int phase_idx = 0; phase_idx < PHASE_CANDIDATES; phase_idx++)
        phase_mismatch_count_q[phase_idx] <= 32'hffff_ffff;
      dfii_final_q <= 1'b0;
      dfii_phasecmd_sweep_q <= 1'b0;
      dfii_assoc_sweep_q <= 1'b0;
      dfii_addr_sweep_q <= 1'b0;
      dfii_pattern_mode_q <= DFII_PATTERN_MODE_RAMP;
      dfii_phasecmd_index_q <= 4'd0;
      dfii_assoc_index_q <= 4'd0;
      dfii_addr_index_q <= 2'd0;
      for (int mode_idx = 0; mode_idx < 3; mode_idx++)
        dfii_mode_mismatch_q[mode_idx] <= 16'd0;
      for (int combo_idx = 0; combo_idx < 16; combo_idx++)
        dfii_phasecmd_mismatch_q[combo_idx] <= 16'd0;
      for (int assoc_idx = 0; assoc_idx < 16; assoc_idx++) begin
        dfii_assoc_nonzero_mask_q[assoc_idx] <= 16'd0;
        dfii_assoc_match_mask_q[assoc_idx] <= 16'd0;
        dfii_half_nonzero_high_q[assoc_idx] <= 4'd0;
        dfii_half_low_match_high_q[assoc_idx] <= 4'd0;
        dfii_half_high_match_low_q[assoc_idx] <= 16'd0;
        dfii_half_high_match_high_q[assoc_idx] <= 4'd0;
      end
      for (int addr_idx = 0; addr_idx < DFII_ADDR_SLOTS; addr_idx++) begin
        dfii_addr_mismatch_mask_q[addr_idx] <= 16'd0;
        dfii_addr_nonzero_mask_q[addr_idx] <= 16'd0;
        dfii_addr_match_mask_q[addr_idx] <= 16'd0;
      end
      for (int lane_idx = 0; lane_idx < CAL_BYTE_LANES; lane_idx++) begin
        lane_selected_bitslip_q[lane_idx] <= 3'd0;
        lane_selected_wbitslip_q[lane_idx] <= 3'd0;
        lane_selected_delay_q[lane_idx] <= 5'd0;
        lane_selected_logical_byte_q[lane_idx] <= 3'd0;
        lane_best_bitslip_q[lane_idx] <= 3'd0;
        lane_best_wbitslip_q[lane_idx] <= 3'd0;
        lane_best_delay_q[lane_idx] <= 5'd0;
        lane_best_logical_byte_q[lane_idx] <= 3'd0;
        lane_best_mismatch_count_q[lane_idx] <= 32'hffff_ffff;
        cal_byte_mismatch_count_q[lane_idx] <= 32'd0;
      end
      state_q <= PROBE_RESET;
    end else begin
      unique case (state_q)
        PROBE_RESET: begin
          if (init_error || init_seq_error_q)
            state_q <= PROBE_ERROR;
          else if (init_done && init_seq_done) begin
            read_addr_q <= 25'd0;
            compare_addr_q <= 25'd0;
            command_count_q <= 32'd0;
            response_count_q <= 32'd0;
            write_command_count_q <= 32'd0;
            write_data_count_q <= 32'd0;
            write_drain_count_q <= 32'd0;
            read_cycle_count_q <= 32'd0;
            command_stall_count_q <= 32'd0;
            checksum_q <= 32'd0;
            last_rdata_q <= 64'd0;
            mismatch_count_q <= 32'd0;
            first_mismatch_addr_q <= 28'd0;
            first_expected_q <= 64'd0;
            first_actual_q <= 64'd0;
            first_expected_full_q <= 576'd0;
            first_actual_full_q <= 576'd0;
            first_chunk_mismatch_q <= 9'd0;
            dfii_final_q <= !(DFII_DISPLACEMENT_PROBE_ONLY ||
                              DFII_CSR_ECHO_PROBE_ONLY ||
                              DFII_WBITSLIP_SWEEP_ONLY ||
                              DFII_RBITSLIP_SWEEP_ONLY ||
                              DFII_EDGE_MAP_PROBE_ONLY ||
                              DFII_EDGE_COMP_PROBE_ONLY ||
                              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY);
            dfii_phasecmd_sweep_q <=
              DFII_DISPLACEMENT_PROBE_ONLY || DFII_CSR_ECHO_PROBE_ONLY ||
              DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY ||
              DFII_EDGE_MAP_PROBE_ONLY || DFII_EDGE_COMP_PROBE_ONLY ||
              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY;
            dfii_assoc_sweep_q <= 1'b0;
            dfii_addr_sweep_q <= 1'b0;
            dfii_pattern_mode_q <= DFII_PATTERN_MODE_UNIFORM;
            dfii_phasecmd_index_q <= 4'd0;
            dfii_assoc_index_q <= 4'd0;
            dfii_addr_index_q <= 2'd0;
            cal_bitslip_q <= 3'd0;
            cal_wbitslip_q <= 3'd0;
            cal_delay_q <= 5'd0;
            state_q <= (DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY) ?
              PROBE_DFII_WBITSLIP_CONFIG : PROBE_DFII_RUN;
          end
          else
            state_q <= PROBE_WAIT_INIT;
        end
        PROBE_WAIT_INIT: begin
          if (init_error || init_seq_error_q)
            state_q <= PROBE_ERROR;
          else if (init_done && init_seq_done) begin
            read_addr_q <= 25'd0;
            compare_addr_q <= 25'd0;
            command_count_q <= 32'd0;
            response_count_q <= 32'd0;
            write_command_count_q <= 32'd0;
            write_data_count_q <= 32'd0;
            write_drain_count_q <= 32'd0;
            read_cycle_count_q <= 32'd0;
            command_stall_count_q <= 32'd0;
            checksum_q <= 32'd0;
            last_rdata_q <= 64'd0;
            mismatch_count_q <= 32'd0;
            first_mismatch_addr_q <= 28'd0;
            first_expected_q <= 64'd0;
            first_actual_q <= 64'd0;
            first_expected_full_q <= 576'd0;
            first_actual_full_q <= 576'd0;
            first_chunk_mismatch_q <= 9'd0;
            dfii_final_q <= !(DFII_DISPLACEMENT_PROBE_ONLY ||
                              DFII_CSR_ECHO_PROBE_ONLY ||
                              DFII_WBITSLIP_SWEEP_ONLY ||
                              DFII_RBITSLIP_SWEEP_ONLY ||
                              DFII_EDGE_MAP_PROBE_ONLY ||
                              DFII_EDGE_COMP_PROBE_ONLY ||
                              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY);
            dfii_phasecmd_sweep_q <=
              DFII_DISPLACEMENT_PROBE_ONLY || DFII_CSR_ECHO_PROBE_ONLY ||
              DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY ||
              DFII_EDGE_MAP_PROBE_ONLY || DFII_EDGE_COMP_PROBE_ONLY ||
              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY;
            dfii_assoc_sweep_q <= 1'b0;
            dfii_addr_sweep_q <= 1'b0;
            dfii_pattern_mode_q <= DFII_PATTERN_MODE_UNIFORM;
            dfii_phasecmd_index_q <= 4'd0;
            dfii_assoc_index_q <= 4'd0;
            dfii_addr_index_q <= 2'd0;
            cal_bitslip_q <= 3'd0;
            cal_wbitslip_q <= 3'd0;
            cal_delay_q <= 5'd0;
            state_q <= (DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY) ?
              PROBE_DFII_WBITSLIP_CONFIG : PROBE_DFII_RUN;
          end
        end
        PROBE_DFII_WBITSLIP_CONFIG: begin
          if (cal_config_failed) begin
            state_q <= PROBE_ERROR;
          end else if (cal_config_done) begin
            read_cycle_count_q <= 32'd0;
            state_q <= PROBE_DFII_RUN;
          end
        end
        PROBE_DFII_RUN: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen || dfii_wb_timeout_seen_q) begin
            state_q <= PROBE_TIMEOUT;
          end else if (dfii_failed_q || dfii_wb_error_seen_q) begin
            state_q <= PROBE_ERROR;
          end else if (dfii_done_q) begin
            if (dfii_phasecmd_sweep_q) begin
              dfii_phasecmd_mismatch_q[dfii_result_slot] <=
                dfii_displacement_probe_mode ?
                dfii_word_mismatch_q[15:0] :
                dfii_half_order_matrix_mode ?
                ~dfii_half_low_match_mask_next[15:0] :
                dfii_phase_matrix_mode ?
                ~dfii_phase_matrix_match_mask_next :
                dfii_word_mismatch_q[15:0];
              if (dfii_phase_matrix_mode) begin
                if (dfii_displacement_probe_mode) begin
                  dfii_assoc_nonzero_mask_q[dfii_result_slot] <=
                    dfii_half_nonzero_mask_next[15:0];
                  dfii_assoc_match_mask_q[dfii_result_slot] <=
                    ~dfii_word_mismatch_q[15:0];
                  dfii_half_nonzero_high_q[dfii_result_slot] <=
                    dfii_half_nonzero_mask_next[19:16];
                  dfii_half_low_match_high_q[dfii_result_slot] <=
                    ~dfii_word_mismatch_q[19:16];
                  dfii_half_high_match_low_q[dfii_result_slot] <=
                    16'd0;
                  dfii_half_high_match_high_q[dfii_result_slot] <=
                    4'd0;
                end else if (dfii_half_order_matrix_mode) begin
                  dfii_assoc_nonzero_mask_q[dfii_result_slot] <=
                    dfii_half_nonzero_mask_next[15:0];
                  dfii_assoc_match_mask_q[dfii_result_slot] <=
                    dfii_half_low_match_mask_next[15:0];
                  dfii_half_nonzero_high_q[dfii_result_slot] <=
                    dfii_half_nonzero_mask_next[19:16];
                  dfii_half_low_match_high_q[dfii_result_slot] <=
                    dfii_half_low_match_mask_next[19:16];
                  dfii_half_high_match_low_q[dfii_result_slot] <=
                    dfii_half_high_match_mask_next[15:0];
                  dfii_half_high_match_high_q[dfii_result_slot] <=
                    dfii_half_high_match_mask_next[19:16];
                end else begin
                  dfii_assoc_nonzero_mask_q[dfii_result_slot] <=
                    dfii_phase_matrix_nonzero_mask_next;
                  dfii_assoc_match_mask_q[dfii_result_slot] <=
                    dfii_phase_matrix_match_mask_next;
                end
              end
              if (DFII_WBITSLIP_SWEEP_ONLY) begin
                if (cal_wbitslip_q == 3'd7) begin
                  dfii_phasecmd_sweep_q <= 1'b0;
                  dfii_assoc_sweep_q <= 1'b0;
                  dfii_addr_sweep_q <= 1'b0;
                  state_q <= PROBE_DFII_DONE;
                end else begin
                  cal_wbitslip_q <= cal_wbitslip_q + 3'd1;
                  cal_bitslip_q <= 3'd0;
                  cal_delay_q <= 5'd0;
                  state_q <= PROBE_DFII_WBITSLIP_CONFIG;
                end
              end else if (DFII_RBITSLIP_SWEEP_ONLY) begin
                if (cal_bitslip_q == 3'd7) begin
                  dfii_phasecmd_sweep_q <= 1'b0;
                  dfii_assoc_sweep_q <= 1'b0;
                  dfii_addr_sweep_q <= 1'b0;
                  state_q <= PROBE_DFII_DONE;
                end else begin
                  cal_bitslip_q <= cal_bitslip_q + 3'd1;
                  cal_wbitslip_q <= 3'd0;
                  cal_delay_q <= 5'd0;
                  state_q <= PROBE_DFII_WBITSLIP_CONFIG;
                end
              end else if (DFII_DISPLACEMENT_PROBE_ONLY ||
                           DFII_CSR_ECHO_PROBE_ONLY ||
                           DFII_EDGE_MAP_PROBE_ONLY ||
                           DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY) begin
                dfii_phasecmd_sweep_q <= 1'b0;
                dfii_assoc_sweep_q <= 1'b0;
                dfii_addr_sweep_q <= 1'b0;
                state_q <= PROBE_DFII_DONE;
              end else if (DFII_EDGE_COMP_PROBE_ONLY) begin
                if (dfii_phasecmd_index_q == 4'd3) begin
                  dfii_phasecmd_sweep_q <= 1'b0;
                  dfii_assoc_sweep_q <= 1'b0;
                  dfii_addr_sweep_q <= 1'b0;
                  state_q <= PROBE_DFII_DONE;
                end else begin
                  dfii_phasecmd_index_q <= dfii_phasecmd_index_q + 4'd1;
                  state_q <= PROBE_DFII_RESTART;
                end
              end else if (dfii_phasecmd_index_q == 4'hf) begin
                dfii_phasecmd_sweep_q <= 1'b0;
                if (DFII_PHASE_MATRIX_ONLY ||
                    DFII_SOURCE_COMMAND_MATRIX_ONLY ||
                    DFII_SOURCE_ORDER_MATRIX_ONLY ||
                    DFII_HALF_ORDER_MATRIX_ONLY ||
                    DFII_DISPLACEMENT_PROBE_ONLY ||
                    DFII_CSR_ECHO_PROBE_ONLY ||
                    DFII_EDGE_MAP_PROBE_ONLY ||
                    DFII_EDGE_COMP_PROBE_ONLY ||
                    DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY) begin
                  dfii_assoc_sweep_q <= 1'b0;
                  dfii_addr_sweep_q <= 1'b0;
                  state_q <= PROBE_DFII_DONE;
                end else begin
                  dfii_assoc_sweep_q <= 1'b1;
                  dfii_addr_sweep_q <= 1'b0;
                  dfii_assoc_index_q <= 4'd0;
                  for (int assoc_idx = 0; assoc_idx < 16; assoc_idx++) begin
                    dfii_assoc_nonzero_mask_q[assoc_idx] <= 16'd0;
                    dfii_assoc_match_mask_q[assoc_idx] <= 16'd0;
                    dfii_half_nonzero_high_q[assoc_idx] <= 4'd0;
                    dfii_half_low_match_high_q[assoc_idx] <= 4'd0;
                    dfii_half_high_match_low_q[assoc_idx] <= 16'd0;
                    dfii_half_high_match_high_q[assoc_idx] <= 4'd0;
                  end
                  state_q <= PROBE_DFII_RESTART;
                end
              end else begin
                dfii_phasecmd_index_q <= dfii_phasecmd_index_q + 4'd1;
                state_q <= PROBE_DFII_RESTART;
              end
            end else if (dfii_assoc_sweep_q) begin
              dfii_assoc_nonzero_mask_q[dfii_assoc_index_q] <=
                dfii_assoc_nonzero_mask_next;
              dfii_assoc_match_mask_q[dfii_assoc_index_q] <=
                dfii_assoc_match_mask_next;
              if (dfii_assoc_index_q == 4'hf) begin
                dfii_assoc_sweep_q <= 1'b0;
                dfii_addr_sweep_q <= 1'b1;
                dfii_addr_index_q <= 2'd0;
                for (int addr_idx = 0;
                     addr_idx < DFII_ADDR_SLOTS;
                     addr_idx++) begin
                  dfii_addr_mismatch_mask_q[addr_idx] <= 16'd0;
                  dfii_addr_nonzero_mask_q[addr_idx] <= 16'd0;
                  dfii_addr_match_mask_q[addr_idx] <= 16'd0;
                end
                state_q <= PROBE_DFII_RESTART;
              end else begin
                dfii_assoc_index_q <= dfii_assoc_index_q + 4'd1;
                state_q <= PROBE_DFII_RESTART;
              end
            end else if (dfii_addr_sweep_q) begin
              dfii_addr_mismatch_mask_q[dfii_addr_index_q] <=
                dfii_word_mismatch_q[15:0];
              dfii_addr_nonzero_mask_q[dfii_addr_index_q] <=
                dfii_addr_nonzero_mask_next;
              dfii_addr_match_mask_q[dfii_addr_index_q] <=
                dfii_addr_match_mask_next;
              if (dfii_addr_index_q == 2'd3) begin
                dfii_addr_sweep_q <= 1'b0;
                read_addr_q <= 25'd0;
                compare_addr_q <= 25'd0;
                command_count_q <= 32'd0;
                response_count_q <= 32'd0;
                write_command_count_q <= 32'd0;
                write_data_count_q <= 32'd0;
                write_drain_count_q <= 32'd0;
                read_cycle_count_q <= 32'd0;
                command_stall_count_q <= 32'd0;
                checksum_q <= 32'd0;
                last_rdata_q <= 64'd0;
                mismatch_count_q <= 32'd0;
                first_mismatch_addr_q <= 28'd0;
                first_expected_q <= 64'd0;
                first_actual_q <= 64'd0;
                first_expected_full_q <= 576'd0;
                first_actual_full_q <= 576'd0;
                first_chunk_mismatch_q <= 9'd0;
                sample_valid_count_q <= 8'd0;
                for (int sample_idx = 0;
                     sample_idx < READBACK_SAMPLE_COUNT;
                     sample_idx++)
                  sample_rdata_q[sample_idx] <= 64'd0;
                byte_diag_valid_count_q <= 8'd0;
                for (int byte_sample_idx = 0;
                     byte_sample_idx < BYTE_DIAG_SAMPLE_COUNT;
                     byte_sample_idx++)
                  byte_diag_rdata_q[byte_sample_idx] <= 64'd0;
                state_q <= PROBE_BYTE_CLEAR_WRITES;
              end else begin
                dfii_addr_index_q <= dfii_addr_index_q + 2'd1;
                state_q <= PROBE_DFII_RESTART;
              end
            end else if (dfii_final_q) begin
              dfii_mode_mismatch_q[dfii_pattern_mode_q] <=
                dfii_word_mismatch_q[15:0];
              if (dfii_pattern_mode_q == DFII_PATTERN_MODE_RAMP) begin
                dfii_phasecmd_sweep_q <= 1'b1;
                dfii_phasecmd_index_q <= 4'd0;
                dfii_pattern_mode_q <= DFII_PATTERN_MODE_PHASE;
                for (int combo_idx = 0; combo_idx < 16; combo_idx++) begin
                  dfii_phasecmd_mismatch_q[combo_idx] <= 16'd0;
                  dfii_assoc_nonzero_mask_q[combo_idx] <= 16'd0;
                  dfii_assoc_match_mask_q[combo_idx] <= 16'd0;
                end
                state_q <= PROBE_DFII_RESTART;
              end else begin
                dfii_pattern_mode_q <= dfii_pattern_mode_q + 2'd1;
                state_q <= PROBE_DFII_RESTART;
              end
            end else begin
              mismatch_count_q <= cal_candidate_score;
              cal_last_mismatch_count_q <= cal_candidate_score;
              cal_candidates_tested_q <= cal_candidates_tested_q + 32'd1;
              if (cal_candidate_score < best_mismatch_count_q) begin
                best_mismatch_count_q <= cal_candidate_score;
                best_bitslip_q <= cal_bitslip_q;
                best_wbitslip_q <= cal_wbitslip_q;
                best_delay_q <= cal_delay_q;
              end
              if (cal_candidate_better) begin
                lane_best_mismatch_count_q[cal_lane_q] <= cal_candidate_score;
                lane_best_bitslip_q[cal_lane_q] <= cal_bitslip_q;
                lane_best_wbitslip_q[cal_lane_q] <= cal_wbitslip_q;
                lane_best_delay_q[cal_lane_q] <= cal_delay_q;
                lane_best_logical_byte_q[cal_lane_q] <= cal_lane_q;
              end

              if (cal_last_candidate) begin
                selected_bitslip_q <= lane_best_bitslip_next;
                selected_wbitslip_q <= lane_best_wbitslip_next;
                selected_delay_q <= lane_best_delay_next;
                lane_selected_bitslip_q[cal_lane_q] <= lane_best_bitslip_next;
                lane_selected_wbitslip_q[cal_lane_q] <= lane_best_wbitslip_next;
                lane_selected_delay_q[cal_lane_q] <= lane_best_delay_next;
                lane_selected_logical_byte_q[cal_lane_q] <= cal_lane_q;
                lane_best_mismatch_count_q[cal_lane_q] <= lane_best_mismatch_next;
                lane_best_wbitslip_q[cal_lane_q] <= lane_best_wbitslip_next;
                state_q <= PROBE_CAL_APPLY_BEST;
              end else begin
                if (cal_delay_q == 5'd31) begin
                  cal_delay_q <= 5'd0;
                  if (cal_bitslip_q == 3'd7) begin
                    cal_bitslip_q <= 3'd0;
                    cal_wbitslip_q <= cal_wbitslip_q + 3'd1;
                  end else begin
                    cal_bitslip_q <= cal_bitslip_q + 3'd1;
                  end
                end else begin
                  cal_delay_q <= cal_delay_q + 5'd1;
                end
                state_q <= PROBE_CAL_CONFIG;
              end
            end
          end
        end
        PROBE_DFII_DONE: begin
          state_q <= PROBE_DFII_DONE;
        end
        PROBE_DFII_RESTART: begin
          state_q <= PROBE_DFII_RUN;
        end
        PROBE_PHASE_CONFIG: begin
          if (cal_config_failed) begin
            state_q <= PROBE_ERROR;
          end else if (cal_config_done) begin
            read_addr_q <= 25'd0;
            compare_addr_q <= 25'd0;
            command_count_q <= 32'd0;
            response_count_q <= 32'd0;
            write_command_count_q <= 32'd0;
            write_data_count_q <= 32'd0;
            write_drain_count_q <= 32'd0;
            read_cycle_count_q <= 32'd0;
            command_stall_count_q <= 32'd0;
            checksum_q <= 32'd0;
            last_rdata_q <= 64'd0;
            mismatch_count_q <= 32'd0;
            first_mismatch_addr_q <= 28'd0;
            first_expected_q <= 64'd0;
            first_actual_q <= 64'd0;
            first_expected_full_q <= 576'd0;
            first_actual_full_q <= 576'd0;
            first_chunk_mismatch_q <= 9'd0;
            state_q <= PROBE_PHASE_RUN_WRITES;
          end
        end
        PROBE_PHASE_APPLY_BEST: begin
          if (cal_config_failed) begin
            state_q <= PROBE_ERROR;
          end else if (cal_config_done) begin
            read_addr_q <= 25'd0;
            compare_addr_q <= 25'd0;
            command_count_q <= 32'd0;
            response_count_q <= 32'd0;
            write_command_count_q <= 32'd0;
            write_data_count_q <= 32'd0;
            write_drain_count_q <= 32'd0;
            read_cycle_count_q <= 32'd0;
            command_stall_count_q <= 32'd0;
            checksum_q <= 32'd0;
            last_rdata_q <= 64'd0;
            mismatch_count_q <= 32'd0;
            first_mismatch_addr_q <= 28'd0;
            first_expected_q <= 64'd0;
            first_actual_q <= 64'd0;
            first_expected_full_q <= 576'd0;
            first_actual_full_q <= 576'd0;
            first_chunk_mismatch_q <= 9'd0;
            sample_valid_count_q <= 8'd0;
            for (int sample_idx = 0; sample_idx < READBACK_SAMPLE_COUNT; sample_idx++)
              sample_rdata_q[sample_idx] <= 64'd0;
            state_q <= PROBE_RUN_WRITES;
          end
        end
        PROBE_CAL_CONFIG: begin
          if (cal_config_failed) begin
            state_q <= PROBE_ERROR;
          end else if (cal_config_done) begin
            read_addr_q <= 25'd0;
            compare_addr_q <= 25'd0;
            command_count_q <= 32'd0;
            response_count_q <= 32'd0;
            write_command_count_q <= 32'd0;
            write_data_count_q <= 32'd0;
            write_drain_count_q <= 32'd0;
            read_cycle_count_q <= 32'd0;
            command_stall_count_q <= 32'd0;
            checksum_q <= 32'd0;
            last_rdata_q <= 64'd0;
            mismatch_count_q <= 32'd0;
            first_mismatch_addr_q <= 28'd0;
            first_expected_q <= 64'd0;
            first_actual_q <= 64'd0;
            first_expected_full_q <= 576'd0;
            first_actual_full_q <= 576'd0;
            first_chunk_mismatch_q <= 9'd0;
            for (int byte_idx = 0; byte_idx < CAL_BYTE_LANES; byte_idx++)
              cal_byte_mismatch_count_q[byte_idx] <= 32'd0;
            state_q <= PROBE_CAL_RUN_WRITES;
          end
        end
        PROBE_CAL_APPLY_BEST: begin
          if (cal_config_failed) begin
            state_q <= PROBE_ERROR;
          end else if (cal_config_done) begin
            read_addr_q <= 25'd0;
            compare_addr_q <= 25'd0;
            command_count_q <= 32'd0;
            response_count_q <= 32'd0;
            write_command_count_q <= 32'd0;
            write_data_count_q <= 32'd0;
            write_drain_count_q <= 32'd0;
            read_cycle_count_q <= 32'd0;
            command_stall_count_q <= 32'd0;
            checksum_q <= 32'd0;
            last_rdata_q <= 64'd0;
            mismatch_count_q <= 32'd0;
            first_mismatch_addr_q <= 28'd0;
            first_expected_q <= 64'd0;
            first_actual_q <= 64'd0;
            first_expected_full_q <= 576'd0;
            first_actual_full_q <= 576'd0;
            first_chunk_mismatch_q <= 9'd0;
            for (int byte_idx = 0; byte_idx < CAL_BYTE_LANES; byte_idx++)
              cal_byte_mismatch_count_q[byte_idx] <= 32'd0;

            if (cal_lane_last) begin
              sample_valid_count_q <= 8'd0;
              for (int sample_idx = 0; sample_idx < READBACK_SAMPLE_COUNT; sample_idx++)
                sample_rdata_q[sample_idx] <= 64'd0;
              dfii_final_q <= 1'b0;
              dfii_phasecmd_sweep_q <= 1'b0;
              dfii_assoc_sweep_q <= 1'b0;
              dfii_addr_sweep_q <= 1'b0;
              dfii_pattern_mode_q <= DFII_PATTERN_MODE_UNIFORM;
              dfii_phasecmd_index_q <= 4'd0;
              dfii_assoc_index_q <= 4'd0;
              dfii_addr_index_q <= 2'd0;
              for (int mode_idx = 0; mode_idx < 3; mode_idx++)
                dfii_mode_mismatch_q[mode_idx] <= 16'd0;
              for (int combo_idx = 0; combo_idx < 16; combo_idx++)
                dfii_phasecmd_mismatch_q[combo_idx] <= 16'd0;
              for (int assoc_idx = 0; assoc_idx < 16; assoc_idx++) begin
                dfii_assoc_nonzero_mask_q[assoc_idx] <= 16'd0;
                dfii_assoc_match_mask_q[assoc_idx] <= 16'd0;
                dfii_half_nonzero_high_q[assoc_idx] <= 4'd0;
                dfii_half_low_match_high_q[assoc_idx] <= 4'd0;
                dfii_half_high_match_low_q[assoc_idx] <= 16'd0;
                dfii_half_high_match_high_q[assoc_idx] <= 4'd0;
              end
              for (int addr_idx = 0;
                   addr_idx < DFII_ADDR_SLOTS;
                   addr_idx++) begin
                dfii_addr_mismatch_mask_q[addr_idx] <= 16'd0;
                dfii_addr_nonzero_mask_q[addr_idx] <= 16'd0;
                dfii_addr_match_mask_q[addr_idx] <= 16'd0;
              end
              state_q <= PROBE_RUN_WRITES;
            end else begin
              cal_lane_q <= cal_lane_q + 3'd1;
              cal_bitslip_q <= 3'd0;
              cal_wbitslip_q <= 3'd0;
              cal_delay_q <= 5'd0;
              state_q <= PROBE_CAL_NEXT_LANE;
            end
          end
        end
        PROBE_CAL_NEXT_LANE: begin
          state_q <= PROBE_CAL_CONFIG;
        end
        PROBE_PHASE_RUN_WRITES: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen) begin
            state_q <= PROBE_TIMEOUT;
          end else if (write_data_target_seen && write_command_target_seen) begin
            write_drain_count_q <= active_write_drain_cycles;
            state_q <= PROBE_PHASE_WRITE_DRAIN;
          end
        end
        PROBE_PHASE_WRITE_DRAIN: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
          else if (write_drain_done)
            state_q <= PROBE_PHASE_RUN_READS;
          else
            write_drain_count_q <= write_drain_count_q - 32'd1;
        end
        PROBE_PHASE_RUN_READS: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
        end
        PROBE_CAL_RUN_WRITES: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen) begin
            state_q <= PROBE_TIMEOUT;
          end else if (write_data_target_seen && write_command_target_seen) begin
            write_drain_count_q <= active_write_drain_cycles;
            state_q <= PROBE_CAL_WRITE_DRAIN;
          end
        end
        PROBE_CAL_WRITE_DRAIN: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
          else if (write_drain_done)
            state_q <= PROBE_CAL_RUN_READS;
          else
            write_drain_count_q <= write_drain_count_q - 32'd1;
        end
        PROBE_CAL_RUN_READS: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
        end
        PROBE_BYTE_CLEAR_WRITES: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen) begin
            state_q <= PROBE_TIMEOUT;
          end else if (write_data_target_seen && write_command_target_seen) begin
            write_command_count_q <= 32'd0;
            write_data_count_q <= 32'd0;
            command_stall_count_q <= 32'd0;
            state_q <= PROBE_BYTE_MASK_WRITES;
          end
        end
        PROBE_BYTE_MASK_WRITES: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen) begin
            state_q <= PROBE_TIMEOUT;
          end else if (write_data_target_seen && write_command_target_seen) begin
            write_drain_count_q <= active_write_drain_cycles;
            state_q <= PROBE_BYTE_WRITE_DRAIN;
          end
        end
        PROBE_BYTE_WRITE_DRAIN: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
          else if (write_drain_done) begin
            read_addr_q <= 25'd0;
            compare_addr_q <= 25'd0;
            command_count_q <= 32'd0;
            response_count_q <= 32'd0;
            state_q <= PROBE_BYTE_RUN_READS;
          end else begin
            write_drain_count_q <= write_drain_count_q - 32'd1;
          end
        end
        PROBE_BYTE_RUN_READS: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
        end
        PROBE_RUN_WRITES: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen) begin
            state_q <= PROBE_TIMEOUT;
          end else if (write_data_target_seen && write_command_target_seen) begin
            write_drain_count_q <= active_write_drain_cycles;
            state_q <= PROBE_WRITE_DRAIN;
          end
        end
        PROBE_WRITE_DRAIN: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
          else if (write_drain_done)
            state_q <= PROBE_RUN_READS;
          else
            write_drain_count_q <= write_drain_count_q - 32'd1;
        end
        PROBE_RUN_READS: begin
          read_cycle_count_q <= read_cycle_count_q + 32'd1;
          if (timeout_seen)
            state_q <= PROBE_TIMEOUT;
        end
        default: begin
          state_q <= state_q;
        end
      endcase

      if (write_state) begin
        if (wdata_valid && wdata_ready)
          write_data_count_q <= write_data_count_q + 32'd1;

        if (cmd_valid && cmd_ready)
          write_command_count_q <= write_command_count_q + 32'd1;

        if ((cmd_valid && !cmd_ready) || (wdata_valid && !wdata_ready))
          command_stall_count_q <= command_stall_count_q + 32'd1;
      end

      if (read_state) begin
        if (cmd_valid && cmd_ready) begin
          command_count_q <= command_count_q + 32'd1;
          read_addr_q <= read_addr_q + 25'd1;
        end else if (cmd_valid && !cmd_ready) begin
          command_stall_count_q <= command_stall_count_q + 32'd1;
        end

        if (rdata_valid) begin
          response_count_q <= response_count_q + 32'd1;
          compare_addr_q <= compare_addr_q + 25'd1;
          last_rdata_q <= rdata[63:0];
          checksum_q <= checksum_q ^ rdata[31:0] ^ rdata[63:32];
          if (byte_diag_read_state &&
              response_count_q < BYTE_DIAG_WORDS) begin
            byte_diag_rdata_q[response_count_q[2:0]] <= rdata[63:0];
            byte_diag_valid_count_q <= response_count_q[7:0] + 8'd1;
          end
          if (!cal_read_state && !byte_diag_read_state &&
              response_count_q < READBACK_SAMPLE_COUNT_WORDS) begin
            sample_rdata_q[response_count_q[2:0]] <= rdata[63:0];
            sample_valid_count_q <= response_count_q[7:0] + 8'd1;
          end
          if (cal_read_state) begin
            for (int byte_idx = 0; byte_idx < CAL_BYTE_LANES; byte_idx++)
              cal_byte_mismatch_count_q[byte_idx] <=
                cal_byte_mismatch_next[byte_idx];
          end
          if (response_mismatch) begin
            mismatch_count_q <= next_mismatch_count;
            if (!mismatch_seen) begin
              first_mismatch_addr_q <= compare_addr_q;
              first_expected_q <= expected_rdata[63:0];
              first_actual_q <= rdata[63:0];
              first_expected_full_q <= expected_rdata;
              first_actual_full_q <= rdata;
              first_chunk_mismatch_q <= response_chunk_mismatch;
            end
          end
          if ((response_count_q + 32'd1) >= active_target_words) begin
            if (byte_diag_read_state) begin
              read_addr_q <= 25'd0;
              compare_addr_q <= 25'd0;
              command_count_q <= 32'd0;
              response_count_q <= 32'd0;
              write_command_count_q <= 32'd0;
              write_data_count_q <= 32'd0;
              write_drain_count_q <= 32'd0;
              read_cycle_count_q <= 32'd0;
              command_stall_count_q <= 32'd0;
              checksum_q <= 32'd0;
              last_rdata_q <= 64'd0;
              mismatch_count_q <= 32'd0;
              first_mismatch_addr_q <= 28'd0;
              first_expected_q <= 64'd0;
              first_actual_q <= 64'd0;
              first_expected_full_q <= 576'd0;
              first_actual_full_q <= 576'd0;
              first_chunk_mismatch_q <= 9'd0;
              sample_valid_count_q <= 8'd0;
              for (int sample_idx = 0;
                   sample_idx < READBACK_SAMPLE_COUNT;
                   sample_idx++)
                sample_rdata_q[sample_idx] <= 64'd0;
              state_q <= PROBE_RUN_WRITES;
            end else if (phase_read_state) begin
              phase_mismatch_count_q[phase_candidate_index] <=
                phase_mismatch_next;
              phase_candidates_tested_q <= phase_candidates_tested_q + 32'd1;
              cal_candidates_tested_q <= phase_candidates_tested_q + 32'd1;
              if (phase_candidate_better) begin
                phase_best_mismatch_count_q <= phase_mismatch_next;
                phase_best_rd_q <= phase_rd_q;
                phase_best_wr_q <= phase_wr_q;
                best_mismatch_count_q <= phase_mismatch_next;
                best_bitslip_q <= {1'b0, phase_rd_q};
                best_wbitslip_q <= {1'b0, phase_wr_q};
                best_delay_q <= 5'd0;
              end
              if (phase_last_candidate) begin
                phase_rd_q <= phase_best_rd_next;
                phase_wr_q <= phase_best_wr_next;
                phase_best_mismatch_count_q <= phase_best_mismatch_next;
                best_mismatch_count_q <= phase_best_mismatch_next;
                best_bitslip_q <= {1'b0, phase_best_rd_next};
                best_wbitslip_q <= {1'b0, phase_best_wr_next};
                best_delay_q <= 5'd0;
                read_addr_q <= 25'd0;
                compare_addr_q <= 25'd0;
                command_count_q <= 32'd0;
                response_count_q <= 32'd0;
                write_command_count_q <= 32'd0;
                write_data_count_q <= 32'd0;
                write_drain_count_q <= 32'd0;
                read_cycle_count_q <= 32'd0;
                command_stall_count_q <= 32'd0;
                checksum_q <= 32'd0;
                last_rdata_q <= 64'd0;
                mismatch_count_q <= 32'd0;
                first_mismatch_addr_q <= 28'd0;
                first_expected_q <= 64'd0;
                first_actual_q <= 64'd0;
                first_expected_full_q <= 576'd0;
                first_actual_full_q <= 576'd0;
                first_chunk_mismatch_q <= 9'd0;
                state_q <= PROBE_PHASE_APPLY_BEST;
              end else begin
                if (phase_rd_q == 2'd3) begin
                  phase_rd_q <= 2'd0;
                  phase_wr_q <= phase_wr_q + 2'd1;
                end else begin
                  phase_rd_q <= phase_rd_q + 2'd1;
                end
                read_addr_q <= 25'd0;
                compare_addr_q <= 25'd0;
                command_count_q <= 32'd0;
                response_count_q <= 32'd0;
                write_command_count_q <= 32'd0;
                write_data_count_q <= 32'd0;
                write_drain_count_q <= 32'd0;
                read_cycle_count_q <= 32'd0;
                command_stall_count_q <= 32'd0;
                checksum_q <= 32'd0;
                last_rdata_q <= 64'd0;
                mismatch_count_q <= 32'd0;
                first_mismatch_addr_q <= 28'd0;
                first_expected_q <= 64'd0;
                first_actual_q <= 64'd0;
                first_expected_full_q <= 576'd0;
                first_actual_full_q <= 576'd0;
                first_chunk_mismatch_q <= 9'd0;
                state_q <= PROBE_PHASE_CONFIG;
              end
            end else if (cal_read_state) begin
              cal_last_mismatch_count_q <= cal_candidate_min_mismatch;
              cal_candidates_tested_q <= cal_candidates_tested_q + 32'd1;
              if (cal_candidate_min_mismatch < best_mismatch_count_q) begin
                best_mismatch_count_q <= cal_candidate_min_mismatch;
                best_bitslip_q <= cal_bitslip_q;
                best_wbitslip_q <= cal_wbitslip_q;
                best_delay_q <= cal_delay_q;
              end
              if (cal_candidate_better) begin
                lane_best_mismatch_count_q[cal_lane_q] <=
                  cal_candidate_min_mismatch;
                lane_best_bitslip_q[cal_lane_q] <= cal_bitslip_q;
                lane_best_wbitslip_q[cal_lane_q] <= cal_wbitslip_q;
                lane_best_delay_q[cal_lane_q] <= cal_delay_q;
                lane_best_logical_byte_q[cal_lane_q] <=
                  cal_candidate_min_byte;
              end
              if (cal_last_candidate) begin
                selected_bitslip_q <= lane_best_bitslip_next;
                selected_wbitslip_q <= lane_best_wbitslip_next;
                selected_delay_q <= lane_best_delay_next;
                lane_selected_bitslip_q[cal_lane_q] <= lane_best_bitslip_next;
                lane_selected_wbitslip_q[cal_lane_q] <= lane_best_wbitslip_next;
                lane_selected_delay_q[cal_lane_q] <= lane_best_delay_next;
                lane_selected_logical_byte_q[cal_lane_q] <=
                  lane_best_logical_byte_next;
                lane_best_mismatch_count_q[cal_lane_q] <= lane_best_mismatch_next;
                lane_best_wbitslip_q[cal_lane_q] <= lane_best_wbitslip_next;
                read_addr_q <= 25'd0;
                compare_addr_q <= 25'd0;
                command_count_q <= 32'd0;
                response_count_q <= 32'd0;
                write_command_count_q <= 32'd0;
                write_data_count_q <= 32'd0;
                write_drain_count_q <= 32'd0;
                read_cycle_count_q <= 32'd0;
                command_stall_count_q <= 32'd0;
                checksum_q <= 32'd0;
                last_rdata_q <= 64'd0;
                mismatch_count_q <= 32'd0;
                first_mismatch_addr_q <= 28'd0;
                first_expected_q <= 64'd0;
                first_actual_q <= 64'd0;
                first_expected_full_q <= 576'd0;
                first_actual_full_q <= 576'd0;
                first_chunk_mismatch_q <= 9'd0;
                state_q <= PROBE_CAL_APPLY_BEST;
              end else begin
                if (cal_delay_q == 5'd31) begin
                  cal_delay_q <= 5'd0;
                  if (cal_bitslip_q == 3'd7) begin
                    cal_bitslip_q <= 3'd0;
                    cal_wbitslip_q <= cal_wbitslip_q + 3'd1;
                  end else begin
                    cal_bitslip_q <= cal_bitslip_q + 3'd1;
                  end
                end else begin
                  cal_delay_q <= cal_delay_q + 5'd1;
                end
                read_addr_q <= 25'd0;
                compare_addr_q <= 25'd0;
                command_count_q <= 32'd0;
                response_count_q <= 32'd0;
                write_command_count_q <= 32'd0;
                write_data_count_q <= 32'd0;
                write_drain_count_q <= 32'd0;
                read_cycle_count_q <= 32'd0;
                command_stall_count_q <= 32'd0;
                checksum_q <= 32'd0;
                last_rdata_q <= 64'd0;
                mismatch_count_q <= 32'd0;
                first_mismatch_addr_q <= 28'd0;
                first_expected_q <= 64'd0;
                first_actual_q <= 64'd0;
                first_expected_full_q <= 576'd0;
                first_actual_full_q <= 576'd0;
                first_chunk_mismatch_q <= 9'd0;
                state_q <= PROBE_CAL_CONFIG;
              end
            end else begin
              state_q <= (next_mismatch_count != 32'd0) ?
                PROBE_ERROR : PROBE_DONE;
            end
          end
        end
      end
    end
  end

  logic [JTAG_DEBUG_WIDTH - 1:0] jtag_debug_payload;
  wire [15:0] status_bits;
  wire [31:0] extended_status_bits;

  assign status_bits = {
    wb_timeout_seen_q || cal_wb_timeout_seen_q || dfii_wb_timeout_seen_q,
    wb_error_seen_q || cal_wb_error_seen_q || dfii_wb_error_seen_q,
    init_seq_error_q,
    init_seq_done,
    init_seq_running,
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

  assign extended_status_bits = {
    9'd0,
    cal_last_candidate,
    cal_candidate_success,
    cal_config_done,
    cal_mode || phase_mode,
    config_reset_done,
    core_rst,
    wb_ctrl_cyc_mux,
    wb_ctrl_stb_mux,
    wb_ctrl_we_mux,
    wb_ctrl_ack,
    wb_ctrl_err,
    state_q == PROBE_TIMEOUT,
    state_q == PROBE_ERROR,
    state_q == PROBE_DONE,
    read_target_seen,
    mismatch_seen,
    write_drain_done,
    write_command_target_seen,
    write_data_target_seen,
    cmd_we,
    cmd_valid,
    wdata_valid,
    wdata_ready
  };

  always_comb begin
    jtag_debug_payload = '0;
    jtag_debug_payload[0 +: 32] = JTAG_DEBUG_MAGIC;
    jtag_debug_payload[32 +: 8] = JTAG_DEBUG_VERSION;
    jtag_debug_payload[40 +: 8] = {3'd0, state_q};
    jtag_debug_payload[48 +: 16] = status_bits;
    jtag_debug_payload[64 +: 32] = read_cycle_count_q;
    jtag_debug_payload[96 +: 32] = command_count_q;
    jtag_debug_payload[128 +: 32] = response_count_q;
    jtag_debug_payload[160 +: 32] = command_stall_count_q;
    jtag_debug_payload[192 +: 32] = checksum_q;
    jtag_debug_payload[224 +: 64] = last_rdata_q;
    jtag_debug_payload[288 +: 28] = read_addr_q;
    jtag_debug_payload[320 +: 32] = active_target_words;
    jtag_debug_payload[352 +: 8] = {4'd0, init_state_q};
    jtag_debug_payload[360 +: 8] = init_step_q;
    jtag_debug_payload[368 +: 32] = init_delay_q;
    jtag_debug_payload[400 +: 32] =
      wb_ack_count_q + cal_wb_ack_count_q + dfii_wb_ack_count_q;
    jtag_debug_payload[432 +: 32] =
      wb_wait_count_q + cal_wb_wait_count_q + dfii_wb_wait_count_q;
    jtag_debug_payload[464 +: 16] =
      init_seq_running ? last_wb_addr_q :
      (dfii_seq_running ? dfii_last_wb_addr_q : cal_last_wb_addr_q);
    jtag_debug_payload[480 +: 32] =
      init_seq_running ? last_wb_data_q :
      (dfii_seq_running ? dfii_last_wb_data_q : cal_last_wb_data_q);
    jtag_debug_payload[512 +: 32] = write_data_count_q;
    jtag_debug_payload[544 +: 32] = write_command_count_q;
    jtag_debug_payload[576 +: 32] = {4'd0, compare_addr_q};
    jtag_debug_payload[608 +: 32] = mismatch_count_q;
    jtag_debug_payload[640 +: 32] = {4'd0, first_mismatch_addr_q};
    jtag_debug_payload[672 +: 64] = first_expected_q;
    jtag_debug_payload[736 +: 64] = first_actual_q;
    jtag_debug_payload[800 +: 32] = extended_status_bits;
    jtag_debug_payload[832 +: 8] = {6'd0, phase_rd_q};
    jtag_debug_payload[840 +: 8] = {6'd0, phase_wr_q};
    jtag_debug_payload[848 +: 8] = {4'd0, cal_config_state_q};
    jtag_debug_payload[856 +: 8] = cal_config_step_q;
    jtag_debug_payload[864 +: 32] = phase_candidates_tested_q;
    jtag_debug_payload[896 +: 32] = phase_best_mismatch_count_q;
    jtag_debug_payload[928 +: 8] = {6'd0, phase_best_rd_q};
    jtag_debug_payload[936 +: 8] = {6'd0, phase_best_wr_q};
    jtag_debug_payload[944 +: 8] = {6'd0, phase_best_rd_q};
    jtag_debug_payload[952 +: 8] = {6'd0, phase_best_wr_q};
    jtag_debug_payload[960 +: 8] = {4'd0, phase_candidate_index};
    jtag_debug_payload[968 +: 32] = phase_best_mismatch_count_q;
    for (int lane_idx = 0; lane_idx < 8; lane_idx++) begin
      jtag_debug_payload[1000 + lane_idx * 8 +: 8] = {
        lane_selected_bitslip_q[lane_idx],
        lane_selected_delay_q[lane_idx]
      };
      jtag_debug_payload[1064 + lane_idx * 8 +: 8] =
        (lane_best_mismatch_count_q[lane_idx] > 32'd255) ?
        8'hff : lane_best_mismatch_count_q[lane_idx][7:0];
      jtag_debug_payload[1136 + lane_idx * 4 +: 4] = {
        1'b0,
        lane_selected_wbitslip_q[lane_idx]
      };
    end
    jtag_debug_payload[1128 +: 8] = {
      lane_best_bitslip_q[cal_lane_q],
      lane_best_delay_q[cal_lane_q]
    };
    jtag_debug_payload[1168 +: 8] = {
      5'd0,
      lane_best_wbitslip_q[cal_lane_q]
    };
    jtag_debug_payload[1184 +: 8] = sample_valid_count_q;
    for (int sample_idx = 0; sample_idx < READBACK_SAMPLE_COUNT; sample_idx++)
      jtag_debug_payload[1216 + sample_idx * 64 +: 64] =
        sample_rdata_q[sample_idx];
    jtag_debug_payload[1728 +: 8] = {5'd0, dfii_seq_state_q};
    jtag_debug_payload[1736 +: 8] = dfii_step_q;
    jtag_debug_payload[1744 +: 32] = dfii_wb_ack_count_q;
    jtag_debug_payload[1776 +: 32] = dfii_wb_wait_count_q;
    jtag_debug_payload[1808 +: 32] = {12'd0, dfii_word_mismatch_q};
    jtag_debug_payload[1840 +: 32] = dfii_last_read_data_q;
    for (int dfii_idx = 0; dfii_idx < 16; dfii_idx++)
      jtag_debug_payload[1872 + dfii_idx * 32 +: 32] =
        dfii_rddata_q[dfii_idx];
    for (int dfii_high_idx = 0; dfii_high_idx < 4; dfii_high_idx++)
      jtag_debug_payload[4096 + dfii_high_idx * 32 +: 32] =
        dfii_rddata_q[dfii_high_idx + 16];
    for (int mode_idx = 0; mode_idx < 3; mode_idx++)
      jtag_debug_payload[2384 + mode_idx * 16 +: 16] =
        dfii_mode_mismatch_q[mode_idx];
    jtag_debug_payload[2432 +: 8] = {6'd0, dfii_pattern_mode_q};
    for (int combo_idx = 0; combo_idx < 16; combo_idx++)
      jtag_debug_payload[2464 + combo_idx * 16 +: 16] =
        dfii_phasecmd_mismatch_q[combo_idx];
    jtag_debug_payload[2720 +: 2] = dfii_write_command_phase;
    jtag_debug_payload[2722 +: 2] = dfii_read_command_phase;
    jtag_debug_payload[2728 +: 4] = dfii_phasecmd_index_q;
    jtag_debug_payload[2736 +: 8] = byte_diag_valid_count_q;
    for (int byte_sample_idx = 0;
         byte_sample_idx < BYTE_DIAG_SAMPLE_COUNT;
         byte_sample_idx++)
      jtag_debug_payload[2752 + byte_sample_idx * 64 +: 64] =
        byte_diag_rdata_q[byte_sample_idx];
    jtag_debug_payload[3264 +: 4] = dfii_assoc_index_q;
    jtag_debug_payload[3272 +: 8] = {
      DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY,
      DFII_EDGE_COMP_PROBE_ONLY,
      DFII_EDGE_MAP_PROBE_ONLY,
      DFII_RBITSLIP_SWEEP_ONLY,
      DFII_WBITSLIP_SWEEP_ONLY,
      dfii_addr_sweep_q,
      dfii_assoc_sweep_q,
      dfii_final_q
    };
    for (int assoc_idx = 0; assoc_idx < 16; assoc_idx++) begin
      jtag_debug_payload[3296 + assoc_idx * 16 +: 16] =
        dfii_assoc_nonzero_mask_q[assoc_idx];
      jtag_debug_payload[3552 + assoc_idx * 16 +: 16] =
        dfii_assoc_match_mask_q[assoc_idx];
    end
    jtag_debug_payload[3808 +: 4] = {2'd0, dfii_addr_index_q};
    jtag_debug_payload[3816 +: 8] = {
      DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY,
      DFII_EDGE_COMP_PROBE_ONLY,
      DFII_EDGE_MAP_PROBE_ONLY,
      DFII_RBITSLIP_SWEEP_ONLY,
      DFII_WBITSLIP_SWEEP_ONLY,
      dfii_addr_sweep_q,
      dfii_assoc_sweep_q,
      dfii_final_q
    };
    jtag_debug_payload[3824 +: 64] = dfii_addr_column_payload;
    jtag_debug_payload[3888 +: 64] = dfii_addr_mismatch_payload;
    jtag_debug_payload[3952 +: 64] = dfii_addr_nonzero_payload;
    jtag_debug_payload[4016 +: 64] = dfii_addr_match_payload;
    jtag_debug_payload[4080 +: 1] = DFII_DISABLE_WRITE_COMMAND;
    jtag_debug_payload[4081 +: 1] = DFII_PHASE_MATRIX_ONLY;
    jtag_debug_payload[4082 +: 1] = DFII_SOURCE_COMMAND_MATRIX_ONLY;
    jtag_debug_payload[4083 +: 1] = DFII_SOURCE_ORDER_MATRIX_ONLY;
    jtag_debug_payload[4084 +: 2] = DFII_SOURCE_COMMAND_READ_PHASE[1:0];
    jtag_debug_payload[4086 +: 1] = DFII_WBITSLIP_SWEEP_ONLY;
    jtag_debug_payload[4087 +: 1] = DFII_HALF_ORDER_MATRIX_ONLY;
    jtag_debug_payload[4088 +: 2] = DFII_SOURCE_ORDER_SOURCE_PHASE[1:0];
    jtag_debug_payload[4090 +: 2] = DFII_SOURCE_ORDER_WRITE_PHASE[1:0];
    jtag_debug_payload[4092 +: 2] = DFII_SOURCE_ORDER_READ_PHASE[1:0];
    jtag_debug_payload[4094 +: 1] = DFII_DISPLACEMENT_PROBE_ONLY;
    jtag_debug_payload[4095 +: 1] = DFII_CSR_ECHO_PROBE_ONLY;
    jtag_debug_payload[4224 +: 64] = dfii_half_nonzero_high_payload;
    jtag_debug_payload[4288 +: 64] = dfii_half_low_match_high_payload;
    jtag_debug_payload[4352 +: 256] = dfii_half_high_match_low_payload;
    jtag_debug_payload[4608 +: 64] = dfii_half_high_match_high_payload;
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
    .user_port_native_0_cmd_addr(cmd_addr),
    .user_port_native_0_cmd_ready(cmd_ready),
    .user_port_native_0_cmd_valid(cmd_valid),
    .user_port_native_0_cmd_we(cmd_we),
    .user_port_native_0_rdata_data(rdata),
    .user_port_native_0_rdata_ready(1'b1),
    .user_port_native_0_rdata_valid(rdata_valid),
    .user_port_native_0_wdata_data(wdata),
    .user_port_native_0_wdata_ready(wdata_ready),
    .user_port_native_0_wdata_valid(wdata_valid),
    .user_port_native_0_wdata_we(wdata_we),
    .wb_ctrl_ack(wb_ctrl_ack),
    .wb_ctrl_adr(wb_ctrl_adr_mux),
    .wb_ctrl_bte(2'd0),
    .wb_ctrl_cti(3'd0),
    .wb_ctrl_cyc(wb_ctrl_cyc_mux),
    .wb_ctrl_dat_r(wb_ctrl_dat_r),
    .wb_ctrl_dat_w(wb_ctrl_dat_w_mux),
    .wb_ctrl_err(wb_ctrl_err),
    .wb_ctrl_sel(4'hf),
    .wb_ctrl_stb(wb_ctrl_stb_mux),
    .wb_ctrl_we(wb_ctrl_we_mux)
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
