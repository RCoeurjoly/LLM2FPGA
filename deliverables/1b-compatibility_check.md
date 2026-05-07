# Tables

## Results summary

|        |                  |                                         |               |
|--------|------------------|-----------------------------------------|---------------|
| Status | Project/pipeline | Can HDL be parsed by Yosys/yosys-slang? | If HLS is use |

d, can C/C++ be compiled by FOSS HLS? \| Repo URL \| Commit \| Flow /
Tooling

| Main blockage / note | logs |
|----------------------|------|

——————————————————————–~~———————————————————————~~——————————————~~——————
—————-~~————————————————————————————————————–+————————————–\|

|                                                            |                                          |                                                                                                                       |     |
|------------------------------------------------------------|------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|-----|
| partial                                                    | deepwok/MASE                             | HDL is generated and partially parsed by yosys-slang, but elaboration fails due to missing modules (generator issue). | N/A |
| <https://github.com/RCoeurjoly/mase/tree/RCoeurjoly/flake> | bd0364fc2e6e789511d25482dcd2daa6e5605043 | Yosys + slang (SV                                                                                                     |     |

) \| Missing net<sub>\*source</sub> modules in generated top.sv \|
deliverables/1b/mase.log \|

|                  |      |                 |               |
|------------------|------|-----------------|---------------|
| ok (RTL via HLS) | TMMA | yes, via Yosys. | yes, via Pand |

A-bambu \| <https://github.com/RCoeurjoly/MatMul_SA> \|
5db3d530d6e7362192de218a2d60d5786a0a01c1 \| PandA-bambu to Ve rilog \|
Vitis headers ok via bambu; large netlist in Yosys \|
deliverables/1b/TMMA.log \|

|          |          |     |              |
|----------|----------|-----|--------------|
| rejected | LoopLynx | N/A | no realistic |

path to Yosys with open tooling without re-implementing the design. \|
<https://github.com/zjnyly/LoopLynx> \|
e74592af31d015369dd176077252914c0ed267fe \| Vendor (XRT/Vitis /Vivado)
\| Requires XRT/Vitis/Vivado; no practical open flow \| N/A \|

|          |              |     |              |
|----------|--------------|-----|--------------|
| rejected | HLSTransform | N/A | no realistic |

path to Yosys with open tooling without re-implementing the design. \|
<https://github.com/HLSTransform/submission> \|
5c7b068a1d6c6709163e2cec28cedea3ed2d7ca9 \| AWS EC2/FPGA AMI/ S3 \|
Cloud-only reference flow, contradicts local goal \| N/A \|

|                                         |                                          |                                                                                                                                                |     |
|-----------------------------------------|------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|-----|
| ok (IR only)                            | allo                                     | We achieved lowering to MLIR, and we assume it can be further lowered to Verilog, like it has been demonstrated in Torch-MLIR + CIRCT analysis | N/A |
| <https://github.com/cornell-zhang/allo> | 89d1ae33ced34df5d66be3ef2f47acee6742162a | MLIR IR + mlir-op                                                                                                                              |     |

t \| MLIR IR canonicalizes; \| N/A (see allo heading) \|

|                                                                       |                                          |                   |     |
|-----------------------------------------------------------------------|------------------------------------------|-------------------|-----|
| ok (RTL)                                                              | Torch-MLIR + CIRCT                       | yes               | N/A |
| <https://github.com/RCoeurjoly/hot-chips-2022-pytorch-circt-hls-demo> | 6e47a9a05d06463ba17e8d241e73fbd23c69781e | Torch-MLIR + CIRC |     |

T + yosys-slang \| Torch-MLIR + CIRCT + yosys-slang pipeline
demostrated, GPT2 to MLIR demostrated (SystemVerilog lowering WIP) \|
deliverables/1b/Torch-MLIR<sub>CIRCT</sub>.log \|

## Activity / popularity snapshot

| Project      | Repo URL                                     | stars | commits | last updated | Snapshot date      |
|--------------|----------------------------------------------|-------|---------|--------------|--------------------|
| deepwok/mase | <https://github.com/deepwok/mase>            | 183   | 541     | 7 months ago | \<2025-11-12 Wed\> |
| TMMA         | <https://github.com/Richielee630/TMMA>       | 23    | 34      | 8 months ago | \<2025-11-12 Wed\> |
| LoopLynx     | <https://github.com/zjnyly/LoopLynx>         | 1     | 8       | 3 weeks ago  | \<2025-11-12 Wed\> |
| HLSTransform | <https://github.com/HLSTransform/submission> | 111   | 4       | last year    | \<2025-11-12 Wed\> |
| allo         | <https://github.com/cornell-zhang/allo>      | 296   | 369     | 2 days ago   | \<2025-11-12 Wed\> |
| Torch-MLIR   | <https://github.com/llvm/torch-mlir>         | 1700  | 3531    | 20 hours ago | \<2025-11-26 Wed\> |
| CIRCT        | <https://github.com/llvm/circt>              | 2000  | 10580   | 12 hours ago | \<2025-11-26 Wed\> |
| PandA-bambu  | <https://github.com/ferrandi/PandA-bambu>    | 296   | 6300    | 6 months ago | \<2025-11-27 Thu\> |

# Deepwok/MASE

## Steps run

``` bash
git clone git@github.com:RCoeurjoly/mase.git
cd mase
git checkout RCoeurjoly/flake

# Dev env (works, not fully polished)
nix develop
source .venv/bin/activate

# Generate RTL via MASE helper
python LLM2FPGA.py

# Check outputs
ls ~/.mase

# Build yosys-slang (per its README), ensure yosys in PATH
cd ~/yosys-slang

# Elaborate with slang (SystemVerilog)
yosys -m build/slang.so -p \
  "read_slang \
     /home/roland/mase/src/mase_components/memory/rtl/fifo.sv \
     /home/roland/mase/src/mase_components/common/rtl/mux.sv \
     /home/roland/.mase/top/hardware/rtl/*.sv \
     /home/roland/mase/src/mase_components/common/rtl/single_element_repeat.sv \
     /home/roland/mase/src/mase_components/common/rtl/unpacked_register_slice.sv \
     /home/roland/mase/src/mase_components/cast/rtl/fixed_rounding.sv \
     /home/roland/mase/src/mase_components/memory/rtl/input_buffer.sv \
     /home/roland/mase/src/mase_components/memory/rtl/unpacked_skid_buffer.sv \
     /home/roland/mase/src/mase_components/cast/rtl/fixed_round.sv \
     /home/roland/mase/src/mase_components/cast/rtl/fixed_signed_cast.sv \
     /home/roland/mase/src/mase_components/cast/rtl/signed_clamp.sv \
     /home/roland/mase/src/mase_components/cast/rtl/floor_round.sv \
     /home/roland/mase/src/mase_components/memory/rtl/blk_mem_gen_0.sv \
     /home/roland/mase/src/mase_components/memory/rtl/simple_dual_port_ram.sv \
     --top top"
```

## Output

``` text
Full yosys/slang run output is intentionally omitted to keep docs conversion fast.
The run failed with hierarchy errors (net_* module misses) and SLANG warnings.
See the structured Output (summary) below for actionable results.
+end_src
** Output (summary)
- Yosys: 0.45+126 (80119386c)
- Frontend: slang (SystemVerilog)
- Errors (3): unknown module instances required by top:
  - net_0_bias_source
  - net_2_weight_source
  - net_2_bias_source
- Warnings (10): `$fatal` form (“finish argument must be 0/1/2”) — non-blocking for 1b.

** Conclusion
- Status: partially compatible.
- We can generate SystemVerilog from MASE, but Yosys+slang elaboration fails because some net_*_source modules are not generated by LLM2FPGA.py (design incomplete).
- This is a generator issue, not a limitation of Yosys or slang.
* LoopLynx
They point to https://github.com/zjnyly/TeraFly, with requires the following proprietary tools:
- XRT   2023.2
- Vitis HLS & Vivado    2023.2
** Conclusion
- Status: incompatible with the LLM2FPGA constraints.
- The published flow depends on AMD/Xilinx proprietary tooling (XRT, Vitis HLS, Vivado 2023.2).
- Reaching Yosys from this codebase would require re-implementing the hardware or replacing the entire vendor toolchain, which is outside the scope of LLM2FPGA.
* HLSTransform
Of the four prerequisites (https://github.com/HLSTransform/submission?tab=readme-ov-file#prerequisites), three are contrary to the goals of LLM2FPGA.

1. EC2 instance (z1d.2xlarge recommended), 2. AWS FPGA Developer AMI (install) and 3. S3 Bucket would lock us in a cloud environment, contrary to our purpose of local inference.
** Conclusion
- Status: incompatible with the LLM2FPGA constraints.
- The reference flow requires AWS EC2, the AWS FPGA Developer AMI and S3, which contradicts the project goal of local, open-source inference without cloud lock-in.
- No attempt was made to reproduce their cloud-based flow; instead, the incompatibility is at the environment/tooling level.
* allo
Allo has 4 backends:
- LLVM (CPU)
- AMD Vitis HLS (FPGA)
- RapidStream TAPA (FPGA)
  - Requires Vitis HLS (https://github.com/rapidstream-org/rapidstream-tapa?tab=readme-ov-file#prerequisites)
- Multi-Threaded Simulator (CPU)
- AMD MLIR-AIE (AI Engine)
  - Targets AMD AI Engine-enabled devices, not FPGAs (https://github.com/Xilinx/mlir-aie/tree/main?tab=readme-ov-file)

The only one that we can consider for our purposes is LLVM.

We install allo with docker (https://cornell-zhang.github.io/allo/setup/index.html#install-from-docker)

inside docker, we first tutorial:
python tutorials/tutorial_01_get_started.py

We copy that resulting IR to tut.ir:
module {
  func.func @gemm(%arg0: memref<32x32xi32>, %arg1: memref<32x32xi32>) -> memref<32x32xi32> attributes {itypes = "ss", otypes = "s"} {
    %c0_i32 = arith.constant 0 : i32
    %c0_i32_0 = arith.constant 0 : i32
    %alloc = memref.alloc() {name = "C"} : memref<32x32xi32>
    linalg.fill ins(%c0_i32_0 : i32) outs(%alloc : memref<32x32xi32>)
    affine.for %arg2 = 0 to 32 {
      affine.for %arg3 = 0 to 32 {
        affine.for %arg4 = 0 to 32 {
          %0 = affine.load %arg0[%arg2, %arg4] {from = "A"} : memref<32x32xi32>
          %1 = affine.load %arg1[%arg4, %arg3] {from = "B"} : memref<32x32xi32>
          %2 = arith.extsi %0 : i32 to i64
          %3 = arith.extsi %1 : i32 to i64
          %4 = arith.muli %2, %3 : i64
          %5 = affine.load %alloc[%arg2, %arg3] {from = "C"} : memref<32x32xi32>
          %6 = arith.extsi %5 : i32 to i65
          %7 = arith.extsi %4 : i64 to i65
          %8 = arith.addi %6, %7 : i65
          %9 = arith.trunci %8 : i65 to i32
          affine.store %9, %alloc[%arg2, %arg3] {to = "C"} : memref<32x32xi32>
        } {loop_name = "k"}
      } {loop_name = "j"}
    } {loop_name = "i", op_name = "S_i_j_k_0"}
    return %alloc : memref<32x32xi32>
  }
}

We try to canonicalize, to see if the MLIR + CIRCT can apply to allo:
nix shell "github:NixOS/nixpkgs/ee09932cedcef15aaf476f9343d1dea2cb77e261#llvmPackages_21.mlir" -c mlir-opt tut.ir   -canonicalize   -cse   -o allo_canonical.mlir

Success!!
* TMMA
https://github.com/Richielee630/TMMA/tree/main?tab=readme-ov-file#-ongoing-research--work-in-progress

The accelerator resides in the git submodule https://github.com/Richielee630/MatMul_SA

It requires Vitis HSL to compile:

https://github.com/Richielee630/MatMul_SA?tab=readme-ov-file#example

Vitis HSL is freeware, not open source
https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools.html

https://adaptivesupport.amd.com/s/article/Xilinx-Licensing-Solution-Center?language=en_US

There are open source HLS tools:
https://github.com/ymherklotz/vericert, but the headers in MatMul_SA are vitis specific

https://github.com/Richielee630/MatMul_SA/blob/main/mmult_accel.cpp#L1

We try elaboration with panda bambu.

My work resides on the fork: https://github.com/RCoeurjoly/MatMul_SA

** panda bambu

../PandA-bambu/bambu.AppImage --generate-interface=INFER mmult_accel.cpp --top-fname=mmult_accel
 ==  Bambu executed with: /tmp/.mount_bambu.hm7Z7N/usr/bin/bambu --generate-interface=INFER --top-fname=mmult_accel mmult_accel.cpp

#+begin_src text
The full Bambu and Yosys logs are intentionally omitted to keep repository docs conversion fast.

Observed outcome:
- Bambu produced `mmult_accel.v` and associated files under `HLS_output/`.
- `array_ref_*.mem` files were emitted; `array.mem` and `array_a.mem` were sourced from those outputs.
- Yosys succeeded on the generated Verilog and produced a very large kernel-level netlist.
- Final scale numbers were very large (~2.8M wires, ~14M wire bits, ~2.7M cells, ~2.4M multiplexers/logic terms).
- CPU time for full Yosys elaboration was multi-thousand seconds in local profiling.
```

## Conclusion

- Status: compatible at kernel level via open-source HLS.

- The Vitis-HLS-based kernel mmult<sub>accel</sub>.cpp can be
  synthesized with PandA-bambu (2024.10) to Verilog
  (mmult<sub>accel</sub>.v) using the command:

  ``` bash
  ../PandA-bambu/bambu.AppImage --generate-interface=INFER mmult_accel.cpp --top-fname=mmult_accel
  ```

- Yosys 0.45 can parse and elaborate mmult<sub>accel</sub>.v, after
  providing the expected \*.mem files (array.mem,
  array<sub>a</sub>.mem). The resulting netlist is large but valid:

  - ~2.8M wires, ~14M wire bits.
  - ~2.7M cells (≈1.16M \$mux, ≈1.0M \$and, ≈249k \$dffe, etc.).
  - No \$mem cells (Bambu emitted only flop-based logic, no inferred
    RAMs).

- This demonstrates that an open-source HLS path (PandA-bambu -\>
  Verilog -\> Yosys) exists for TMMA’s core accelerator, without relying
  on Vitis HLS.

# Torch-MLIR + CIRCT

The compatibility check lives here:
<https://github.com/RCoeurjoly/hot-chips-2022-pytorch-circt-hls-demo>

To run it reproducibly, you have to install 2 tools:

- Torch-MLIR
  <https://github.com/llvm/torch-mlir?tab=readme-ov-file#install-torch-mlir-snapshot>:
  I followed virtual environment route.
- CIRCT: <https://github.com/dtzSiFive/circt-nix>, just do nix build

I achieved a PyTorch to SystemVerilog pipeline, and the SystemVerilog
was processed successfully with yosys-slang.

The pipeline had to be updated with respect to upstream
(<https://github.com/mikeurbach/hot-chips-2022-pytorch-circt-hls-demo>)
because the tools it used were outdated:

- CIRCT-HLS (<https://github.com/circt-hls/circt-hls>) is no longer
  maintained and the developers recomend using CIRCT directly.
- Polygeist (<https://github.com/llvm/Polygeist>) has not been
  maintained for a year.

The pipeline
(<https://github.com/RCoeurjoly/hot-chips-2022-pytorch-circt-hls-demo/blob/main/my-demo.sh>)
consists of successive lowering from PyTorch to SystemVerilog.

I have also attempted to lower GPT2, a 120M (124439808) parameter model.

Torch-MLIR successfully lowers GPT2 to MLIR, but more work is needed for
lowering to SystemVerilog, mainly choosing the right transforms/passes.

## Conclusion

- Status: compatible (for small kernels), scalable WIP.
- A PyTorch -\> MLIR -\> SystemVerilog pipeline exists (in my fork) and
  the generated SV elaborates successfully with yosys-slang for the demo
  kernels.
- Torch-MLIR can lower GPT-2 (120M parameters) to MLIR, but the CIRCT
  lowering to SystemVerilog is not yet complete; more work is needed on
  the pass pipeline.
