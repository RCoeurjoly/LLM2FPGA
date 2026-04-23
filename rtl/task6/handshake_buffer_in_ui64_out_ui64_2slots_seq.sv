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

  reg [63:0] data_reg;
  reg        full_reg;

  always_ff @(posedge clock) begin
    if (reset) begin
      data_reg <= 64'h0;
      full_reg <= 1'h0;
    end else if (full_reg) begin
      if (out0_ready) begin
        if (in0_valid) begin
          data_reg <= in0;
          full_reg <= 1'h1;
        end else begin
          full_reg <= 1'h0;
        end
      end
    end else if (in0_valid && !out0_ready) begin
      data_reg <= in0;
      full_reg <= 1'h1;
    end
  end

  assign in0_ready = ~full_reg | out0_ready;
  assign out0 = full_reg ? data_reg : in0;
  assign out0_valid = full_reg | in0_valid;
endmodule
