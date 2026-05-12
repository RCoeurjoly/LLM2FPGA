`timescale 1ns/1ps
`default_nettype none

module task6_uberddr3_rowstream_loader_contract_tb;
  localparam int COMMAND_WIDTH = 192;
  localparam int WB_ADDR_BITS = 10;
  localparam int WB_DATA_BITS = 512;
  localparam int WB_SEL_BITS = WB_DATA_BITS / 8;
  localparam logic [31:0] COMMAND_MAGIC = 32'h33445244;
  localparam logic [7:0] OP_WRITE_LOWBYTE = 8'h03;
  localparam logic [7:0] OP_READ_LOWBYTE = 8'h04;
  localparam logic [7:0] OP_WRITE_DENSE_BYTE = 8'h05;
  localparam logic [7:0] OP_READ_DENSE_BEAT = 8'h06;
  localparam logic [7:0] OP_WRITE_DENSE_FILL = 8'h08;
  localparam logic [7:0] OP_RUN_FULLBEAT = 8'h09;

  logic clk;
  logic rst_n;
  logic boot_done;
  logic [COMMAND_WIDTH - 1:0] command_payload;
  logic command_event;
  wire wb_cyc;
  wire wb_stb;
  wire wb_we;
  wire [WB_ADDR_BITS - 1:0] wb_addr;
  wire [WB_DATA_BITS - 1:0] wb_data_w;
  wire [WB_SEL_BITS - 1:0] wb_sel;
  logic wb_stall;
  logic wb_ack;
  logic wb_err;
  logic [WB_DATA_BITS - 1:0] wb_data_r;
  wire loader_done;
  wire loader_error;
  wire loader_write_ack_seen;
  wire loader_read_ack_seen;
  wire loader_stall_seen;
  wire [WB_DATA_BITS - 1:0] loader_read_data;
  wire [31:0] loader_wait_cycles;
  wire [31:0] loader_command_payload_addr;
  wire [7:0] loader_last_opcode;
  wire [1:0] loader_last_chunk;
  wire loader_last_magic_ok;
  wire loader_last_accepted;
  wire loader_fullbeat_done;
  wire [6:0] loader_fullbeat_mismatch_count;
  wire [WB_ADDR_BITS - 1:0] loader_fullbeat_addr;
  wire [7:0] loader_fullbeat_expected_base;
  wire [3:0] loader_state;

  logic [WB_DATA_BITS - 1:0] mem [0:1023];
  int write_count;
  int read_count;
  int errors;
  logic [WB_ADDR_BITS - 1:0] boot_write_addr_ref;
  logic [WB_DATA_BITS - 1:0] boot_write_data_ref;
  logic [WB_SEL_BITS - 1:0] boot_write_sel_ref;

  task6_uberddr3_rowstream_loader_contract #(
    .JTAG_COMMAND_WIDTH(COMMAND_WIDTH),
    .WB_ADDR_BITS(WB_ADDR_BITS),
    .WB_DATA_BITS(WB_DATA_BITS),
    .WB_SEL_BITS(WB_SEL_BITS),
    .LOADER_COMMAND_MAGIC(COMMAND_MAGIC),
    .LOADER_OP_WRITE_LOWBYTE(OP_WRITE_LOWBYTE),
    .LOADER_OP_READ_LOWBYTE(OP_READ_LOWBYTE),
    .LOADER_OP_WRITE_DENSE_BYTE(OP_WRITE_DENSE_BYTE),
    .LOADER_OP_READ_DENSE_BEAT(OP_READ_DENSE_BEAT),
    .LOADER_OP_WRITE_DENSE_FILL(OP_WRITE_DENSE_FILL),
    .LOADER_OP_RUN_FULLBEAT(OP_RUN_FULLBEAT)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .boot_done_i(boot_done),
    .command_payload_i(command_payload),
    .command_event_i(command_event),
    .wb_cyc_o(wb_cyc),
    .wb_stb_o(wb_stb),
    .wb_we_o(wb_we),
    .wb_addr_o(wb_addr),
    .wb_data_o(wb_data_w),
    .wb_sel_o(wb_sel),
    .wb_stall_i(wb_stall),
    .wb_ack_i(wb_ack),
    .wb_err_i(wb_err),
    .wb_data_i(wb_data_r),
    .loader_done_o(loader_done),
    .loader_error_o(loader_error),
    .loader_write_ack_seen_o(loader_write_ack_seen),
    .loader_read_ack_seen_o(loader_read_ack_seen),
    .loader_stall_seen_o(loader_stall_seen),
    .loader_read_data_o(loader_read_data),
    .loader_wait_cycles_o(loader_wait_cycles),
    .loader_command_payload_addr_o(loader_command_payload_addr),
    .loader_last_opcode_o(loader_last_opcode),
    .loader_last_chunk_o(loader_last_chunk),
    .loader_last_magic_ok_o(loader_last_magic_ok),
    .loader_last_accepted_o(loader_last_accepted),
    .loader_fullbeat_done_o(loader_fullbeat_done),
    .loader_fullbeat_mismatch_count_o(loader_fullbeat_mismatch_count),
    .loader_fullbeat_addr_o(loader_fullbeat_addr),
    .loader_fullbeat_expected_base_o(loader_fullbeat_expected_base),
    .loader_state_o(loader_state)
  );

  always #5 clk = ~clk;

  function automatic logic [COMMAND_WIDTH - 1:0] make_command(
    input logic [31:0] magic,
    input logic [7:0] opcode,
    input logic [1:0] chunk,
    input logic [31:0] addr,
    input logic [7:0] data_byte
  );
    logic [COMMAND_WIDTH - 1:0] payload;
    begin
      payload = '0;
      payload[0 +: 32] = magic;
      payload[32 +: 8] = opcode;
      payload[40 +: 2] = chunk;
      payload[48 +: 32] = addr;
      payload[64 +: 8] = data_byte;
      make_command = payload;
    end
  endfunction

  function automatic logic [COMMAND_WIDTH - 1:0] make_command_arg(
    input logic [31:0] magic,
    input logic [7:0] opcode,
    input logic [1:0] chunk,
    input logic [31:0] addr,
    input logic [7:0] data_byte,
    input logic [7:0] data_arg
  );
    logic [COMMAND_WIDTH - 1:0] payload;
    begin
      payload = make_command(magic, opcode, chunk, addr, data_byte);
      payload[72 +: 8] = data_arg;
      make_command_arg = payload;
    end
  endfunction

  task automatic pulse_command(input logic [COMMAND_WIDTH - 1:0] payload);
    begin
      @(negedge clk);
      command_payload = payload;
      command_event = 1'b1;
      @(negedge clk);
      command_event = 1'b0;
    end
  endtask

  task automatic wait_done(input string label);
    int timeout;
    begin
      timeout = 0;
      while (!loader_done && !loader_error && timeout < 1200) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 1200) begin
        $display("FAIL: %s timed out", label);
        errors = errors + 1;
      end
    end
  endtask

  task automatic pulse_command_pair_and_wait(
    input logic [COMMAND_WIDTH - 1:0] payload,
    input string label
  );
    begin
      pulse_command(payload);
      repeat (4) @(negedge clk);
      if (!loader_done && !loader_error) begin
        pulse_command(payload);
        wait_done(label);
      end
    end
  endtask

  task automatic check_cond(input bit condition, input string message);
    begin
      if (!condition) begin
        $display("FAIL: %s", message);
        errors = errors + 1;
      end
    end
  endtask

  task automatic make_boot_write_reference(
    input logic [5:0] stream_base,
    input logic [1:0] write_index,
    input logic [7:0] expected_byte
  );
    logic [5:0] boot_addr;
    logic [7:0] boot_byte;
    begin
      boot_addr = stream_base + {4'd0, write_index};
      boot_byte = expected_byte + {2'd0, stream_base} + {6'd0, write_index};
      boot_write_addr_ref = {{(WB_ADDR_BITS - 6){1'b0}}, boot_addr};
      boot_write_data_ref = {WB_SEL_BITS{boot_byte}};
      boot_write_sel_ref = {WB_SEL_BITS{1'b1}};
    end
  endtask

  task automatic check_write_lowbyte_bus_shape(
    input logic [31:0] stream_addr,
    input logic [7:0] value,
    input bit require_stb,
    input string phase
  );
    begin
      check_cond(wb_cyc == 1'b1, {phase, ": wb_cyc must stay asserted"});
      if (require_stb)
        check_cond(wb_stb == 1'b1, {phase, ": wb_stb must stay asserted"});
      check_cond(wb_we == 1'b1, {phase, ": wb_we must be write"});
      check_cond(wb_addr == stream_addr[WB_ADDR_BITS - 1:0], {phase, ": wb_addr must match command address"});
      check_cond(wb_sel == {WB_SEL_BITS{1'b1}}, {phase, ": wb_sel must select all byte lanes"});
      check_cond(wb_data_w == {WB_SEL_BITS{value}}, {phase, ": wb_data must repeat the payload byte"});
    end
  endtask

  task automatic check_write_lowbyte_matches_boot_write(
    input logic [31:0] stream_addr,
    input logic [7:0] value,
    input string phase
  );
    begin
      make_boot_write_reference(stream_addr[5:0], 2'd0, value);
      check_cond(wb_addr == boot_write_addr_ref, {phase, ": loader write address must match boot BIST write address"});
      check_cond(wb_sel == boot_write_sel_ref, {phase, ": loader write select must match boot BIST write select"});
      check_cond(wb_data_w == boot_write_data_ref, {phase, ": loader write data must match boot BIST write data"});
    end
  endtask

  task automatic pulse_lowbyte_and_check_bus_through_ack(
    input logic [31:0] stream_addr,
    input logic [7:0] value
  );
    begin
      wb_stall = 1'b1;
      pulse_command(make_command(COMMAND_MAGIC, OP_WRITE_LOWBYTE, 2'd0, stream_addr, value));
      repeat (2) @(negedge clk);
      check_write_lowbyte_bus_shape(stream_addr, value, 1'b1, "write-lowbyte stalled issue");
      check_write_lowbyte_matches_boot_write(stream_addr, value, "write-lowbyte stalled issue");

      repeat (3) begin
        @(negedge clk);
        check_write_lowbyte_bus_shape(stream_addr, value, 1'b1, "write-lowbyte held under stall");
        check_write_lowbyte_matches_boot_write(stream_addr, value, "write-lowbyte held under stall");
      end

      wb_stall = 1'b0;
      @(negedge clk);
      check_write_lowbyte_bus_shape(stream_addr, value, 1'b0, "write-lowbyte ack boundary");
      check_write_lowbyte_matches_boot_write(stream_addr, value, "write-lowbyte ack request cycle");
      wait_done("write-lowbyte stalled bus-shape");
      check_cond(loader_error == 1'b0, "write-lowbyte stalled bus-shape must not raise loader_error");
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_ack <= 1'b0;
      wb_data_r <= '0;
      write_count <= 0;
      read_count <= 0;
    end else begin
      wb_ack <= wb_cyc && wb_stb && !wb_stall;
      wb_data_r <= mem[wb_addr];
      if (wb_cyc && wb_stb && !wb_stall) begin
        if (wb_we) begin
          for (int lane = 0; lane < WB_SEL_BITS; lane = lane + 1) begin
            if (wb_sel[lane])
              mem[wb_addr][lane * 8 +: 8] <= wb_data_w[lane * 8 +: 8];
          end
          write_count <= write_count + 1;
        end else begin
          read_count <= read_count + 1;
        end
      end
    end
  end

  initial begin : init_control
    logic [COMMAND_WIDTH - 1:0] write_cmd;
    logic [COMMAND_WIDTH - 1:0] read_cmd;
    logic [COMMAND_WIDTH - 1:0] dense_cmd;
    logic [COMMAND_WIDTH - 1:0] dense_read_cmd;
    logic [COMMAND_WIDTH - 1:0] dense_fill_cmd;
    logic [COMMAND_WIDTH - 1:0] dense_fill_read_cmd;
    logic [COMMAND_WIDTH - 1:0] fullbeat_cmd;
    int i;

    clk = 1'b0;
    rst_n = 1'b0;
    boot_done = 1'b0;
    command_payload = '0;
    command_event = 1'b0;
    wb_stall = 1'b0;
    wb_err = 1'b0;
    errors = 0;
    for (i = 0; i < 1024; i = i + 1)
      mem[i] = '0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    write_cmd = make_command(COMMAND_MAGIC, OP_WRITE_LOWBYTE, 2'd0, 32'd0, 8'h5a);
    pulse_command(write_cmd);
    pulse_command(write_cmd);
    repeat (6) @(negedge clk);
    check_cond(write_count == 0, "commands before boot_done must not write");

    boot_done = 1'b1;
    pulse_lowbyte_and_check_bus_through_ack(32'd0, 8'h5a);
    check_cond(loader_error == 1'b0, "write-lowbyte must not raise loader_error");
    check_cond(write_count == 1, "first accepted write must issue one Wishbone write");
    check_cond(wb_addr == 10'd0, "write-lowbyte must present the command address");
    check_cond(wb_sel == {WB_SEL_BITS{1'b1}}, "write-lowbyte must assert all byte selects");
    check_cond(mem[0][7:0] == 8'h5a, "write-lowbyte must store the payload byte in lane 0");
    check_cond(mem[0][511:504] == 8'h5a, "write-lowbyte v35 must replicate across the full beat");

    pulse_command(write_cmd);
    repeat (8) @(negedge clk);
    check_cond(write_count == 1, "duplicate command event must be ignored by every-other filter");

    read_cmd = make_command(COMMAND_MAGIC, OP_READ_LOWBYTE, 2'd0, 32'd0, 8'h00);
    pulse_command(read_cmd);
    wait_done("read-lowbyte first duplicate phase");
    if (!loader_done) begin
      pulse_command(read_cmd);
      wait_done("read-lowbyte");
    end
    check_cond(loader_error == 1'b0, "read-lowbyte must not raise loader_error");
    check_cond(read_count == 1, "read-lowbyte must issue one Wishbone read");
    check_cond(wb_sel == {{(WB_SEL_BITS - 1){1'b0}}, 1'b1}, "read-lowbyte must select lane 0");
    check_cond(loader_read_data[7:0] == 8'h5a, "read-lowbyte must capture the stored lane-0 byte");

    for (i = 0; i < 16; i = i + 1) begin
      dense_cmd = make_command(COMMAND_MAGIC, OP_WRITE_DENSE_BYTE, 2'd0, i[31:0], i[7:0]);
      pulse_command_pair_and_wait(dense_cmd, "write-dense-byte");
      check_cond(loader_error == 1'b0, "write-dense-byte must not raise loader_error");
      check_cond(wb_addr == 10'd0, "write-dense-byte addresses 0..15 must target beat 0");
      check_cond(wb_sel == (64'd1 << i), "write-dense-byte must select exactly the byte lane");
      check_cond(mem[0][i * 8 +: 8] == i[7:0], "write-dense-byte must store the payload byte in its lane");
    end

    dense_read_cmd = make_command(COMMAND_MAGIC, OP_READ_DENSE_BEAT, 2'd0, 32'd0, 8'h00);
    pulse_command_pair_and_wait(dense_read_cmd, "read-dense-beat");
    check_cond(loader_error == 1'b0, "read-dense-beat must not raise loader_error");
    check_cond(wb_sel == {WB_SEL_BITS{1'b1}}, "read-dense-beat must select the full beat");
    for (i = 0; i < 16; i = i + 1)
      check_cond(loader_read_data[i * 8 +: 8] == i[7:0], "read-dense-beat must capture dense byte lanes 0..15");

    dense_fill_cmd = make_command(COMMAND_MAGIC, OP_WRITE_DENSE_FILL, 2'd0, 32'd2, 8'h5a);
    pulse_command_pair_and_wait(dense_fill_cmd, "write-dense-fill");
    check_cond(loader_error == 1'b0, "write-dense-fill must not raise loader_error");
    check_cond(wb_addr == 10'd2, "write-dense-fill must present the command beat address");
    check_cond(wb_sel == {WB_SEL_BITS{1'b1}}, "write-dense-fill must select the full beat");
    for (i = 0; i < 64; i = i + 1)
      check_cond(mem[2][i * 8 +: 8] == 8'h5a, "write-dense-fill must store the payload byte in every lane");

    dense_fill_read_cmd = make_command(COMMAND_MAGIC, OP_READ_DENSE_BEAT, 2'd0, 32'd2, 8'h00);
    pulse_command_pair_and_wait(dense_fill_read_cmd, "read-dense-fill");
    check_cond(loader_error == 1'b0, "read-dense-fill must not raise loader_error");
    for (i = 0; i < 16; i = i + 1)
      check_cond(loader_read_data[i * 8 +: 8] == 8'h5a, "read-dense-fill must capture repeated byte lanes 0..15");

    fullbeat_cmd = make_command(COMMAND_MAGIC, OP_RUN_FULLBEAT, 2'd0, 32'd3, 8'h20);
    pulse_command_pair_and_wait(fullbeat_cmd, "run-fullbeat");
    check_cond(loader_error == 1'b0, "run-fullbeat must not raise loader_error");
    check_cond(loader_fullbeat_done == 1'b1, "run-fullbeat must set fullbeat_done after readback");
    check_cond(loader_fullbeat_mismatch_count == 7'd0, "run-fullbeat must compare all generated lanes");
    check_cond(loader_fullbeat_addr == 10'd3, "run-fullbeat must record the beat address");
    check_cond(loader_fullbeat_expected_base == 8'h20, "run-fullbeat must record the generated base byte");
    check_cond(mem[3][7:0] == 8'h20, "run-fullbeat must write generated lane 0");
    check_cond(mem[3][511:504] == 8'h5f, "run-fullbeat must write generated lane 63");

    fullbeat_cmd = make_command(COMMAND_MAGIC, OP_RUN_FULLBEAT, 2'd1, 32'd4, 8'ha5);
    pulse_command_pair_and_wait(fullbeat_cmd, "run-fullbeat-constant");
    check_cond(loader_error == 1'b0, "run-fullbeat constant must not raise loader_error");
    check_cond(loader_fullbeat_mismatch_count == 7'd0, "run-fullbeat constant must compare all generated lanes");
    check_cond(mem[4][7:0] == 8'ha5, "run-fullbeat constant must write lane 0");
    check_cond(mem[4][511:504] == 8'ha5, "run-fullbeat constant must write lane 63");

    fullbeat_cmd = make_command(COMMAND_MAGIC, OP_RUN_FULLBEAT, 2'd2, 32'd5, 8'h30);
    pulse_command_pair_and_wait(fullbeat_cmd, "run-fullbeat-word");
    check_cond(loader_error == 1'b0, "run-fullbeat word pattern must not raise loader_error");
    check_cond(loader_fullbeat_mismatch_count == 7'd0, "run-fullbeat word pattern must compare all generated lanes");
    check_cond(mem[5][7:0] == 8'h30, "run-fullbeat word pattern lane 0");
    check_cond(mem[5][15:8] == 8'h31, "run-fullbeat word pattern lane 1");
    check_cond(mem[5][31:24] == 8'h33, "run-fullbeat word pattern lane 3");
    check_cond(mem[5][39:32] == 8'h30, "run-fullbeat word pattern repeats at lane 4");

    fullbeat_cmd = make_command_arg(COMMAND_MAGIC, OP_RUN_FULLBEAT, 2'd3, 32'd6, 8'hc3, 8'd2);
    pulse_command_pair_and_wait(fullbeat_cmd, "run-fullbeat-bytepos");
    check_cond(loader_error == 1'b0, "run-fullbeat byte-position pattern must not raise loader_error");
    check_cond(loader_fullbeat_mismatch_count == 7'd0, "run-fullbeat byte-position pattern must compare all generated lanes");
    check_cond(mem[6][7:0] == 8'h00, "run-fullbeat byte-position lane 0 must be zero");
    check_cond(mem[6][15:8] == 8'h00, "run-fullbeat byte-position lane 1 must be zero");
    check_cond(mem[6][23:16] == 8'hc3, "run-fullbeat byte-position lane 2 must carry sentinel");
    check_cond(mem[6][31:24] == 8'h00, "run-fullbeat byte-position lane 3 must be zero");
    check_cond(mem[6][55:48] == 8'hc3, "run-fullbeat byte-position repeats at lane 6");

    pulse_command(make_command(32'h0, OP_WRITE_LOWBYTE, 2'd0, 32'd7, 8'ha5));
    repeat (8) @(negedge clk);
    check_cond(write_count == 22, "bad magic must not issue Wishbone writes");

    if (errors == 0) begin
      $display(
        "PASS: task6 rowstream loader contract writes %0d reads %0d state %0d wait_cycles %0d",
        write_count,
        read_count,
        loader_state,
        loader_wait_cycles
      );
      $finish;
    end else begin
      $display("FAIL: task6 rowstream loader contract errors %0d", errors);
      $fatal(1);
    end
  end
endmodule

`default_nettype wire
