module tiny_stories_selftest_top(
  input  logic       SYS_CLK,
  input  logic       SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);

  localparam logic [31:0] TIMEOUT_CYCLES   = 32'd50000000;
  localparam logic [7:0]  BOOT_RESET_CYCLES = 8'd16;

  logic reset;
  logic [7:0]  boot_count;
  logic [31:0] cycle_count;
  logic [25:0] blink_count;
  logic pass_latched;
  logic fail_latched;

  // DUT inputs driven by this wrapper.
  logic [63:0] in16_ld0_data;
  logic        in16_ld0_data_valid;
  logic        in17_st0_done_valid;
  logic        in18_valid;
  logic        out0_ready;
  logic        in17_st0_ready;
  logic        in16_ld0_addr_ready;

  // DUT outputs observed by this wrapper.
  logic        in16_ld0_data_ready;
  logic        in17_st0_done_ready;
  logic        in18_ready;
  logic        out0_valid;
  struct packed {logic [15:0] address; logic [31:0] data; } in17_st0;
  logic        in17_st0_valid;
  logic        in16_ld0_addr_valid;

  logic load_pending;
  logic store_done_pending;

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      boot_count <= 8'd0;
    end else if (boot_count <= BOOT_RESET_CYCLES) begin
      boot_count <= boot_count + 8'd1;
    end
  end

  assign reset = (boot_count <= BOOT_RESET_CYCLES);

  // Send the single zero-width start token.
  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      in18_valid <= 1'b1;
    end else if (reset) begin
      in18_valid <= 1'b1;
    end else if (in18_valid && in18_ready) begin
      in18_valid <= 1'b0;
    end
  end

  // Respond to the zero-width load address request with fixed 64-bit data.
  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      load_pending <= 1'b0;
    end else if (reset) begin
      load_pending <= 1'b0;
    end else begin
      if (!load_pending && in16_ld0_addr_valid && in16_ld0_addr_ready) begin
        load_pending <= 1'b1;
      end else if (load_pending && in16_ld0_data_valid && in16_ld0_data_ready) begin
        load_pending <= 1'b0;
      end
    end
  end

  assign in16_ld0_addr_ready = ~load_pending;
  assign in16_ld0_data_valid = load_pending;
  assign in16_ld0_data       = 64'h0123_4567_89AB_CDEF;

  // Always ready to accept the final completion token.
  assign out0_ready = 1'b1;

  // Accept a store request, then return the zero-width store-done token.
  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      store_done_pending <= 1'b0;
    end else if (reset) begin
      store_done_pending <= 1'b0;
    end else begin
      if (!store_done_pending && in17_st0_valid && in17_st0_ready) begin
        store_done_pending <= 1'b1;
      end else if (store_done_pending && in17_st0_done_ready) begin
        store_done_pending <= 1'b0;
      end
    end
  end

  assign in17_st0_ready      = ~store_done_pending;
  assign in17_st0_done_valid = store_done_pending;

  // Pass/fail monitor.
  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      pass_latched <= 1'b0;
      fail_latched <= 1'b0;
      cycle_count  <= 32'd0;
      blink_count  <= 26'd0;
    end else begin
      blink_count <= blink_count + 26'd1;

      if (reset) begin
        pass_latched <= 1'b0;
        fail_latched <= 1'b0;
        cycle_count  <= 32'd0;
      end else if (!(pass_latched || fail_latched)) begin
        if (out0_valid) begin
          pass_latched <= 1'b1;
        end else if (cycle_count >= TIMEOUT_CYCLES) begin
          fail_latched <= 1'b1;
        end else begin
          cycle_count <= cycle_count + 32'd1;
        end
      end
    end
  end

  assign led_3bits_tri_o[0] = blink_count[25];
  assign led_3bits_tri_o[1] = pass_latched;
  assign led_3bits_tri_o[2] = fail_latched;

  main u_dut (
    .in16_ld0_data        (in16_ld0_data),
    .in16_ld0_data_valid  (in16_ld0_data_valid),
    .in17_st0_done_valid  (in17_st0_done_valid),
    .in18_valid           (in18_valid),
    .clock                (SYS_CLK),
    .reset                (reset),
    .out0_ready           (out0_ready),
    .in17_st0_ready       (in17_st0_ready),
    .in16_ld0_addr_ready  (in16_ld0_addr_ready),

    .in16_ld0_data_ready  (in16_ld0_data_ready),
    .in17_st0_done_ready  (in17_st0_done_ready),
    .in18_ready           (in18_ready),
    .out0_valid           (out0_valid),
    .in17_st0             (in17_st0),
    .in17_st0_valid       (in17_st0_valid),
    .in16_ld0_addr_valid  (in16_ld0_addr_valid)
  );

endmodule
