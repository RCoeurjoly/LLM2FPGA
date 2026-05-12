`timescale 1ns/1ps
`default_nettype none

module task6_uberddr3_signature_hypothesis_tb;
  localparam int LANES = 8;
  localparam int BURSTS = 8;
  localparam int BEAT_BYTES = LANES * BURSTS;
  localparam int WB_DATA_BITS = BEAT_BYTES * 8;

  int errors;
  int checks;
  int dense_signature_solutions;
  int v63_signature_solutions;

  logic [WB_DATA_BITS - 1:0] expected_dense;
  logic [WB_DATA_BITS - 1:0] expected_v63;
  logic [WB_DATA_BITS - 1:0] residue_dense;
  logic [WB_DATA_BITS - 1:0] residue_v63;
  logic [WB_DATA_BITS - 1:0] candidate;

  function automatic int byte_index(input int burst, input int lane);
    begin
      byte_index = burst * LANES + lane;
    end
  endfunction

  function automatic logic [7:0] get_byte(
    input logic [WB_DATA_BITS - 1:0] data,
    input int index
  );
    begin
      get_byte = data[index * 8 +: 8];
    end
  endfunction

  task automatic set_byte(
    inout logic [WB_DATA_BITS - 1:0] data,
    input int index,
    input logic [7:0] value
  );
    begin
      data[index * 8 +: 8] = value;
    end
  endtask

  task automatic fill_ramp(input logic [7:0] base, output logic [WB_DATA_BITS - 1:0] data);
    begin
      data = '0;
      for (int index = 0; index < BEAT_BYTES; index = index + 1)
        set_byte(data, index, base + index[7:0]);
    end
  endtask

  task automatic check_cond(input bit condition, input string message);
    begin
      checks = checks + 1;
      if (!condition) begin
        $display("FAIL: %s", message);
        errors = errors + 1;
      end
    end
  endtask

  function automatic bit lower16_matches_dense(
    input logic [WB_DATA_BITS - 1:0] data
  );
    logic [127:0] observed;
    begin
      observed = 128'h0f0e5100000051000000c1000000c100;
      lower16_matches_dense = data[127:0] == observed;
    end
  endfunction

  function automatic bit lower16_matches_v63(
    input logic [WB_DATA_BITS - 1:0] data
  );
    logic [127:0] observed;
    begin
      observed = 128'h2fa851a82ba851a827a8c1a823a8c1a8;
      lower16_matches_v63 = data[127:0] == observed;
    end
  endfunction

  task automatic blend_by_lane_mask(
    output logic [WB_DATA_BITS - 1:0] out_data,
    input logic [WB_DATA_BITS - 1:0] fresh_data,
    input logic [WB_DATA_BITS - 1:0] stale_data,
    input logic [LANES - 1:0] fresh_lane_mask
  );
    begin
      out_data = stale_data;
      for (int burst = 0; burst < BURSTS; burst = burst + 1) begin
        for (int lane = 0; lane < LANES; lane = lane + 1) begin
          if (fresh_lane_mask[lane])
            set_byte(out_data, byte_index(burst, lane), get_byte(fresh_data, byte_index(burst, lane)));
        end
      end
    end
  endtask

  task automatic blend_by_byte_mask(
    output logic [WB_DATA_BITS - 1:0] out_data,
    input logic [WB_DATA_BITS - 1:0] fresh_data,
    input logic [WB_DATA_BITS - 1:0] stale_data,
    input logic [15:0] fresh_lower16_mask
  );
    begin
      out_data = stale_data;
      for (int index = 0; index < 16; index = index + 1) begin
        if (fresh_lower16_mask[index])
          set_byte(out_data, index, get_byte(fresh_data, index));
      end
    end
  endtask

  task automatic apply_data_start_index_one_lane(
    output logic [WB_DATA_BITS - 1:0] out_data,
    input logic [WB_DATA_BITS - 1:0] fresh_data,
    input logic [WB_DATA_BITS - 1:0] stale_data,
    input int lane,
    input int byte_shift
  );
    begin
      out_data = fresh_data;
      for (int burst = 0; burst < BURSTS; burst = burst + 1) begin
        if (burst < byte_shift)
          set_byte(out_data, byte_index(burst, lane), get_byte(stale_data, byte_index(burst, lane)));
        else
          set_byte(
            out_data,
            byte_index(burst, lane),
            get_byte(fresh_data, byte_index(burst - byte_shift, lane))
          );
      end
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;
    dense_signature_solutions = 0;
    v63_signature_solutions = 0;

    fill_ramp(8'h00, expected_dense);
    fill_ramp(8'h20, expected_v63);

    residue_dense = '0;
    // This residue pattern is the stable non-ramp byte class seen around the
    // dense gate failure.  The sim checks whether a lane/byte capture mask can
    // explain the board signature without blaming host packing.
    for (int index = 0; index < BEAT_BYTES; index = index + 1)
      set_byte(residue_dense, index, 8'h00);
    for (int index = 0; index < 16; index = index + 1) begin
      if ((index == 1) || (index == 5))
        set_byte(residue_dense, index, 8'hc1);
      if ((index == 9) || (index == 13))
        set_byte(residue_dense, index, 8'h51);
    end

    residue_v63 = '0;
    for (int index = 0; index < 16; index = index + 1) begin
      set_byte(residue_v63, index, 8'ha8);
      if ((index == 1) || (index == 5))
        set_byte(residue_v63, index, 8'hc1);
      if ((index == 9) || (index == 13))
        set_byte(residue_v63, index, 8'h51);
    end

    check_cond(!lower16_matches_dense(expected_dense), "clean dense ramp must not equal failed dense signature");
    check_cond(!lower16_matches_v63(expected_v63), "clean v63 ramp must not equal failed v63 signature");

    for (int mask = 0; mask < (1 << LANES); mask = mask + 1) begin
      blend_by_lane_mask(candidate, expected_dense, residue_dense, mask[LANES - 1:0]);
      if (lower16_matches_dense(candidate))
        dense_signature_solutions = dense_signature_solutions + 1;

      blend_by_lane_mask(candidate, expected_v63, residue_v63, mask[LANES - 1:0]);
      if (lower16_matches_v63(candidate))
        v63_signature_solutions = v63_signature_solutions + 1;
    end

    for (int mask = 0; mask < (1 << 16); mask = mask + 1) begin
      blend_by_byte_mask(candidate, expected_dense, residue_dense, mask[15:0]);
      if (lower16_matches_dense(candidate))
        dense_signature_solutions = dense_signature_solutions + 1;

      blend_by_byte_mask(candidate, expected_v63, residue_v63, mask[15:0]);
      if (lower16_matches_v63(candidate))
        v63_signature_solutions = v63_signature_solutions + 1;
    end

    for (int lane = 0; lane < LANES; lane = lane + 1) begin
      apply_data_start_index_one_lane(candidate, expected_dense, residue_dense, lane, 1);
      check_cond(
        !lower16_matches_dense(candidate),
        "single-lane data_start_index shift alone must not explain dense signature"
      );
      apply_data_start_index_one_lane(candidate, expected_v63, residue_v63, lane, 1);
      check_cond(
        !lower16_matches_v63(candidate),
        "single-lane data_start_index shift alone must not explain v63 signature"
      );
    end

    check_cond(
      dense_signature_solutions > 0,
      "dense signature must be explainable by stale byte/lane capture masks"
    );
    check_cond(
      v63_signature_solutions > 0,
      "v63 signature must be explainable by stale byte/lane capture masks"
    );

    if (errors == 0) begin
      $display(
        "PASS: task6 UberDDR3 signature hypothesis sim checks %0d dense_solutions %0d v63_solutions %0d",
        checks, dense_signature_solutions, v63_signature_solutions
      );
      $finish;
    end else begin
      $display(
        "FAIL: task6 UberDDR3 signature hypothesis sim errors %0d checks %0d dense_solutions %0d v63_solutions %0d",
        errors, checks, dense_signature_solutions, v63_signature_solutions
      );
      $fatal(1);
    end
  end
endmodule

`default_nettype wire
