`timescale 1ns/1ps
`default_nettype none

module task6_uberddr3_stage2_timing_tb;
  localparam int LANES = 8;
  localparam int BURSTS = 8;
  localparam int BEAT_BYTES = LANES * BURSTS;
  localparam int WB_DATA_BITS = BEAT_BYTES * 8;
  localparam int STAGE2_DATA_DEPTH = 2;

  int errors;
  int checks;
  int update_count;
  int hold_count;
  int read_pipe_updates;
  logic clk;
  logic rst_n;
  logic stage2_update;
  logic [WB_DATA_BITS - 1:0] stage1_data;
  logic [WB_DATA_BITS - 1:0] stage2_data_unaligned;
  logic [WB_DATA_BITS - 1:0] stage2_data [0:STAGE2_DATA_DEPTH - 1];
  logic [63:0] unaligned_data [0:LANES - 1];
  logic [6:0] data_start_index [0:LANES - 1];
  logic late_dq [0:LANES - 1];
  logic [WB_DATA_BITS - 1:0] read_phy_data;
  logic [WB_DATA_BITS - 1:0] o_wb_data_q [0:1];
  logic [1:0] delay_read_pipe [0:1];
  logic added_read_pipe [0:LANES - 1];
  logic added_read_pipe_max;
  logic index_wb_data;
  logic [WB_DATA_BITS - 1:0] reference_a;
  logic [WB_DATA_BITS - 1:0] reference_b;

  always #5 clk = ~clk;

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

  task automatic fill_ramp(input logic [7:0] base, output logic [WB_DATA_BITS - 1:0] data);
    begin
      data = '0;
      for (int index = 0; index < BEAT_BYTES; index = index + 1)
        set_byte(data, index, ramp_byte(base, index));
    end
  endtask

  function automatic logic [63:0] lane_pack(input logic [WB_DATA_BITS - 1:0] data, input int lane);
    begin
      lane_pack = '0;
      for (int burst = 0; burst < BURSTS; burst = burst + 1)
        lane_pack[burst * 8 +: 8] = data[byte_index(burst, lane) * 8 +: 8];
    end
  endfunction

  task automatic unpack_lane(
    inout logic [WB_DATA_BITS - 1:0] data,
    input int lane,
    input logic [63:0] lane_word
  );
    begin
      for (int burst = 0; burst < BURSTS; burst = burst + 1)
        set_byte(data, byte_index(burst, lane), lane_word[burst * 8 +: 8]);
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

  task automatic check_lane_equals(
    input logic [WB_DATA_BITS - 1:0] data,
    input logic [WB_DATA_BITS - 1:0] expected,
    input int lane,
    input string message
  );
    begin
      for (int burst = 0; burst < BURSTS; burst = burst + 1)
        check_cond(
          get_byte(data, byte_index(burst, lane)) ==
            get_byte(expected, byte_index(burst, lane)),
          message
        );
    end
  endtask

  task automatic apply_stage2_alignment;
    logic [63:0] lane_word;
    logic [127:0] shifted;
    begin
      for (int lane = 0; lane < LANES; lane = lane + 1) begin
        lane_word = lane_pack(stage2_data_unaligned, lane);
        if (late_dq[lane]) begin
          shifted = ({64'd0, lane_word} << {data_start_index[lane][6:1], 1'b0}) |
            {64'd0, unaligned_data[lane]};
          unaligned_data[lane] = shifted[127:64];
          unpack_lane(stage2_data[1], lane, shifted[63:0]);
        end else begin
          shifted = ({64'd0, lane_word} << data_start_index[lane]) |
            {64'd0, unaligned_data[lane]};
          unaligned_data[lane] = shifted[127:64];
          unpack_lane(stage2_data[0], lane, shifted[63:0]);
        end
      end
    end
  endtask

  task automatic apply_read_pipe_capture;
    begin
      for (int lane = 0; lane < LANES; lane = lane + 1) begin
        if (delay_read_pipe[0][added_read_pipe_max != added_read_pipe[lane]]) begin
          unpack_lane(o_wb_data_q[0], lane, lane_pack(read_phy_data, lane));
          read_pipe_updates = read_pipe_updates + 1;
        end
        if (delay_read_pipe[1][added_read_pipe_max != added_read_pipe[lane]]) begin
          unpack_lane(o_wb_data_q[1], lane, lane_pack(read_phy_data, lane));
          read_pipe_updates = read_pipe_updates + 1;
        end
      end
    end
  endtask

  task automatic step_controller;
    begin
      @(negedge clk);
      @(posedge clk);
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stage2_data_unaligned = '0;
      for (int index = 0; index < STAGE2_DATA_DEPTH; index = index + 1)
        stage2_data[index] = '0;
      for (int lane = 0; lane < LANES; lane = lane + 1)
        unaligned_data[lane] = '0;
      update_count = 0;
      hold_count = 0;
    end else if (stage2_update) begin
      stage2_data_unaligned = stage1_data;
      stage2_data[1] = stage2_data[0];
      apply_stage2_alignment();
      update_count = update_count + 1;
    end else begin
      hold_count = hold_count + 1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      o_wb_data_q[0] = '0;
      o_wb_data_q[1] = '0;
      index_wb_data = 1'b0;
    end else begin
      apply_read_pipe_capture();
      if (delay_read_pipe[0][0])
        index_wb_data = !index_wb_data;
    end
  end

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    stage2_update = 1'b0;
    stage1_data = '0;
    read_phy_data = '0;
    delay_read_pipe[0] = 2'b00;
    delay_read_pipe[1] = 2'b00;
    added_read_pipe_max = 1'b1;
    errors = 0;
    checks = 0;
    update_count = 0;
    hold_count = 0;
    read_pipe_updates = 0;
    for (int lane = 0; lane < LANES; lane = lane + 1) begin
      data_start_index[lane] = 7'd0;
      late_dq[lane] = 1'b0;
      added_read_pipe[lane] = lane[0];
    end

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    fill_ramp(8'h20, reference_a);
    stage1_data = reference_a;
    stage2_update = 1'b1;
    step_controller();
    stage2_update = 1'b0;

    for (int lane = 0; lane < LANES; lane = lane + 1)
      check_lane_equals(stage2_data[0], reference_a, lane, "zero-offset stage2 lane must match input ramp");
    check_cond(update_count == 1, "stage2_update must advance the write data pipeline");

    fill_ramp(8'h40, reference_b);
    stage1_data = reference_b;
    stage2_update = 1'b0;
    step_controller();
    for (int lane = 0; lane < LANES; lane = lane + 1)
      check_lane_equals(stage2_data[0], reference_a, lane, "stage2_update low must hold stage2 data");
    check_cond(hold_count == 1, "stage2_update low must count as a held cycle");

    stage2_update = 1'b1;
    step_controller();
    stage2_update = 1'b0;
    for (int lane = 0; lane < LANES; lane = lane + 1)
      check_lane_equals(stage2_data[0], reference_b, lane, "stage2_update high must accept next write data");

    data_start_index[3] = 7'd8;
    late_dq[3] = 1'b0;
    fill_ramp(8'h60, reference_a);
    stage1_data = reference_a;
    stage2_update = 1'b1;
    step_controller();
    stage2_update = 1'b0;
    check_cond(
      get_byte(stage2_data[0], byte_index(0, 3)) == 8'h00,
      "data_start_index 8 must insert carryover/stale byte at first lane 3 burst"
    );
    check_cond(
      get_byte(stage2_data[0], byte_index(1, 3)) == ramp_byte(8'h60, byte_index(0, 3)),
      "data_start_index 8 must shift lane 3 burst0 into burst1"
    );
    check_cond(
      unaligned_data[3][0 +: 8] == ramp_byte(8'h60, byte_index(7, 3)),
      "data_start_index 8 must carry lane 3 burst7 into unaligned_data"
    );

    data_start_index[7] = 7'd1;
    late_dq[7] = 1'b1;
    fill_ramp(8'h80, reference_b);
    stage1_data = reference_b;
    stage2_update = 1'b1;
    step_controller();
    stage2_update = 1'b0;
    check_cond(
      get_byte(stage2_data[1], byte_index(0, 7)) == ramp_byte(8'h80, byte_index(0, 7)),
      "late_dq with data_start_index 1 must forward lane 7 to stage2_data[1] without byte shift"
    );
    check_cond(
      get_byte(stage2_data[0], byte_index(0, 7)) != ramp_byte(8'h80, byte_index(0, 7)),
      "late_dq lane 7 must not update stage2_data[0] directly"
    );

    fill_ramp(8'ha0, read_phy_data);
    delay_read_pipe[0] = 2'b10;
    delay_read_pipe[1] = 2'b00;
    step_controller();
    for (int lane = 0; lane < LANES; lane = lane + 1) begin
      if (added_read_pipe[lane] == 1'b0)
        check_lane_equals(o_wb_data_q[0], read_phy_data, lane, "read pipe early lanes must update first");
      else
        check_cond(
          get_byte(o_wb_data_q[0], byte_index(0, lane)) != ramp_byte(8'ha0, byte_index(0, lane)),
          "read pipe delayed lanes must not update on early tap"
        );
    end

    delay_read_pipe[0] = 2'b01;
    step_controller();
    for (int lane = 0; lane < LANES; lane = lane + 1)
      check_lane_equals(o_wb_data_q[0], read_phy_data, lane, "read pipe late tap must complete all lanes");
    check_cond(index_wb_data == 1'b1, "read ack low tap must toggle output read buffer index");

    if (errors == 0) begin
      $display(
        "PASS: task6 UberDDR3 stage2 timing sim checks %0d updates %0d holds %0d read_pipe_updates %0d",
        checks, update_count, hold_count, read_pipe_updates
      );
      $finish;
    end else begin
      $display("FAIL: task6 UberDDR3 stage2 timing sim errors %0d checks %0d", errors, checks);
      $fatal(1);
    end
  end
endmodule

`default_nettype wire
