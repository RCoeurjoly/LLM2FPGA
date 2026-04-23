module task6_ui1_fork5(
  input  in0,
  input  in0_valid,
         clock,
         reset,
         out0_ready,
         out1_ready,
         out2_ready,
         out3_ready,
         out4_ready,
  output in0_ready,
         out0,
         out0_valid,
         out1,
         out1_valid,
         out2,
         out2_valid,
         out3,
         out3_valid,
         out4,
         out4_valid
);

  // Keep the generated fork contract, but encode per-output completion as one
  // small vector so abc9 can share the common control terms more directly.
  reg [4:0] emitted_reg;

  wire [4:0] ready_vec = {
    out4_ready,
    out3_ready,
    out2_ready,
    out1_ready,
    out0_ready
  };
  wire [4:0] pending_vec = { 5 { in0_valid } } & ~emitted_reg;
  wire [4:0] done_vec = emitted_reg | (ready_vec & pending_vec);
  wire       all_done = &done_vec;

  always_ff @(posedge clock) begin
    if (reset) begin
      emitted_reg <= 5'b0;
    end else if (all_done) begin
      emitted_reg <= 5'b0;
    end else begin
      emitted_reg <= done_vec;
    end
  end

  assign in0_ready = all_done;
  assign out0 = in0;
  assign out0_valid = pending_vec[0];
  assign out1 = in0;
  assign out1_valid = pending_vec[1];
  assign out2 = in0;
  assign out2_valid = pending_vec[2];
  assign out3 = in0;
  assign out3_valid = pending_vec[3];
  assign out4 = in0;
  assign out4_valid = pending_vec[4];
endmodule
