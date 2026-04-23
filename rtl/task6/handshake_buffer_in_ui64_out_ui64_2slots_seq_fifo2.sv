module handshake_buffer_in_ui64_out_ui64_2slots_seq(
  input  [63:0] in0,
  input         in0_valid,
                clock,
                reset,
                out0_ready,
  output        in0_ready,
  output [63:0] out0,
  output        out0_valid
);
  task6_ui64_fifo2_buffer impl (
    .in0        (in0),
    .in0_valid  (in0_valid),
    .clock      (clock),
    .reset      (reset),
    .out0_ready (out0_ready),
    .in0_ready  (in0_ready),
    .out0       (out0),
    .out0_valid (out0_valid)
  );
endmodule
