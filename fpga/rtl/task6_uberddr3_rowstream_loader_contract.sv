`timescale 1ns/1ps
`default_nettype none

module task6_uberddr3_rowstream_loader_contract #(
  parameter int JTAG_COMMAND_WIDTH = 192,
  parameter int WB_ADDR_BITS = 25,
  parameter int WB_DATA_BITS = 512,
  parameter int WB_SEL_BITS = WB_DATA_BITS / 8,
  parameter logic [31:0] LOADER_COMMAND_MAGIC = 32'h33445244,
  parameter logic [7:0] LOADER_OP_WRITE_LOWBYTE = 8'h03,
  parameter logic [7:0] LOADER_OP_READ_LOWBYTE = 8'h04,
  parameter logic [7:0] LOADER_OP_WRITE_DENSE_BYTE = 8'h05,
  parameter logic [7:0] LOADER_OP_READ_DENSE_BEAT = 8'h06,
  parameter logic [7:0] LOADER_OP_WRITE_DENSE_FILL = 8'h08
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic                            boot_done_i,
  input  logic [JTAG_COMMAND_WIDTH - 1:0] command_payload_i,
  input  logic                            command_event_i,
  output logic                            wb_cyc_o,
  output logic                            wb_stb_o,
  output logic                            wb_we_o,
  output logic [WB_ADDR_BITS - 1:0]       wb_addr_o,
  output logic [WB_DATA_BITS - 1:0]       wb_data_o,
  output logic [WB_SEL_BITS - 1:0]        wb_sel_o,
  input  logic                            wb_stall_i,
  input  logic                            wb_ack_i,
  input  logic                            wb_err_i,
  input  logic [WB_DATA_BITS - 1:0]       wb_data_i,
  output logic                            loader_done_o,
  output logic                            loader_error_o,
  output logic                            loader_write_ack_seen_o,
  output logic                            loader_read_ack_seen_o,
  output logic                            loader_stall_seen_o,
  output logic [WB_DATA_BITS - 1:0]       loader_read_data_o,
  output logic [31:0]                     loader_wait_cycles_o,
  output logic [31:0]                     loader_command_payload_addr_o,
  output logic [7:0]                      loader_last_opcode_o,
  output logic [1:0]                      loader_last_chunk_o,
  output logic                            loader_last_magic_ok_o,
  output logic                            loader_last_accepted_o,
  output logic [3:0]                      loader_state_o
);
  typedef enum logic [1:0] {
    LOADER_IDLE = 2'd0,
    LOADER_ISSUE = 2'd1,
    LOADER_WAIT_ACK = 2'd2,
    LOADER_ERROR = 2'd3
  } loader_state_t;

  loader_state_t state_q;
  logic command_accept_phase_q;

  wire [31:0] command_magic = command_payload_i[0 +: 32];
  wire [7:0] command_opcode = command_payload_i[32 +: 8];
  wire [1:0] command_chunk = command_payload_i[40 +: 2];
  wire [31:0] command_addr = command_payload_i[48 +: 32];
  wire [127:0] command_data = command_payload_i[64 +: 128];
  wire command_magic_ok = command_magic == LOADER_COMMAND_MAGIC;
  wire command_accepted =
    command_event_i && !command_accept_phase_q && boot_done_i && command_magic_ok;
  wire [WB_ADDR_BITS - 1:0] command_dense_addr =
    {{(WB_ADDR_BITS - 10){1'b0}}, command_addr[15:6]};
  wire [WB_SEL_BITS - 1:0] command_dense_sel =
    {{(WB_SEL_BITS - 1){1'b0}}, 1'b1} << command_addr[5:0];
  logic [WB_DATA_BITS - 1:0] command_dense_data;

  always_comb begin
    command_dense_data = '0;
    command_dense_data[command_addr[5:0] * 8 +: 8] = command_data[7:0];
  end

  assign loader_state_o =
    state_q == LOADER_IDLE ? 4'd1 :
    state_q == LOADER_ISSUE ? 4'd2 :
    state_q == LOADER_WAIT_ACK ? 4'd3 :
    4'd4;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      command_accept_phase_q <= 1'b0;
      state_q <= LOADER_IDLE;
      wb_cyc_o <= 1'b0;
      wb_stb_o <= 1'b0;
      wb_we_o <= 1'b0;
      wb_addr_o <= '0;
      wb_data_o <= '0;
      wb_sel_o <= '0;
      loader_done_o <= 1'b0;
      loader_error_o <= 1'b0;
      loader_write_ack_seen_o <= 1'b0;
      loader_read_ack_seen_o <= 1'b0;
      loader_stall_seen_o <= 1'b0;
      loader_read_data_o <= '0;
      loader_wait_cycles_o <= 32'd0;
      loader_command_payload_addr_o <= 32'd0;
      loader_last_opcode_o <= 8'd0;
      loader_last_chunk_o <= 2'd0;
      loader_last_magic_ok_o <= 1'b0;
      loader_last_accepted_o <= 1'b0;
    end else begin
      if (command_event_i)
        command_accept_phase_q <= ~command_accept_phase_q;

      loader_done_o <= 1'b0;
      loader_last_accepted_o <= 1'b0;

      if (command_accepted && state_q == LOADER_IDLE) begin
        loader_last_opcode_o <= command_opcode;
        loader_last_chunk_o <= command_chunk;
        loader_command_payload_addr_o <= command_addr;
        loader_last_magic_ok_o <= 1'b1;
        loader_last_accepted_o <= 1'b1;
        loader_error_o <= 1'b0;
        loader_stall_seen_o <= 1'b0;
        loader_wait_cycles_o <= 32'd0;

        if (command_opcode == LOADER_OP_WRITE_LOWBYTE) begin
          wb_addr_o <= command_addr[WB_ADDR_BITS - 1:0];
          wb_data_o <= {WB_SEL_BITS{command_data[7:0]}};
          wb_sel_o <= {WB_SEL_BITS{1'b1}};
          wb_we_o <= 1'b1;
          wb_cyc_o <= 1'b1;
          wb_stb_o <= 1'b1;
          state_q <= LOADER_ISSUE;
        end else if (command_opcode == LOADER_OP_READ_LOWBYTE) begin
          wb_addr_o <= command_addr[WB_ADDR_BITS - 1:0];
          wb_data_o <= '0;
          wb_sel_o <= {{(WB_SEL_BITS - 1){1'b0}}, 1'b1};
          wb_we_o <= 1'b0;
          wb_cyc_o <= 1'b1;
          wb_stb_o <= 1'b1;
          state_q <= LOADER_ISSUE;
        end else if (command_opcode == LOADER_OP_WRITE_DENSE_BYTE) begin
          wb_addr_o <= command_dense_addr;
          wb_data_o <= command_dense_data;
          wb_sel_o <= command_dense_sel;
          wb_we_o <= 1'b1;
          wb_cyc_o <= 1'b1;
          wb_stb_o <= 1'b1;
          state_q <= LOADER_ISSUE;
        end else if (command_opcode == LOADER_OP_READ_DENSE_BEAT) begin
          wb_addr_o <= command_addr[WB_ADDR_BITS - 1:0];
          wb_data_o <= '0;
          wb_sel_o <= {WB_SEL_BITS{1'b1}};
          wb_we_o <= 1'b0;
          wb_cyc_o <= 1'b1;
          wb_stb_o <= 1'b1;
          state_q <= LOADER_ISSUE;
        end else if (command_opcode == LOADER_OP_WRITE_DENSE_FILL) begin
          wb_addr_o <= command_addr[WB_ADDR_BITS - 1:0];
          wb_data_o <= {WB_SEL_BITS{command_data[7:0]}};
          wb_sel_o <= {WB_SEL_BITS{1'b1}};
          wb_we_o <= 1'b1;
          wb_cyc_o <= 1'b1;
          wb_stb_o <= 1'b1;
          state_q <= LOADER_ISSUE;
        end else begin
          loader_error_o <= 1'b1;
          state_q <= LOADER_ERROR;
        end
      end else if (command_event_i && !command_accept_phase_q && boot_done_i) begin
        loader_last_opcode_o <= command_opcode;
        loader_last_chunk_o <= command_chunk;
        loader_command_payload_addr_o <= command_addr;
        loader_last_magic_ok_o <= 1'b0;
      end else begin
        case (state_q)
        LOADER_IDLE: begin
          wb_cyc_o <= 1'b0;
          wb_stb_o <= 1'b0;
          wb_we_o <= 1'b0;
        end

        LOADER_ISSUE: begin
          if (wb_stall_i) begin
            loader_stall_seen_o <= 1'b1;
            loader_wait_cycles_o <= loader_wait_cycles_o + 32'd1;
          end else begin
            wb_stb_o <= 1'b0;
            state_q <= wb_ack_i ? LOADER_IDLE : LOADER_WAIT_ACK;
          end
          if (wb_err_i) begin
            loader_error_o <= 1'b1;
            wb_cyc_o <= 1'b0;
            wb_stb_o <= 1'b0;
            wb_we_o <= 1'b0;
            state_q <= LOADER_ERROR;
          end
          if (wb_ack_i) begin
            wb_cyc_o <= 1'b0;
            wb_stb_o <= 1'b0;
            if (wb_we_o) begin
              loader_write_ack_seen_o <= 1'b1;
            end else begin
              loader_read_ack_seen_o <= 1'b1;
              loader_read_data_o <= wb_data_i;
            end
            loader_done_o <= 1'b1;
          end
        end

        LOADER_WAIT_ACK: begin
          loader_wait_cycles_o <= loader_wait_cycles_o + 32'd1;
          if (wb_err_i) begin
            loader_error_o <= 1'b1;
            wb_cyc_o <= 1'b0;
            wb_stb_o <= 1'b0;
            wb_we_o <= 1'b0;
            state_q <= LOADER_ERROR;
          end else if (wb_ack_i) begin
            wb_cyc_o <= 1'b0;
            if (wb_we_o) begin
              loader_write_ack_seen_o <= 1'b1;
            end else begin
              loader_read_ack_seen_o <= 1'b1;
              loader_read_data_o <= wb_data_i;
            end
            loader_done_o <= 1'b1;
            state_q <= LOADER_IDLE;
          end
        end

        LOADER_ERROR: begin
          wb_cyc_o <= 1'b0;
          wb_stb_o <= 1'b0;
          wb_we_o <= 1'b0;
        end

        default: state_q <= LOADER_ERROR;
        endcase
      end
    end
  end
endmodule

`default_nettype wire
