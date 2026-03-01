module matmul_selftest_top(
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);
  localparam logic [31:0] EXPECTED = 32'd816;
  localparam logic [31:0] TIMEOUT_CYCLES = 32'd50000000;
  localparam logic [7:0] BOOT_RESET_CYCLES = 8'd16;

  logic reset;
  logic [7:0] boot_count;
  logic [31:0] cycle_count;
  logic [25:0] blink_count;
  logic pass_latched;
  logic fail_latched;

  logic in3_valid;
  logic in3_ready;

  logic [3:0] in0_ld0_addr;
  logic in0_ld0_addr_valid;
  logic [31:0] in0_ld0_data;
  logic in0_ld0_data_valid;
  logic [3:0] in1_ld0_addr;
  logic in1_ld0_addr_valid;
  logic [31:0] in1_ld0_data;
  logic in1_ld0_data_valid;

  logic [31:0] in2_st0;
  logic in2_st0_valid;
  logic in2_st0_done_ready;
  logic in2_st0_done_valid;
  logic in2_st0_ready;
  logic out0_valid;
  logic out0_ready;
  logic in0_ld0_addr_ready;
  logic in1_ld0_addr_ready;
  logic in0_ld0_data_ready;
  logic in1_ld0_data_ready;

  function automatic logic [31:0] vec_a(input logic [3:0] idx);
    case (idx)
      4'd0: vec_a = 32'd1;
      4'd1: vec_a = 32'd2;
      4'd2: vec_a = 32'd3;
      4'd3: vec_a = 32'd4;
      4'd4: vec_a = 32'd5;
      4'd5: vec_a = 32'd6;
      4'd6: vec_a = 32'd7;
      4'd7: vec_a = 32'd8;
      4'd8: vec_a = 32'd9;
      4'd9: vec_a = 32'd10;
      4'd10: vec_a = 32'd11;
      4'd11: vec_a = 32'd12;
      4'd12: vec_a = 32'd13;
      4'd13: vec_a = 32'd14;
      4'd14: vec_a = 32'd15;
      4'd15: vec_a = 32'd16;
      default: vec_a = 32'd0;
    endcase
  endfunction

  function automatic logic [31:0] vec_b(input logic [3:0] idx);
    case (idx)
      4'd0: vec_b = 32'd16;
      4'd1: vec_b = 32'd15;
      4'd2: vec_b = 32'd14;
      4'd3: vec_b = 32'd13;
      4'd4: vec_b = 32'd12;
      4'd5: vec_b = 32'd11;
      4'd6: vec_b = 32'd10;
      4'd7: vec_b = 32'd9;
      4'd8: vec_b = 32'd8;
      4'd9: vec_b = 32'd7;
      4'd10: vec_b = 32'd6;
      4'd11: vec_b = 32'd5;
      4'd12: vec_b = 32'd4;
      4'd13: vec_b = 32'd3;
      4'd14: vec_b = 32'd2;
      4'd15: vec_b = 32'd1;
      default: vec_b = 32'd0;
    endcase
  endfunction

  assign in0_ld0_data = in0_ld0_addr_valid ? vec_a(in0_ld0_addr) : 32'd0;
  assign in0_ld0_data_valid = in0_ld0_addr_valid;
  assign in1_ld0_data = in1_ld0_addr_valid ? vec_b(in1_ld0_addr) : 32'd0;
  assign in1_ld0_data_valid = in1_ld0_addr_valid;

  assign out0_ready = 1'b1;
  assign in0_ld0_addr_ready = 1'b1;
  assign in1_ld0_addr_ready = 1'b1;
  assign in2_st0_ready = 1'b1;
  assign in2_st0_done_valid = 1'b0;

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      boot_count <= 8'd0;
      reset <= 1'b1;
    end else if (boot_count < BOOT_RESET_CYCLES) begin
      boot_count <= boot_count + 8'd1;
      reset <= 1'b1;
    end else begin
      reset <= 1'b0;
    end
  end

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN) begin
      in3_valid <= 1'b1;
    end else if (reset) begin
      in3_valid <= 1'b1;
    end else if (in3_valid && in3_ready) begin
      in3_valid <= 1'b0;
    end
  end

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
        if (in2_st0_valid) begin
          if (in2_st0 == EXPECTED) begin
            pass_latched <= 1'b1;
          end else begin
            fail_latched <= 1'b1;
          end
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
    .clock(SYS_CLK),
    .reset(reset),
    .in3_valid(in3_valid),
    .in3_ready(in3_ready),
    .out0_ready(out0_ready),
    .out0_valid(out0_valid),
    .in0_ld0_addr_ready(in0_ld0_addr_ready),
    .in0_ld0_addr(in0_ld0_addr),
    .in0_ld0_addr_valid(in0_ld0_addr_valid),
    .in0_ld0_data(in0_ld0_data),
    .in0_ld0_data_valid(in0_ld0_data_valid),
    .in0_ld0_data_ready(in0_ld0_data_ready),
    .in1_ld0_addr_ready(in1_ld0_addr_ready),
    .in1_ld0_addr(in1_ld0_addr),
    .in1_ld0_addr_valid(in1_ld0_addr_valid),
    .in1_ld0_data(in1_ld0_data),
    .in1_ld0_data_valid(in1_ld0_data_valid),
    .in1_ld0_data_ready(in1_ld0_data_ready),
    .in2_st0_done_ready(in2_st0_done_ready),
    .in2_st0_done_valid(in2_st0_done_valid),
    .in2_st0_ready(in2_st0_ready),
    .in2_st0(in2_st0),
    .in2_st0_valid(in2_st0_valid)
  );
endmodule
