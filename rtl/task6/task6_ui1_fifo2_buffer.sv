module task6_ui1_fifo2_buffer(
  input  in0,
  input  in0_valid,
         clock,
         reset,
         out0_ready,
  output in0_ready,
         out0,
         out0_valid
);

  reg data0_reg;
  reg data1_reg;
  reg [1:0] count_reg;

  wire do_enq = in0_valid & in0_ready;
  wire do_deq = out0_valid & out0_ready;

  always_ff @(posedge clock) begin
    if (reset) begin
      data0_reg <= 1'b0;
      data1_reg <= 1'b0;
      count_reg <= 2'h0;
    end else begin
      case ({do_enq, do_deq})
        2'b00: begin
        end
        2'b01: begin
          if (count_reg == 2'h2) begin
            data0_reg <= data1_reg;
            count_reg <= 2'h1;
          end else begin
            count_reg <= 2'h0;
          end
        end
        2'b10: begin
          if (count_reg == 2'h0) begin
            data0_reg <= in0;
            count_reg <= 2'h1;
          end else begin
            data1_reg <= in0;
            count_reg <= 2'h2;
          end
        end
        2'b11: begin
          if (count_reg == 2'h1) begin
            data0_reg <= in0;
          end else begin
            data0_reg <= data1_reg;
            data1_reg <= in0;
          end
        end
      endcase
    end
  end

  assign in0_ready = count_reg != 2'h2;
  assign out0 = data0_reg;
  assign out0_valid = count_reg != 2'h0;
endmodule
