// Shorter approximate, synthesizable CIRCT Handshake FP externs.
// Same external module names/ports and Q16.16 behavior as the prior simplified file.

package circt_fp_fixed_pkg;
  localparam logic signed [31:0]
    Q_ONE = 32'sd1  <<< 16, Q4 = 32'sd4  <<< 16, Q8 = 32'sd8  <<< 16,
    Q9    = 32'sd9  <<< 16, Q27 = 32'sd27 <<< 16, Q3_2 = 32'sd3 <<< 15;

  function automatic logic signed [31:0] sat32(input logic signed [63:0] x);
    begin
      sat32 = (x > 64'sh000000007fffffff) ? 32'sh7fffffff :
              (x < -64'sh0000000080000000) ? 32'sh80000000 : x[31:0];
    end
  endfunction

`define FP_TO_Q16_16(FN,W,EW,FW,BIAS,EMIN) \
  function automatic logic signed [31:0] FN(input logic [W-1:0] f); \
    logic sign; logic [EW-1:0] exp; logic [FW-1:0] frac; logic [FW:0] mant; \
    integer e, shift; logic signed [63:0] scaled; \
    begin \
      sign=f[W-1]; exp=f[W-2:FW]; frac=f[FW-1:0]; \
      if ((exp=='0) && (frac=='0)) FN=32'sh00000000; \
      else if (exp=={EW{1'b1}}) FN=sign ? 32'sh80000000 : 32'sh7fffffff; \
      else begin \
        mant={exp!='0,frac}; e=(exp=='0) ? EMIN : ($signed({1'b0,exp})-BIAS); shift=e-FW+16; \
        scaled=$signed({{(63-FW){1'b0}},mant}); scaled=(shift>=0) ? (scaled<<<shift) : (scaled>>>(-shift)); \
        if (sign) scaled=-scaled; FN=sat32(scaled); \
      end \
    end \
  endfunction
  `FP_TO_Q16_16(f32_to_q16_16,32,8,23,127,-126)
  `FP_TO_Q16_16(f64_to_q16_16,64,11,52,1023,-1022)
`undef FP_TO_Q16_16

  function automatic logic [31:0] q16_16_to_f32(input logic signed [31:0] q);
    logic sign; logic [63:0] mag, norm; logic [7:0] exp; integer msb, e, i;
    begin
      if (q==0) q16_16_to_f32=32'h00000000;
      else begin
        sign=q[31]; mag=sign ? $unsigned(-q) : $unsigned(q); msb=0;
        for (i=0;i<64;i=i+1) if (mag[i]) msb=i;
        e=msb-16;
        if (e>127) q16_16_to_f32={sign,8'hfe,23'h7fffff};
        else if (e<-126) q16_16_to_f32={sign,8'h00,23'h000000};
        else begin
          norm=(msb>=23) ? (mag>>(msb-23)) : (mag<<(23-msb)); exp=e+127;
          q16_16_to_f32={sign,exp,norm[22:0]};
        end
      end
    end
  endfunction

  function automatic logic signed [31:0] q_mul(input logic signed [31:0] a, input logic signed [31:0] b);
    logic signed [63:0] prod; begin prod=$signed(a)*$signed(b); q_mul=sat32(prod>>>16); end
  endfunction

  function automatic logic signed [31:0] q_div(input logic signed [31:0] a, input logic signed [31:0] b);
    logic signed [63:0] num, quo;
    begin
      if (b==0) q_div=a[31] ? 32'sh80000000 : 32'sh7fffffff;
      else begin num=$signed(a)<<<16; quo=num/$signed(b); q_div=sat32(quo); end
    end
  endfunction

`define EXP_STEP(D) term=q_mul(term,x); acc=$signed(sum)+($signed(term)/(D)); sum=sat32(acc);
  function automatic logic signed [31:0] q_exp_approx(input logic signed [31:0] x);
    logic signed [31:0] sum, term; logic signed [63:0] acc;
    begin
      if (x<=-Q8) q_exp_approx=32'sd0;
      else if (x>=Q8) q_exp_approx=32'sh7fffffff;
      else begin sum=Q_ONE; term=Q_ONE; `EXP_STEP(1) `EXP_STEP(2) `EXP_STEP(6) `EXP_STEP(24) q_exp_approx=sum; end
    end
  endfunction
`undef EXP_STEP

  function automatic logic signed [31:0] q_tanh_approx(input logic signed [31:0] x);
    logic signed [31:0] x2, num, den; logic signed [63:0] tmp;
    begin
      if (x>=Q4) q_tanh_approx=Q_ONE;
      else if (x<=-Q4) q_tanh_approx=-Q_ONE;
      else begin
        x2=q_mul(x,x); tmp=$signed(Q27)+$signed(x2); num=q_mul(x,sat32(tmp));
        tmp=$signed(Q27)+$signed(q_mul(Q9,x2)); den=sat32(tmp); q_tanh_approx=q_div(num,den);
      end
    end
  endfunction

  function automatic logic signed [31:0] q_rsqrt_approx(input logic signed [31:0] x);
    logic signed [31:0] y, y2, xy2, term; integer iter;
    begin
      if (x<=0) q_rsqrt_approx=32'sd0;
      else begin
        y=Q_ONE;
        for (iter=0;iter<3;iter=iter+1) begin
          y2=q_mul(y,y); xy2=q_mul(x,y2); term=sat32($signed(Q3_2)-($signed(xy2)>>>1)); y=q_mul(y,term);
        end
        q_rsqrt_approx=y;
      end
    end
  endfunction

  function automatic logic signed [31:0] q_powi_approx(input logic signed [31:0] x, input logic [63:0] p);
    logic signed [31:0] base, res; integer i;
    begin
      base=x; res=Q_ONE;
      for (i=0;i<64;i=i+1) begin if (p[i]) res=q_mul(res,base); base=q_mul(base,base); end
      q_powi_approx=res;
    end
  endfunction

  function automatic logic signed [31:0] q_from_s32(input logic [31:0] x);
    logic signed [63:0] wide; begin wide=$signed(x); q_from_s32=sat32(wide<<<16); end
  endfunction

  function automatic logic signed [31:0] q_roundeven(input logic signed [31:0] x);
    logic sign; logic signed [31:0] mag, int_part, rounded; logic [15:0] frac;
    begin
      sign=x[31]; mag=sign ? -x : x; int_part=mag>>>16; frac=mag[15:0];
      rounded=((frac>16'h8000)||((frac==16'h8000)&&int_part[0])) ? int_part+1 : int_part;
      q_roundeven=sign ? -sat32($signed(rounded)<<<16) : sat32($signed(rounded)<<<16);
    end
  endfunction
endpackage

`define RV1 assign out0_valid=in0_valid; assign in0_ready=out0_ready;
`define RV2 assign out0_valid=in0_valid&in1_valid; assign in0_ready=out0_ready&in1_valid; assign in1_ready=out0_ready&in0_valid;

`define M1(N,I,O,BODY) \
module N(input logic I in0, input logic in0_valid, input logic out0_ready, output logic in0_ready, output logic O out0, output logic out0_valid); \
  import circt_fp_fixed_pkg::*; BODY `RV1 \
endmodule

`define M2(N,O,EXPR) \
module N(input logic [31:0] in0, input logic in0_valid, input logic [31:0] in1, input logic in1_valid, input logic out0_ready, output logic in0_ready, output logic in1_ready, output logic O out0, output logic out0_valid); \
  import circt_fp_fixed_pkg::*; logic signed [31:0] a_q, b_q; assign a_q=f32_to_q16_16(in0); assign b_q=f32_to_q16_16(in1); assign out0=EXPR; `RV2 \
endmodule

`define UQ(N,EXPR) `M1(N,[31:0],[31:0],logic signed [31:0] x_q; assign x_q=f32_to_q16_16(in0); assign out0=q16_16_to_f32(EXPR);)
`define TO8(N,EXPR) `M1(N,[31:0],[7:0],logic signed [31:0] qv; logic signed [31:0] iv; assign qv=f32_to_q16_16(in0); assign iv=qv>>>16; assign out0=EXPR;)
`define TOF(N,I,EXPR) `M1(N,I,[31:0],assign out0=q16_16_to_f32(EXPR);)

`M2(arith_addf_in_f32_f32_out_f32,[31:0],q16_16_to_f32(sat32($signed(a_q)+$signed(b_q))))
`M2(arith_subf_in_f32_f32_out_f32,[31:0],q16_16_to_f32(sat32($signed(a_q)-$signed(b_q))))
`M2(arith_mulf_in_f32_f32_out_f32,[31:0],q16_16_to_f32(q_mul(a_q,b_q)))
`M2(arith_divf_in_f32_f32_out_f32,[31:0],q16_16_to_f32(q_div(a_q,b_q)))
`M2(arith_maximumf_in_f32_f32_out_f32,[31:0],q16_16_to_f32(($signed(a_q)>$signed(b_q)) ? a_q : b_q))
`M2(arith_cmpf_in_f32_f32_out_ui1_ogt,,($signed(a_q)>$signed(b_q)))
`M2(arith_cmpf_in_f32_f32_out_ui1_ugt,,($signed(a_q)>$signed(b_q)))
`M2(arith_cmpf_in_f32_f32_out_ui1_ult,,($signed(a_q)<$signed(b_q)))

`TO8(arith_fptosi_in_f32_out_ui8,((iv>32'sd127) ? 8'sh7f : (iv<-32'sd128) ? 8'sh80 : iv[7:0]))
`TO8(arith_fptoui_in_f32_out_ui8,((iv<=0) ? 8'h00 : (iv>=32'sd255) ? 8'hff : iv[7:0]))
`TOF(arith_sitofp_in_ui32_out_f32,[31:0],q_from_s32(in0))
`TOF(arith_uitofp_in_ui1_out_f32,,(in0 ? Q_ONE : 32'sd0))
`TOF(arith_truncf_in_f64_out_f32,[63:0],f64_to_q16_16(in0))

`UQ(math_roundeven_in_f32_out_f32,q_roundeven(x_q))
`UQ(math_exp_in_f32_out_f32,q_exp_approx(x_q))
`UQ(math_rsqrt_in_f32_out_f32,q_rsqrt_approx(x_q))
`UQ(math_tanh_in_f32_out_f32,q_tanh_approx(x_q))

module math_fpowi_in_f32_ui64_out_f32(
  input logic [31:0] in0, input logic in0_valid,
  input logic [63:0] in1, input logic in1_valid, input logic out0_ready,
  output logic in0_ready, output logic in1_ready, output logic [31:0] out0, output logic out0_valid);
  import circt_fp_fixed_pkg::*; logic signed [31:0] x_q;
  assign x_q=f32_to_q16_16(in0); assign out0=q16_16_to_f32(q_powi_approx(x_q,in1)); `RV2
endmodule

`undef RV1
`undef RV2
`undef M1
`undef M2
`undef UQ
`undef TO8
`undef TOF
