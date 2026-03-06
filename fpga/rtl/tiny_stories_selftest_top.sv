module tiny_stories_selftest_top(
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);
  localparam logic [31:0] TIMEOUT_CYCLES = 32'd50000000;
  localparam logic [7:0] BOOT_RESET_CYCLES = 8'd16;

  logic reset;
  logic [7:0] boot_count;
  logic [31:0] cycle_count;
  logic [25:0] blink_count;
  logic pass_latched;
  logic fail_latched;

  // Start token channel.
  logic in6_valid;
  logic in6_ready;

  // Load channels (request).
  logic in0_ld0_addr_ready;
  logic [21:0] in0_ld0_addr;
  logic in0_ld0_addr_valid;
  logic in1_ld0_addr_ready;
  logic [16:0] in1_ld0_addr;
  logic in1_ld0_addr_valid;
  logic in3_ld0_addr_ready;
  logic [21:0] in3_ld0_addr;
  logic in3_ld0_addr_valid;
  logic in4_ld0_addr_ready;
  logic in4_ld0_addr_valid;

  // Load channels (response).
  logic [7:0] in0_ld0_data;
  logic in0_ld0_data_valid;
  logic in0_ld0_data_ready;
  logic [7:0] in1_ld0_data;
  logic in1_ld0_data_valid;
  logic in1_ld0_data_ready;
  logic [31:0] in3_ld0_data;
  logic in3_ld0_data_valid;
  logic in3_ld0_data_ready;
  logic [63:0] in4_ld0_data;
  logic in4_ld0_data_valid;
  logic in4_ld0_data_ready;

  // Store channel.
  typedef struct packed {
    logic [15:0] address;
    logic [31:0] data;
  } st0_t;
  st0_t in5_st0;
  logic in5_st0_valid;
  logic in5_st0_ready;
  logic in5_st0_done_valid;
  logic in5_st0_done_ready;

  // Completion token.
  logic out0_valid;
  logic out0_ready;

  // One-entry response queues per load channel.
  logic in0_pending;
  logic [21:0] in0_addr_q;
  logic in1_pending;
  logic [16:0] in1_addr_q;
  logic in3_pending;
  logic [21:0] in3_addr_q;
  logic in4_pending;

  // One-entry completion queue for store done token.
  logic store_done_pending;
  logic [31:0] store_count;

  function automatic logic [7:0] mix8_22(input logic [21:0] addr);
    mix8_22 = addr[7:0] ^ addr[15:8] ^ {2'b00, addr[21:16]};
  endfunction

  function automatic logic [7:0] mix8_17(input logic [16:0] addr);
    mix8_17 = addr[7:0] ^ addr[15:8] ^ {7'b0, addr[16]};
  endfunction

  function automatic logic [31:0] mix32_22(input logic [21:0] addr);
    mix32_22 = {10'h0, addr} ^ {addr, 10'h0} ^ 32'h1357_9BDF;
  endfunction

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      boot_count <= 8'd0;
    end else if (boot_count <= BOOT_RESET_CYCLES) begin
      boot_count <= boot_count + 8'd1;
    end
  end
  assign reset = (boot_count <= BOOT_RESET_CYCLES);

  // Keep start token asserted until accepted.
  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      in6_valid <= 1'b1;
    end else if (reset) begin
      in6_valid <= 1'b1;
    end else if (in6_valid && in6_ready) begin
      in6_valid <= 1'b0;
    end
  end

  // Load channel adapters.
  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      in0_pending <= 1'b0;
      in0_addr_q <= 22'd0;
      in1_pending <= 1'b0;
      in1_addr_q <= 17'd0;
      in3_pending <= 1'b0;
      in3_addr_q <= 22'd0;
      in4_pending <= 1'b0;
    end else if (reset) begin
      in0_pending <= 1'b0;
      in0_addr_q <= 22'd0;
      in1_pending <= 1'b0;
      in1_addr_q <= 17'd0;
      in3_pending <= 1'b0;
      in3_addr_q <= 22'd0;
      in4_pending <= 1'b0;
    end else begin
      if (!in0_pending && in0_ld0_addr_valid && in0_ld0_addr_ready) begin
        in0_pending <= 1'b1;
        in0_addr_q <= in0_ld0_addr;
      end else if (in0_pending && in0_ld0_data_valid && in0_ld0_data_ready) begin
        in0_pending <= 1'b0;
      end

      if (!in1_pending && in1_ld0_addr_valid && in1_ld0_addr_ready) begin
        in1_pending <= 1'b1;
        in1_addr_q <= in1_ld0_addr;
      end else if (in1_pending && in1_ld0_data_valid && in1_ld0_data_ready) begin
        in1_pending <= 1'b0;
      end

      if (!in3_pending && in3_ld0_addr_valid && in3_ld0_addr_ready) begin
        in3_pending <= 1'b1;
        in3_addr_q <= in3_ld0_addr;
      end else if (in3_pending && in3_ld0_data_valid && in3_ld0_data_ready) begin
        in3_pending <= 1'b0;
      end

      if (!in4_pending && in4_ld0_addr_valid && in4_ld0_addr_ready) begin
        in4_pending <= 1'b1;
      end else if (in4_pending && in4_ld0_data_valid && in4_ld0_data_ready) begin
        in4_pending <= 1'b0;
      end
    end
  end

  assign in0_ld0_addr_ready = ~in0_pending;
  assign in0_ld0_data_valid = in0_pending;
  assign in0_ld0_data = mix8_22(in0_addr_q);

  assign in1_ld0_addr_ready = ~in1_pending;
  assign in1_ld0_data_valid = in1_pending;
  assign in1_ld0_data = mix8_17(in1_addr_q);

  assign in3_ld0_addr_ready = ~in3_pending;
  assign in3_ld0_data_valid = in3_pending;
  assign in3_ld0_data = mix32_22(in3_addr_q);

  assign in4_ld0_addr_ready = ~in4_pending;
  assign in4_ld0_data_valid = in4_pending;
  assign in4_ld0_data = 64'h0123_4567_89AB_CDEF;

  // Always consume completion token.
  assign out0_ready = 1'b1;

  // Store adapter: allow one outstanding "done" token.
  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      store_done_pending <= 1'b0;
      store_count <= 32'd0;
    end else if (reset) begin
      store_done_pending <= 1'b0;
      store_count <= 32'd0;
    end else begin
      if (!store_done_pending && in5_st0_valid && in5_st0_ready) begin
        store_done_pending <= 1'b1;
        store_count <= store_count + 32'd1;
      end else if (store_done_pending && in5_st0_done_ready) begin
        store_done_pending <= 1'b0;
      end
    end
  end

  assign in5_st0_ready = ~store_done_pending;
  assign in5_st0_done_valid = store_done_pending;

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      pass_latched <= 1'b0;
      fail_latched <= 1'b0;
      cycle_count <= 32'd0;
      blink_count <= 26'd0;
    end else begin
      blink_count <= blink_count + 26'd1;
      if (reset) begin
        pass_latched <= 1'b0;
        fail_latched <= 1'b0;
        cycle_count <= 32'd0;
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

  main u_dut(
    .in0_ld0_data(in0_ld0_data),
    .in0_ld0_data_valid(in0_ld0_data_valid),
    .in1_ld0_data(in1_ld0_data),
    .in1_ld0_data_valid(in1_ld0_data_valid),
    .in3_ld0_data(in3_ld0_data),
    .in3_ld0_data_valid(in3_ld0_data_valid),
    .in4_ld0_data(in4_ld0_data),
    .in4_ld0_data_valid(in4_ld0_data_valid),
    .in5_st0_done_valid(in5_st0_done_valid),
    .in6_valid(in6_valid),
    .clock(SYS_CLK),
    .reset(reset),
    .out0_ready(out0_ready),
    .in5_st0_ready(in5_st0_ready),
    .in4_ld0_addr_ready(in4_ld0_addr_ready),
    .in3_ld0_addr_ready(in3_ld0_addr_ready),
    .in1_ld0_addr_ready(in1_ld0_addr_ready),
    .in0_ld0_addr_ready(in0_ld0_addr_ready),
    .in0_ld0_data_ready(in0_ld0_data_ready),
    .in1_ld0_data_ready(in1_ld0_data_ready),
    .in3_ld0_data_ready(in3_ld0_data_ready),
    .in4_ld0_data_ready(in4_ld0_data_ready),
    .in5_st0_done_ready(in5_st0_done_ready),
    .in6_ready(in6_ready),
    .out0_valid(out0_valid),
    .in5_st0(in5_st0),
    .in5_st0_valid(in5_st0_valid),
    .in4_ld0_addr_valid(in4_ld0_addr_valid),
    .in3_ld0_addr(in3_ld0_addr),
    .in3_ld0_addr_valid(in3_ld0_addr_valid),
    .in1_ld0_addr(in1_ld0_addr),
    .in1_ld0_addr_valid(in1_ld0_addr_valid),
    .in0_ld0_addr(in0_ld0_addr),
    .in0_ld0_addr_valid(in0_ld0_addr_valid)
  );
endmodule
