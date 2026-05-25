`timescale 1ns/1ps
`default_nettype none

module task6_pcie_axil_rowstream_loopback_tb;
  logic clk;
  logic rst_n;
  logic [31:0] awaddr;
  logic awvalid;
  wire awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  wire wready;
  wire [1:0] bresp;
  wire bvalid;
  logic bready;
  logic [31:0] araddr;
  logic arvalid;
  wire arready;
  wire [31:0] rdata;
  wire rvalid;
  logic rready;
  wire [1:0] rresp;

  int errors;

  axil_minimum dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready),
    .s_axi_rresp(rresp)
  );

  always #5 clk = ~clk;

  function automatic logic [7:0] payload_byte(input int index);
    int value;
    begin
      value = index * 17 + 23;
      payload_byte = value[7:0];
    end
  endfunction

  function automatic logic [31:0] payload_word(input int word_index);
    payload_word = {
      payload_byte(word_index * 4 + 0),
      payload_byte(word_index * 4 + 1),
      payload_byte(word_index * 4 + 2),
      payload_byte(word_index * 4 + 3)
    };
  endfunction

  task automatic check(input bit condition, input string message);
    if (!condition) begin
      $display("FAIL: %s", message);
      errors++;
    end
  endtask

  task automatic axil_write(input logic [31:0] addr, input logic [31:0] data);
    bit aw_seen;
    bit w_seen;
    begin
      @(negedge clk);
      awaddr = addr;
      wdata = data;
      wstrb = 4'hf;
      awvalid = 1'b1;
      wvalid = 1'b1;
      bready = 1'b1;
      aw_seen = 1'b0;
      w_seen = 1'b0;
      while (!aw_seen || !w_seen) begin
        @(negedge clk);
        if (awready) aw_seen = 1'b1;
        if (wready) w_seen = 1'b1;
      end
      @(negedge clk);
      awvalid = 1'b0;
      wvalid = 1'b0;
      while (!bvalid) @(negedge clk);
      check(bresp == 2'b00, "write response must be OKAY");
      @(negedge clk);
      bready = 1'b0;
    end
  endtask

  task automatic axil_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      @(negedge clk);
      araddr = addr;
      arvalid = 1'b1;
      rready = 1'b1;
      while (arvalid) begin
        @(negedge clk);
        if (arready) arvalid = 1'b0;
      end
      while (!rvalid) @(negedge clk);
      data = rdata;
      check(rresp == 2'b00, "read response must be OKAY");
      @(negedge clk);
      rready = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] value;
    logic [31:0] expected_sum;
    logic [31:0] expected_xor;
    int payload_bytes;
    int words;

    clk = 1'b0;
    rst_n = 1'b0;
    awaddr = '0;
    awvalid = 1'b0;
    wdata = '0;
    wstrb = '0;
    wvalid = 1'b0;
    bready = 1'b0;
    araddr = '0;
    arvalid = 1'b0;
    rready = 1'b0;
    errors = 0;
    payload_bytes = 64;
    words = payload_bytes / 4;
    expected_sum = 32'd0;
    expected_xor = 32'd0;

    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(negedge clk);

    axil_read(32'h000, value);
    check(value == 32'h54365043, "magic must match T6PC");
    axil_read(32'h004, value);
    check(value == 32'd2, "version must be 2");

    for (int i = 0; i < payload_bytes; i++)
      expected_sum = expected_sum + {24'd0, payload_byte(i)};
    for (int i = 0; i < words; i++)
      expected_xor = expected_xor ^ payload_word(i);

    axil_write(32'h008, 32'h1);
    axil_write(32'h010, payload_bytes[31:0]);
    axil_write(32'h010, payload_bytes[31:0]);
    axil_write(32'h014, expected_sum);
    axil_write(32'h014, expected_sum);
    for (int i = 0; i < words; i++) begin
      axil_write(32'h100 + i * 4, payload_word(i));
      axil_write(32'h100 + i * 4, payload_word(i));
    end
    axil_write(32'h018, 32'h1);
    axil_write(32'h018, 32'h1);

    axil_read(32'h008, value);
    check(value[2] == 1'b1, "done bit must set");
    check(value[3] == 1'b0, "error bit must stay clear");
    axil_read(32'h00c, value);
    check(value == 32'd1, "accepted count must increment");
    axil_read(32'h020, value);
    check(value == expected_sum, "observed byte sum must match");
    axil_read(32'h024, value);
    check(value == expected_xor, "observed xor must match");
    axil_read(32'h028, value);
    check(value == payload_word(0), "first word must match");
    axil_read(32'h02c, value);
    check(value == payload_word(words - 1), "last word must match");
    axil_read(32'h030, value);
    check(value == 32'd0, "mismatch summary must be zero");
    axil_read(32'h034, value);
    check(value == payload_bytes[31:0], "written byte count must match");
    axil_read(32'h100, value);
    check(value == payload_word(0), "payload readback first word must match");

    if (errors == 0) begin
      $display("PASS: task6 PCIe rowstream loopback AXI-lite simulation");
      $finish;
    end else begin
      $display("FAIL: task6 PCIe rowstream loopback AXI-lite simulation errors %0d", errors);
      $fatal(1);
    end
  end
endmodule

`default_nettype wire
