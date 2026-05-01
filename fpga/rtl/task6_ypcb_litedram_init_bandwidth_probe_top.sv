module task6_ypcb_litedram_init_bandwidth_probe_top #(
  parameter int JTAG_DEBUG_WIDTH = 6464,
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
  parameter bit DFII_EDGE_COMP_ACTIVE_ONLY = 1'b0,
  parameter bit DFII_EDGE_COMP_BIST_ONLY = 1'b0,
  parameter bit DFII_EDGE_COMP_ADDRWALK_ONLY = 1'b0,
  parameter bit DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE = 1'b0,
  parameter bit DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN = 1'b0,
  parameter bit DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN_RELEASE = 1'b0,
  parameter bit DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN_SPARSE = 1'b0,
  parameter bit NATIVE_SPARSE_READSCAN_ONLY = 1'b0,
  parameter bit NATIVE_READSCAN_SINGLE_OUTSTANDING = 1'b0,
  parameter bit DFII_BYTE_PHASE_ASSOC_PROBE_ONLY = 1'b0,
  parameter bit DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY = 1'b0,
  parameter bit DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY = 1'b0,
  parameter bit DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY = 1'b0,
  parameter bit DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY = 1'b0,
  parameter bit NATIVE_BYTE_ASSOC_PROBE_ONLY = 1'b0,
  parameter bit NATIVE_BYTE_ASSOC_FULL_WE = 1'b0,
  parameter bit DFII_EDGE_COMP_CSR_ONLY = 1'b0,
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
  localparam logic [7:0] JTAG_DEBUG_VERSION = 8'd109;
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
  // v78 adds per-variant wrdata CSR echo masks before issuing DRAM commands.
  // v79 prunes v78 to a CSR-only edge-variant sweep after v78 init timeout.
  // v80 restores DRAM final-word variants and records DFI wrdata word4 taps.
  // v81 reports all 20 edge-comp read mismatch bits for final-word variants.
  // v82 packs those high mismatch bits into the existing edge-comp flags word.
  // v83 promotes the all-phase final-word compensation to the active DFII test.
  // v84 adds an eight-case compensated DFII BIST before native/rowstream use.
  // v85 adds a 16-column compensated DFII address-walk BIST.
  // v86 runs that address-walk first, then runs a compact native-port gate.
  // v87 skips native writes and scans native reads after the address-walk.
  // v88 repeats hardware-control release and waits before that read-scan.
  // v89 changes that read-scan to the sparse DFII address-walk columns.
  // v90 runs the same sparse native read-scan without prior DFII traffic.
  // v91 keeps the v89 logic shape while skipping DFII before sparse reads.
  // v92 serializes native sparse reads to one outstanding command.
  // v93 adds a one-hot DFI byte/phase association matrix probe.
  // v94 adds a compact source/write-command/read-command phase matrix.
  // v95 adds DDRPHY wrphase/rdphase to that discriminator.
  // v96 probes the compensated final-word lane7/lane8 association with DFI taps.
  // v97 adds a native-port 72-byte write-enable/data association matrix.
  // v98 scans native readback bytes sequentially so the probe meets timing.
  // v99 repeats native association with full write-enable to split byte-enable
  // semantics from write-data association.
  // v100 exposes the DFI write-data debug tap during native association.
  // v102 keeps native accepted-data counters but restores broad DFI capture.
  // v103 adds a generated LiteDRAM native-wdata hold experiment.
  // v104 paces native association writes by DFI wrdata consumption.
  // v105 exposes DFI command/address taps during native writes.
  // v106 records DFI command/data/ODT/DQ/DQS temporal association.
  // v107 removes the intrusive PHY timing tap while keeping DFI timing taps.
  // v108 reruns association probes after single-driver native DFI hold cleanup.
  // v109 adds a phase-0-only byte/word association target after the command
  // matrix showed only DFII source phase 0 returning tags.
  localparam int CAL_BYTE_LANES = 8;
  localparam int PHASE_CANDIDATES = 16;
  localparam int DFII_BYTE_PHASE_SOURCES = 72;
  localparam int DFII_BYTE_PHASE_PHASE0_SOURCES = 18;
  localparam int DFII_BYTE_PHASE_CMD_SOURCES = 64;
  localparam int DFII_BYTE_PHASE_PHY_PHASE_SOURCES = 64;
  localparam int DFII_BYTE_PHASE_FINAL_SOURCES = 16;
  localparam int NATIVE_BYTE_ASSOC_SOURCES = 72;
  localparam logic [6:0] DFII_BYTE_PHASE_DEST_NONE = 7'h7f;
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
    PROBE_DFII_WBITSLIP_CONFIG = 5'd26,
    PROBE_DFII_BYTE_SCAN = 5'd27
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

  function automatic logic [63:0] first_nonzero_chunk_data(
    input logic [575:0] data
  );
    logic found;
    begin
      first_nonzero_chunk_data = 64'd0;
      found = 1'b0;
      for (int chunk_idx = 0; chunk_idx < 9; chunk_idx++) begin
        if (!found && data[chunk_idx * 64 +: 64] != 64'd0) begin
          first_nonzero_chunk_data = data[chunk_idx * 64 +: 64];
          found = 1'b1;
        end
      end
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
  logic [31:0] native_nonzero_count_q = 32'd0;
  logic [27:0] native_first_nonzero_addr_q = 28'd0;
  logic [63:0] native_first_nonzero_data_q = 64'd0;
  logic [8:0] native_first_nonzero_chunk_q = 9'd0;
  logic [8:0] native_nonzero_chunk_seen_q = 9'd0;
  logic [31:0] native_change_count_q = 32'd0;
  logic [27:0] native_last_addr_q = 28'd0;
  logic [63:0] native_last_data_q = 64'd0;
  logic [31:0] native_max_outstanding_q = 32'd0;
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
  logic [DFII_RDDATA_WORDS - 1:0] dfii_csr_mismatch_q = '0;
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
  logic [6:0] dfii_byte_phase_source_q = 7'd0;
  logic dfii_byte_phase_invert_q = 1'b0;
  logic [6:0] dfii_byte_phase_dest_q [0:DFII_BYTE_PHASE_SOURCES - 1];
  logic [6:0] dfii_byte_phase_inv_dest_q [0:DFII_BYTE_PHASE_SOURCES - 1];
  logic [3:0] dfii_byte_phase_count_q [0:DFII_BYTE_PHASE_SOURCES - 1];
  logic [3:0] dfii_byte_phase_inv_count_q [0:DFII_BYTE_PHASE_SOURCES - 1];

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
  wire [31:0] outstanding_count;
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
  wire [3:0] debug_dfi_wrdata_en;
  wire [63:0] debug_dfi_wrdata_word4;
  wire [7:0] debug_dfi_wrdata_word4_mask;
  wire [3:0] debug_dfi_write_cmd;
  wire [3:0] debug_dfi_read_cmd;
  wire [3:0] debug_dfi_activate_cmd;
  wire [3:0] debug_dfi_odt;
  wire [3:0] debug_dfi_rddata_en;
  wire [3:0] debug_dfi_rddata_valid;
  wire [7:0] debug_phy_write_timing;
  wire [59:0] debug_dfi_address;
  wire [11:0] debug_dfi_bank;
  wire [3:0] debug_dfi_wrdata_word4_nonzero;
  wire [3:0] debug_dfi_wrdata_word4_unmasked;
  wire native_debug_wdata_accept;
  wire native_debug_cmd_accept;
  wire [63:0] native_debug_wdata_word4;
  wire [7:0] native_debug_wdata_word4_we;
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
  wire dfii_edge_comp_active_mode;
  wire dfii_edge_comp_bist_mode;
  wire dfii_edge_comp_addrwalk_mode;
  wire dfii_byte_phase_assoc_mode;
  wire dfii_byte_phase_phase0_assoc_mode;
  wire dfii_byte_phase_cmd_matrix_mode;
  wire dfii_byte_phase_phy_phase_matrix_mode;
  wire dfii_byte_phase_final_matrix_mode;
  wire [6:0] dfii_byte_phase_active_sources;
  wire native_readscan_mode;
  wire native_readscan_release_mode;
  wire native_sparse_readscan_mode;
  wire native_sparse_readscan_only_mode;
  wire native_readscan_single_outstanding_mode;
  wire native_byte_assoc_mode;
  wire dfii_edge_lane7_locator_probe_mode;
  wire dfii_bitslip_sweep_mode;
  wire dfii_wide_word_mode;
  wire [1:0] dfii_matrix_source_phase;
  wire [3:0] dfii_result_slot;
  wire [7:0] dfii_source_order_tag;
  wire [7:0] dfii_half_low_tag;
  wire [7:0] dfii_half_high_tag;
  wire [7:0] dfii_phy_phase_step_offset;
  wire [4:0] dfii_wrdata_index20;
  wire [4:0] dfii_rddata_index20;
  wire [4:0] dfii_read_store_index;
  wire [7:0] dfii_seq_done_step;
  wire [4:0] dfii_csr_echo_read_index20;
  wire [4:0] dfii_edge_comp_csr_echo_read_index20;
  wire dfii_edge_comp_csr_echo_read_step;
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
  logic [31:0] dfii_bist_mismatch_word_count;
  logic [4:0] dfii_bist_first_mismatch_word;
  logic [31:0] dfii_bist_first_expected_word;
  logic [31:0] dfii_bist_first_actual_word;
  logic dfii_bist_mismatch_seen;
  logic [4:0] dfii_byte_phase_scan_word_q;
  logic [1:0] dfii_byte_phase_scan_byte_q;
  logic [6:0] dfii_byte_phase_scan_dest_q;
  logic [3:0] dfii_byte_phase_scan_count_q;
  logic [575:0] native_byte_assoc_rdata_q;
  wire [7:0] dfii_byte_phase_scan_byte_value;
  wire dfii_byte_phase_scan_match;
  wire dfii_byte_phase_scan_last;
  wire [6:0] dfii_byte_phase_scan_dest_next;
  wire [3:0] dfii_byte_phase_scan_count_next;
  logic [575:0] dfii_byte_phase_dest0_payload;
  logic [287:0] dfii_byte_phase_count0_payload;
  logic [575:0] dfii_byte_phase_dest1_payload;
  logic [287:0] dfii_byte_phase_count1_payload;
  logic [3:0] dfi_debug_wrdata_seen_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_last_en_q = 4'd0;
  logic [15:0] dfi_debug_wrdata_word4_q [0:3];
  logic [7:0] dfi_debug_wrdata_word4_mask_q = 8'd0;
  logic [3:0] dfi_debug_wrdata_event_count_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_word4_nonzero_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_word4_unmasked_q = 4'd0;
  logic [7:0] native_debug_wdata_accept_count_q = 8'd0;
  logic [7:0] native_debug_cmd_accept_count_q = 8'd0;
  logic [6:0] native_debug_last_wdata_source_q = 7'd0;
  logic native_debug_last_wdata_invert_q = 1'b0;
  logic [63:0] native_debug_last_wdata_word4_q = 64'd0;
  logic [7:0] native_debug_last_wdata_word4_we_q = 8'd0;
  logic native_dfi_pace_wait_q = 1'b0;
  logic [3:0] dfi_debug_write_cmd_seen_q = 4'd0;
  logic [3:0] dfi_debug_read_cmd_seen_q = 4'd0;
  logic [3:0] dfi_debug_activate_cmd_seen_q = 4'd0;
  logic [3:0] dfi_debug_write_cmd_last_q = 4'd0;
  logic [3:0] dfi_debug_write_cmd_event_count_q = 4'd0;
  logic [59:0] dfi_debug_write_cmd_address_q = 60'd0;
  logic [11:0] dfi_debug_write_cmd_bank_q = 12'd0;
  logic [3:0] dfi_debug_odt_seen_q = 4'd0;
  logic [3:0] dfi_debug_rddata_en_seen_q = 4'd0;
  logic [3:0] dfi_debug_rddata_valid_seen_q = 4'd0;
  logic [7:0] dfi_debug_phy_write_timing_seen_q = 8'd0;
  logic [15:0] dfi_debug_wrdata_after_write_cmd_q = 16'd0;
  logic [15:0] dfi_debug_write_cmd_after_wrdata_q = 16'd0;
  logic [3:0] dfi_debug_write_cmd_odt_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_odt_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_dq_oe_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_dqs_oe_q = 4'd0;
  logic [3:0] dfi_debug_write_cmd_hist0_q = 4'd0;
  logic [3:0] dfi_debug_write_cmd_hist1_q = 4'd0;
  logic [3:0] dfi_debug_write_cmd_hist2_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_hist0_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_hist1_q = 4'd0;
  logic [3:0] dfi_debug_wrdata_hist2_q = 4'd0;
  wire init_seq_done;
  wire init_seq_running;
  wire response_mismatch;
  wire lane_response_mismatch;
  wire [8:0] response_chunk_mismatch;
  wire [8:0] response_nonzero_chunk;
  wire response_any_nonzero;
  wire [63:0] response_first_nonzero_data;
  wire [24:0] active_read_addr;
  wire [24:0] active_compare_addr;
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
    logic [71:0] mask;
    begin
      mask = 72'd0;
      for (int beat_idx = 0; beat_idx < NATIVE_BEATS; beat_idx++)
        mask[beat_idx * 9 + {1'b0, lane[2:0]}] = 1'b1;
      byte_diag_we_mask = mask;
    end
  endfunction

  function automatic logic [7:0] native_byte_assoc_tag(
    input logic [6:0] source,
    input logic invert
  );
    logic [7:0] tag;
    begin
      tag = 8'h80 + {1'b0, source};
      native_byte_assoc_tag = invert ? ~tag : tag;
    end
  endfunction

  function automatic logic [575:0] native_byte_assoc_word(
    input logic [6:0] source,
    input logic invert
  );
    begin
      native_byte_assoc_word = 576'd0;
      native_byte_assoc_word[{3'd0, source, 3'd0} +: 8] =
        native_byte_assoc_tag(source, invert);
    end
  endfunction

  function automatic logic [71:0] native_byte_assoc_we_mask(
    input logic [6:0] source
  );
    begin
      native_byte_assoc_we_mask = 72'd0;
      native_byte_assoc_we_mask[source] = 1'b1;
    end
  endfunction

  function automatic logic [6:0] native_byte_assoc_dest(
    input logic [575:0] data,
    input logic [6:0] source,
    input logic invert
  );
    logic found;
    logic [7:0] tag;
    begin
      native_byte_assoc_dest = DFII_BYTE_PHASE_DEST_NONE;
      found = 1'b0;
      tag = native_byte_assoc_tag(source, invert);
      for (int byte_idx = 0; byte_idx < NATIVE_BYTE_ASSOC_SOURCES; byte_idx++) begin
        if (!found && data[byte_idx * 8 +: 8] == tag) begin
          native_byte_assoc_dest = byte_idx[6:0];
          found = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [3:0] native_byte_assoc_count(
    input logic [575:0] data,
    input logic [6:0] source,
    input logic invert
  );
    logic [7:0] tag;
    begin
      native_byte_assoc_count = 4'd0;
      tag = native_byte_assoc_tag(source, invert);
      for (int byte_idx = 0; byte_idx < NATIVE_BYTE_ASSOC_SOURCES; byte_idx++) begin
        if (data[byte_idx * 8 +: 8] == tag &&
            native_byte_assoc_count != 4'hf)
          native_byte_assoc_count = native_byte_assoc_count + 4'd1;
      end
    end
  endfunction

  function automatic logic [7:0] native_byte_assoc_scan_byte(
    input logic [575:0] data,
    input logic [4:0] word,
    input logic [1:0] byte_index
  );
    begin
      native_byte_assoc_scan_byte =
        data[{word, byte_index, 3'd0} +: 8];
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

  function automatic logic [1:0] dfii_byte_phase_source_phase(
    input logic [6:0] source
  );
    begin
      if (source < 7'd18)
        dfii_byte_phase_source_phase = 2'd0;
      else if (source < 7'd36)
        dfii_byte_phase_source_phase = 2'd1;
      else if (source < 7'd54)
        dfii_byte_phase_source_phase = 2'd2;
      else
        dfii_byte_phase_source_phase = 2'd3;
    end
  endfunction

  function automatic logic [4:0] dfii_byte_phase_source_slot(
    input logic [6:0] source
  );
    begin
      if (source < 7'd18)
        dfii_byte_phase_source_slot = source[4:0];
      else if (source < 7'd36)
        dfii_byte_phase_source_slot = source - 7'd18;
      else if (source < 7'd54)
        dfii_byte_phase_source_slot = source - 7'd36;
      else
        dfii_byte_phase_source_slot = source - 7'd54;
    end
  endfunction

  function automatic logic [7:0] dfii_byte_phase_tag(
    input logic [6:0] source,
    input logic invert
  );
    logic [7:0] tag;
    begin
      tag = 8'h80 + {1'b0, source};
      dfii_byte_phase_tag = invert ? ~tag : tag;
    end
  endfunction

  function automatic logic [2:0] dfii_byte_phase_slot_word(
    input logic [4:0] slot
  );
    begin
      if (slot < 5'd4)
        dfii_byte_phase_slot_word = 3'd0;
      else if (slot < 5'd8)
        dfii_byte_phase_slot_word = 3'd1;
      else if (slot < 5'd12)
        dfii_byte_phase_slot_word = 3'd2;
      else if (slot < 5'd16)
        dfii_byte_phase_slot_word = 3'd3;
      else
        dfii_byte_phase_slot_word = 3'd4;
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_slot_byte(
    input logic [4:0] slot
  );
    begin
      if (slot < 5'd4)
        dfii_byte_phase_slot_byte = slot[1:0];
      else if (slot < 5'd8)
        dfii_byte_phase_slot_byte = slot[1:0];
      else if (slot < 5'd12)
        dfii_byte_phase_slot_byte = slot - 5'd8;
      else if (slot < 5'd16)
        dfii_byte_phase_slot_byte = slot - 5'd12;
      else
        dfii_byte_phase_slot_byte = slot - 5'd16;
    end
  endfunction

  function automatic logic [31:0] dfii_byte_phase_assoc_write_word(
    input logic [1:0] phase,
    input logic [2:0] word,
    input logic [6:0] source,
    input logic invert
  );
    logic [4:0] slot;
    begin
      slot = dfii_byte_phase_source_slot(source);
      dfii_byte_phase_assoc_write_word = 32'd0;
      if (phase == dfii_byte_phase_source_phase(source) &&
          word == dfii_byte_phase_slot_word(slot))
        dfii_byte_phase_assoc_write_word =
          dfii_place_byte(
            dfii_byte_phase_tag(source, invert),
            dfii_byte_phase_slot_byte(slot)
          );
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_cmd_source_phase(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_cmd_source_phase = source[5:4];
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_cmd_write_phase(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_cmd_write_phase = source[3:2];
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_cmd_read_phase(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_cmd_read_phase = source[1:0];
    end
  endfunction

  function automatic logic [31:0] dfii_byte_phase_cmd_matrix_write_word(
    input logic [1:0] phase,
    input logic [2:0] word,
    input logic [6:0] source,
    input logic invert
  );
    begin
      dfii_byte_phase_cmd_matrix_write_word = 32'd0;
      if (phase == dfii_byte_phase_cmd_source_phase(source) && word == 3'd0)
        dfii_byte_phase_cmd_matrix_write_word =
          dfii_place_byte(dfii_byte_phase_tag(source, invert), 2'd0);
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_phy_wrphase(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_phy_wrphase = source[3:2];
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_phy_rdphase(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_phy_rdphase = source[1:0];
    end
  endfunction

  function automatic logic dfii_byte_phase_final_broadcast(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_final_broadcast = source[3];
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_final_source_phase(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_final_source_phase = source[2:1];
    end
  endfunction

  function automatic logic [3:0] dfii_byte_phase_final_lane(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_final_lane = source[0] ? 4'd8 : 4'd7;
    end
  endfunction

  function automatic logic [1:0] dfii_byte_phase_final_byte(
    input logic [6:0] source
  );
    begin
      dfii_byte_phase_final_byte = source[0] ? 2'd1 : 2'd0;
    end
  endfunction

  function automatic logic [31:0] dfii_byte_phase_final_matrix_write_word(
    input logic [1:0] phase,
    input logic [2:0] word,
    input logic [6:0] source,
    input logic invert
  );
    begin
      dfii_byte_phase_final_matrix_write_word = 32'd0;
      if (word == 3'd4 &&
          (dfii_byte_phase_final_broadcast(source) ||
           phase == dfii_byte_phase_final_source_phase(source)))
        dfii_byte_phase_final_matrix_write_word =
          dfii_place_byte(
            dfii_byte_phase_tag(source, invert),
            dfii_byte_phase_final_byte(source)
          );
    end
  endfunction

  function automatic logic [15:0] dfii_byte_phase_final_expected_word4(
    input logic [6:0] source,
    input logic invert
  );
    begin
      dfii_byte_phase_final_expected_word4 = 16'd0;
      if (dfii_byte_phase_final_lane(source) == 4'd7)
        dfii_byte_phase_final_expected_word4[7:0] =
          dfii_byte_phase_tag(source, invert);
      else
        dfii_byte_phase_final_expected_word4[15:8] =
          dfii_byte_phase_tag(source, invert);
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

  function automatic logic [7:0] dfii_bist_tag(
    input logic [3:0] case_index,
    input logic [1:0] slot,
    input logic [3:0] lane
  );
    logic [7:0] bit_mask;
    begin
      bit_mask = 8'h01 << lane[2:0];
      unique case (case_index)
        4'd0: dfii_bist_tag = 8'h00;
        4'd1: dfii_bist_tag = 8'hff;
        4'd2: dfii_bist_tag = bit_mask;
        4'd3: dfii_bist_tag = ~bit_mask;
        4'd4: dfii_bist_tag = 8'h10 + {2'd0, slot, lane};
        4'd5: dfii_bist_tag = lane[0] ? 8'h55 : 8'haa;
        4'd6: dfii_bist_tag = 8'hc0 ^ {2'd0, slot, lane};
        default: dfii_bist_tag = 8'h5a ^ {slot, lane, 2'b01};
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_bist_write_word(
    input logic [1:0] phase,
    input logic [2:0] word,
    input logic [3:0] case_index,
    input logic [1:0] slot
  );
    begin
      dfii_edge_comp_bist_write_word = 32'd0;
      unique case ({phase, word})
        5'b00_000:
          dfii_edge_comp_bist_write_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd0), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd1), 2'd1) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd2), 2'd2) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd3), 2'd3);
        5'b00_001:
          dfii_edge_comp_bist_write_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd4), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd5), 2'd1) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd6), 2'd2) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd7), 2'd3);
        5'b00_010:
          dfii_edge_comp_bist_write_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd8), 2'd0);
        5'b00_100, 5'b01_100, 5'b10_100, 5'b11_100:
          dfii_edge_comp_bist_write_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd7), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd8), 2'd1);
        default:
          dfii_edge_comp_bist_write_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_bist_read_word(
    input logic [3:0] case_index,
    input logic [1:0] slot,
    input logic [2:0] word
  );
    begin
      unique case (word)
        3'd0:
          dfii_edge_comp_bist_read_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd0), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd1), 2'd1) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd2), 2'd2) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd3), 2'd3);
        3'd1:
          dfii_edge_comp_bist_read_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd4), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd5), 2'd1) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd6), 2'd2) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd7), 2'd3);
        3'd2:
          dfii_edge_comp_bist_read_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd8), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd0), 2'd1) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd1), 2'd2) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd2), 2'd3);
        3'd3:
          dfii_edge_comp_bist_read_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd3), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd4), 2'd1) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd5), 2'd2) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd6), 2'd3);
        3'd4:
          dfii_edge_comp_bist_read_word =
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd7), 2'd0) |
            dfii_place_byte(dfii_bist_tag(case_index, slot, 4'd8), 2'd1);
        default:
          dfii_edge_comp_bist_read_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_bist_read_index_word(
    input logic [3:0] case_index,
    input logic [1:0] slot,
    input logic [4:0] index
  );
    begin
      dfii_edge_comp_bist_read_index_word =
        dfii_edge_comp_bist_read_word(
          case_index,
          slot,
          dfii_index20_word(index)
        );
    end
  endfunction

  function automatic logic [31:0] dfii_addrwalk_column(
    input logic [3:0] addr_index
  );
    begin
      unique case (addr_index)
        4'd0: dfii_addrwalk_column = 32'h0000_0000;
        4'd1: dfii_addrwalk_column = 32'h0000_0008;
        4'd2: dfii_addrwalk_column = 32'h0000_0010;
        4'd3: dfii_addrwalk_column = 32'h0000_0018;
        4'd4: dfii_addrwalk_column = 32'h0000_0040;
        4'd5: dfii_addrwalk_column = 32'h0000_0048;
        4'd6: dfii_addrwalk_column = 32'h0000_0050;
        4'd7: dfii_addrwalk_column = 32'h0000_0058;
        4'd8: dfii_addrwalk_column = 32'h0000_0100;
        4'd9: dfii_addrwalk_column = 32'h0000_0108;
        4'd10: dfii_addrwalk_column = 32'h0000_0110;
        4'd11: dfii_addrwalk_column = 32'h0000_0118;
        4'd12: dfii_addrwalk_column = 32'h0000_0200;
        4'd13: dfii_addrwalk_column = 32'h0000_0208;
        4'd14: dfii_addrwalk_column = 32'h0000_0210;
        default: dfii_addrwalk_column = 32'h0000_0218;
      endcase
    end
  endfunction

  function automatic logic [24:0] native_sparse_read_addr(
    input logic [3:0] addr_index
  );
    begin
      unique case (addr_index)
        4'd0: native_sparse_read_addr = 25'h0_0000;
        4'd1: native_sparse_read_addr = 25'h0_0008;
        4'd2: native_sparse_read_addr = 25'h0_0010;
        4'd3: native_sparse_read_addr = 25'h0_0018;
        4'd4: native_sparse_read_addr = 25'h0_0040;
        4'd5: native_sparse_read_addr = 25'h0_0048;
        4'd6: native_sparse_read_addr = 25'h0_0050;
        4'd7: native_sparse_read_addr = 25'h0_0058;
        4'd8: native_sparse_read_addr = 25'h0_0100;
        4'd9: native_sparse_read_addr = 25'h0_0108;
        4'd10: native_sparse_read_addr = 25'h0_0110;
        4'd11: native_sparse_read_addr = 25'h0_0118;
        4'd12: native_sparse_read_addr = 25'h0_0200;
        4'd13: native_sparse_read_addr = 25'h0_0208;
        4'd14: native_sparse_read_addr = 25'h0_0210;
        default: native_sparse_read_addr = 25'h0_0218;
      endcase
    end
  endfunction

  function automatic logic [7:0] dfii_addrwalk_tag(
    input logic [3:0] addr_index,
    input logic [3:0] lane
  );
    begin
      dfii_addrwalk_tag = 8'h5a ^ {addr_index, lane};
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_addrwalk_write_word(
    input logic [1:0] phase,
    input logic [2:0] word,
    input logic [3:0] addr_index
  );
    begin
      dfii_edge_comp_addrwalk_write_word = 32'd0;
      unique case ({phase, word})
        5'b00_000:
          dfii_edge_comp_addrwalk_write_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd0), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd1), 2'd1) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd2), 2'd2) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd3), 2'd3);
        5'b00_001:
          dfii_edge_comp_addrwalk_write_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd4), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd5), 2'd1) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd6), 2'd2) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd7), 2'd3);
        5'b00_010:
          dfii_edge_comp_addrwalk_write_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd8), 2'd0);
        5'b00_100, 5'b01_100, 5'b10_100, 5'b11_100:
          dfii_edge_comp_addrwalk_write_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd7), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd8), 2'd1);
        default:
          dfii_edge_comp_addrwalk_write_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_addrwalk_read_word(
    input logic [3:0] addr_index,
    input logic [2:0] word
  );
    begin
      unique case (word)
        3'd0:
          dfii_edge_comp_addrwalk_read_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd0), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd1), 2'd1) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd2), 2'd2) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd3), 2'd3);
        3'd1:
          dfii_edge_comp_addrwalk_read_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd4), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd5), 2'd1) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd6), 2'd2) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd7), 2'd3);
        3'd2:
          dfii_edge_comp_addrwalk_read_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd8), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd0), 2'd1) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd1), 2'd2) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd2), 2'd3);
        3'd3:
          dfii_edge_comp_addrwalk_read_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd3), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd4), 2'd1) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd5), 2'd2) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd6), 2'd3);
        3'd4:
          dfii_edge_comp_addrwalk_read_word =
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd7), 2'd0) |
            dfii_place_byte(dfii_addrwalk_tag(addr_index, 4'd8), 2'd1);
        default:
          dfii_edge_comp_addrwalk_read_word = 32'd0;
      endcase
    end
  endfunction

  function automatic logic [31:0] dfii_edge_comp_addrwalk_read_index_word(
    input logic [3:0] addr_index,
    input logic [4:0] index
  );
    begin
      dfii_edge_comp_addrwalk_read_index_word =
        dfii_edge_comp_addrwalk_read_word(
          addr_index,
          dfii_index20_word(index)
        );
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
  assign native_byte_assoc_mode = NATIVE_BYTE_ASSOC_PROBE_ONLY;
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
    (byte_diag_mode ?
      (native_byte_assoc_mode ? 32'd72 : BYTE_DIAG_WORDS) :
      READ_COUNT_WORDS));
  assign active_write_drain_cycles =
    (cal_mode || phase_mode) ? CAL_WRITE_DRAIN_CYCLES : WRITE_DRAIN_CYCLES;
  assign read_target_issued = command_count_q >= active_target_words;
  assign read_target_seen = response_count_q >= active_target_words;
  assign write_data_target_seen = write_data_count_q >= active_target_words;
  assign write_command_target_seen = write_command_count_q >= active_target_words;
  assign write_drain_done = write_drain_count_q == 32'd0;
  assign outstanding_count = command_count_q - response_count_q;
  assign outstanding_full =
    (native_readscan_single_outstanding_mode || native_byte_assoc_mode) ?
    (outstanding_count != 32'd0) :
    outstanding_count >= 32'd64;
  assign timeout_seen = read_cycle_count_q[TIMEOUT_LOG2 - 1];
  assign cmd_valid =
    (write_state && !write_command_target_seen &&
     (write_command_count_q <= write_data_count_q)) ||
    (read_state && !read_target_issued && !outstanding_full);
  assign cmd_we = write_state;
  assign active_read_addr =
    native_sparse_readscan_mode ? native_sparse_read_addr(read_addr_q[3:0]) :
    read_addr_q;
  assign active_compare_addr =
    native_sparse_readscan_mode ? native_sparse_read_addr(compare_addr_q[3:0]) :
    compare_addr_q;
  assign cmd_addr =
    byte_diag_mode ?
      (BYTE_DIAG_BASE_ADDR +
       (cmd_we ? write_command_count_q[24:0] : read_addr_q)) :
      (cmd_we ? write_command_count_q[24:0] : active_read_addr);
  assign wdata_valid =
    write_state && !write_data_target_seen &&
    !(native_byte_assoc_mode && native_dfi_pace_wait_q) &&
    (write_data_count_q <= write_command_count_q ||
     ((write_data_count_q - write_command_count_q) < WRITE_DATA_AHEAD_LIMIT));
  assign wdata =
    byte_diag_clear_state ? 576'd0 :
    (byte_diag_mask_state ?
      (native_byte_assoc_mode ?
        native_byte_assoc_word(
          write_data_count_q[6:0],
          dfii_byte_phase_invert_q
        ) :
        byte_diag_word(write_data_count_q[2:0])) :
      pattern_for_addr(write_data_count_q[24:0]));
  assign wdata_we =
    byte_diag_mask_state ?
      (native_byte_assoc_mode ?
        (NATIVE_BYTE_ASSOC_FULL_WE ?
          {72{1'b1}} :
          native_byte_assoc_we_mask(write_data_count_q[6:0])) :
        byte_diag_we_mask(write_data_count_q[2:0])) :
      {72{1'b1}};
  assign native_debug_wdata_accept =
    native_byte_assoc_mode && byte_diag_mask_state && wdata_valid &&
    wdata_ready;
  assign native_debug_cmd_accept =
    native_byte_assoc_mode && byte_diag_mask_state && cmd_valid && cmd_ready;
  assign native_debug_wdata_word4 = {
    wdata[575:560],
    wdata[431:416],
    wdata[287:272],
    wdata[143:128]
  };
  assign native_debug_wdata_word4_we = {
    wdata_we[71:70],
    wdata_we[53:52],
    wdata_we[35:34],
    wdata_we[17:16]
  };
  assign debug_dfi_wrdata_word4_nonzero = {
    |debug_dfi_wrdata_word4[63:48],
    |debug_dfi_wrdata_word4[47:32],
    |debug_dfi_wrdata_word4[31:16],
    |debug_dfi_wrdata_word4[15:0]
  };
  assign debug_dfi_wrdata_word4_unmasked = {
    ~&debug_dfi_wrdata_word4_mask[7:6],
    ~&debug_dfi_wrdata_word4_mask[5:4],
    ~&debug_dfi_wrdata_word4_mask[3:2],
    ~&debug_dfi_wrdata_word4_mask[1:0]
  };
  assign expected_rdata = pattern_for_addr(active_compare_addr);
  assign lane_response_mismatch =
    select_lane_burst(rdata, cal_lane_q) !=
    select_lane_burst(expected_rdata, cal_lane_q);
  assign response_mismatch =
    read_state && !byte_diag_read_state && !native_readscan_mode &&
    rdata_valid &&
    (cal_read_state ? lane_response_mismatch : rdata != expected_rdata);
  for (genvar chunk_idx = 0; chunk_idx < 9; chunk_idx++) begin : gen_response_chunk_mismatch
    assign response_chunk_mismatch[chunk_idx] =
      rdata[chunk_idx * 64 +: 64] != expected_rdata[chunk_idx * 64 +: 64];
    assign response_nonzero_chunk[chunk_idx] =
      rdata[chunk_idx * 64 +: 64] != 64'd0;
  end
  assign response_any_nonzero = |response_nonzero_chunk;
  assign response_first_nonzero_data = first_nonzero_chunk_data(rdata);
  assign next_mismatch_count =
    mismatch_count_q + (response_mismatch ? 32'd1 : 32'd0);
  assign mismatch_seen = mismatch_count_q != 32'd0;
  assign dfii_byte_phase_scan_byte_value =
    native_byte_assoc_mode ?
      native_byte_assoc_scan_byte(
        native_byte_assoc_rdata_q,
        dfii_byte_phase_scan_word_q,
        dfii_byte_phase_scan_byte_q
      ) :
      byte_from_word(
        dfii_rddata_q[dfii_byte_phase_scan_word_q],
        dfii_byte_phase_scan_byte_q
      );
  assign dfii_byte_phase_scan_match =
    dfii_byte_phase_scan_byte_value ==
    (native_byte_assoc_mode ?
      native_byte_assoc_tag(dfii_byte_phase_source_q, dfii_byte_phase_invert_q) :
      dfii_byte_phase_tag(dfii_byte_phase_source_q, dfii_byte_phase_invert_q));
  assign dfii_byte_phase_scan_last =
    dfii_byte_phase_scan_word_q ==
      (native_byte_assoc_mode ? 5'd17 : (DFII_RDDATA_WORDS - 1)) &&
    dfii_byte_phase_scan_byte_q == 2'd3;
  assign dfii_byte_phase_scan_dest_next =
    (dfii_byte_phase_scan_match &&
     dfii_byte_phase_scan_dest_q == DFII_BYTE_PHASE_DEST_NONE) ?
    {dfii_byte_phase_scan_word_q, dfii_byte_phase_scan_byte_q} :
    dfii_byte_phase_scan_dest_q;
  assign dfii_byte_phase_scan_count_next =
    (dfii_byte_phase_scan_match && dfii_byte_phase_scan_count_q != 4'hf) ?
    (dfii_byte_phase_scan_count_q + 4'd1) :
    dfii_byte_phase_scan_count_q;
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
  assign dfii_wrdata_index20 =
    dfii_step_q[4:0] -
    (dfii_byte_phase_phy_phase_matrix_mode ? 5'd4 : 5'd2);
  assign dfii_rddata_index20 =
    dfii_step_q[4:0] -
    (dfii_byte_phase_phy_phase_matrix_mode ? 5'd12 : 5'd10);
  assign dfii_csr_echo_read_index20 = dfii_step_q[4:0] - 5'd22;
  assign dfii_edge_comp_csr_echo_read_index20 = dfii_step_q - 8'd22;
  assign dfii_wbitslip_sweep_mode =
    DFII_WBITSLIP_SWEEP_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_rbitslip_sweep_mode =
    DFII_RBITSLIP_SWEEP_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_edge_map_probe_mode =
    DFII_EDGE_MAP_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_edge_comp_probe_mode =
    DFII_EDGE_COMP_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_edge_comp_active_mode =
    DFII_EDGE_COMP_ACTIVE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_edge_comp_bist_mode =
    DFII_EDGE_COMP_BIST_ONLY && dfii_phasecmd_sweep_q;
  assign native_sparse_readscan_mode =
    DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN_SPARSE ||
    native_sparse_readscan_only_mode;
  assign native_sparse_readscan_only_mode = NATIVE_SPARSE_READSCAN_ONLY;
  assign native_readscan_single_outstanding_mode =
    NATIVE_READSCAN_SINGLE_OUTSTANDING && native_readscan_mode;
  assign native_readscan_release_mode =
    DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN_RELEASE ||
    DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN_SPARSE;
  assign native_readscan_mode =
    DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN ||
    native_readscan_release_mode ||
    native_sparse_readscan_only_mode;
  assign dfii_edge_comp_addrwalk_mode =
    (DFII_EDGE_COMP_ADDRWALK_ONLY ||
     DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
     DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN ||
     native_readscan_release_mode) &&
    dfii_phasecmd_sweep_q;
  assign dfii_byte_phase_assoc_mode =
    DFII_BYTE_PHASE_ASSOC_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_byte_phase_phase0_assoc_mode =
    DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_byte_phase_cmd_matrix_mode =
    DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_byte_phase_phy_phase_matrix_mode =
    DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_byte_phase_final_matrix_mode =
    DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_byte_phase_active_sources =
    dfii_byte_phase_phase0_assoc_mode ? 7'd18 :
    dfii_byte_phase_final_matrix_mode ? 7'd16 :
    (dfii_byte_phase_cmd_matrix_mode ||
     dfii_byte_phase_phy_phase_matrix_mode) ?
    7'd64 : 7'd72;
  assign dfii_edge_lane7_locator_probe_mode =
    DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY && dfii_phasecmd_sweep_q;
  assign dfii_bitslip_sweep_mode =
    dfii_wbitslip_sweep_mode || dfii_rbitslip_sweep_mode;
  assign dfii_wide_word_mode =
    dfii_half_order_matrix_mode || dfii_displacement_probe_mode ||
    dfii_csr_echo_probe_mode || dfii_edge_map_probe_mode ||
    dfii_edge_comp_probe_mode || dfii_edge_comp_active_mode ||
    dfii_edge_comp_bist_mode || dfii_edge_comp_addrwalk_mode ||
    dfii_byte_phase_assoc_mode || dfii_byte_phase_phase0_assoc_mode ||
    dfii_byte_phase_cmd_matrix_mode ||
    dfii_byte_phase_phy_phase_matrix_mode ||
    dfii_byte_phase_final_matrix_mode ||
    dfii_edge_lane7_locator_probe_mode;
  assign dfii_edge_comp_csr_echo_read_step =
    dfii_edge_comp_probe_mode && DFII_EDGE_COMP_CSR_ONLY &&
    dfii_step_q >= 8'd22 &&
    dfii_step_q <= 8'd41;
  assign dfii_read_store_index =
    (dfii_edge_comp_probe_mode && DFII_EDGE_COMP_CSR_ONLY) ?
      dfii_edge_comp_csr_echo_read_index20 :
    dfii_csr_echo_probe_mode ? dfii_csr_echo_read_index20 :
    (dfii_wide_word_mode ? dfii_rddata_index20 : dfii_rddata_index);
  assign dfii_seq_done_step =
    (dfii_edge_comp_probe_mode && DFII_EDGE_COMP_CSR_ONLY) ? 8'd43 :
    dfii_csr_echo_probe_mode ? 8'd43 :
    (dfii_wide_word_mode ?
      (native_readscan_release_mode ? 8'd65 :
       (8'd63 + dfii_phy_phase_step_offset)) :
      8'd55);
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
     dfii_edge_comp_active_mode || dfii_edge_comp_bist_mode ||
     dfii_edge_comp_addrwalk_mode || dfii_byte_phase_assoc_mode ||
     dfii_byte_phase_phase0_assoc_mode ||
     dfii_byte_phase_cmd_matrix_mode ||
     dfii_byte_phase_phy_phase_matrix_mode ||
     dfii_byte_phase_final_matrix_mode ||
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
  assign dfii_phy_phase_step_offset =
    dfii_byte_phase_phy_phase_matrix_mode ? 8'd2 : 8'd0;
  assign dfii_write_command_phase =
    dfii_source_command_matrix_mode ? dfii_phasecmd_index_q[1:0] :
    dfii_byte_phase_cmd_matrix_mode ?
    dfii_byte_phase_cmd_write_phase(dfii_byte_phase_source_q) :
    (dfii_source_order_matrix_mode || dfii_half_order_matrix_mode ||
     dfii_displacement_probe_mode || dfii_csr_echo_probe_mode ||
     dfii_edge_map_probe_mode || dfii_edge_comp_probe_mode ||
     dfii_edge_comp_active_mode || dfii_edge_comp_bist_mode ||
     dfii_edge_comp_addrwalk_mode || dfii_byte_phase_assoc_mode ||
     dfii_byte_phase_phase0_assoc_mode ||
     dfii_byte_phase_phy_phase_matrix_mode ||
     dfii_byte_phase_final_matrix_mode ||
     dfii_edge_lane7_locator_probe_mode ||
     dfii_bitslip_sweep_mode) ?
    DFII_SOURCE_ORDER_WRITE_PHASE[1:0] :
    dfii_phasecmd_sweep_q ? dfii_phasecmd_index_q[3:2] : 2'd3;
  assign dfii_read_command_phase =
    dfii_source_command_matrix_mode ?
    DFII_SOURCE_COMMAND_READ_PHASE[1:0] :
    dfii_byte_phase_cmd_matrix_mode ?
    dfii_byte_phase_cmd_read_phase(dfii_byte_phase_source_q) :
    (dfii_source_order_matrix_mode || dfii_half_order_matrix_mode ||
     dfii_displacement_probe_mode || dfii_csr_echo_probe_mode ||
     dfii_edge_map_probe_mode || dfii_edge_comp_probe_mode ||
     dfii_edge_comp_active_mode || dfii_edge_comp_bist_mode ||
     dfii_edge_comp_addrwalk_mode || dfii_byte_phase_assoc_mode ||
     dfii_byte_phase_phase0_assoc_mode ||
     dfii_byte_phase_phy_phase_matrix_mode ||
     dfii_byte_phase_final_matrix_mode ||
     dfii_edge_lane7_locator_probe_mode ||
     dfii_bitslip_sweep_mode) ?
    DFII_SOURCE_ORDER_READ_PHASE[1:0] :
    dfii_phasecmd_sweep_q ? dfii_phasecmd_index_q[1:0] : 2'd2;
  assign cal_last_candidate =
    cal_wbitslip_q == 3'd7 && cal_bitslip_q == 3'd7 &&
    cal_delay_q == 5'd31;
  assign cal_lane_last = cal_lane_q == 3'd7;

  always_comb begin
    dfii_bist_mismatch_word_count = 32'd0;
    dfii_bist_first_mismatch_word = 5'd0;
    dfii_bist_first_expected_word = 32'd0;
    dfii_bist_first_actual_word = 32'd0;
    dfii_bist_mismatch_seen = 1'b0;
    for (int word_idx = 0; word_idx < DFII_RDDATA_WORDS; word_idx++) begin
      if (dfii_word_mismatch_q[word_idx]) begin
        dfii_bist_mismatch_word_count =
          dfii_bist_mismatch_word_count + 32'd1;
        if (!dfii_bist_mismatch_seen) begin
          dfii_bist_mismatch_seen = 1'b1;
          dfii_bist_first_mismatch_word = word_idx[4:0];
          dfii_bist_first_expected_word = dfii_edge_comp_addrwalk_mode ?
            dfii_edge_comp_addrwalk_read_index_word(
              dfii_phasecmd_index_q,
              word_idx[4:0]
            ) :
            dfii_edge_comp_bist_read_index_word(
              dfii_phasecmd_index_q,
              dfii_phasecmd_index_q[1:0],
              word_idx[4:0]
            );
          dfii_bist_first_actual_word = dfii_rddata_q[word_idx];
        end
      end
    end
  end

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

  always_comb begin
    dfii_byte_phase_dest0_payload = 576'd0;
    dfii_byte_phase_count0_payload = 288'd0;
    dfii_byte_phase_dest1_payload = 576'd0;
    dfii_byte_phase_count1_payload = 288'd0;
    for (int source_idx = 0;
         source_idx < DFII_BYTE_PHASE_SOURCES;
         source_idx++) begin
      dfii_byte_phase_dest0_payload[source_idx * 8 +: 8] =
        {1'b0, dfii_byte_phase_dest_q[source_idx]};
      dfii_byte_phase_count0_payload[source_idx * 4 +: 4] =
        dfii_byte_phase_count_q[source_idx];
      dfii_byte_phase_dest1_payload[source_idx * 8 +: 8] =
        {1'b0, dfii_byte_phase_inv_dest_q[source_idx]};
      dfii_byte_phase_count1_payload[source_idx * 4 +: 4] =
        dfii_byte_phase_inv_count_q[source_idx];
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

`ifndef TASK6_LITEDRAM_DEBUG_PORTS
  assign debug_dfi_wrdata_en = 4'd0;
  assign debug_dfi_wrdata_word4 = 64'd0;
  assign debug_dfi_wrdata_word4_mask = 8'd0;
  assign debug_dfi_write_cmd = 4'd0;
  assign debug_dfi_read_cmd = 4'd0;
  assign debug_dfi_activate_cmd = 4'd0;
  assign debug_dfi_odt = 4'd0;
  assign debug_dfi_rddata_en = 4'd0;
  assign debug_dfi_rddata_valid = 4'd0;
  assign debug_dfi_address = 60'd0;
  assign debug_dfi_bank = 12'd0;
`endif
  assign debug_phy_write_timing = 8'd0;

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
    end else if (dfii_edge_comp_probe_mode && DFII_EDGE_COMP_CSR_ONLY) begin
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
        dfii_step_wb_data = dfii_edge_comp_write_word(
          dfii_index20_phase(dfii_wrdata_index20),
          dfii_index20_word(dfii_wrdata_index20),
          dfii_phasecmd_index_q[1:0]
        );
      end else if (dfii_step_q >= 8'd22 && dfii_step_q <= 8'd41) begin
        dfii_step_is_read = 1'b1;
        dfii_step_wb_addr = dfii_pi_wrdata_addr5(
          dfii_index20_phase(dfii_edge_comp_csr_echo_read_index20),
          dfii_index20_word(dfii_edge_comp_csr_echo_read_index20)
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
      end else if (dfii_byte_phase_phy_phase_matrix_mode &&
                   dfii_step_q == 8'd2) begin
        dfii_step_wb_addr = WB_ADDR_DDRPHY_RDPHASE;
        dfii_step_wb_data =
          {30'd0, dfii_byte_phase_phy_rdphase(dfii_byte_phase_source_q)};
      end else if (dfii_byte_phase_phy_phase_matrix_mode &&
                   dfii_step_q == 8'd3) begin
        dfii_step_wb_addr = WB_ADDR_DDRPHY_WRPHASE;
        dfii_step_wb_data =
          {30'd0, dfii_byte_phase_phy_wrphase(dfii_byte_phase_source_q)};
      end else if (dfii_step_q >= (8'd2 + dfii_phy_phase_step_offset) &&
                   dfii_step_q <= (8'd21 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = dfii_pi_wrdata_addr5(
          dfii_index20_phase(dfii_wrdata_index20),
          dfii_index20_word(dfii_wrdata_index20)
        );
        dfii_step_wb_data =
          dfii_byte_phase_final_matrix_mode ?
          dfii_byte_phase_final_matrix_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20),
            dfii_byte_phase_source_q,
            dfii_byte_phase_invert_q
          ) :
          (dfii_byte_phase_cmd_matrix_mode ||
           dfii_byte_phase_phy_phase_matrix_mode) ?
          dfii_byte_phase_cmd_matrix_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20),
            dfii_byte_phase_source_q,
            dfii_byte_phase_invert_q
          ) :
          (dfii_byte_phase_assoc_mode ||
           dfii_byte_phase_phase0_assoc_mode) ?
          dfii_byte_phase_assoc_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20),
            dfii_byte_phase_source_q,
            dfii_byte_phase_invert_q
          ) :
          dfii_edge_lane7_locator_probe_mode ?
          dfii_lane7_locator_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20)
          ) :
          dfii_edge_comp_addrwalk_mode ?
          dfii_edge_comp_addrwalk_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20),
            dfii_phasecmd_index_q
          ) :
          dfii_edge_comp_bist_mode ?
          dfii_edge_comp_bist_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20),
            dfii_phasecmd_index_q,
            dfii_phasecmd_index_q[1:0]
          ) :
          (dfii_edge_comp_probe_mode || dfii_edge_comp_active_mode) ?
          dfii_edge_comp_write_word(
            dfii_index20_phase(dfii_wrdata_index20),
            dfii_index20_word(dfii_wrdata_index20),
            dfii_edge_comp_active_mode ? 2'd0 : dfii_phasecmd_index_q[1:0]
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
      end else if (dfii_step_q == (8'd22 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == (8'd23 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == (8'd24 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND;
        dfii_step_wb_data = DFII_COMMAND_RAS | DFII_COMMAND_CS;
      end else if (dfii_step_q == (8'd25 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        dfii_step_wb_data = 32'd1;
      end else if (dfii_step_q == (8'd26 + dfii_phy_phase_step_offset)) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q == (8'd27 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = dfii_pi_address_addr(dfii_write_command_phase);
        dfii_step_wb_data =
          dfii_edge_comp_addrwalk_mode ?
          dfii_addrwalk_column(dfii_phasecmd_index_q) :
          dfii_edge_comp_bist_mode ?
          dfii_addr_column(dfii_phasecmd_index_q[1:0]) :
          (dfii_edge_comp_probe_mode || dfii_edge_comp_active_mode) ?
          dfii_addr_column(
            dfii_edge_comp_active_mode ? 2'd0 : dfii_phasecmd_index_q[1:0]
          ) :
          32'd0;
      end else if (dfii_step_q == (8'd28 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = dfii_pi_baddress_addr(dfii_write_command_phase);
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == (8'd29 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = dfii_pi_command_addr(dfii_write_command_phase);
        dfii_step_wb_data =
          DFII_DISABLE_WRITE_COMMAND ? 32'd0 :
          (DFII_COMMAND_CAS | DFII_COMMAND_WE | DFII_COMMAND_CS |
           DFII_COMMAND_WRDATA);
      end else if (dfii_step_q == (8'd30 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr =
          dfii_pi_command_issue_addr(dfii_write_command_phase);
        dfii_step_wb_data = DFII_DISABLE_WRITE_COMMAND ? 32'd0 : 32'd1;
      end else if (dfii_step_q == (8'd31 + dfii_phy_phase_step_offset)) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q == (8'd32 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = dfii_pi_address_addr(dfii_read_command_phase);
        dfii_step_wb_data =
          dfii_edge_comp_addrwalk_mode ?
          dfii_addrwalk_column(dfii_phasecmd_index_q) :
          dfii_edge_comp_bist_mode ?
          dfii_addr_column(dfii_phasecmd_index_q[1:0]) :
          (dfii_edge_comp_probe_mode || dfii_edge_comp_active_mode) ?
          dfii_addr_column(
            dfii_edge_comp_active_mode ? 2'd0 : dfii_phasecmd_index_q[1:0]
          ) :
          32'd0;
      end else if (dfii_step_q == (8'd33 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = dfii_pi_baddress_addr(dfii_read_command_phase);
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == (8'd34 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = dfii_pi_command_addr(dfii_read_command_phase);
        dfii_step_wb_data =
          DFII_COMMAND_CAS | DFII_COMMAND_CS | DFII_COMMAND_RDDATA;
      end else if (dfii_step_q == (8'd35 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr =
          dfii_pi_command_issue_addr(dfii_read_command_phase);
        dfii_step_wb_data = 32'd1;
      end else if (dfii_step_q == (8'd36 + dfii_phy_phase_step_offset)) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q == (8'd37 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_ADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == (8'd38 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_BADDRESS;
        dfii_step_wb_data = 32'd0;
      end else if (dfii_step_q == (8'd39 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND;
        dfii_step_wb_data =
          DFII_COMMAND_RAS | DFII_COMMAND_WE | DFII_COMMAND_CS;
      end else if (dfii_step_q == (8'd40 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_PI0_COMMAND_ISSUE;
        dfii_step_wb_data = 32'd1;
      end else if (dfii_step_q == (8'd41 + dfii_phy_phase_step_offset)) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd1_500;
      end else if (dfii_step_q >= (8'd42 + dfii_phy_phase_step_offset) &&
                   dfii_step_q <= (8'd61 + dfii_phy_phase_step_offset)) begin
        dfii_step_is_read = 1'b1;
        dfii_step_wb_addr = dfii_pi_rddata_addr5(
          dfii_index20_phase(dfii_rddata_index20),
          dfii_index20_word(dfii_rddata_index20)
        );
      end else if (dfii_step_q == (8'd62 + dfii_phy_phase_step_offset)) begin
        dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
        dfii_step_wb_data = DFII_CONTROL_HARDWARE;
      end else if (dfii_step_q == 8'd63 &&
                   native_readscan_release_mode &&
                   dfii_edge_comp_addrwalk_mode) begin
        dfii_step_wb_addr = WB_ADDR_DFII_CONTROL;
        dfii_step_wb_data = DFII_CONTROL_HARDWARE;
      end else if (dfii_step_q == 8'd64 &&
                   native_readscan_release_mode &&
                   dfii_edge_comp_addrwalk_mode) begin
        dfii_step_is_delay = 1'b1;
        dfii_step_delay = 32'd10_000;
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
    if (user_rst || core_rst ||
        state_q == PROBE_RESET ||
        state_q == PROBE_WAIT_INIT ||
        state_q == PROBE_CAL_CONFIG ||
        !native_byte_assoc_mode ||
        !byte_diag_write_state) begin
      native_dfi_pace_wait_q <= 1'b0;
    end else if (native_dfi_pace_wait_q && |debug_dfi_wrdata_en) begin
      native_dfi_pace_wait_q <= 1'b0;
    end else if (wdata_valid && wdata_ready) begin
      native_dfi_pace_wait_q <= 1'b1;
    end
  end

  always_ff @(posedge user_clk) begin
    if (user_rst || core_rst ||
        state_q == PROBE_RESET ||
        state_q == PROBE_WAIT_INIT ||
        state_q == PROBE_CAL_CONFIG ||
        state_q == PROBE_DFII_RESTART ||
        state_q == PROBE_DFII_WBITSLIP_CONFIG ||
        (dfii_seq_state_q == DFII_SEQ_IDLE && dfii_seq_running)) begin
      dfi_debug_wrdata_seen_q <= 4'd0;
      dfi_debug_wrdata_last_en_q <= 4'd0;
      dfi_debug_wrdata_word4_mask_q <= 8'd0;
      dfi_debug_wrdata_event_count_q <= 4'd0;
      dfi_debug_wrdata_word4_nonzero_q <= 4'd0;
      dfi_debug_wrdata_word4_unmasked_q <= 4'd0;
      dfi_debug_write_cmd_seen_q <= 4'd0;
      dfi_debug_read_cmd_seen_q <= 4'd0;
      dfi_debug_activate_cmd_seen_q <= 4'd0;
      dfi_debug_write_cmd_last_q <= 4'd0;
      dfi_debug_write_cmd_event_count_q <= 4'd0;
      dfi_debug_write_cmd_address_q <= 60'd0;
      dfi_debug_write_cmd_bank_q <= 12'd0;
      dfi_debug_odt_seen_q <= 4'd0;
      dfi_debug_rddata_en_seen_q <= 4'd0;
      dfi_debug_rddata_valid_seen_q <= 4'd0;
      dfi_debug_phy_write_timing_seen_q <= 8'd0;
      dfi_debug_wrdata_after_write_cmd_q <= 16'd0;
      dfi_debug_write_cmd_after_wrdata_q <= 16'd0;
      dfi_debug_write_cmd_odt_q <= 4'd0;
      dfi_debug_wrdata_odt_q <= 4'd0;
      dfi_debug_wrdata_dq_oe_q <= 4'd0;
      dfi_debug_wrdata_dqs_oe_q <= 4'd0;
      dfi_debug_write_cmd_hist0_q <= 4'd0;
      dfi_debug_write_cmd_hist1_q <= 4'd0;
      dfi_debug_write_cmd_hist2_q <= 4'd0;
      dfi_debug_wrdata_hist0_q <= 4'd0;
      dfi_debug_wrdata_hist1_q <= 4'd0;
      dfi_debug_wrdata_hist2_q <= 4'd0;
      for (int phase_idx = 0; phase_idx < 4; phase_idx++)
        dfi_debug_wrdata_word4_q[phase_idx] <= 16'd0;
    end else begin
      dfi_debug_odt_seen_q <= dfi_debug_odt_seen_q | debug_dfi_odt;
      dfi_debug_rddata_en_seen_q <=
        dfi_debug_rddata_en_seen_q | debug_dfi_rddata_en;
      dfi_debug_rddata_valid_seen_q <=
        dfi_debug_rddata_valid_seen_q | debug_dfi_rddata_valid;
      dfi_debug_phy_write_timing_seen_q <=
        dfi_debug_phy_write_timing_seen_q | debug_phy_write_timing;
      dfi_debug_write_cmd_seen_q <=
        dfi_debug_write_cmd_seen_q | debug_dfi_write_cmd;
      dfi_debug_read_cmd_seen_q <=
        dfi_debug_read_cmd_seen_q | debug_dfi_read_cmd;
      dfi_debug_activate_cmd_seen_q <=
        dfi_debug_activate_cmd_seen_q | debug_dfi_activate_cmd;
      dfi_debug_write_cmd_odt_q <=
        dfi_debug_write_cmd_odt_q | (debug_dfi_write_cmd & debug_dfi_odt);
      dfi_debug_wrdata_odt_q <=
        dfi_debug_wrdata_odt_q | (debug_dfi_wrdata_en & debug_dfi_odt);
      dfi_debug_wrdata_dq_oe_q <=
        dfi_debug_wrdata_dq_oe_q |
        (debug_dfi_wrdata_en &
         {4{debug_phy_write_timing[0] |
            debug_phy_write_timing[2] |
            debug_phy_write_timing[3]}});
      dfi_debug_wrdata_dqs_oe_q <=
        dfi_debug_wrdata_dqs_oe_q |
        (debug_dfi_wrdata_en &
         {4{debug_phy_write_timing[1] |
            debug_phy_write_timing[4] |
            debug_phy_write_timing[5]}});
      if (|debug_dfi_wrdata_en) begin
        dfi_debug_wrdata_after_write_cmd_q[0 +: 4] <=
          dfi_debug_wrdata_after_write_cmd_q[0 +: 4] |
          (debug_dfi_wrdata_en & debug_dfi_write_cmd);
        dfi_debug_wrdata_after_write_cmd_q[4 +: 4] <=
          dfi_debug_wrdata_after_write_cmd_q[4 +: 4] |
          (debug_dfi_wrdata_en & dfi_debug_write_cmd_hist0_q);
        dfi_debug_wrdata_after_write_cmd_q[8 +: 4] <=
          dfi_debug_wrdata_after_write_cmd_q[8 +: 4] |
          (debug_dfi_wrdata_en & dfi_debug_write_cmd_hist1_q);
        dfi_debug_wrdata_after_write_cmd_q[12 +: 4] <=
          dfi_debug_wrdata_after_write_cmd_q[12 +: 4] |
          (debug_dfi_wrdata_en & dfi_debug_write_cmd_hist2_q);
      end
      if (|debug_dfi_write_cmd) begin
        dfi_debug_write_cmd_after_wrdata_q[0 +: 4] <=
          dfi_debug_write_cmd_after_wrdata_q[0 +: 4] |
          (debug_dfi_write_cmd & debug_dfi_wrdata_en);
        dfi_debug_write_cmd_after_wrdata_q[4 +: 4] <=
          dfi_debug_write_cmd_after_wrdata_q[4 +: 4] |
          (debug_dfi_write_cmd & dfi_debug_wrdata_hist0_q);
        dfi_debug_write_cmd_after_wrdata_q[8 +: 4] <=
          dfi_debug_write_cmd_after_wrdata_q[8 +: 4] |
          (debug_dfi_write_cmd & dfi_debug_wrdata_hist1_q);
        dfi_debug_write_cmd_after_wrdata_q[12 +: 4] <=
          dfi_debug_write_cmd_after_wrdata_q[12 +: 4] |
          (debug_dfi_write_cmd & dfi_debug_wrdata_hist2_q);
      end
      if (|debug_dfi_write_cmd) begin
        dfi_debug_write_cmd_last_q <= debug_dfi_write_cmd;
        dfi_debug_write_cmd_address_q <= debug_dfi_address;
        dfi_debug_write_cmd_bank_q <= debug_dfi_bank;
        if (dfi_debug_write_cmd_event_count_q != 4'hf)
          dfi_debug_write_cmd_event_count_q <=
            dfi_debug_write_cmd_event_count_q + 4'd1;
      end
      if (|debug_dfi_wrdata_en) begin
        dfi_debug_wrdata_seen_q <=
          dfi_debug_wrdata_seen_q | debug_dfi_wrdata_en;
        dfi_debug_wrdata_word4_nonzero_q <=
          dfi_debug_wrdata_word4_nonzero_q |
          (debug_dfi_wrdata_en & debug_dfi_wrdata_word4_nonzero);
        dfi_debug_wrdata_word4_unmasked_q <=
          dfi_debug_wrdata_word4_unmasked_q |
          (debug_dfi_wrdata_en & debug_dfi_wrdata_word4_unmasked);
        dfi_debug_wrdata_last_en_q <= debug_dfi_wrdata_en;
        dfi_debug_wrdata_word4_mask_q <= debug_dfi_wrdata_word4_mask;
        if (dfi_debug_wrdata_event_count_q != 4'hf)
          dfi_debug_wrdata_event_count_q <=
            dfi_debug_wrdata_event_count_q + 4'd1;
        for (int phase_idx = 0; phase_idx < 4; phase_idx++) begin
          if (debug_dfi_wrdata_en[phase_idx])
            dfi_debug_wrdata_word4_q[phase_idx] <=
              debug_dfi_wrdata_word4[phase_idx * 16 +: 16];
        end
      end
      dfi_debug_write_cmd_hist0_q <= debug_dfi_write_cmd;
      dfi_debug_write_cmd_hist1_q <= dfi_debug_write_cmd_hist0_q;
      dfi_debug_write_cmd_hist2_q <= dfi_debug_write_cmd_hist1_q;
      dfi_debug_wrdata_hist0_q <= debug_dfi_wrdata_en;
      dfi_debug_wrdata_hist1_q <= dfi_debug_wrdata_hist0_q;
      dfi_debug_wrdata_hist2_q <= dfi_debug_wrdata_hist1_q;
    end
  end

  always_ff @(posedge user_clk) begin
    if (user_rst || core_rst ||
        state_q == PROBE_RESET ||
        state_q == PROBE_WAIT_INIT ||
        state_q == PROBE_CAL_CONFIG ||
        (native_byte_assoc_mode && byte_diag_clear_state)) begin
      native_debug_wdata_accept_count_q <= 8'd0;
      native_debug_cmd_accept_count_q <= 8'd0;
      native_debug_last_wdata_source_q <= 7'd0;
      native_debug_last_wdata_invert_q <= 1'b0;
      native_debug_last_wdata_word4_q <= 64'd0;
      native_debug_last_wdata_word4_we_q <= 8'd0;
    end else begin
      if (native_debug_wdata_accept) begin
        if (native_debug_wdata_accept_count_q != 8'hff)
          native_debug_wdata_accept_count_q <=
            native_debug_wdata_accept_count_q + 8'd1;
        native_debug_last_wdata_source_q <= write_data_count_q[6:0];
        native_debug_last_wdata_invert_q <= dfii_byte_phase_invert_q;
        native_debug_last_wdata_word4_q <= native_debug_wdata_word4;
        native_debug_last_wdata_word4_we_q <= native_debug_wdata_word4_we;
      end
      if (native_debug_cmd_accept &&
          native_debug_cmd_accept_count_q != 8'hff)
        native_debug_cmd_accept_count_q <=
          native_debug_cmd_accept_count_q + 8'd1;
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
      dfii_csr_mismatch_q <= '0;
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
      dfii_csr_mismatch_q <= '0;
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
          dfii_csr_mismatch_q <= '0;
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
                if (dfii_edge_comp_probe_mode &&
                    dfii_edge_comp_csr_echo_read_step) begin
                  if (wb_ctrl_dat_r !=
                      dfii_edge_comp_write_word(
                        dfii_index20_phase(dfii_read_store_index),
                        dfii_index20_word(dfii_read_store_index),
                        dfii_phasecmd_index_q[1:0]
                      ))
                    dfii_csr_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_csr_echo_probe_mode) begin
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
                end else if (dfii_edge_comp_active_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_edge_comp_read_word(
                        dfii_index20_word(dfii_read_store_index),
                        2'd0
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_edge_comp_addrwalk_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_edge_comp_addrwalk_read_index_word(
                        dfii_phasecmd_index_q,
                        dfii_read_store_index
                      ))
                    dfii_word_mismatch_q[dfii_read_store_index] <= 1'b1;
                end else if (dfii_byte_phase_assoc_mode ||
                             dfii_byte_phase_phase0_assoc_mode ||
                             dfii_byte_phase_cmd_matrix_mode ||
                             dfii_byte_phase_phy_phase_matrix_mode ||
                             dfii_byte_phase_final_matrix_mode) begin
                  // The one-hot association probe records tag locations after
                  // the sequence completes; any destination is useful evidence.
                end else if (dfii_edge_comp_bist_mode) begin
                  if (wb_ctrl_dat_r !=
                      dfii_edge_comp_bist_read_index_word(
                        dfii_phasecmd_index_q,
                        dfii_phasecmd_index_q[1:0],
                        dfii_read_store_index
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
      native_nonzero_count_q <= 32'd0;
      native_first_nonzero_addr_q <= 28'd0;
      native_first_nonzero_data_q <= 64'd0;
      native_first_nonzero_chunk_q <= 9'd0;
      native_nonzero_chunk_seen_q <= 9'd0;
      native_change_count_q <= 32'd0;
      native_last_addr_q <= 28'd0;
      native_last_data_q <= 64'd0;
      native_max_outstanding_q <= 32'd0;
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
      dfii_byte_phase_source_q <= 7'd0;
      dfii_byte_phase_invert_q <= 1'b0;
      dfii_byte_phase_scan_word_q <= 5'd0;
      dfii_byte_phase_scan_byte_q <= 2'd0;
      dfii_byte_phase_scan_dest_q <= DFII_BYTE_PHASE_DEST_NONE;
      dfii_byte_phase_scan_count_q <= 4'd0;
      native_byte_assoc_rdata_q <= 576'd0;
      for (int source_idx = 0;
           source_idx < DFII_BYTE_PHASE_SOURCES;
           source_idx++) begin
        dfii_byte_phase_dest_q[source_idx] <= DFII_BYTE_PHASE_DEST_NONE;
        dfii_byte_phase_inv_dest_q[source_idx] <= DFII_BYTE_PHASE_DEST_NONE;
        dfii_byte_phase_count_q[source_idx] <= 4'd0;
        dfii_byte_phase_inv_count_q[source_idx] <= 4'd0;
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
            native_nonzero_count_q <= 32'd0;
            native_first_nonzero_addr_q <= 28'd0;
            native_first_nonzero_data_q <= 64'd0;
            native_first_nonzero_chunk_q <= 9'd0;
            native_nonzero_chunk_seen_q <= 9'd0;
            native_change_count_q <= 32'd0;
            native_last_addr_q <= 28'd0;
            native_last_data_q <= 64'd0;
            native_max_outstanding_q <= 32'd0;
            dfii_final_q <= !(DFII_DISPLACEMENT_PROBE_ONLY ||
                              DFII_CSR_ECHO_PROBE_ONLY ||
                              DFII_WBITSLIP_SWEEP_ONLY ||
                              DFII_RBITSLIP_SWEEP_ONLY ||
                              DFII_EDGE_MAP_PROBE_ONLY ||
                              DFII_EDGE_COMP_PROBE_ONLY ||
                              DFII_EDGE_COMP_ACTIVE_ONLY ||
                              DFII_EDGE_COMP_BIST_ONLY ||
                              DFII_EDGE_COMP_ADDRWALK_ONLY ||
                              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
                              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN ||
                              DFII_BYTE_PHASE_ASSOC_PROBE_ONLY ||
                              DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY ||
                              DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY ||
                              DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY ||
                              DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY ||
                              NATIVE_BYTE_ASSOC_PROBE_ONLY ||
                              native_readscan_release_mode ||
                              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY);
            dfii_phasecmd_sweep_q <=
              DFII_DISPLACEMENT_PROBE_ONLY || DFII_CSR_ECHO_PROBE_ONLY ||
              DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY ||
              DFII_EDGE_MAP_PROBE_ONLY || DFII_EDGE_COMP_PROBE_ONLY ||
              DFII_EDGE_COMP_ACTIVE_ONLY ||
              DFII_EDGE_COMP_BIST_ONLY ||
              DFII_EDGE_COMP_ADDRWALK_ONLY ||
              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN ||
              DFII_BYTE_PHASE_ASSOC_PROBE_ONLY ||
              DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY ||
              DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY ||
              DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY ||
              DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY ||
              native_readscan_release_mode ||
              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY;
            dfii_assoc_sweep_q <= 1'b0;
            dfii_addr_sweep_q <= 1'b0;
            dfii_pattern_mode_q <= DFII_PATTERN_MODE_UNIFORM;
            dfii_phasecmd_index_q <= 4'd0;
            dfii_assoc_index_q <= 4'd0;
            dfii_addr_index_q <= 2'd0;
            dfii_byte_phase_source_q <= 7'd0;
            dfii_byte_phase_invert_q <= 1'b0;
            dfii_byte_phase_scan_word_q <= 5'd0;
            dfii_byte_phase_scan_byte_q <= 2'd0;
            dfii_byte_phase_scan_dest_q <= DFII_BYTE_PHASE_DEST_NONE;
            dfii_byte_phase_scan_count_q <= 4'd0;
            native_byte_assoc_rdata_q <= 576'd0;
            for (int source_idx = 0;
                 source_idx < DFII_BYTE_PHASE_SOURCES;
                 source_idx++) begin
              dfii_byte_phase_dest_q[source_idx] <=
                DFII_BYTE_PHASE_DEST_NONE;
              dfii_byte_phase_inv_dest_q[source_idx] <=
                DFII_BYTE_PHASE_DEST_NONE;
              dfii_byte_phase_count_q[source_idx] <= 4'd0;
              dfii_byte_phase_inv_count_q[source_idx] <= 4'd0;
            end
            cal_bitslip_q <= 3'd0;
            cal_wbitslip_q <= 3'd0;
            cal_delay_q <= 5'd0;
            state_q <=
              NATIVE_BYTE_ASSOC_PROBE_ONLY ? PROBE_BYTE_CLEAR_WRITES :
              native_sparse_readscan_only_mode ? PROBE_RUN_READS :
              ((DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY) ?
               PROBE_DFII_WBITSLIP_CONFIG : PROBE_DFII_RUN);
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
            native_nonzero_count_q <= 32'd0;
            native_first_nonzero_addr_q <= 28'd0;
            native_first_nonzero_data_q <= 64'd0;
            native_first_nonzero_chunk_q <= 9'd0;
            native_nonzero_chunk_seen_q <= 9'd0;
            native_change_count_q <= 32'd0;
            native_last_addr_q <= 28'd0;
            native_last_data_q <= 64'd0;
            native_max_outstanding_q <= 32'd0;
            dfii_final_q <= !(DFII_DISPLACEMENT_PROBE_ONLY ||
                              DFII_CSR_ECHO_PROBE_ONLY ||
                              DFII_WBITSLIP_SWEEP_ONLY ||
                              DFII_RBITSLIP_SWEEP_ONLY ||
                              DFII_EDGE_MAP_PROBE_ONLY ||
                              DFII_EDGE_COMP_PROBE_ONLY ||
                              DFII_EDGE_COMP_ACTIVE_ONLY ||
                              DFII_EDGE_COMP_BIST_ONLY ||
                              DFII_EDGE_COMP_ADDRWALK_ONLY ||
                              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
                              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN ||
                              DFII_BYTE_PHASE_ASSOC_PROBE_ONLY ||
                              DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY ||
                              DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY ||
                              DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY ||
                              DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY ||
                              NATIVE_BYTE_ASSOC_PROBE_ONLY ||
                              native_readscan_release_mode ||
                              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY);
            dfii_phasecmd_sweep_q <=
              DFII_DISPLACEMENT_PROBE_ONLY || DFII_CSR_ECHO_PROBE_ONLY ||
              DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY ||
              DFII_EDGE_MAP_PROBE_ONLY || DFII_EDGE_COMP_PROBE_ONLY ||
              DFII_EDGE_COMP_ACTIVE_ONLY ||
              DFII_EDGE_COMP_BIST_ONLY ||
              DFII_EDGE_COMP_ADDRWALK_ONLY ||
              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
              DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE_READSCAN ||
              DFII_BYTE_PHASE_ASSOC_PROBE_ONLY ||
              DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY ||
              DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY ||
              DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY ||
              DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY ||
              native_readscan_release_mode ||
              DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY;
            dfii_assoc_sweep_q <= 1'b0;
            dfii_addr_sweep_q <= 1'b0;
            dfii_pattern_mode_q <= DFII_PATTERN_MODE_UNIFORM;
            dfii_phasecmd_index_q <= 4'd0;
            dfii_assoc_index_q <= 4'd0;
            dfii_addr_index_q <= 2'd0;
            dfii_byte_phase_source_q <= 7'd0;
            dfii_byte_phase_invert_q <= 1'b0;
            for (int source_idx = 0;
                 source_idx < DFII_BYTE_PHASE_SOURCES;
                 source_idx++) begin
              dfii_byte_phase_dest_q[source_idx] <=
                DFII_BYTE_PHASE_DEST_NONE;
              dfii_byte_phase_inv_dest_q[source_idx] <=
                DFII_BYTE_PHASE_DEST_NONE;
              dfii_byte_phase_count_q[source_idx] <= 4'd0;
              dfii_byte_phase_inv_count_q[source_idx] <= 4'd0;
            end
            cal_bitslip_q <= 3'd0;
            cal_wbitslip_q <= 3'd0;
            cal_delay_q <= 5'd0;
            state_q <=
              NATIVE_BYTE_ASSOC_PROBE_ONLY ? PROBE_BYTE_CLEAR_WRITES :
              native_sparse_readscan_only_mode ? PROBE_RUN_READS :
              ((DFII_WBITSLIP_SWEEP_ONLY || DFII_RBITSLIP_SWEEP_ONLY) ?
               PROBE_DFII_WBITSLIP_CONFIG : PROBE_DFII_RUN);
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
                dfii_edge_comp_probe_mode ?
                (DFII_EDGE_COMP_CSR_ONLY ?
                 dfii_csr_mismatch_q[15:0] :
                 dfii_word_mismatch_q[15:0]) :
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
              if (dfii_edge_comp_probe_mode) begin
                if (DFII_EDGE_COMP_CSR_ONLY) begin
                  dfii_assoc_nonzero_mask_q[dfii_result_slot] <=
                    dfii_csr_mismatch_q[15:0];
                  dfii_assoc_match_mask_q[dfii_result_slot] <=
                    ~dfii_csr_mismatch_q[15:0];
                  dfii_half_nonzero_high_q[dfii_result_slot] <=
                    dfii_csr_mismatch_q[19:16];
                  dfii_half_low_match_high_q[dfii_result_slot] <=
                    ~dfii_csr_mismatch_q[19:16];
                end else begin
                  dfii_assoc_nonzero_mask_q[dfii_result_slot] <= {
                    dfii_word_mismatch_q[19:16],
                    dfi_debug_wrdata_event_count_q,
                    dfi_debug_wrdata_last_en_q,
                    dfi_debug_wrdata_seen_q
                  };
                  dfii_assoc_match_mask_q[{dfii_result_slot[1:0], 2'd0}] <=
                    dfi_debug_wrdata_word4_q[0];
                  dfii_assoc_match_mask_q[{dfii_result_slot[1:0], 2'd1}] <=
                    dfi_debug_wrdata_word4_q[1];
                  dfii_assoc_match_mask_q[{dfii_result_slot[1:0], 2'd2}] <=
                    dfi_debug_wrdata_word4_q[2];
                  dfii_assoc_match_mask_q[{dfii_result_slot[1:0], 2'd3}] <=
                    dfi_debug_wrdata_word4_q[3];
                  dfii_half_nonzero_high_q[dfii_result_slot] <=
                    dfi_debug_wrdata_word4_mask_q[3:0];
                  dfii_half_low_match_high_q[dfii_result_slot] <=
                    dfi_debug_wrdata_word4_mask_q[7:4];
                end
              end
              if (dfii_edge_comp_bist_mode ||
                  dfii_edge_comp_addrwalk_mode) begin
                dfii_assoc_nonzero_mask_q[dfii_result_slot] <= {
                  12'd0,
                  dfii_word_mismatch_q[19:16]
                };
                dfii_assoc_match_mask_q[dfii_result_slot] <=
                  ~dfii_word_mismatch_q[15:0];
                dfii_half_nonzero_high_q[dfii_result_slot] <=
                  dfii_word_mismatch_q[19:16];
                dfii_half_low_match_high_q[dfii_result_slot] <=
                  ~dfii_word_mismatch_q[19:16];
                mismatch_count_q <=
                  mismatch_count_q + dfii_bist_mismatch_word_count;
                cal_candidates_tested_q <= cal_candidates_tested_q + 32'd1;
                if (mismatch_count_q == 32'd0 &&
                    dfii_bist_mismatch_seen) begin
                  first_mismatch_addr_q <= {
                    19'd0,
                    dfii_phasecmd_index_q,
                    dfii_bist_first_mismatch_word
                  };
                  first_expected_q <= {32'd0, dfii_bist_first_expected_word};
                  first_actual_q <= {32'd0, dfii_bist_first_actual_word};
                end
              end
              if (DFII_BYTE_PHASE_ASSOC_PROBE_ONLY ||
                  DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY ||
                  DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY ||
                  DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY ||
                  DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY) begin
                if (dfii_byte_phase_final_matrix_mode) begin
                  if (dfii_byte_phase_invert_q) begin
                    dfii_half_high_match_low_q[dfii_byte_phase_source_q[3:0]]
                      <= {
                        dfi_debug_wrdata_word4_mask_q,
                        dfi_debug_wrdata_last_en_q,
                        dfi_debug_wrdata_seen_q
                      };
                    dfii_half_high_match_high_q[
                      dfii_byte_phase_source_q[3:0]
                    ] <= {
                      dfi_debug_wrdata_word4_q[3] ==
                        dfii_byte_phase_final_expected_word4(
                          dfii_byte_phase_source_q,
                          dfii_byte_phase_invert_q
                        ),
                      dfi_debug_wrdata_word4_q[2] ==
                        dfii_byte_phase_final_expected_word4(
                          dfii_byte_phase_source_q,
                          dfii_byte_phase_invert_q
                        ),
                      dfi_debug_wrdata_word4_q[1] ==
                        dfii_byte_phase_final_expected_word4(
                          dfii_byte_phase_source_q,
                          dfii_byte_phase_invert_q
                        ),
                      dfi_debug_wrdata_word4_q[0] ==
                        dfii_byte_phase_final_expected_word4(
                          dfii_byte_phase_source_q,
                          dfii_byte_phase_invert_q
                        )
                    };
                  end else begin
                    dfii_assoc_nonzero_mask_q[dfii_byte_phase_source_q[3:0]]
                      <= {
                        dfi_debug_wrdata_word4_mask_q,
                        dfi_debug_wrdata_last_en_q,
                        dfi_debug_wrdata_seen_q
                      };
                    dfii_assoc_match_mask_q[dfii_byte_phase_source_q[3:0]]
                      <= {
                        8'd0,
                        dfi_debug_wrdata_event_count_q,
                        dfi_debug_wrdata_word4_q[3] ==
                          dfii_byte_phase_final_expected_word4(
                            dfii_byte_phase_source_q,
                            dfii_byte_phase_invert_q
                          ),
                        dfi_debug_wrdata_word4_q[2] ==
                          dfii_byte_phase_final_expected_word4(
                            dfii_byte_phase_source_q,
                            dfii_byte_phase_invert_q
                          ),
                        dfi_debug_wrdata_word4_q[1] ==
                          dfii_byte_phase_final_expected_word4(
                            dfii_byte_phase_source_q,
                            dfii_byte_phase_invert_q
                          ),
                        dfi_debug_wrdata_word4_q[0] ==
                          dfii_byte_phase_final_expected_word4(
                            dfii_byte_phase_source_q,
                            dfii_byte_phase_invert_q
                          )
                      };
                  end
                end
                dfii_byte_phase_scan_word_q <= 5'd0;
                dfii_byte_phase_scan_byte_q <= 2'd0;
                dfii_byte_phase_scan_dest_q <= DFII_BYTE_PHASE_DEST_NONE;
                dfii_byte_phase_scan_count_q <= 4'd0;
                state_q <= PROBE_DFII_BYTE_SCAN;
              end else if (DFII_WBITSLIP_SWEEP_ONLY) begin
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
                           DFII_EDGE_COMP_ACTIVE_ONLY ||
                           DFII_EDGE_LANE7_LOCATOR_PROBE_ONLY) begin
                dfii_phasecmd_sweep_q <= 1'b0;
                dfii_assoc_sweep_q <= 1'b0;
                dfii_addr_sweep_q <= 1'b0;
                state_q <= PROBE_DFII_DONE;
              end else if (DFII_EDGE_COMP_BIST_ONLY ||
                           DFII_EDGE_COMP_ADDRWALK_ONLY ||
                           DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
                           native_readscan_mode) begin
                if (dfii_phasecmd_index_q ==
                    ((DFII_EDGE_COMP_ADDRWALK_ONLY ||
                      DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
                      native_readscan_mode) ?
                     4'd15 : 4'd7)) begin
                  dfii_phasecmd_sweep_q <= 1'b0;
                  dfii_assoc_sweep_q <= 1'b0;
                  dfii_addr_sweep_q <= 1'b0;
                  if (DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
                      native_readscan_mode) begin
                    if ((mismatch_count_q +
                         dfii_bist_mismatch_word_count) != 32'd0) begin
                      state_q <= PROBE_ERROR;
                    end else begin
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
                      native_nonzero_count_q <= 32'd0;
                      native_first_nonzero_addr_q <= 28'd0;
                      native_first_nonzero_data_q <= 64'd0;
                      native_first_nonzero_chunk_q <= 9'd0;
                      native_nonzero_chunk_seen_q <= 9'd0;
                      native_change_count_q <= 32'd0;
                      native_last_addr_q <= 28'd0;
                      native_last_data_q <= 64'd0;
                      native_max_outstanding_q <= 32'd0;
                      sample_valid_count_q <= 8'd0;
                      for (int sample_idx = 0;
                           sample_idx < READBACK_SAMPLE_COUNT;
                           sample_idx++)
                        sample_rdata_q[sample_idx] <= 64'd0;
                      state_q <=
                        native_readscan_mode ?
                        PROBE_RUN_READS : PROBE_RUN_WRITES;
                    end
                  end else begin
                    state_q <= PROBE_DFII_DONE;
                  end
                end else begin
                  dfii_phasecmd_index_q <= dfii_phasecmd_index_q + 4'd1;
                  state_q <= PROBE_DFII_RESTART;
                end
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
                    DFII_EDGE_COMP_ACTIVE_ONLY ||
                    DFII_EDGE_COMP_BIST_ONLY ||
                    DFII_EDGE_COMP_ADDRWALK_ONLY ||
                    DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
                    native_readscan_mode ||
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
        PROBE_DFII_BYTE_SCAN: begin
          dfii_byte_phase_scan_dest_q <= dfii_byte_phase_scan_dest_next;
          dfii_byte_phase_scan_count_q <= dfii_byte_phase_scan_count_next;
          if (dfii_byte_phase_scan_last) begin
            if (native_byte_assoc_mode) begin
              if (dfii_byte_phase_invert_q) begin
                dfii_byte_phase_inv_dest_q[dfii_byte_phase_source_q] <=
                  dfii_byte_phase_scan_dest_next;
                dfii_byte_phase_inv_count_q[dfii_byte_phase_source_q] <=
                  dfii_byte_phase_scan_count_next;
              end else begin
                dfii_byte_phase_dest_q[dfii_byte_phase_source_q] <=
                  dfii_byte_phase_scan_dest_next;
                dfii_byte_phase_count_q[dfii_byte_phase_source_q] <=
                  dfii_byte_phase_scan_count_next;
              end

              if (dfii_byte_phase_source_q == 7'd71) begin
                if (dfii_byte_phase_invert_q) begin
                  state_q <= PROBE_DONE;
                end else begin
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
                  dfii_byte_phase_invert_q <= 1'b1;
                  for (int sample_idx = 0;
                       sample_idx < READBACK_SAMPLE_COUNT;
                       sample_idx++)
                    sample_rdata_q[sample_idx] <= 64'd0;
                  state_q <= PROBE_BYTE_CLEAR_WRITES;
                end
              end else begin
                state_q <= PROBE_BYTE_RUN_READS;
              end
            end else if (dfii_byte_phase_invert_q) begin
              dfii_byte_phase_inv_dest_q[dfii_byte_phase_source_q] <=
                dfii_byte_phase_scan_dest_next;
              dfii_byte_phase_inv_count_q[dfii_byte_phase_source_q] <=
                dfii_byte_phase_scan_count_next;
              if (dfii_byte_phase_source_q ==
                  (dfii_byte_phase_active_sources - 7'd1)) begin
                dfii_phasecmd_sweep_q <= 1'b0;
                dfii_assoc_sweep_q <= 1'b0;
                dfii_addr_sweep_q <= 1'b0;
                state_q <= PROBE_DFII_DONE;
              end else begin
                dfii_byte_phase_source_q <= dfii_byte_phase_source_q + 7'd1;
                dfii_byte_phase_invert_q <= 1'b0;
                state_q <= PROBE_DFII_RESTART;
              end
            end else begin
              dfii_byte_phase_dest_q[dfii_byte_phase_source_q] <=
                dfii_byte_phase_scan_dest_next;
              dfii_byte_phase_count_q[dfii_byte_phase_source_q] <=
                dfii_byte_phase_scan_count_next;
              dfii_byte_phase_invert_q <= 1'b1;
              state_q <= PROBE_DFII_RESTART;
            end
          end else begin
            if (dfii_byte_phase_scan_byte_q == 2'd3) begin
              dfii_byte_phase_scan_byte_q <= 2'd0;
              dfii_byte_phase_scan_word_q <=
                dfii_byte_phase_scan_word_q + 5'd1;
            end else begin
              dfii_byte_phase_scan_byte_q <=
                dfii_byte_phase_scan_byte_q + 2'd1;
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
          if (native_readscan_mode &&
              (outstanding_count + 32'd1) > native_max_outstanding_q)
            native_max_outstanding_q <= outstanding_count + 32'd1;
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
          if (native_byte_assoc_mode &&
              byte_diag_read_state &&
              response_count_q < 32'd72) begin
            native_byte_assoc_rdata_q <= rdata;
            dfii_byte_phase_source_q <= response_count_q[6:0];
            dfii_byte_phase_scan_word_q <= 5'd0;
            dfii_byte_phase_scan_byte_q <= 2'd0;
            dfii_byte_phase_scan_dest_q <= DFII_BYTE_PHASE_DEST_NONE;
            dfii_byte_phase_scan_count_q <= 4'd0;
            state_q <= PROBE_DFII_BYTE_SCAN;
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
          if (native_readscan_mode && response_any_nonzero) begin
            native_nonzero_count_q <= native_nonzero_count_q + 32'd1;
            native_nonzero_chunk_seen_q <=
              native_nonzero_chunk_seen_q | response_nonzero_chunk;
            if (native_nonzero_count_q == 32'd0) begin
              native_first_nonzero_addr_q <= {3'd0, active_compare_addr};
              native_first_nonzero_data_q <= response_first_nonzero_data;
              native_first_nonzero_chunk_q <= response_nonzero_chunk;
            end
          end
          if (native_readscan_mode) begin
            if (response_count_q != 32'd0 &&
                response_first_nonzero_data != native_last_data_q)
              native_change_count_q <= native_change_count_q + 32'd1;
            native_last_addr_q <= {3'd0, active_compare_addr};
            native_last_data_q <= response_first_nonzero_data;
          end
          if (response_mismatch) begin
            mismatch_count_q <= next_mismatch_count;
            if (!mismatch_seen) begin
              first_mismatch_addr_q <= {3'd0, active_compare_addr};
              first_expected_q <= expected_rdata[63:0];
              first_actual_q <= rdata[63:0];
              first_expected_full_q <= expected_rdata;
              first_actual_full_q <= rdata;
              first_chunk_mismatch_q <= response_chunk_mismatch;
            end
          end
          if (!native_byte_assoc_mode &&
              (response_count_q + 32'd1) >= active_target_words) begin
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
      DFII_EDGE_COMP_PROBE_ONLY || DFII_EDGE_COMP_ACTIVE_ONLY ||
      DFII_EDGE_COMP_BIST_ONLY || DFII_EDGE_COMP_ADDRWALK_ONLY ||
      DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
      native_readscan_mode,
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
      DFII_EDGE_COMP_PROBE_ONLY || DFII_EDGE_COMP_ACTIVE_ONLY ||
      DFII_EDGE_COMP_BIST_ONLY || DFII_EDGE_COMP_ADDRWALK_ONLY ||
      DFII_EDGE_COMP_ADDRWALK_THEN_NATIVE ||
      native_readscan_mode,
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
`ifdef TASK6_LITEDRAM_DEBUG_PORTS
    jtag_debug_payload[4128 +: 4] = dfi_debug_wrdata_seen_q;
    jtag_debug_payload[4132 +: 4] = dfi_debug_wrdata_last_en_q;
    jtag_debug_payload[4136 +: 8] = dfi_debug_wrdata_word4_mask_q;
    jtag_debug_payload[4144 +: 4] = dfi_debug_wrdata_event_count_q;
    jtag_debug_payload[4148 +: 4] = dfi_debug_wrdata_word4_nonzero_q;
    jtag_debug_payload[4152 +: 4] = dfi_debug_wrdata_word4_unmasked_q;
    jtag_debug_payload[4160 +: 64] = {
      dfi_debug_wrdata_word4_q[3],
      dfi_debug_wrdata_word4_q[2],
      dfi_debug_wrdata_word4_q[1],
      dfi_debug_wrdata_word4_q[0]
    };
    jtag_debug_payload[4224 +: 8] = native_debug_wdata_accept_count_q;
    jtag_debug_payload[4232 +: 8] = native_debug_cmd_accept_count_q;
    jtag_debug_payload[4240 +: 7] = native_debug_last_wdata_source_q;
    jtag_debug_payload[4247 +: 1] = native_debug_last_wdata_invert_q;
    jtag_debug_payload[4256 +: 64] = native_debug_last_wdata_word4_q;
    jtag_debug_payload[4320 +: 8] = native_debug_last_wdata_word4_we_q;
    jtag_debug_payload[4336 +: 4] = dfi_debug_write_cmd_seen_q;
    jtag_debug_payload[4340 +: 4] = dfi_debug_read_cmd_seen_q;
    jtag_debug_payload[4344 +: 4] = dfi_debug_activate_cmd_seen_q;
    jtag_debug_payload[4348 +: 4] = dfi_debug_write_cmd_last_q;
    jtag_debug_payload[4352 +: 4] = dfi_debug_write_cmd_event_count_q;
    jtag_debug_payload[4360 +: 60] = dfi_debug_write_cmd_address_q;
    jtag_debug_payload[4420 +: 12] = dfi_debug_write_cmd_bank_q;
`endif
    if (native_readscan_mode) begin
      jtag_debug_payload[4096 +: 1] = native_sparse_readscan_only_mode;
      jtag_debug_payload[4224 +: 32] = native_nonzero_count_q;
      jtag_debug_payload[4256 +: 32] = {4'd0, native_first_nonzero_addr_q};
      jtag_debug_payload[4288 +: 64] = native_first_nonzero_data_q;
      jtag_debug_payload[4352 +: 9] = native_nonzero_chunk_seen_q;
      jtag_debug_payload[4368 +: 9] = native_first_nonzero_chunk_q;
      jtag_debug_payload[4384 +: 32] = native_change_count_q;
      jtag_debug_payload[4416 +: 32] = {4'd0, native_last_addr_q};
      jtag_debug_payload[4448 +: 64] = native_last_data_q;
      jtag_debug_payload[4512 +: 1] = native_readscan_single_outstanding_mode;
      jtag_debug_payload[4544 +: 32] = native_max_outstanding_q;
    end else begin
      jtag_debug_payload[4224 +: 64] = dfii_half_nonzero_high_payload;
      jtag_debug_payload[4288 +: 64] = dfii_half_low_match_high_payload;
      jtag_debug_payload[4352 +: 256] = dfii_half_high_match_low_payload;
      jtag_debug_payload[4608 +: 64] = dfii_half_high_match_high_payload;
    end
`ifdef TASK6_LITEDRAM_DEBUG_PORTS
    if (NATIVE_BYTE_ASSOC_PROBE_ONLY) begin
      jtag_debug_payload[4224 +: 8] = native_debug_wdata_accept_count_q;
      jtag_debug_payload[4232 +: 8] = native_debug_cmd_accept_count_q;
      jtag_debug_payload[4240 +: 7] = native_debug_last_wdata_source_q;
      jtag_debug_payload[4247 +: 1] = native_debug_last_wdata_invert_q;
      jtag_debug_payload[4256 +: 64] = native_debug_last_wdata_word4_q;
      jtag_debug_payload[4320 +: 8] = native_debug_last_wdata_word4_we_q;
      jtag_debug_payload[4336 +: 4] = dfi_debug_write_cmd_seen_q;
      jtag_debug_payload[4340 +: 4] = dfi_debug_read_cmd_seen_q;
      jtag_debug_payload[4344 +: 4] = dfi_debug_activate_cmd_seen_q;
      jtag_debug_payload[4348 +: 4] = dfi_debug_write_cmd_last_q;
      jtag_debug_payload[4352 +: 4] = dfi_debug_write_cmd_event_count_q;
      jtag_debug_payload[4360 +: 60] = dfi_debug_write_cmd_address_q;
      jtag_debug_payload[4420 +: 12] = dfi_debug_write_cmd_bank_q;
      jtag_debug_payload[4432 +: 4] = dfi_debug_odt_seen_q;
      jtag_debug_payload[4436 +: 4] = dfi_debug_rddata_en_seen_q;
      jtag_debug_payload[4440 +: 4] = dfi_debug_rddata_valid_seen_q;
      jtag_debug_payload[4444 +: 8] = dfi_debug_phy_write_timing_seen_q;
      jtag_debug_payload[4452 +: 16] = dfi_debug_wrdata_after_write_cmd_q;
      jtag_debug_payload[4468 +: 16] = dfi_debug_write_cmd_after_wrdata_q;
      jtag_debug_payload[4484 +: 4] = dfi_debug_write_cmd_odt_q;
      jtag_debug_payload[4488 +: 4] = dfi_debug_wrdata_odt_q;
      jtag_debug_payload[4492 +: 4] = dfi_debug_wrdata_dq_oe_q;
      jtag_debug_payload[4496 +: 4] = dfi_debug_wrdata_dqs_oe_q;
    end
`endif
    if (DFII_BYTE_PHASE_ASSOC_PROBE_ONLY ||
        DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY ||
        DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY ||
        DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY ||
        DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY ||
        NATIVE_BYTE_ASSOC_PROBE_ONLY) begin
      jtag_debug_payload[4672 +: 576] = dfii_byte_phase_dest0_payload;
      jtag_debug_payload[5248 +: 288] = dfii_byte_phase_count0_payload;
      jtag_debug_payload[5536 +: 576] = dfii_byte_phase_dest1_payload;
      jtag_debug_payload[6112 +: 288] = dfii_byte_phase_count1_payload;
      jtag_debug_payload[6400 +: 7] = dfii_byte_phase_source_q;
      jtag_debug_payload[6407 +: 1] = dfii_byte_phase_invert_q;
      jtag_debug_payload[6408 +: 1] = DFII_BYTE_PHASE_ASSOC_PROBE_ONLY;
      jtag_debug_payload[6409 +: 1] = DFII_BYTE_PHASE_CMD_MATRIX_PROBE_ONLY;
      jtag_debug_payload[6410 +: 1] =
        DFII_BYTE_PHASE_PHY_PHASE_MATRIX_PROBE_ONLY;
      jtag_debug_payload[6411 +: 1] =
        DFII_BYTE_PHASE_FINAL_MATRIX_PROBE_ONLY;
      jtag_debug_payload[6412 +: 1] = NATIVE_BYTE_ASSOC_PROBE_ONLY;
      jtag_debug_payload[6413 +: 1] = NATIVE_BYTE_ASSOC_FULL_WE;
      jtag_debug_payload[6414 +: 1] =
        DFII_BYTE_PHASE_PHASE0_ASSOC_PROBE_ONLY;
    end
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
`ifdef TASK6_LITEDRAM_DEBUG_PORTS
    ,
    .debug_dfi_wrdata_en(debug_dfi_wrdata_en),
    .debug_dfi_wrdata_word4(debug_dfi_wrdata_word4),
    .debug_dfi_wrdata_word4_mask(debug_dfi_wrdata_word4_mask),
    .debug_dfi_write_cmd(debug_dfi_write_cmd),
    .debug_dfi_read_cmd(debug_dfi_read_cmd),
    .debug_dfi_activate_cmd(debug_dfi_activate_cmd),
    .debug_dfi_odt(debug_dfi_odt),
    .debug_dfi_rddata_en(debug_dfi_rddata_en),
    .debug_dfi_rddata_valid(debug_dfi_rddata_valid),
    .debug_dfi_address(debug_dfi_address),
    .debug_dfi_bank(debug_dfi_bank)
`endif
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
