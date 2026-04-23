module task6_ctrl_fifo2_buffer(
  input  in0_valid,
         clock,
         reset,
         out0_ready,
  output in0_ready,
  output out0_valid
);

  // Zero-width control tokens only need occupancy tracking.
  reg [1:0] count_reg;

  wire do_enq = in0_valid & in0_ready;
  wire do_deq = out0_valid & out0_ready;

  always_ff @(posedge clock) begin
    if (reset) begin
      count_reg <= 2'h0;
    end else begin
      case ({do_enq, do_deq})
        2'b00: begin
        end
        2'b01: begin
          count_reg <= count_reg - 2'h1;
        end
        2'b10: begin
          count_reg <= count_reg + 2'h1;
        end
        2'b11: begin
        end
      endcase
    end
  end

  assign in0_ready = count_reg != 2'h2;
  assign out0_valid = count_reg != 2'h0;
endmodule
