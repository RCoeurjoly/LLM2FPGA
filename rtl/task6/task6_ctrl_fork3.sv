module task6_ctrl_fork3(
  input  in0_valid,
         clock,
         reset,
         out0_ready,
         out1_ready,
         out2_ready,
  output in0_ready,
         out0_valid,
         out1_valid,
         out2_valid
);

  reg [2:0] emitted_reg;

  wire [2:0] ready_vec = { out2_ready, out1_ready, out0_ready };
  wire [2:0] pending_vec = { 3 { in0_valid } } & ~emitted_reg;
  wire [2:0] done_vec = emitted_reg | (ready_vec & pending_vec);
  wire       all_done = &done_vec;

  always_ff @(posedge clock) begin
    if (reset) begin
      emitted_reg <= 3'b0;
    end else if (all_done) begin
      emitted_reg <= 3'b0;
    end else begin
      emitted_reg <= done_vec;
    end
  end

  assign in0_ready = all_done;
  assign out0_valid = pending_vec[0];
  assign out1_valid = pending_vec[1];
  assign out2_valid = pending_vec[2];
endmodule
