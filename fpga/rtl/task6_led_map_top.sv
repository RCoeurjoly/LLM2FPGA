`timescale 1ns/1ps

module task6_led_map_top(
  input logic SYS_CLK,
  input logic SYS_RSTN,
  output logic [2:0] led_3bits_tri_o
);
  logic [26:0] counter_q;

  always_ff @(posedge SYS_CLK or negedge SYS_RSTN) begin
    if (!SYS_RSTN)
      counter_q <= 27'd0;
    else
      counter_q <= counter_q + 27'd1;
  end

  always_comb begin
    unique case (counter_q[26:25])
      2'b00: led_3bits_tri_o = 3'b001;
      2'b01: led_3bits_tri_o = 3'b010;
      2'b10: led_3bits_tri_o = 3'b100;
      default: led_3bits_tri_o = 3'b111;
    endcase
  end
endmodule
