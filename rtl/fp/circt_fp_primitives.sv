// Minimal blackbox stubs for CIRCT-exported floating-point primitive modules.
// These let Yosys parse the generated SystemVerilog when FP extern modules
// are not provided by a backend library.

(* blackbox *)
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
endmodule

(* blackbox *)
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
endmodule

(* blackbox *)
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
endmodule

(* blackbox *)
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
endmodule

(* blackbox *)
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
endmodule

(* blackbox *)
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
endmodule

(* blackbox *)
module arith_truncf_in_f64_out_f32 (
  input  logic [63:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
endmodule

(* blackbox *)
module math_exp_in_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
endmodule

(* blackbox *)
module math_rsqrt_in_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
endmodule

(* blackbox *)
module math_tanh_in_f32_out_f32 (
  input  logic [31:0] in0,
  input  logic        in0_valid,
  input  logic        out0_ready,
  output logic        in0_ready,
  output logic [31:0] out0,
  output logic        out0_valid
);
endmodule

(* blackbox *)
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
endmodule
