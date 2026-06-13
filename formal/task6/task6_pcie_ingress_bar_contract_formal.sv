`timescale 1ns/1ps
`default_nettype none

module task6_pcie_ingress_bar_contract_formal;
  (* gclk *) reg clk;
  reg rst_n = 1'b0;

  reg [31:0] s_axi_awaddr;
  reg        s_axi_awvalid;
  reg [31:0] s_axi_wdata;
  reg [3:0]  s_axi_wstrb;
  reg        s_axi_wvalid;
  reg        s_axi_bready;
  reg [31:0] s_axi_araddr;
  reg        s_axi_arvalid;
  reg        s_axi_rready;

  wire s_axi_awready;
  wire s_axi_wready;
  wire [1:0] s_axi_bresp;
  wire s_axi_bvalid;
  wire s_axi_arready;
  wire [31:0] s_axi_rdata;
  wire s_axi_rvalid;
  wire [1:0] s_axi_rresp;

  wire [191:0] command_payload;
  wire command_event;

  (* anyconst *) reg         calib_complete;
  (* anyconst *) reg         boot_done;
  (* anyconst *) reg [31:0]  ddr_debug1;
  (* anyconst *) reg [31:0]  debug_rowstream_heartbeat_count;
  (* anyconst *) reg [31:0]  debug_rowstream_status;
  (* anyconst *) reg [31:0]  debug_rowstream_seen;
  (* anyconst *) reg         loader_done;
  (* anyconst *) reg         loader_error;
  (* anyconst *) reg         loader_last_accepted;
  (* anyconst *) reg         loader_last_magic_ok;
  (* anyconst *) reg [7:0]   loader_last_opcode;
  (* anyconst *) reg [1:0]   loader_last_chunk;
  (* anyconst *) reg [31:0]  loader_command_payload_addr;
  (* anyconst *) reg [31:0]  loader_wait_cycles;
  (* anyconst *) reg [511:0] loader_read_data;
  wire status_clear_pulse;

  wire [511:0] top1_hidden_vector;
  wire top1_start_pulse;
  wire top1_status_clear_pulse;
  (* anyconst *) reg         top1_busy;
  (* anyconst *) reg         top1_done;
  (* anyconst *) reg         top1_error;
  (* anyconst *) reg [31:0]  top1_token;
  (* anyconst *) reg [31:0]  top1_score_q024;
  (* anyconst *) reg [31:0]  top1_rows_scanned;
  (* anyconst *) reg [31:0]  top1_cycle_count;
  (* anyconst *) reg [31:0]  top1_debug_status;
  (* anyconst *) reg [31:0]  top1_debug_reader_addr;
  (* anyconst *) reg [31:0]  top1_debug_wb_ack_count;
  (* anyconst *) reg [31:0]  top1_debug_wb_err_count;
  (* anyconst *) reg [31:0]  top1_debug_packet_wb_write_ack_count;
  (* anyconst *) reg [31:0]  top1_debug_packet_wb_read_ack_count;

  (* anyconst *) reg         mlp_selftest_present;
  (* anyconst *) reg [31:0]  mlp_selftest_status;
  (* anyconst *) reg [31:0]  mlp_selftest_cycle_count;
  (* anyconst *) reg [31:0]  mlp_selftest_fail_detail;
  (* anyconst *) reg [31:0]  mlp_selftest_fail_values;
  (* anyconst *) reg [31:0]  mlp_selftest_first_add_sample;
  (* anyconst *) reg [31:0]  mlp_selftest_first_requant_sample;
  (* anyconst *) reg [31:0]  mlp_selftest_requant_debug0;
  (* anyconst *) reg [31:0]  mlp_selftest_requant_debug1;
  wire [31:0] mlp_selftest_debug_select;

  wire [511:0] mlp_accel_activation_vector;
  wire [511:0] mlp_accel_residual_vector;
  wire mlp_accel_start_pulse;
  wire mlp_accel_clear_pulse;
  (* anyconst *) reg [31:0]  mlp_accel_status;
  (* anyconst *) reg [31:0]  mlp_accel_cycle_count;
  (* anyconst *) reg [31:0]  mlp_accel_output_checksum;
  (* anyconst *) reg [31:0]  mlp_accel_output_sample0;
  (* anyconst *) reg [31:0]  mlp_accel_output_sample1;
  (* anyconst *) reg [511:0] mlp_accel_output_vector;

  wire [511:0] m2_full_block_input_vector;
  wire [511:0] m2_full_block_residual_vector;
  wire m2_full_block_start_pulse;
  wire m2_full_block_clear_pulse;
  (* anyconst *) reg [31:0]  m2_full_block_status;
  (* anyconst *) reg [31:0]  m2_full_block_cycle_count;
  (* anyconst *) reg [31:0]  m2_full_block_output_checksum;
  (* anyconst *) reg [31:0]  m2_full_block_output_sample0;
  (* anyconst *) reg [31:0]  m2_full_block_output_sample1;
  (* anyconst *) reg [31:0]  m2_full_block_output_count;
  (* anyconst *) reg [31:0]  m2_full_block_debug;
  (* anyconst *) reg [31:0]  m2_full_block_debug1;
  (* anyconst *) reg [31:0]  m2_full_block_debug2;
  (* anyconst *) reg [31:0]  m2_full_block_provenance;
  (* anyconst *) reg [511:0] m2_full_block_output_vector;

  task6_pcie_axil_rowstream_loader_ingress dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .s_axi_rresp(s_axi_rresp),
    .command_payload_o(command_payload),
    .command_event_o(command_event),
    .calib_complete_i(calib_complete),
    .boot_done_i(boot_done),
    .ddr_debug1_i(ddr_debug1),
    .debug_rowstream_heartbeat_count_i(debug_rowstream_heartbeat_count),
    .debug_rowstream_status_i(debug_rowstream_status),
    .debug_rowstream_seen_i(debug_rowstream_seen),
    .loader_done_i(loader_done),
    .loader_error_i(loader_error),
    .loader_last_accepted_i(loader_last_accepted),
    .loader_last_magic_ok_i(loader_last_magic_ok),
    .loader_last_opcode_i(loader_last_opcode),
    .loader_last_chunk_i(loader_last_chunk),
    .loader_command_payload_addr_i(loader_command_payload_addr),
    .loader_wait_cycles_i(loader_wait_cycles),
    .loader_read_data_i(loader_read_data),
    .status_clear_pulse_o(status_clear_pulse),
    .top1_hidden_vector_o(top1_hidden_vector),
    .top1_start_pulse_o(top1_start_pulse),
    .top1_status_clear_pulse_o(top1_status_clear_pulse),
    .top1_busy_i(top1_busy),
    .top1_done_i(top1_done),
    .top1_error_i(top1_error),
    .top1_token_i(top1_token),
    .top1_score_q024_i(top1_score_q024),
    .top1_rows_scanned_i(top1_rows_scanned),
    .top1_cycle_count_i(top1_cycle_count),
    .top1_debug_status_i(top1_debug_status),
    .top1_debug_reader_addr_i(top1_debug_reader_addr),
    .top1_debug_wb_ack_count_i(top1_debug_wb_ack_count),
    .top1_debug_wb_err_count_i(top1_debug_wb_err_count),
    .top1_debug_packet_wb_write_ack_count_i(top1_debug_packet_wb_write_ack_count),
    .top1_debug_packet_wb_read_ack_count_i(top1_debug_packet_wb_read_ack_count),
    .mlp_selftest_present_i(mlp_selftest_present),
    .mlp_selftest_status_i(mlp_selftest_status),
    .mlp_selftest_cycle_count_i(mlp_selftest_cycle_count),
    .mlp_selftest_fail_detail_i(mlp_selftest_fail_detail),
    .mlp_selftest_fail_values_i(mlp_selftest_fail_values),
    .mlp_selftest_first_add_sample_i(mlp_selftest_first_add_sample),
    .mlp_selftest_first_requant_sample_i(mlp_selftest_first_requant_sample),
    .mlp_selftest_requant_debug0_i(mlp_selftest_requant_debug0),
    .mlp_selftest_requant_debug1_i(mlp_selftest_requant_debug1),
    .mlp_selftest_debug_select_o(mlp_selftest_debug_select),
    .mlp_accel_activation_vector_o(mlp_accel_activation_vector),
    .mlp_accel_residual_vector_o(mlp_accel_residual_vector),
    .mlp_accel_start_pulse_o(mlp_accel_start_pulse),
    .mlp_accel_clear_pulse_o(mlp_accel_clear_pulse),
    .mlp_accel_status_i(mlp_accel_status),
    .mlp_accel_cycle_count_i(mlp_accel_cycle_count),
    .mlp_accel_output_checksum_i(mlp_accel_output_checksum),
    .mlp_accel_output_sample0_i(mlp_accel_output_sample0),
    .mlp_accel_output_sample1_i(mlp_accel_output_sample1),
    .mlp_accel_output_vector_i(mlp_accel_output_vector),
    .m2_full_block_input_vector_o(m2_full_block_input_vector),
    .m2_full_block_residual_vector_o(m2_full_block_residual_vector),
    .m2_full_block_start_pulse_o(m2_full_block_start_pulse),
    .m2_full_block_clear_pulse_o(m2_full_block_clear_pulse),
    .m2_full_block_status_i(m2_full_block_status),
    .m2_full_block_cycle_count_i(m2_full_block_cycle_count),
    .m2_full_block_output_checksum_i(m2_full_block_output_checksum),
    .m2_full_block_output_sample0_i(m2_full_block_output_sample0),
    .m2_full_block_output_sample1_i(m2_full_block_output_sample1),
    .m2_full_block_output_count_i(m2_full_block_output_count),
    .m2_full_block_debug_i(m2_full_block_debug),
    .m2_full_block_debug1_i(m2_full_block_debug1),
    .m2_full_block_debug2_i(m2_full_block_debug2),
    .m2_full_block_provenance_i(m2_full_block_provenance),
    .m2_full_block_output_vector_i(m2_full_block_output_vector)
  );

  reg past_valid = 1'b0;
  reg [3:0] cycle_count = 4'd0;
  (* anyconst *) reg [9:0] target_word;
  wire [31:0] expected_rdata;
  reg read_accepted_q = 1'b0;
  reg response_pending_q = 1'b0;
  reg [31:0] accepted_expected_q = 32'd0;
  wire target_is_checked;
  wire read_fire;

  initial begin
    assume(!rst_n);
    assume(!past_valid);
    assume(!read_accepted_q);
    assume(!response_pending_q);
  end

  always @(posedge clk) begin
    past_valid <= 1'b1;
    cycle_count <= cycle_count + 4'd1;
    rst_n <= past_valid;
  end

  always @(*) begin
    s_axi_awaddr = 32'd0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata = 32'd0;
    s_axi_wstrb = 4'd0;
    s_axi_wvalid = 1'b0;
    s_axi_bready = 1'b1;
    s_axi_araddr = {20'd0, target_word, 2'b00};
    s_axi_arvalid = rst_n && !read_accepted_q;
    s_axi_rready = 1'b1;
  end

  assign read_fire = s_axi_arvalid && s_axi_arready;

  assign target_is_checked =
    target_word == 10'h0c0 ||
    target_word == 10'h0c1 ||
    target_word == 10'h0cc ||
    target_word == 10'h0ce ||
    target_word == 10'h0cf ||
    target_word == 10'h0f0 ||
    target_word == 10'h0f1 ||
    target_word == 10'h0f2 ||
    target_word == 10'h0f4 ||
    target_word == 10'h0f5 ||
    (target_word >= 10'h100 && target_word <= 10'h10f) ||
    target_word == 10'h140 ||
    target_word == 10'h141 ||
    target_word == 10'h142 ||
    target_word == 10'h143 ||
    target_word == 10'h145 ||
    target_word == 10'h146 ||
    target_word == 10'h147 ||
    (target_word >= 10'h150 && target_word <= 10'h15f) ||
    (target_word >= 10'h160 && target_word <= 10'h16f) ||
    target_word == 10'h170 ||
    target_word == 10'h171 ||
    target_word == 10'h172 ||
    target_word == 10'h173 ||
    target_word == 10'h174 ||
    target_word == 10'h175 ||
    (target_word >= 10'h180 && target_word <= 10'h18f);

  function automatic [31:0] expected_bar_word(input [9:0] word_index);
    begin
      expected_bar_word = 32'd0;
      case (word_index)
        10'h0c0: expected_bar_word = 32'h54364d4c;
        10'h0c1: expected_bar_word = 32'd1;
        10'h0cc: expected_bar_word = mlp_accel_status;
        10'h0ce: expected_bar_word = mlp_accel_cycle_count;
        10'h0cf: expected_bar_word = mlp_accel_output_checksum;
        10'h0f0: expected_bar_word = mlp_accel_output_sample0;
        10'h0f1: expected_bar_word = mlp_accel_output_sample1;
        10'h0f2: expected_bar_word = mlp_selftest_debug_select;
        10'h0f4: expected_bar_word = mlp_selftest_requant_debug0;
        10'h0f5: expected_bar_word = mlp_selftest_requant_debug1;
        10'h140: expected_bar_word = 32'h54364d32;
        10'h141: expected_bar_word = 32'd1;
        10'h142: expected_bar_word = 32'd1;
        10'h143: expected_bar_word = m2_full_block_status;
        10'h145: expected_bar_word = m2_full_block_cycle_count;
        10'h146: expected_bar_word = m2_full_block_output_checksum;
        10'h147: expected_bar_word = m2_full_block_output_count;
        10'h170: expected_bar_word = m2_full_block_output_sample0;
        10'h171: expected_bar_word = m2_full_block_output_sample1;
        10'h172: expected_bar_word = m2_full_block_debug;
        10'h173: expected_bar_word = m2_full_block_debug1;
        10'h174: expected_bar_word = m2_full_block_debug2;
        10'h175: expected_bar_word = m2_full_block_provenance;
        default: begin
          if (word_index >= 10'h100 && word_index <= 10'h10f) begin
            expected_bar_word = mlp_accel_output_vector[((word_index - 10'h100) * 32) +: 32];
          end else if (word_index >= 10'h150 && word_index <= 10'h15f) begin
            expected_bar_word = m2_full_block_input_vector[((word_index - 10'h150) * 32) +: 32];
          end else if (word_index >= 10'h160 && word_index <= 10'h16f) begin
            expected_bar_word = m2_full_block_residual_vector[((word_index - 10'h160) * 32) +: 32];
          end else if (word_index >= 10'h180 && word_index <= 10'h18f) begin
            expected_bar_word = m2_full_block_output_vector[((word_index - 10'h180) * 32) +: 32];
          end
        end
      endcase
    end
  endfunction

  assign expected_rdata = expected_bar_word(target_word);

  always @(*) begin
    assume(target_is_checked);
    if (response_pending_q && s_axi_rvalid) assert(s_axi_rresp == 2'b00);
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      read_accepted_q <= 1'b0;
      response_pending_q <= 1'b0;
      accepted_expected_q <= 32'd0;
    end else begin
      if (!read_accepted_q && read_fire) begin
        read_accepted_q <= 1'b1;
        response_pending_q <= 1'b1;
        accepted_expected_q <= expected_rdata;
      end

      if (response_pending_q && s_axi_rvalid) begin
        assert(s_axi_rdata == accepted_expected_q);
        response_pending_q <= 1'b0;
      end
    end
  end
endmodule

`default_nettype wire
