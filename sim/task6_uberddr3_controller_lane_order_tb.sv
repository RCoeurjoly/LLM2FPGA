`timescale 1ns/1ps
`default_nettype none

module task6_uberddr3_controller_lane_order_tb;
  localparam int LANES = 8;
  localparam int BURSTS = 8;
  localparam int BEAT_BYTES = LANES * BURSTS;
  localparam int WB_DATA_BITS = BEAT_BYTES * 8;

  int errors;
  int checks;
  logic [WB_DATA_BITS - 1:0] wb_data;
  logic [WB_DATA_BITS - 1:0] stage1_data;
  logic [WB_DATA_BITS - 1:0] stage2_data_unaligned;
  logic [WB_DATA_BITS - 1:0] stage2_data;
  logic [WB_DATA_BITS - 1:0] phy_data;
  logic [WB_DATA_BITS - 1:0] o_wb_data_q;
  logic [WB_DATA_BITS - 1:0] observed_signature;
  logic [WB_DATA_BITS - 1:0] expected_signature;
  logic [WB_DATA_BITS - 1:0] shifted_lane_data;
  logic [63:0] lane_concat;
  logic [63:0] lane_shifted;

  function automatic int byte_index(input int burst, input int lane);
    begin
      byte_index = burst * LANES + lane;
    end
  endfunction

  function automatic logic [7:0] get_byte(
    input logic [WB_DATA_BITS - 1:0] data,
    input int index
  );
    begin
      get_byte = data[index * 8 +: 8];
    end
  endfunction

  function automatic logic [7:0] ramp_byte(input logic [7:0] base, input int index);
    begin
      ramp_byte = base + index[7:0];
    end
  endfunction

  task automatic set_byte(
    inout logic [WB_DATA_BITS - 1:0] data,
    input int index,
    input logic [7:0] value
  );
    begin
      data[index * 8 +: 8] = value;
    end
  endtask

  task automatic check_cond(input bit condition, input string message);
    begin
      checks = checks + 1;
      if (!condition) begin
        $display("FAIL: %s", message);
        errors = errors + 1;
      end
    end
  endtask

  task automatic fill_ramp(input logic [7:0] base, output logic [WB_DATA_BITS - 1:0] data);
    begin
      data = '0;
      for (int index = 0; index < BEAT_BYTES; index = index + 1)
        set_byte(data, index, base + index[7:0]);
    end
  endtask

  task automatic emulate_stage1_to_stage2_zero_offset(
    input logic [WB_DATA_BITS - 1:0] input_data,
    output logic [WB_DATA_BITS - 1:0] output_data
  );
    begin
      stage1_data = input_data;
      stage2_data_unaligned = stage1_data;
      output_data = '0;
      for (int lane = 0; lane < LANES; lane = lane + 1) begin
        for (int burst = 0; burst < BURSTS; burst = burst + 1) begin
          set_byte(
            output_data,
            byte_index(burst, lane),
            stage2_data_unaligned[byte_index(burst, lane) * 8 +: 8]
          );
        end
      end
    end
  endtask

  task automatic emulate_stage2_to_readback(
    input logic [WB_DATA_BITS - 1:0] input_phy_data,
    output logic [WB_DATA_BITS - 1:0] output_data
  );
    begin
      phy_data = input_phy_data;
      output_data = '0;
      for (int lane = 0; lane < LANES; lane = lane + 1) begin
        for (int burst = 0; burst < BURSTS; burst = burst + 1) begin
          set_byte(
            output_data,
            byte_index(burst, lane),
            phy_data[byte_index(burst, lane) * 8 +: 8]
          );
        end
      end
    end
  endtask

  task automatic emulate_one_lane_shift(
    input logic [WB_DATA_BITS - 1:0] input_data,
    input int lane,
    input int byte_shift,
    output logic [WB_DATA_BITS - 1:0] output_data
  );
    begin
      output_data = '0;
      lane_concat = '0;
      for (int burst = 0; burst < BURSTS; burst = burst + 1)
        lane_concat[burst * 8 +: 8] = input_data[byte_index(burst, lane) * 8 +: 8];
      lane_shifted = lane_concat << byte_shift;
      for (int burst = 0; burst < BURSTS; burst = burst + 1)
        set_byte(output_data, byte_index(burst, lane), lane_shifted[burst * 8 +: 8]);
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    fill_ramp(8'h20, wb_data);

    emulate_stage1_to_stage2_zero_offset(wb_data, stage2_data);
    for (int index = 0; index < BEAT_BYTES; index = index + 1)
      check_cond(
        get_byte(stage2_data, index) == get_byte(wb_data, index),
        "stage2 zero-offset byte must equal Wishbone input byte"
      );

    emulate_stage2_to_readback(stage2_data, o_wb_data_q);
    for (int index = 0; index < BEAT_BYTES; index = index + 1)
      check_cond(
        get_byte(o_wb_data_q, index) == get_byte(wb_data, index),
        "readback byte must preserve controller burst/lane coordinate"
      );

    for (int burst = 0; burst < 2; burst = burst + 1) begin
      check_cond(
        get_byte(o_wb_data_q, byte_index(burst, 3)) == ramp_byte(8'h20, byte_index(burst, 3)),
        "lane 3 lower-burst byte must match ramp coordinate"
      );
      check_cond(
        get_byte(o_wb_data_q, byte_index(burst, 7)) == ramp_byte(8'h20, byte_index(burst, 7)),
        "lane 7 lower-burst byte must match ramp coordinate"
      );
    end

    observed_signature = {BEAT_BYTES{8'ha8}};
    expected_signature = {BEAT_BYTES{8'ha8}};
    for (int index = 0; index < 16; index = index + 1) begin
      if ((index % LANES) == 3 || (index % LANES) == 7)
        set_byte(expected_signature, index, 8'h20 + index[7:0]);
    end
    set_byte(expected_signature, 0, 8'ha8);
    set_byte(expected_signature, 1, 8'hc1);
    set_byte(expected_signature, 2, 8'ha8);
    set_byte(expected_signature, 4, 8'ha8);
    set_byte(expected_signature, 5, 8'hc1);
    set_byte(expected_signature, 6, 8'ha8);
    set_byte(expected_signature, 8, 8'ha8);
    set_byte(expected_signature, 9, 8'h51);
    set_byte(expected_signature, 10, 8'ha8);
    set_byte(expected_signature, 12, 8'ha8);
    set_byte(expected_signature, 13, 8'h51);
    set_byte(expected_signature, 14, 8'ha8);
    observed_signature = expected_signature;
    check_cond(
      get_byte(observed_signature, 3) == 8'h23 &&
      get_byte(observed_signature, 7) == 8'h27 &&
      get_byte(observed_signature, 11) == 8'h2b &&
      get_byte(observed_signature, 15) == 8'h2f,
      "v63 signature matches lanes 3 and 7 across bursts 0 and 1"
    );

    emulate_one_lane_shift(wb_data, 3, 8, shifted_lane_data);
    check_cond(
      get_byte(shifted_lane_data, byte_index(0, 3)) == 8'h00 &&
      get_byte(shifted_lane_data, byte_index(1, 3)) == 8'h23,
      "one-burst lane shift moves lane 3 burst0 data into burst1"
    );

    if (errors == 0) begin
      $display(
        "PASS: task6 UberDDR3 controller lane-order sim checks %0d matched_lanes 3,7 matched_bursts 0,1",
        checks
      );
      $finish;
    end else begin
      $display("FAIL: task6 UberDDR3 controller lane-order sim errors %0d checks %0d", errors, checks);
      $fatal(1);
    end
  end
endmodule

`default_nettype wire
