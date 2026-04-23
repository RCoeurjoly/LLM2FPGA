module task6_ui1_init0_fifo2_fork4(
  input  in0,
  input  in0_valid,
         clock,
         reset,
         out0_ready,
         out1_ready,
         out2_ready,
         out3_ready,
  output in0_ready,
         out0,
         out0_valid,
         out1,
         out1_valid,
         out2,
         out2_valid,
         out3,
         out3_valid
);

  // Merge the init-0 selector buffer and four-way fork into one local helper.
  reg       data0_reg;
  reg       data1_reg;
  reg [1:0] count_reg;
  reg [3:0] emitted_reg;

  wire       token_valid = count_reg != 2'h0;
  wire       token_data = data0_reg;
  wire [3:0] ready_vec = {
    out3_ready,
    out2_ready,
    out1_ready,
    out0_ready
  };
  wire [3:0] pending_vec = { 4 { token_valid } } & ~emitted_reg;
  wire [3:0] done_vec = emitted_reg | (ready_vec & pending_vec);
  wire       all_done = token_valid & &done_vec;
  wire       queue_has_space = count_reg != 2'h2;

  assign in0_ready = queue_has_space | all_done;
  wire do_enq = in0_valid & in0_ready;

  always_ff @(posedge clock) begin
    if (reset) begin
      data0_reg <= 1'b0;
      data1_reg <= 1'b0;
      count_reg <= 2'h1;
      emitted_reg <= 4'h0;
    end else begin
      if (all_done) begin
        emitted_reg <= 4'h0;
        case (count_reg)
          2'h1: begin
            if (do_enq) begin
              data0_reg <= in0;
              count_reg <= 2'h1;
            end else begin
              count_reg <= 2'h0;
            end
          end
          2'h2: begin
            if (do_enq) begin
              data0_reg <= data1_reg;
              data1_reg <= in0;
              count_reg <= 2'h2;
            end else begin
              data0_reg <= data1_reg;
              count_reg <= 2'h1;
            end
          end
          default: begin
            if (do_enq) begin
              data0_reg <= in0;
              count_reg <= 2'h1;
            end
          end
        endcase
      end else begin
        if (token_valid) begin
          emitted_reg <= done_vec;
        end else begin
          emitted_reg <= 4'h0;
        end

        if (do_enq) begin
          case (count_reg)
            2'h0: begin
              data0_reg <= in0;
              count_reg <= 2'h1;
            end
            2'h1: begin
              data1_reg <= in0;
              count_reg <= 2'h2;
            end
            default: begin
            end
          endcase
        end
      end
    end
  end

  assign out0 = token_data;
  assign out0_valid = pending_vec[0];
  assign out1 = token_data;
  assign out1_valid = pending_vec[1];
  assign out2 = token_data;
  assign out2_valid = pending_vec[2];
  assign out3 = token_data;
  assign out3_valid = pending_vec[3];
endmodule
