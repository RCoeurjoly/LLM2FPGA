// Approximate, synthesizable FP primitive implementations used to materialize
// CIRCT Handshake floating-point extern modules.
//
// These modules avoid blackboxes and provide deterministic arithmetic on
// float-encoded bit patterns via a fixed-point (Q16.16) approximation.

package circt_fp_fixed_pkg;
  function automatic logic signed [31:0] sat32(input logic signed [63:0] x);
    begin
      if (x > 64'sh000000007fffffff)
        sat32 = 32'sh7fffffff;
      else if (x < -64'sh0000000080000000)
        sat32 = 32'sh80000000;
      else
        sat32 = x[31:0];
    end
  endfunction

  function automatic logic signed [31:0]
      f32_to_q16_16(input logic [31:0] f);
    logic sign;
    logic [7:0] exp;
    logic [22:0] frac;
    logic [23:0] mant;
    integer e;
    integer shift;
    logic signed [63:0] scaled;
    begin
      sign = f[31];
      exp = f[30:23];
      frac = f[22:0];
      if ((exp == 8'h00) && (frac == 23'h0)) begin
        f32_to_q16_16 = 32'sh00000000;
      end else if (exp == 8'hff) begin
        f32_to_q16_16 = sign ? 32'sh80000000 : 32'sh7fffffff;
      end else begin
        if (exp == 8'h00) begin
          mant = {1'b0, frac};
          e = -126;
        end else begin
          mant = {1'b1, frac};
          e = $signed({1'b0, exp}) - 127;
        end
        shift = e - 23 + 16;
        scaled = $signed({40'b0, mant});
        if (shift >= 0)
          scaled = scaled <<< shift;
        else
          scaled = scaled >>> (-shift);
        if (sign)
          scaled = -scaled;
        f32_to_q16_16 = sat32(scaled);
      end
    end
  endfunction

  function automatic logic signed [31:0]
      f64_to_q16_16(input logic [63:0] f);
    logic sign;
    logic [10:0] exp;
    logic [51:0] frac;
    logic [52:0] mant;
    integer e;
    integer shift;
    logic signed [63:0] scaled;
    begin
      sign = f[63];
      exp = f[62:52];
      frac = f[51:0];
      if ((exp == 11'h000) && (frac == 52'h0)) begin
        f64_to_q16_16 = 32'sh00000000;
      end else if (exp == 11'h7ff) begin
        f64_to_q16_16 = sign ? 32'sh80000000 : 32'sh7fffffff;
      end else begin
        if (exp == 11'h000) begin
          mant = {1'b0, frac};
          e = -1022;
        end else begin
          mant = {1'b1, frac};
          e = $signed({1'b0, exp}) - 1023;
        end
        shift = e - 52 + 16;
        scaled = $signed({11'b0, mant});
        if (shift >= 0)
          scaled = scaled <<< shift;
        else
          scaled = scaled >>> (-shift);
        if (sign)
          scaled = -scaled;
        f64_to_q16_16 = sat32(scaled);
      end
    end
  endfunction

  function automatic logic [31:0]
      q16_16_to_f32(input logic signed [31:0] q);
    logic sign;
    logic [63:0] mag;
    logic [63:0] norm;
    logic [7:0] exp;
    logic [22:0] frac;
    integer msb;
    integer e;
    integer i;
    integer found;
    logic signed [31:0] q_local;
    begin
      q_local = q;
      if (q_local == 0) begin
        q16_16_to_f32 = 32'h00000000;
      end else begin
        sign = q_local[31];
        if (sign)
          mag = $unsigned(-q_local);
        else
          mag = $unsigned(q_local);

        msb = 0;
        found = 0;
        for (i = 63; i >= 0; i = i - 1) begin
          if ((found == 0) && mag[i]) begin
            msb = i;
            found = 1;
          end
        end

        if (found == 0) begin
          q16_16_to_f32 = 32'h00000000;
        end else begin
          e = msb - 16;
          if (e > 127) begin
            q16_16_to_f32 = {sign, 8'hfe, 23'h7fffff};
          end else if (e < -126) begin
            q16_16_to_f32 = {sign, 8'h00, 23'h000000};
          end else begin
            if (msb >= 23)
              norm = mag >> (msb - 23);
            else
              norm = mag << (23 - msb);
            exp = e + 127;
            frac = norm[22:0];
            q16_16_to_f32 = {sign, exp, frac};
          end
        end
      end
    end
  endfunction

  function automatic logic signed [31:0]
      q_mul(input logic signed [31:0] a, input logic signed [31:0] b);
    logic signed [63:0] prod;
    begin
      prod = $signed(a) * $signed(b);
      q_mul = sat32(prod >>> 16);
    end
  endfunction

  function automatic logic signed [31:0]
      q_div(input logic signed [31:0] a, input logic signed [31:0] b);
    logic signed [63:0] num;
    logic signed [63:0] quo;
    begin
      if (b == 0) begin
        q_div = a[31] ? 32'sh80000000 : 32'sh7fffffff;
      end else begin
        num = $signed(a) <<< 16;
        quo = num / $signed(b);
        q_div = sat32(quo);
      end
    end
  endfunction

  function automatic logic signed [31:0]
      q_exp_approx(input logic signed [31:0] x);
    logic signed [31:0] sum;
    logic signed [31:0] term;
    logic signed [63:0] acc;
    begin
      if (x <= -(32'sd8 <<< 16)) begin
        q_exp_approx = 32'sd0;
      end else if (x >= (32'sd8 <<< 16)) begin
        q_exp_approx = 32'sh7fffffff;
      end else begin
        sum = (32'sd1 <<< 16);
        term = (32'sd1 <<< 16);

        term = q_mul(term, x);
        acc = $signed(sum) + $signed(term);
        sum = sat32(acc);

        term = q_mul(term, x);
        acc = $signed(sum) + ($signed(term) / 2);
        sum = sat32(acc);

        term = q_mul(term, x);
        acc = $signed(sum) + ($signed(term) / 6);
        sum = sat32(acc);

        term = q_mul(term, x);
        acc = $signed(sum) + ($signed(term) / 24);
        sum = sat32(acc);

        q_exp_approx = sum;
      end
    end
  endfunction

  function automatic logic signed [31:0]
      q_tanh_approx(input logic signed [31:0] x);
    logic signed [31:0] x2;
    logic signed [31:0] num;
    logic signed [31:0] den;
    logic signed [63:0] tmp;
    begin
      if (x >= (32'sd4 <<< 16)) begin
        q_tanh_approx = (32'sd1 <<< 16);
      end else if (x <= -(32'sd4 <<< 16)) begin
        q_tanh_approx = -(32'sd1 <<< 16);
      end else begin
        x2 = q_mul(x, x);
        tmp = $signed(32'sd27 <<< 16) + $signed(x2);
        num = q_mul(x, sat32(tmp));
        tmp = $signed(32'sd27 <<< 16) + $signed(q_mul(32'sd9 <<< 16, x2));
        den = sat32(tmp);
        q_tanh_approx = q_div(num, den);
      end
    end
  endfunction

  function automatic logic signed [31:0]
      q_rsqrt_approx(input logic signed [31:0] x);
    logic signed [31:0] y;
    logic signed [31:0] y2;
    logic signed [31:0] xy2;
    logic signed [31:0] term;
    integer iter;
    begin
      if (x <= 0) begin
        q_rsqrt_approx = 32'sd0;
      end else begin
        y = (32'sd1 <<< 16);
        for (iter = 0; iter < 3; iter = iter + 1) begin
          y2 = q_mul(y, y);
          xy2 = q_mul(x, y2);
          term = sat32($signed(32'sd3 <<< 15) - ($signed(xy2) >>> 1));
          y = q_mul(y, term);
        end
        q_rsqrt_approx = y;
      end
    end
  endfunction

  function automatic logic signed [31:0]
      q_powi_approx(input logic signed [31:0] x, input logic [63:0] p);
    logic [63:0] exp_work;
    logic signed [31:0] base;
    logic signed [31:0] res;
    integer i;
    begin
      exp_work = p;
      base = x;
      res = (32'sd1 <<< 16);
      for (i = 0; i < 64; i = i + 1) begin
        if (exp_work[0])
          res = q_mul(res, base);
        exp_work = exp_work >> 1;
        base = q_mul(base, base);
      end
      q_powi_approx = res;
    end
  endfunction
endpackage

module arith_addf_in_f32_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic [31:0] in1,
  input  logic        in1_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic        in1_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] a_q;
  logic signed [31:0] b_q;
  logic signed [31:0] r_q;
  always_comb begin
    a_q = f32_to_q16_16(in0);
    b_q = f32_to_q16_16(in1);
    r_q = sat32($signed(a_q) + $signed(b_q));
  end
  assign out0 = q16_16_to_f32(r_q);
  assign out0_valid = in0_valid & in1_valid;
  assign in0_ready = out0_ready & in1_valid;
  assign in1_ready = out0_ready & in0_valid;
endmodule

module arith_subf_in_f32_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic [31:0] in1,
  input  logic        in1_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic        in1_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] a_q;
  logic signed [31:0] b_q;
  logic signed [31:0] r_q;
  always_comb begin
    a_q = f32_to_q16_16(in0);
    b_q = f32_to_q16_16(in1);
    r_q = sat32($signed(a_q) - $signed(b_q));
  end
  assign out0 = q16_16_to_f32(r_q);
  assign out0_valid = in0_valid & in1_valid;
  assign in0_ready = out0_ready & in1_valid;
  assign in1_ready = out0_ready & in0_valid;
endmodule

module arith_mulf_in_f32_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic [31:0] in1,
  input  logic        in1_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic        in1_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] a_q;
  logic signed [31:0] b_q;
  logic signed [31:0] r_q;
  always_comb begin
    a_q = f32_to_q16_16(in0);
    b_q = f32_to_q16_16(in1);
    r_q = q_mul(a_q, b_q);
  end
  assign out0 = q16_16_to_f32(r_q);
  assign out0_valid = in0_valid & in1_valid;
  assign in0_ready = out0_ready & in1_valid;
  assign in1_ready = out0_ready & in0_valid;
endmodule

module arith_divf_in_f32_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic [31:0] in1,
  input  logic        in1_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic        in1_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] a_q;
  logic signed [31:0] b_q;
  logic signed [31:0] r_q;
  always_comb begin
    a_q = f32_to_q16_16(in0);
    b_q = f32_to_q16_16(in1);
    r_q = q_div(a_q, b_q);
  end
  assign out0 = q16_16_to_f32(r_q);
  assign out0_valid = in0_valid & in1_valid;
  assign in0_ready = out0_ready & in1_valid;
  assign in1_ready = out0_ready & in0_valid;
endmodule

module arith_maximumf_in_f32_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic [31:0] in1,
  input  logic        in1_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic        in1_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] a_q;
  logic signed [31:0] b_q;
  logic signed [31:0] r_q;
  always_comb begin
    a_q = f32_to_q16_16(in0);
    b_q = f32_to_q16_16(in1);
    r_q = ($signed(a_q) > $signed(b_q)) ? a_q : b_q;
  end
  assign out0 = q16_16_to_f32(r_q);
  assign out0_valid = in0_valid & in1_valid;
  assign in0_ready = out0_ready & in1_valid;
  assign in1_ready = out0_ready & in0_valid;
endmodule

module arith_cmpf_in_f32_f32_out_ui1_ogt (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic [31:0] in1,
  input  logic        in1_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic        in1_ready,
  output logic        out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] a_q;
  logic signed [31:0] b_q;
  always_comb begin
    a_q = f32_to_q16_16(in0);
    b_q = f32_to_q16_16(in1);
  end
  assign out0 = ($signed(a_q) > $signed(b_q));
  assign out0_valid = in0_valid & in1_valid;
  assign in0_ready = out0_ready & in1_valid;
  assign in1_ready = out0_ready & in0_valid;
endmodule

module arith_truncf_in_f64_out_f32 (
  input  logic [63:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] qv;
  always_comb begin
    qv = f64_to_q16_16(in0);
  end
  assign out0 = q16_16_to_f32(qv);
  assign out0_valid = in0_valid;
  assign in0_ready = out0_ready;
endmodule

module math_exp_in_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] x_q;
  logic signed [31:0] y_q;
  always_comb begin
    x_q = f32_to_q16_16(in0);
    y_q = q_exp_approx(x_q);
  end
  assign out0 = q16_16_to_f32(y_q);
  assign out0_valid = in0_valid;
  assign in0_ready = out0_ready;
endmodule

module math_rsqrt_in_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] x_q;
  logic signed [31:0] y_q;
  always_comb begin
    x_q = f32_to_q16_16(in0);
    y_q = q_rsqrt_approx(x_q);
  end
  assign out0 = q16_16_to_f32(y_q);
  assign out0_valid = in0_valid;
  assign in0_ready = out0_ready;
endmodule

module math_tanh_in_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] x_q;
  logic signed [31:0] y_q;
  always_comb begin
    x_q = f32_to_q16_16(in0);
    y_q = q_tanh_approx(x_q);
  end
  assign out0 = q16_16_to_f32(y_q);
  assign out0_valid = in0_valid;
  assign in0_ready = out0_ready;
endmodule

module math_fpowi_in_f32_ui64_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic [63:0] in1,
  input  logic        in1_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic        in1_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
  import circt_fp_fixed_pkg::*;
  logic signed [31:0] x_q;
  logic signed [31:0] y_q;
  always_comb begin
    x_q = f32_to_q16_16(in0);
    y_q = q_powi_approx(x_q, in1);
  end
  assign out0 = q16_16_to_f32(y_q);
  assign out0_valid = in0_valid & in1_valid;
  assign in0_ready = out0_ready & in1_valid;
  assign in1_ready = out0_ready & in0_valid;
endmodule
