`timescale 1ns/1ps

module task6_q024_topk_score_compare_tb;
  logic clk = 1'b0;
  logic rst = 1'b1;
  logic in_valid = 1'b0;
  logic [15:0] in_token_id = 16'd0;
  logic signed [21:0] in_acc_signed = '0;
  logic [31:0] in_sidecar_word = 32'd0;
  logic out_valid;
  logic out_error_reserved_bits;
  logic [15:0] out_top_token_id;
  logic signed [45:0] out_top_score_signed_q024;

  localparam logic signed [45:0] SCORE_MIN = {1'b1, 45'd0};

  int errors = 0;

  task6_q024_topk_score_compare dut (
    .clk(clk),
    .rst(rst),
    .in_valid(in_valid),
    .in_token_id(in_token_id),
    .in_acc_signed(in_acc_signed),
    .in_sidecar_word(in_sidecar_word),
    .out_valid(out_valid),
    .out_error_reserved_bits(out_error_reserved_bits),
    .out_top_token_id(out_top_token_id),
    .out_top_score_signed_q024(out_top_score_signed_q024)
  );

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  task automatic reset_dut;
    begin
      rst = 1'b1;
      in_valid = 1'b0;
      repeat (2) @(posedge clk);
      rst = 1'b0;
      @(posedge clk);
    end
  endtask

  task automatic apply_candidate(
    input logic [15:0] token_id,
    input logic signed [21:0] accumulator,
    input logic [31:0] sidecar_word,
    input logic expect_error,
    input logic [15:0] expect_top_token,
    input logic signed [45:0] expect_top_score
  );
    begin
      @(negedge clk);
      in_valid = 1'b1;
      in_token_id = token_id;
      in_acc_signed = accumulator;
      in_sidecar_word = sidecar_word;
      @(posedge clk);
      #1;
      if (!out_valid) begin
        $display("FAIL no out_valid for token %0d", token_id);
        errors++;
      end
      if (out_error_reserved_bits !== expect_error) begin
        $display("FAIL token %0d error got %0b expected %0b",
                 token_id, out_error_reserved_bits, expect_error);
        errors++;
      end
      if (out_top_token_id !== expect_top_token) begin
        $display("FAIL token %0d top token got %0d expected %0d",
                 token_id, out_top_token_id, expect_top_token);
        errors++;
      end
      if (out_top_score_signed_q024 !== expect_top_score) begin
        $display("FAIL token %0d top score got %0d expected %0d",
                 token_id, out_top_score_signed_q024, expect_top_score);
        errors++;
      end
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  initial begin
    reset_dut();
    apply_candidate(16'd7, 22'sd1000, 32'h00800000, 1'b0, 16'd7, 46'sd8388608000);
    apply_candidate(16'd9, 22'sd1200, 32'h00600000, 1'b0, 16'd7, 46'sd8388608000);

    reset_dut();
    apply_candidate(16'd2, -22'sd10, 32'h00800000, 1'b0, 16'd2, -46'sd83886080);
    apply_candidate(16'd8, -22'sd9, 32'h00800000, 1'b0, 16'd8, -46'sd75497472);
    apply_candidate(16'd4, 22'sd0, 32'h00ffffff, 1'b0, 16'd4, 46'sd0);

    reset_dut();
    apply_candidate(16'd11, 22'sd512, 32'h00400000, 1'b0, 16'd11, 46'sd2147483648);
    apply_candidate(16'd3, 22'sd1024, 32'h00200000, 1'b0, 16'd3, 46'sd2147483648);

    reset_dut();
    apply_candidate(16'd3, 22'sd1024, 32'h00200000, 1'b0, 16'd3, 46'sd2147483648);
    apply_candidate(16'd11, 22'sd512, 32'h00400000, 1'b0, 16'd3, 46'sd2147483648);

    reset_dut();
    apply_candidate(16'd5, 22'sd1, 32'h01800000, 1'b1, 16'hffff, SCORE_MIN);

    reset_dut();
    apply_candidate(16'd50256, 22'sd1048576, 32'h00ffffff, 1'b0,
                    16'd50256, 46'sd17592184995840);
    apply_candidate(16'd0, -22'sd1048576, 32'h00ffffff, 1'b0,
                    16'd50256, 46'sd17592184995840);

    if (errors == 0) begin
      $display("PASS task6_q024_topk_score_compare_tb");
      $finish;
    end

    $display("FAIL task6_q024_topk_score_compare_tb errors=%0d", errors);
    $fatal(1);
  end
endmodule
