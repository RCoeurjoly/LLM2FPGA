`timescale 1ns/1ps

module task6_l0_gemv64_tb;
  `include "tb_data.sv"

`ifdef ENABLE_WAVES
  initial begin
`ifdef ENABLE_WAVES_VCD
    $dumpfile("wave.vcd");
`else
    $dumpfile("wave.fst");
`endif
    $dumpvars(0, task6_l0_gemv64_tb);
  end
`endif

  localparam int ACTIVATION_WORDS = 64;
  localparam int WEIGHT_WORDS = 4096;
  localparam int TIMEOUT_CYCLES = 200000;

  typedef struct packed {
    logic [5:0] address;
    logic [31:0] data;
  } store_word_t;

  logic clock;
  logic reset;
  logic in3_valid;
  wire in3_ready;

  logic [31:0] in0_ld0_data;
  logic in0_ld0_data_valid;
  wire in0_ld0_data_ready;
  wire [5:0] in0_ld0_addr;
  wire in0_ld0_addr_valid;
  logic in0_ld0_addr_ready;
  logic [5:0] pending_activation_addr;
  logic pending_activation;

  logic [31:0] in1_ld0_data;
  logic in1_ld0_data_valid;
  wire in1_ld0_data_ready;
  wire [11:0] in1_ld0_addr;
  wire in1_ld0_addr_valid;
  logic in1_ld0_addr_ready;
  logic [11:0] pending_weight_addr;
  logic pending_weight;

  store_word_t in2_st0;
  wire in2_st0_valid;
  logic in2_st0_ready;
  logic in2_st0_done_valid;
  wire in2_st0_done_ready;
  wire out0_valid;

  logic store_done_pending;
  logic completion_pending;
  logic [31:0] observed_mem [0:EXPECTED_STORE_COUNT - 1];
  logic seen_mem [0:EXPECTED_STORE_COUNT - 1];
  integer cycles;
  integer store_count;

  main dut(
    .in0_ld0_data(in0_ld0_data),
    .in0_ld0_data_valid(in0_ld0_data_valid),
    .in1_ld0_data(in1_ld0_data),
    .in1_ld0_data_valid(in1_ld0_data_valid),
    .in2_st0_done_valid(in2_st0_done_valid),
    .in3_valid(in3_valid),
    .clock(clock),
    .reset(reset),
    .out0_ready(1'b1),
    .in2_st0_ready(in2_st0_ready),
    .in1_ld0_addr_ready(in1_ld0_addr_ready),
    .in0_ld0_addr_ready(in0_ld0_addr_ready),
    .in0_ld0_data_ready(in0_ld0_data_ready),
    .in1_ld0_data_ready(in1_ld0_data_ready),
    .in2_st0_done_ready(in2_st0_done_ready),
    .in3_ready(in3_ready),
    .out0_valid(out0_valid),
    .in2_st0(in2_st0),
    .in2_st0_valid(in2_st0_valid),
    .in1_ld0_addr(in1_ld0_addr),
    .in1_ld0_addr_valid(in1_ld0_addr_valid),
    .in0_ld0_addr(in0_ld0_addr),
    .in0_ld0_addr_valid(in0_ld0_addr_valid)
  );

  always #5 clock = ~clock;

  assign in0_ld0_addr_ready = !reset && !pending_activation && !in0_ld0_data_valid;
  assign in1_ld0_addr_ready = !reset && !pending_weight && !in1_ld0_data_valid;
  assign in2_st0_done_valid = !reset && store_done_pending;
  assign in2_st0_ready = !reset && (!store_done_pending || in2_st0_done_ready);

  task automatic check_results;
    integer index;
    integer missing_count;
    integer mismatch_count;
    begin
      missing_count = 0;
      mismatch_count = 0;
      if (store_count != EXPECTED_STORE_COUNT) begin
        $display(
          "FAIL: expected %0d stores but observed %0d",
          EXPECTED_STORE_COUNT,
          store_count
        );
        $fatal(1);
      end
      for (index = 0; index < EXPECTED_STORE_COUNT; index = index + 1) begin
        if (!seen_mem[index]) begin
          missing_count = missing_count + 1;
          $display("FAIL: missing store for address %0d", index);
        end else if (observed_mem[index] !== expected_mem[index]) begin
          mismatch_count = mismatch_count + 1;
          $display(
            "FAIL: addr %0d expected 0x%08x got 0x%08x",
            index,
            expected_mem[index],
            observed_mem[index]
          );
        end
      end
      if (missing_count != 0 || mismatch_count != 0) begin
        $fatal(
          1,
          "Result check failed with %0d missing and %0d mismatched outputs",
          missing_count,
          mismatch_count
        );
      end
      $display("PASS: stores %0d outputs %0d", store_count, EXPECTED_STORE_COUNT);
      $finish;
    end
  endtask

  initial begin : init_state
    integer index;
    clock = 1'b0;
    reset = 1'b1;
    in3_valid = 1'b0;
    in0_ld0_data = 32'd0;
    in0_ld0_data_valid = 1'b0;
    pending_activation = 1'b0;
    pending_activation_addr = '0;
    in1_ld0_data = 32'd0;
    in1_ld0_data_valid = 1'b0;
    pending_weight = 1'b0;
    pending_weight_addr = '0;
    store_done_pending = 1'b0;
    completion_pending = 1'b0;
    cycles = 0;
    store_count = 0;
    for (index = 0; index < EXPECTED_STORE_COUNT; index = index + 1) begin
      observed_mem[index] = 32'd0;
      seen_mem[index] = 1'b0;
    end
    #40;
    reset = 1'b0;
    in3_valid = 1'b1;
  end

  always_ff @(posedge clock) begin
    if (!reset && in3_valid && in3_ready)
      in3_valid <= 1'b0;
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      pending_activation <= 1'b0;
      pending_activation_addr <= '0;
      in0_ld0_data <= 32'd0;
      in0_ld0_data_valid <= 1'b0;
    end else begin
      if (in0_ld0_data_valid && in0_ld0_data_ready)
        in0_ld0_data_valid <= 1'b0;
      if (!in0_ld0_data_valid && pending_activation) begin
        in0_ld0_data <= activation_mem[pending_activation_addr];
        in0_ld0_data_valid <= 1'b1;
        pending_activation <= 1'b0;
      end
      if (in0_ld0_addr_valid && in0_ld0_addr_ready) begin
        if (in0_ld0_addr >= ACTIVATION_WORDS)
          $fatal(1, "Activation read address out of range: %0d", in0_ld0_addr);
        pending_activation <= 1'b1;
        pending_activation_addr <= in0_ld0_addr;
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      pending_weight <= 1'b0;
      pending_weight_addr <= '0;
      in1_ld0_data <= 32'd0;
      in1_ld0_data_valid <= 1'b0;
    end else begin
      if (in1_ld0_data_valid && in1_ld0_data_ready)
        in1_ld0_data_valid <= 1'b0;
      if (!in1_ld0_data_valid && pending_weight) begin
        in1_ld0_data <= weight_mem[pending_weight_addr];
        in1_ld0_data_valid <= 1'b1;
        pending_weight <= 1'b0;
      end
      if (in1_ld0_addr_valid && in1_ld0_addr_ready) begin
        if (in1_ld0_addr >= WEIGHT_WORDS)
          $fatal(1, "Weight read address out of range: %0d", in1_ld0_addr);
        pending_weight <= 1'b1;
        pending_weight_addr <= in1_ld0_addr;
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      store_done_pending <= 1'b0;
      completion_pending <= 1'b0;
      store_count <= 0;
    end else begin
      if (store_done_pending && in2_st0_done_ready)
        store_done_pending <= 1'b0;
      if (in2_st0_valid && in2_st0_ready) begin
        if (in2_st0.address >= EXPECTED_STORE_COUNT)
          $fatal(1, "Store address out of range: %0d", in2_st0.address);
        if (seen_mem[in2_st0.address])
          $fatal(1, "Duplicate store observed for address %0d", in2_st0.address);
        observed_mem[in2_st0.address] <= in2_st0.data;
        seen_mem[in2_st0.address] <= 1'b1;
        store_count <= store_count + 1;
        store_done_pending <= 1'b1;
      end
      if (out0_valid)
        completion_pending <= 1'b1;
      else if (completion_pending)
        check_results();
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      cycles <= 0;
    end else begin
      cycles <= cycles + 1;
      if (cycles > TIMEOUT_CYCLES)
        $fatal(1, "Timeout waiting for task6-l0-gemv64 completion");
    end
  end
endmodule
