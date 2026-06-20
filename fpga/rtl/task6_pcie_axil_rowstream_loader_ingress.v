`timescale 1ns/1ps
// SPDX-License-Identifier: MIT
// Task 6 PCIe BAR ingress for the DDR3 rowstream loader command contract.

`default_nettype none

module task6_pcie_axil_rowstream_loader_ingress #(
    parameter [31:0] TASK6_PCIE_MAGIC = 32'h54365043,
    parameter [31:0] TASK6_PCIE_VERSION = 32'd3,
    parameter [31:0] LOADER_COMMAND_MAGIC = 32'h33445244,
    parameter integer COMMAND_WIDTH = 192,
    parameter integer COMMAND_DATA_LSB = 64
) (
    input wire clk,
    input wire rst_n,

    input wire [31:0] s_axi_awaddr,
    input wire        s_axi_awvalid,
    output reg        s_axi_awready,

    input wire [31:0] s_axi_wdata,
    input wire [3:0]  s_axi_wstrb,
    input wire        s_axi_wvalid,
    output reg        s_axi_wready,

    output reg [1:0]  s_axi_bresp,
    output reg        s_axi_bvalid,
    input wire        s_axi_bready,

    input wire [31:0] s_axi_araddr,
    input wire        s_axi_arvalid,
    output reg        s_axi_arready,

    output reg [31:0] s_axi_rdata,
    output reg        s_axi_rvalid,
    input wire        s_axi_rready,
    output reg [1:0]  s_axi_rresp,

    output reg [COMMAND_WIDTH - 1:0] command_payload_o,
    output reg         command_event_o,

    input wire         calib_complete_i,
    input wire         boot_done_i,
    input wire [31:0]  ddr_debug1_i,
    input wire [31:0]  debug_rowstream_heartbeat_count_i,
    input wire [31:0]  debug_rowstream_status_i,
    input wire [31:0]  debug_rowstream_seen_i,
    input wire         loader_done_i,
    input wire         loader_error_i,
    input wire         loader_last_accepted_i,
    input wire         loader_last_magic_ok_i,
    input wire [7:0]   loader_last_opcode_i,
    input wire [1:0]   loader_last_chunk_i,
    input wire [31:0]  loader_command_payload_addr_i,
    input wire [31:0]  loader_wait_cycles_i,
    input wire [511:0] loader_read_data_i,
    output reg         status_clear_pulse_o,

    output reg [511:0] top1_hidden_vector_o,
    output reg         top1_start_pulse_o,
    output reg         top1_status_clear_pulse_o,
    input wire         top1_busy_i,
    input wire         top1_done_i,
    input wire         top1_error_i,
    input wire [31:0]  top1_token_i,
    input wire [31:0]  top1_score_q024_i,
    input wire [31:0]  top1_rows_scanned_i,
    input wire [31:0]  top1_cycle_count_i,
    input wire [31:0]  top1_debug_status_i,
    input wire [31:0]  top1_debug_reader_addr_i,
    input wire [31:0]  top1_debug_wb_ack_count_i,
    input wire [31:0]  top1_debug_wb_err_count_i,
    input wire [31:0]  top1_debug_packet_wb_write_ack_count_i,
    input wire [31:0]  top1_debug_packet_wb_read_ack_count_i,

    input wire         mlp_selftest_present_i,
    input wire [31:0]  mlp_selftest_status_i,
    input wire [31:0]  mlp_selftest_cycle_count_i,
    input wire [31:0]  mlp_selftest_fail_detail_i,
    input wire [31:0]  mlp_selftest_fail_values_i,
    input wire [31:0]  mlp_selftest_first_add_sample_i,
    input wire [31:0]  mlp_selftest_first_requant_sample_i,
    input wire [31:0]  mlp_selftest_requant_debug0_i,
    input wire [31:0]  mlp_selftest_requant_debug1_i,
    output reg [31:0]  mlp_selftest_debug_select_o,

    output reg [511:0] mlp_accel_activation_vector_o,
    output reg [511:0] mlp_accel_residual_vector_o,
    output reg         mlp_accel_start_pulse_o,
    output reg         mlp_accel_clear_pulse_o,
    input wire [31:0]  mlp_accel_status_i,
    input wire [31:0]  mlp_accel_cycle_count_i,
    input wire [31:0]  mlp_accel_output_checksum_i,
    input wire [31:0]  mlp_accel_output_sample0_i,
    input wire [31:0]  mlp_accel_output_sample1_i,
    input wire [511:0] mlp_accel_output_vector_i,

    output reg [511:0] m2_full_block_input_vector_o,
    output reg [511:0] m2_full_block_residual_vector_o,
    output reg         m2_full_block_start_pulse_o,
    output reg         m2_full_block_clear_pulse_o,
    input wire [31:0]  m2_full_block_status_i,
    input wire [31:0]  m2_full_block_cycle_count_i,
    input wire [31:0]  m2_full_block_output_checksum_i,
    input wire [31:0]  m2_full_block_output_sample0_i,
    input wire [31:0]  m2_full_block_output_sample1_i,
    input wire [31:0]  m2_full_block_output_count_i,
    input wire [31:0]  m2_full_block_debug_i,
    input wire [31:0]  m2_full_block_debug1_i,
    input wire [31:0]  m2_full_block_debug2_i,
    input wire [31:0]  m2_full_block_debug3_i,
    input wire [31:0]  m2_full_block_provenance_i,
    input wire [127:0] m2_full_block_output_hash_i,
    input wire [511:0] m2_full_block_output_vector_i
);
    localparam [1:0] EVENT_IDLE = 2'd0;
    localparam [1:0] EVENT_ISSUE = 2'd1;
    localparam [1:0] EVENT_GAP = 2'd2;
    localparam [1:0] EVENT_REARM = 2'd3;

    reg [31:0] awaddr_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        awaddr_valid_q;
    reg        wdata_valid_q;

    reg [31:0] command_magic_q;
    reg [7:0]  command_opcode_q;
    reg [1:0]  command_chunk_q;
    reg [31:0] command_addr_q;
    reg [31:0] command_data_q [0:3];
    reg [31:0] accepted_count_q;
    reg        doorbell_error_q;
    reg        loader_done_seen_q;
    reg        loader_error_seen_q;
    reg        loader_accepted_seen_q;
    reg        loader_magic_ok_seen_q;
    reg [1:0]  event_state_q;
    reg        top1_done_seen_q;
    reg        top1_error_seen_q;
    reg        top1_clear_pending_q;
    reg [31:0] top1_start_count_q;
    reg [31:0] mlp_accel_start_count_q;
    reg [31:0] m2_full_block_start_count_q;
    reg [511:0] m2_full_block_input_raw_q;
    reg [511:0] m2_full_block_input_raw_next;
    reg        last_write_valid_q;
    reg [9:0]  last_write_word_index_q;
    reg [31:0] last_wdata_q;
    reg [3:0]  last_wstrb_q;
    reg        read_pending_q;
    reg        read_response_pending_q;
    reg [9:0]  read_word_index_q;
    reg [3:0]  read_word_offset_q;
    reg [511:0] read_window_q;
    reg [511:0] read_window_data;

    integer i;

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobe;
        begin
            apply_wstrb = old_value;
            if (strobe[0]) apply_wstrb[7:0] = new_value[7:0];
            if (strobe[1]) apply_wstrb[15:8] = new_value[15:8];
            if (strobe[2]) apply_wstrb[23:16] = new_value[23:16];
            if (strobe[3]) apply_wstrb[31:24] = new_value[31:24];
        end
    endfunction

    function [511:0] pcie7x_ror64_to_host_vector;
        input [511:0] raw_value;
        integer lane;
        reg [63:0] raw_pair;
        begin
            pcie7x_ror64_to_host_vector = 512'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                raw_pair = raw_value[lane * 64 +: 64];
                pcie7x_ror64_to_host_vector[lane * 64 +: 64] = {raw_pair[62:0], raw_pair[63]};
            end
        end
    endfunction

    function [COMMAND_WIDTH - 1:0] pack_command_payload;
        input [31:0] magic;
        input [7:0] opcode;
        input [1:0] chunk;
        input [31:0] addr;
        input [31:0] data0;
        input [31:0] data1;
        input [31:0] data2;
        input [31:0] data3;
        begin
            pack_command_payload = {COMMAND_WIDTH{1'b0}};
            pack_command_payload[0 +: 32] = magic;
            pack_command_payload[32 +: 8] = opcode;
            pack_command_payload[40 +: 2] = chunk;
            pack_command_payload[48 +: 32] = addr;
            pack_command_payload[COMMAND_DATA_LSB +: 128] = {data3, data2, data1, data0};
        end
    endfunction

    wire write_ready = awaddr_valid_q && wdata_valid_q && !s_axi_bvalid;
    wire aw_fire = s_axi_awready && s_axi_awvalid;
    wire w_fire = s_axi_wready && s_axi_wvalid;
    wire [9:0] write_word_index = awaddr_q[11:2];
    wire [9:0] read_word_index = s_axi_araddr[11:2];
    wire duplicate_control_write = last_write_valid_q &&
        last_write_word_index_q == write_word_index &&
        last_wdata_q == wdata_q &&
        last_wstrb_q == wstrb_q;
    wire event_active = event_state_q != EVENT_IDLE;

    always @* begin
        read_window_data = 512'd0;
        case (read_word_index_q[9:4])
            6'h00: begin
                read_window_data[0 +: 32] = TASK6_PCIE_MAGIC;
                read_window_data[32 +: 32] = TASK6_PCIE_VERSION;
                read_window_data[64 +: 32] = {25'd0, boot_done_i, calib_complete_i, doorbell_error_q, loader_error_seen_q, loader_done_seen_q, event_active, rst_n};
                read_window_data[96 +: 32] = accepted_count_q;
                read_window_data[128 +: 32] = command_magic_q;
                read_window_data[160 +: 32] = {22'd0, command_chunk_q, command_opcode_q};
                read_window_data[192 +: 32] = command_addr_q;
                read_window_data[256 +: 32] = command_data_q[0];
                read_window_data[288 +: 32] = command_data_q[1];
                read_window_data[320 +: 32] = command_data_q[2];
                read_window_data[352 +: 32] = command_data_q[3];
                read_window_data[416 +: 32] = {26'd0, loader_accepted_seen_q, loader_magic_ok_seen_q, loader_error_seen_q, loader_done_seen_q, boot_done_i, calib_complete_i};
                read_window_data[448 +: 32] = {22'd0, loader_last_chunk_i, loader_last_opcode_i};
                read_window_data[480 +: 32] = loader_command_payload_addr_i;
            end
            6'h01: begin
                read_window_data[0 +: 32] = loader_wait_cycles_i;
                read_window_data[32 +: 32] = loader_read_data_i[31:0];
                read_window_data[64 +: 32] = loader_read_data_i[63:32];
                read_window_data[96 +: 32] = loader_read_data_i[95:64];
                read_window_data[128 +: 32] = loader_read_data_i[127:96];
                read_window_data[160 +: 32] = ddr_debug1_i;
                read_window_data[256 +: 32] = {28'd0, top1_error_seen_q, top1_done_seen_q, top1_busy_i, rst_n};
                read_window_data[288 +: 32] = top1_start_count_q;
                read_window_data[320 +: 32] = top1_token_i;
                read_window_data[352 +: 32] = top1_score_q024_i;
                read_window_data[384 +: 32] = top1_rows_scanned_i;
                read_window_data[416 +: 32] = top1_cycle_count_i;
            end
            6'h02: begin
                read_window_data = top1_hidden_vector_o;
            end
            6'h08: begin
                read_window_data[0 +: 32] = 32'h54364442;
                read_window_data[32 +: 32] = 32'd1;
                read_window_data[64 +: 32] = debug_rowstream_heartbeat_count_i;
                read_window_data[96 +: 32] = debug_rowstream_status_i;
                read_window_data[128 +: 32] = debug_rowstream_seen_i;
                read_window_data[160 +: 32] = ddr_debug1_i;
                read_window_data[192 +: 32] = loader_wait_cycles_i;
                read_window_data[224 +: 32] = top1_debug_status_i;
                read_window_data[256 +: 32] = top1_debug_reader_addr_i;
                read_window_data[288 +: 32] = top1_debug_wb_ack_count_i;
                read_window_data[320 +: 32] = top1_debug_wb_err_count_i;
                read_window_data[352 +: 32] = top1_debug_packet_wb_write_ack_count_i;
                read_window_data[384 +: 32] = top1_debug_packet_wb_read_ack_count_i;
            end
            6'h0c: begin
                read_window_data[0 +: 32] = 32'h54364d4c;
                read_window_data[32 +: 32] = 32'd1;
                read_window_data[64 +: 32] = {31'd0, mlp_selftest_present_i};
                read_window_data[96 +: 32] = mlp_selftest_status_i;
                read_window_data[128 +: 32] = mlp_selftest_cycle_count_i;
                read_window_data[160 +: 32] = mlp_selftest_fail_detail_i;
                read_window_data[192 +: 32] = mlp_selftest_fail_values_i;
                read_window_data[224 +: 32] = mlp_selftest_first_add_sample_i;
                read_window_data[256 +: 32] = mlp_selftest_first_requant_sample_i;
                read_window_data[288 +: 32] = 32'h54364d41;
                read_window_data[320 +: 32] = 32'd1;
                read_window_data[352 +: 32] = {31'd0, mlp_selftest_present_i};
                read_window_data[384 +: 32] = mlp_accel_status_i;
                read_window_data[416 +: 32] = mlp_accel_start_count_q;
                read_window_data[448 +: 32] = mlp_accel_cycle_count_i;
                read_window_data[480 +: 32] = mlp_accel_output_checksum_i;
            end
            6'h0d: begin
                read_window_data = mlp_accel_activation_vector_o;
            end
            6'h0e: begin
                read_window_data = mlp_accel_residual_vector_o;
            end
            6'h0f: begin
                read_window_data[0 +: 32] = mlp_accel_output_sample0_i;
                read_window_data[32 +: 32] = mlp_accel_output_sample1_i;
                read_window_data[64 +: 32] = mlp_selftest_debug_select_o;
                read_window_data[128 +: 32] = mlp_selftest_requant_debug0_i;
                read_window_data[160 +: 32] = mlp_selftest_requant_debug1_i;
            end
            6'h10: begin
                read_window_data = mlp_accel_output_vector_i;
            end
            6'h14: begin
                read_window_data[0 +: 32] = 32'h54364d32;
                read_window_data[32 +: 32] = 32'd1;
                read_window_data[64 +: 32] = 32'd1;
                read_window_data[96 +: 32] = m2_full_block_status_i;
                read_window_data[128 +: 32] = m2_full_block_start_count_q;
                read_window_data[160 +: 32] = m2_full_block_cycle_count_i;
                read_window_data[192 +: 32] = m2_full_block_output_checksum_i;
                read_window_data[224 +: 32] = m2_full_block_output_count_i;
            end
            6'h15: begin
                read_window_data = m2_full_block_input_vector_o;
            end
            6'h16: begin
                read_window_data = m2_full_block_residual_vector_o;
            end
            6'h17: begin
                read_window_data[0 +: 32] = m2_full_block_output_sample0_i;
                read_window_data[32 +: 32] = m2_full_block_output_sample1_i;
                read_window_data[64 +: 32] = m2_full_block_debug_i;
                read_window_data[96 +: 32] = m2_full_block_debug1_i;
                read_window_data[128 +: 32] = m2_full_block_debug2_i;
                read_window_data[160 +: 32] = m2_full_block_provenance_i;
                read_window_data[192 +: 32] = m2_full_block_debug3_i;
                read_window_data[224 +: 32] = m2_full_block_output_vector_i[0 +: 32];
                read_window_data[256 +: 32] = m2_full_block_output_vector_i[32 +: 32];
                read_window_data[288 +: 32] = m2_full_block_output_vector_i[64 +: 32];
                read_window_data[320 +: 32] = m2_full_block_output_vector_i[96 +: 32];
                read_window_data[352 +: 32] = m2_full_block_output_vector_i[128 +: 32];
                read_window_data[384 +: 32] = m2_full_block_output_vector_i[160 +: 32];
                read_window_data[416 +: 32] = m2_full_block_output_vector_i[192 +: 32];
                read_window_data[448 +: 32] = m2_full_block_output_vector_i[224 +: 32];
            end
            6'h18: begin
                read_window_data = m2_full_block_output_vector_i;
            end
            6'h19: begin
                read_window_data[0 +: 32] = m2_full_block_output_hash_i[0 +: 32];
                read_window_data[32 +: 32] = m2_full_block_output_hash_i[32 +: 32];
                read_window_data[64 +: 32] = m2_full_block_output_hash_i[64 +: 32];
                read_window_data[96 +: 32] = m2_full_block_output_hash_i[96 +: 32];
            end
            default: read_window_data = 512'd0;
        endcase
    end

    initial begin
        s_axi_rdata = 32'd0;
        command_payload_o = {COMMAND_WIDTH{1'b0}};
        command_event_o = 1'b0;
        status_clear_pulse_o = 1'b0;
        top1_hidden_vector_o = 512'd0;
        top1_start_pulse_o = 1'b0;
        top1_status_clear_pulse_o = 1'b0;
        mlp_accel_activation_vector_o = 512'd0;
        mlp_accel_residual_vector_o = 512'd0;
        mlp_accel_start_pulse_o = 1'b0;
        mlp_accel_clear_pulse_o = 1'b0;
        mlp_accel_start_count_q = 32'd0;
        m2_full_block_input_vector_o = 512'd0;
        m2_full_block_input_raw_q = 512'd0;
        m2_full_block_input_raw_next = 512'd0;
        m2_full_block_residual_vector_o = 512'd0;
        m2_full_block_start_pulse_o = 1'b0;
        m2_full_block_clear_pulse_o = 1'b0;
        m2_full_block_start_count_q = 32'd0;
        command_magic_q = LOADER_COMMAND_MAGIC;
        command_opcode_q = 8'd0;
        command_chunk_q = 2'd0;
        command_addr_q = 32'd0;
        accepted_count_q = 32'd0;
        doorbell_error_q = 1'b0;
        loader_done_seen_q = 1'b0;
        loader_error_seen_q = 1'b0;
        loader_accepted_seen_q = 1'b0;
        loader_magic_ok_seen_q = 1'b0;
        event_state_q = EVENT_IDLE;
        top1_done_seen_q = 1'b0;
        top1_error_seen_q = 1'b0;
        top1_start_count_q = 32'd0;
        awaddr_valid_q = 1'b0;
        wdata_valid_q = 1'b0;
        last_write_valid_q = 1'b0;
        last_write_word_index_q = 10'd0;
        last_wdata_q = 32'd0;
        last_wstrb_q = 4'd0;
        read_pending_q = 1'b0;
        read_response_pending_q = 1'b0;
        read_word_index_q = 10'd0;
        read_word_offset_q = 4'd0;
        read_window_q = 512'd0;
        read_window_data = 512'd0;
        for (i = 0; i < 4; i = i + 1)
            command_data_q[i] = 32'd0;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            awaddr_valid_q <= 1'b0;
            wdata_valid_q <= 1'b0;
            command_magic_q <= LOADER_COMMAND_MAGIC;
            command_opcode_q <= 8'd0;
            command_chunk_q <= 2'd0;
            command_addr_q <= 32'd0;
            accepted_count_q <= 32'd0;
            doorbell_error_q <= 1'b0;
            loader_done_seen_q <= 1'b0;
            loader_error_seen_q <= 1'b0;
            loader_accepted_seen_q <= 1'b0;
            loader_magic_ok_seen_q <= 1'b0;
            event_state_q <= EVENT_IDLE;
            top1_done_seen_q <= 1'b0;
            top1_error_seen_q <= 1'b0;
            top1_clear_pending_q <= 1'b0;
            top1_start_count_q <= 32'd0;
            command_payload_o <= {COMMAND_WIDTH{1'b0}};
            command_event_o <= 1'b0;
            top1_hidden_vector_o <= 512'd0;
            top1_start_pulse_o <= 1'b0;
            top1_status_clear_pulse_o <= 1'b0;
            mlp_accel_start_pulse_o <= 1'b0;
            mlp_accel_clear_pulse_o <= 1'b0;
            mlp_accel_activation_vector_o <= 512'd0;
            mlp_accel_residual_vector_o <= 512'd0;
            mlp_accel_start_pulse_o <= 1'b0;
            mlp_accel_clear_pulse_o <= 1'b0;
            mlp_accel_start_count_q <= 32'd0;
            mlp_selftest_debug_select_o <= 32'd0;
            m2_full_block_input_vector_o <= 512'd0;
            m2_full_block_input_raw_q <= 512'd0;
            m2_full_block_residual_vector_o <= 512'd0;
            m2_full_block_start_pulse_o <= 1'b0;
            m2_full_block_clear_pulse_o <= 1'b0;
            m2_full_block_start_count_q <= 32'd0;
            last_write_valid_q <= 1'b0;
            last_write_word_index_q <= 10'd0;
            last_wdata_q <= 32'd0;
            last_wstrb_q <= 4'd0;
            for (i = 0; i < 4; i = i + 1)
                command_data_q[i] <= 32'd0;
        end else begin
            command_event_o <= 1'b0;
            status_clear_pulse_o <= 1'b0;
            top1_start_pulse_o <= 1'b0;
            top1_status_clear_pulse_o <= 1'b0;
            mlp_accel_start_pulse_o <= 1'b0;
            mlp_accel_clear_pulse_o <= 1'b0;
            m2_full_block_start_pulse_o <= 1'b0;
            m2_full_block_clear_pulse_o <= 1'b0;
            if (loader_done_i)
                loader_done_seen_q <= 1'b1;
            if (loader_error_i)
                loader_error_seen_q <= 1'b1;
            if (loader_last_accepted_i)
                loader_accepted_seen_q <= 1'b1;
            if (loader_last_magic_ok_i)
                loader_magic_ok_seen_q <= 1'b1;
            if (top1_clear_pending_q && !top1_done_i && !top1_error_i)
                top1_clear_pending_q <= 1'b0;
            if (top1_done_i && !top1_clear_pending_q)
                top1_done_seen_q <= 1'b1;
            if (top1_error_i && !top1_clear_pending_q)
                top1_error_seen_q <= 1'b1;

            s_axi_awready <= !awaddr_valid_q && !write_ready && !s_axi_bvalid;
            s_axi_wready <= !wdata_valid_q && !write_ready && !s_axi_bvalid;

            if (event_state_q == EVENT_ISSUE) begin
                command_event_o <= 1'b1;
                event_state_q <= EVENT_GAP;
            end else if (event_state_q == EVENT_GAP) begin
                event_state_q <= EVENT_REARM;
            end else if (event_state_q == EVENT_REARM) begin
                command_event_o <= 1'b1;
                event_state_q <= EVENT_IDLE;
            end

            if (aw_fire) begin
                awaddr_q <= s_axi_awaddr;
                awaddr_valid_q <= 1'b1;
            end
            if (w_fire) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                wdata_valid_q <= 1'b1;
            end

            if (write_ready) begin
                awaddr_valid_q <= 1'b0;
                wdata_valid_q <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                last_write_valid_q <= 1'b1;
                last_write_word_index_q <= write_word_index;
                last_wdata_q <= wdata_q;
                last_wstrb_q <= wstrb_q;

                case (write_word_index)
                        10'h002: begin
                            if (!duplicate_control_write && wdata_q[0]) begin
                                doorbell_error_q <= 1'b0;
                                loader_done_seen_q <= 1'b0;
                                loader_error_seen_q <= 1'b0;
                                loader_accepted_seen_q <= 1'b0;
                                loader_magic_ok_seen_q <= 1'b0;
                                status_clear_pulse_o <= 1'b1;
                            end
                        end
                        10'h004: command_magic_q <= apply_wstrb(command_magic_q, wdata_q, wstrb_q);
                        10'h005: begin
                            if (wstrb_q[0])
                                command_opcode_q <= wdata_q[7:0];
                            if (wstrb_q[1])
                                command_chunk_q <= wdata_q[9:8];
                        end
                        10'h006: command_addr_q <= apply_wstrb(command_addr_q, wdata_q, wstrb_q);
                        10'h008: command_data_q[0] <= apply_wstrb(command_data_q[0], wdata_q, wstrb_q);
                        10'h009: command_data_q[1] <= apply_wstrb(command_data_q[1], wdata_q, wstrb_q);
                        10'h00a: command_data_q[2] <= apply_wstrb(command_data_q[2], wdata_q, wstrb_q);
                        10'h00b: command_data_q[3] <= apply_wstrb(command_data_q[3], wdata_q, wstrb_q);
                        10'h00c: begin
                            if (!duplicate_control_write && wdata_q[0]) begin
                                if (event_active) begin
                                    doorbell_error_q <= 1'b1;
                                end else begin
                                    command_payload_o <= pack_command_payload(
                                        command_magic_q,
                                        command_opcode_q,
                                        command_chunk_q,
                                        command_addr_q,
                                        command_data_q[0],
                                        command_data_q[1],
                                        command_data_q[2],
                                        command_data_q[3]
                                    );
                                    event_state_q <= EVENT_ISSUE;
                                    accepted_count_q <= accepted_count_q + 32'd1;
                                end
                            end
                        end
                        10'h018: begin
                            if (!duplicate_control_write && wdata_q[1]) begin
                                top1_done_seen_q <= 1'b0;
                                top1_error_seen_q <= 1'b0;
                                top1_clear_pending_q <= 1'b1;
                                top1_status_clear_pulse_o <= 1'b1;
                            end
                            if (!duplicate_control_write && wdata_q[0]) begin
                                if (top1_busy_i) begin
                                    top1_error_seen_q <= 1'b1;
                                end else begin
                                    top1_done_seen_q <= 1'b0;
                                    top1_error_seen_q <= 1'b0;
                                    top1_clear_pending_q <= 1'b1;
                                    top1_start_pulse_o <= 1'b1;
                                    top1_start_count_q <= top1_start_count_q + 32'd1;
                                end
                            end
                        end
                        10'h020: top1_hidden_vector_o[0 +: 32] <= apply_wstrb(top1_hidden_vector_o[0 +: 32], wdata_q, wstrb_q);
                        10'h021: top1_hidden_vector_o[32 +: 32] <= apply_wstrb(top1_hidden_vector_o[32 +: 32], wdata_q, wstrb_q);
                        10'h022: top1_hidden_vector_o[64 +: 32] <= apply_wstrb(top1_hidden_vector_o[64 +: 32], wdata_q, wstrb_q);
                        10'h023: top1_hidden_vector_o[96 +: 32] <= apply_wstrb(top1_hidden_vector_o[96 +: 32], wdata_q, wstrb_q);
                        10'h024: top1_hidden_vector_o[128 +: 32] <= apply_wstrb(top1_hidden_vector_o[128 +: 32], wdata_q, wstrb_q);
                        10'h025: top1_hidden_vector_o[160 +: 32] <= apply_wstrb(top1_hidden_vector_o[160 +: 32], wdata_q, wstrb_q);
                        10'h026: top1_hidden_vector_o[192 +: 32] <= apply_wstrb(top1_hidden_vector_o[192 +: 32], wdata_q, wstrb_q);
                        10'h027: top1_hidden_vector_o[224 +: 32] <= apply_wstrb(top1_hidden_vector_o[224 +: 32], wdata_q, wstrb_q);
                        10'h028: top1_hidden_vector_o[256 +: 32] <= apply_wstrb(top1_hidden_vector_o[256 +: 32], wdata_q, wstrb_q);
                        10'h029: top1_hidden_vector_o[288 +: 32] <= apply_wstrb(top1_hidden_vector_o[288 +: 32], wdata_q, wstrb_q);
                        10'h02a: top1_hidden_vector_o[320 +: 32] <= apply_wstrb(top1_hidden_vector_o[320 +: 32], wdata_q, wstrb_q);
                        10'h02b: top1_hidden_vector_o[352 +: 32] <= apply_wstrb(top1_hidden_vector_o[352 +: 32], wdata_q, wstrb_q);
                        10'h02c: top1_hidden_vector_o[384 +: 32] <= apply_wstrb(top1_hidden_vector_o[384 +: 32], wdata_q, wstrb_q);
                        10'h02d: top1_hidden_vector_o[416 +: 32] <= apply_wstrb(top1_hidden_vector_o[416 +: 32], wdata_q, wstrb_q);
                        10'h02e: top1_hidden_vector_o[448 +: 32] <= apply_wstrb(top1_hidden_vector_o[448 +: 32], wdata_q, wstrb_q);
                        10'h02f: top1_hidden_vector_o[480 +: 32] <= apply_wstrb(top1_hidden_vector_o[480 +: 32], wdata_q, wstrb_q);
                        10'h0d0: mlp_accel_activation_vector_o[0 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[0 +: 32], wdata_q, wstrb_q);
                        10'h0d1: mlp_accel_activation_vector_o[32 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[32 +: 32], wdata_q, wstrb_q);
                        10'h0d2: mlp_accel_activation_vector_o[64 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[64 +: 32], wdata_q, wstrb_q);
                        10'h0d3: mlp_accel_activation_vector_o[96 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[96 +: 32], wdata_q, wstrb_q);
                        10'h0d4: mlp_accel_activation_vector_o[128 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[128 +: 32], wdata_q, wstrb_q);
                        10'h0d5: mlp_accel_activation_vector_o[160 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[160 +: 32], wdata_q, wstrb_q);
                        10'h0d6: mlp_accel_activation_vector_o[192 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[192 +: 32], wdata_q, wstrb_q);
                        10'h0d7: mlp_accel_activation_vector_o[224 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[224 +: 32], wdata_q, wstrb_q);
                        10'h0d8: mlp_accel_activation_vector_o[256 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[256 +: 32], wdata_q, wstrb_q);
                        10'h0d9: mlp_accel_activation_vector_o[288 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[288 +: 32], wdata_q, wstrb_q);
                        10'h0da: mlp_accel_activation_vector_o[320 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[320 +: 32], wdata_q, wstrb_q);
                        10'h0db: mlp_accel_activation_vector_o[352 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[352 +: 32], wdata_q, wstrb_q);
                        10'h0dc: mlp_accel_activation_vector_o[384 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[384 +: 32], wdata_q, wstrb_q);
                        10'h0dd: mlp_accel_activation_vector_o[416 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[416 +: 32], wdata_q, wstrb_q);
                        10'h0de: mlp_accel_activation_vector_o[448 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[448 +: 32], wdata_q, wstrb_q);
                        10'h0df: mlp_accel_activation_vector_o[480 +: 32] <= apply_wstrb(mlp_accel_activation_vector_o[480 +: 32], wdata_q, wstrb_q);
                        10'h0e0: mlp_accel_residual_vector_o[0 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[0 +: 32], wdata_q, wstrb_q);
                        10'h0e1: mlp_accel_residual_vector_o[32 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[32 +: 32], wdata_q, wstrb_q);
                        10'h0e2: mlp_accel_residual_vector_o[64 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[64 +: 32], wdata_q, wstrb_q);
                        10'h0e3: mlp_accel_residual_vector_o[96 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[96 +: 32], wdata_q, wstrb_q);
                        10'h0e4: mlp_accel_residual_vector_o[128 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[128 +: 32], wdata_q, wstrb_q);
                        10'h0e5: mlp_accel_residual_vector_o[160 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[160 +: 32], wdata_q, wstrb_q);
                        10'h0e6: mlp_accel_residual_vector_o[192 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[192 +: 32], wdata_q, wstrb_q);
                        10'h0e7: mlp_accel_residual_vector_o[224 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[224 +: 32], wdata_q, wstrb_q);
                        10'h0e8: mlp_accel_residual_vector_o[256 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[256 +: 32], wdata_q, wstrb_q);
                        10'h0e9: mlp_accel_residual_vector_o[288 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[288 +: 32], wdata_q, wstrb_q);
                        10'h0ea: mlp_accel_residual_vector_o[320 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[320 +: 32], wdata_q, wstrb_q);
                        10'h0eb: mlp_accel_residual_vector_o[352 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[352 +: 32], wdata_q, wstrb_q);
                        10'h0ec: mlp_accel_residual_vector_o[384 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[384 +: 32], wdata_q, wstrb_q);
                        10'h0ed: mlp_accel_residual_vector_o[416 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[416 +: 32], wdata_q, wstrb_q);
                        10'h0ee: mlp_accel_residual_vector_o[448 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[448 +: 32], wdata_q, wstrb_q);
                        10'h0ef: mlp_accel_residual_vector_o[480 +: 32] <= apply_wstrb(mlp_accel_residual_vector_o[480 +: 32], wdata_q, wstrb_q);
                        10'h0cc: begin
                            if (!duplicate_control_write && wdata_q[1])
                                mlp_accel_clear_pulse_o <= 1'b1;
                            if (!duplicate_control_write && wdata_q[0]) begin
                                mlp_accel_start_pulse_o <= 1'b1;
                                mlp_accel_start_count_q <= mlp_accel_start_count_q + 32'd1;
                            end
                        end
                        10'h0f2: mlp_selftest_debug_select_o <= apply_wstrb(mlp_selftest_debug_select_o, wdata_q, wstrb_q);
                        10'h143: begin
                            if (!duplicate_control_write && wdata_q[1])
                                m2_full_block_clear_pulse_o <= 1'b1;
                            if (!duplicate_control_write && wdata_q[0]) begin
                                m2_full_block_start_pulse_o <= 1'b1;
                                m2_full_block_start_count_q <= m2_full_block_start_count_q + 32'd1;
                            end
                        end
                        default: begin
                            if (write_word_index >= 10'h150 && write_word_index <= 10'h15f) begin
                                m2_full_block_input_raw_next = m2_full_block_input_raw_q;
                                m2_full_block_input_raw_next[(write_word_index - 10'h150) * 32 +: 32] =
                                    apply_wstrb(
                                        m2_full_block_input_raw_q[(write_word_index - 10'h150) * 32 +: 32],
                                        wdata_q,
                                        wstrb_q
                                    );
                                m2_full_block_input_raw_q <= m2_full_block_input_raw_next;
                                m2_full_block_input_vector_o <= pcie7x_ror64_to_host_vector(m2_full_block_input_raw_next);
                            end else if (write_word_index >= 10'h160 && write_word_index <= 10'h16f) begin
                                m2_full_block_residual_vector_o[(write_word_index - 10'h160) * 32 +: 32] <=
                                    apply_wstrb(
                                        m2_full_block_residual_vector_o[(write_word_index - 10'h160) * 32 +: 32],
                                        wdata_q,
                                        wstrb_q
                                    );
                            end
                        end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 32'd0;
            read_pending_q <= 1'b0;
            read_response_pending_q <= 1'b0;
            read_word_index_q <= 10'd0;
            read_word_offset_q <= 4'd0;
            read_window_q <= 512'd0;
        end else begin
            s_axi_arready <= !s_axi_rvalid && !read_pending_q && !read_response_pending_q;
            if (!s_axi_rvalid && !read_pending_q && !read_response_pending_q && s_axi_arvalid) begin
                read_word_index_q <= read_word_index;
                read_word_offset_q <= read_word_index[3:0];
                read_pending_q <= 1'b1;
            end else if (read_pending_q) begin
                read_window_q <= read_window_data;
                read_response_pending_q <= 1'b1;
                read_pending_q <= 1'b0;
            end else if (read_response_pending_q) begin
                s_axi_rdata <= read_window_q[read_word_offset_q * 32 +: 32];
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
                read_response_pending_q <= 1'b0;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
