module main(
    input  [31:0]                                                   in0_ld0_data,
    input                                                           in0_ld0_data_valid,
    input  [31:0]                                                   in1_ld0_data,
    input                                                           in1_ld0_data_valid,
    input                                                           in2_st0_done_valid,
    input                                                           in3_valid,
    input                                                           clock,
    input                                                           reset,
    input                                                           out0_ready,
    input                                                           in2_st0_ready,
    input                                                           in1_ld0_addr_ready,
    input                                                           in0_ld0_addr_ready,
    output                                                          in0_ld0_data_ready,
    output                                                          in1_ld0_data_ready,
    output                                                          in2_st0_done_ready,
    output                                                          in3_ready,
    output                                                          out0_valid,
    output struct packed {logic [7:0] address; logic [31:0] data; } in2_st0,
    output                                                          in2_st0_valid,
    output [13:0]                                                   in1_ld0_addr,
    output                                                          in1_ld0_addr_valid,
    output [5:0]                                                    in0_ld0_addr,
    output                                                          in0_ld0_addr_valid
);

  typedef struct packed {
    logic [5:0] address;
    logic [31:0] data;
  } tile_store_t;

  logic        active_q;
  logic [1:0]  phase_q;
  logic        launch_pending_q;

  logic        tile_in3_ready;
  logic        tile_in3_valid;
  logic        tile_out0_valid;
  logic        tile_out0_ready;
  logic        tile_in2_st0_valid;
  logic        tile_in2_st0_ready;
  logic        tile_in2_st0_done_ready;
  logic        tile_in2_st0_done_valid;
  logic        tile_in1_ld0_addr_valid;
  logic [11:0] tile_in1_ld0_addr;
  logic        tile_in0_ld0_addr_valid;
  logic [5:0]  tile_in0_ld0_addr;
  logic        tile_in0_ld0_data_ready;
  logic        tile_in1_ld0_data_ready;
  tile_store_t tile_in2_st0;

  assign tile_in3_valid = active_q ? launch_pending_q : in3_valid;
  assign in3_ready = !active_q && tile_in3_ready;

  assign in0_ld0_addr = tile_in0_ld0_addr;
  assign in0_ld0_addr_valid = tile_in0_ld0_addr_valid;
  assign in0_ld0_data_ready = tile_in0_ld0_data_ready;

  assign in1_ld0_addr = {phase_q, tile_in1_ld0_addr};
  assign in1_ld0_addr_valid = tile_in1_ld0_addr_valid;
  assign in1_ld0_data_ready = tile_in1_ld0_data_ready;

  assign in2_st0.address = {phase_q, tile_in2_st0.address};
  assign in2_st0.data = tile_in2_st0.data;
  assign in2_st0_valid = tile_in2_st0_valid;
  assign tile_in2_st0_ready = in2_st0_ready;
  assign tile_in2_st0_done_valid = in2_st0_done_valid;
  assign in2_st0_done_ready = tile_in2_st0_done_ready;

  assign out0_valid = active_q && (phase_q == 2'd3) && tile_out0_valid;
  assign tile_out0_ready = (active_q && (phase_q == 2'd3)) ? out0_ready : 1'b1;

  always_ff @(posedge clock) begin
    if (reset) begin
      active_q <= 1'b0;
      phase_q <= 2'd0;
      launch_pending_q <= 1'b0;
    end else begin
      if (!active_q) begin
        phase_q <= 2'd0;
        launch_pending_q <= 1'b0;
        if (in3_valid && tile_in3_ready)
          active_q <= 1'b1;
      end else begin
        if (launch_pending_q && tile_in3_ready)
          launch_pending_q <= 1'b0;

        if (tile_out0_valid && tile_out0_ready) begin
          if (phase_q == 2'd3) begin
            active_q <= 1'b0;
            phase_q <= 2'd0;
            launch_pending_q <= 1'b0;
          end else begin
            phase_q <= phase_q + 2'd1;
            launch_pending_q <= 1'b1;
          end
        end
      end
    end
  end

  task6_l2_c_fc_tile64_kernel tile_kernel(
    .in0_ld0_data       (in0_ld0_data),
    .in0_ld0_data_valid (in0_ld0_data_valid),
    .in1_ld0_data       (in1_ld0_data),
    .in1_ld0_data_valid (in1_ld0_data_valid),
    .in2_st0_done_valid (tile_in2_st0_done_valid),
    .in3_valid          (tile_in3_valid),
    .clock              (clock),
    .reset              (reset),
    .out0_ready         (tile_out0_ready),
    .in2_st0_ready      (tile_in2_st0_ready),
    .in1_ld0_addr_ready (in1_ld0_addr_ready),
    .in0_ld0_addr_ready (in0_ld0_addr_ready),
    .in0_ld0_data_ready (tile_in0_ld0_data_ready),
    .in1_ld0_data_ready (tile_in1_ld0_data_ready),
    .in2_st0_done_ready (tile_in2_st0_done_ready),
    .in3_ready          (tile_in3_ready),
    .out0_valid         (tile_out0_valid),
    .in2_st0            (tile_in2_st0),
    .in2_st0_valid      (tile_in2_st0_valid),
    .in1_ld0_addr       (tile_in1_ld0_addr),
    .in1_ld0_addr_valid (tile_in1_ld0_addr_valid),
    .in0_ld0_addr       (tile_in0_ld0_addr),
    .in0_ld0_addr_valid (tile_in0_ld0_addr_valid)
  );

endmodule
