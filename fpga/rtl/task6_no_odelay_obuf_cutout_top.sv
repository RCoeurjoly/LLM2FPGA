module task6_no_odelay_obuf_cutout_top (
  input  wire SYS_CLK,
  input  wire data_i,
  output wire data_o
);
  OBUF obuf (
    .I(data_i),
    .O(data_o)
  );
endmodule

module task6_no_odelay_obufds_cutout_top (
  input  wire SYS_CLK,
  input  wire data_i,
  output wire data_p,
  output wire data_n
);
  OBUFDS obufds (
    .I(data_i),
    .O(data_p),
    .OB(data_n)
  );
endmodule
