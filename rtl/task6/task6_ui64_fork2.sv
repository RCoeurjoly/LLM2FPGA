module task6_ui64_fork2(
  input  [63:0] in0,
  input         in0_valid,
                clock,
                reset,
                out0_ready,
                out1_ready,
  output        in0_ready,
  output [63:0] out0,
  output        out0_valid,
  output [63:0] out1,
  output        out1_valid
);

  reg [1:0] emitted_reg;

  wire [1:0] ready_vec = { out1_ready, out0_ready };
  wire [1:0] pending_vec = { 2 { in0_valid } } & ~emitted_reg;
  wire [1:0] done_vec = emitted_reg | (ready_vec & pending_vec);
  wire       all_done = &done_vec;

  always_ff @(posedge clock) begin
    if (reset) begin
      emitted_reg <= 2'b0;
    end else if (all_done) begin
      emitted_reg <= 2'b0;
    end else begin
      emitted_reg <= done_vec;
    end
  end

  assign in0_ready = all_done;
  assign out0 = in0;
  assign out0_valid = pending_vec[0];
  assign out1 = in0;
  assign out1_valid = pending_vec[1];
endmodule
