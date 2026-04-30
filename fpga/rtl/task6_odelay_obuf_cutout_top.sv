module task6_odelay_obuf_cutout_top (
  input  wire SYS_CLK,
  input  wire data_i,
  output wire data_o
);
  wire delayed;

  ODELAYE2 #(
    .CINVCTRL_SEL("FALSE"),
    .DELAY_SRC("ODATAIN"),
    .HIGH_PERFORMANCE_MODE("TRUE"),
    .ODELAY_TYPE("FIXED"),
    .ODELAY_VALUE(0),
    .PIPE_SEL("FALSE"),
    .REFCLK_FREQUENCY(200.0),
    .SIGNAL_PATTERN("DATA")
  ) odelay (
    .C(SYS_CLK),
    .CE(1'b0),
    .INC(1'b0),
    .LD(1'b0),
    .LDPIPEEN(1'b0),
    .ODATAIN(data_i),
    .DATAOUT(delayed)
  );

  OBUF obuf (
    .I(delayed),
    .O(data_o)
  );
endmodule

module task6_odelay_obufds_cutout_top (
  input  wire SYS_CLK,
  input  wire data_i,
  output wire data_p,
  output wire data_n
);
  wire delayed;

  ODELAYE2 #(
    .CINVCTRL_SEL("FALSE"),
    .DELAY_SRC("ODATAIN"),
    .HIGH_PERFORMANCE_MODE("TRUE"),
    .ODELAY_TYPE("FIXED"),
    .ODELAY_VALUE(0),
    .PIPE_SEL("FALSE"),
    .REFCLK_FREQUENCY(200.0),
    .SIGNAL_PATTERN("DATA")
  ) odelay (
    .C(SYS_CLK),
    .CE(1'b0),
    .INC(1'b0),
    .LD(1'b0),
    .LDPIPEEN(1'b0),
    .ODATAIN(data_i),
    .DATAOUT(delayed)
  );

  OBUFDS obufds (
    .I(delayed),
    .O(data_p),
    .OB(data_n)
  );
endmodule
