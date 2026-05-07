# Notes

### Promissing projects

1.  chosys

    <https://github.com/hm-aemy/chosys> may be helpful

    \## Current Status and Roadmap

    In a first step, support for a limited number of \`seq\` and
    \`comb\` operations for RTLIL is implemented to demonstrate the
    working principal. Support for more operations will be added over
    time.

    <https://github.com/hm-aemy/circt/pull/5/changes>

2.  openhls

    <https://github.com/makslevental/openhls>

    specially flopoco/ - functionality related to converting between
    FloPoCo's nonstandard floating point representation and IEEE754 (for
    purposes of RTL generation and simulation)

## Build all derivations

system=\$(nix eval –impure –raw –expr builtins.currentSystem) nix eval
–json ".#packages.\${system}" \| jq -r 'keys\[\] \| select(. != "all")
\| ".#" + .' \| xargs -r nix build

## update circt-src

nix flake update circt-nix/circt-src

# 3: lowering TinyStories

## dealing with floats

There seems to be two approaches to dealing with this:

- quantization (Quantization is

the process of mapping continuous or high-precision values (e.g., 32-bit
floating-point) to a smaller set of discrete, lower-precision values
(e.g., 8-bit integers))

- lowering model semantics into simpler integer-only operations before
  the CIRCT / Yosys stages.

# <span class="done DONE">DONE</span> 2d: bitstream generation and programming

- State "DONE" from \[2026-03-05 Thu 12:18\]

## nix effort

### WAIT nextpnr-xilinx

- State "WAIT" from "TODO<sub>NEXT</sub>" \[2026-02-25 Wed 23:36\]
- State "TODO<sub>NEXT</sub>" from \[2026-02-25 Wed 22:38\]

### WAIT torch-MLIR

- State "WAIT" from \[2026-02-25 Wed 22:38\]

1.  WAIT build locally

    - State "WAIT" from "TODO<sub>NEXT</sub>" \[2026-02-25 Wed 22:35\]
    - State "TODO<sub>NEXT</sub>" from \[2026-02-25 Wed 22:35\]

## Toolchain status update \[2026-02-25 Wed\]

We currently have changes in both upstream components:

- \`toolchain-nix\` (openXC7 integration path used by this project)
- \`nextpnr-xilinx\` (customized fork/branch used for current bitstream
  flow)

These should be treated as active dependencies of the current 2d flow
and kept in sync with this repo configuration.

We are hitting a segfault in nextpnr-xilinx

### Upstreaming effort

<https://github.com/openXC7/toolchain-nix/issues/7>

## nextpnr-xilinx segfault

### command

### backtrace

Program received signal SIGSEGV, Segmentation fault.
nextpnr<sub>xilinx</sub>::XilinxPacker::pack<sub>constants</sub>
(this=0x7fffffffc770) at /home/roland/nextpnr-xilinx/xilinx/pack.cc:503
503 if (ni-\>driver.cell != nullptr && ni-\>driver.cell-\>type ==
ctx-\>id("GND")) { (gdb) bt \#0
nextpnr<sub>xilinx</sub>::XilinxPacker::pack<sub>constants</sub>
(this=0x7fffffffc770) at /home/roland/nextpnr-xilinx/xilinx/pack.cc:503
\#1 0x00000000005d1247 in nextpnr<sub>xilinx</sub>::Arch::pack
(this=0x6e3340) at /home/roland/nextpnr-xilinx/xilinx/pack.cc:934 \#2
0x000000000043863d in
nextpnr<sub>xilinx</sub>::CommandHandler::executeMain
(this=0x7fffffffcdf0,
ctx=std::unique<sub>ptr</sub>\<nextpnr<sub>xilinx</sub>::Context\> =
{…}) at
/nix/store/14c6s4xzhy14i2b05s00rjns2j93gzz4-gcc-13.2.0/include/c++/13.2.0/bits/unique<sub>ptr</sub>.h:199
\#3 0x000000000043a7f0 in nextpnr<sub>xilinx</sub>::CommandHandler::exec
(this=this@entry=0x7fffffffcdf0) at
/nix/store/14c6s4xzhy14i2b05s00rjns2j93gzz4-gcc-13.2.0/include/c++/13.2.0/bits/unique<sub>ptr</sub>.h:197
\#4 0x00000000004310e4 in main (argc=\<optimized out\>, argv=\<optimized
out\>) at /home/roland/nextpnr-xilinx/xilinx/main.cc:91

## debugging

(gdb) p net \$22 = { first = { index = 115644 }, second = 0x0 }

Is the index always the same? yes

b nextpnr<sub>xilinx</sub>::BaseCtx::createNet if name.index == 115644 b
common/design<sub>utils</sub>.cc:164 if (net && (net-\>name.index ==
115644 \|\| new<sub>name</sub>.index == 115644)) b xilinx/pack.cc:556 if
(old.index == 115644 \|\| newname.index == 115644) b xilinx/pack.cc:559
if (newname.index == 115644)

## building nextpnr-xilinx with debug symbols

in toolchain-nix, do nix develop .#nextpnr-xilinx

## Cable for board

### board

YPCB-00338-1P1

<https://www.cnblogs.com/ruidongwu/p/18564807>

<https://x.com/enjoy_digital/status/1924910401176719375>

<https://www.controlpaths.com/2025/05/18/kintex7-accelerator/>

<https://github.com/litex-hub/litex-boards/commit/6d58ae6b31d80b255de12c2d3f5bfefda4c38b90>

<https://github.com/trabucayre/openFPGALoader/pull/537>

## building nextpnr-xilinx with src overriden with my local clone

nix build –impure –expr ' let flake = builtins.getFlake (toString ./.);
system = builtins.currentSystem; in
(flake.packages.\${system}.nextpnr-xilinx.overrideAttrs (\_: { src =
/home/roland/nextpnr-xilinx; })).outPath '

# CANCELED 2a LLM lowering: tiny stories 1M

- State "CANCELED" from \[2026-02-25 Wed 18:57\]

## TODO<sub>NEXT</sub> Goal: lowering the smallest LLM to RTL using the selected route (Torch-MLIR + CIRCT)

- State "TODO<sub>NEXT</sub>" from \[2025-12-31 Wed 17:08\]

cd source mlir<sub>venv</sub>/bin/activate cd
hot-chips-2022-pytorch-circt-hls-demo/TinyStories/ nix shell
"github:NixOS/nixpkgs/346dd96ad74dc4457a9db9de4f4f57dab2e5731d#llvmPackages<sub>21</sub>.mlir"
-c ./demo.sh

nix shell
"github:NixOS/nixpkgs/ee09932cedcef15aaf476f9343d1dea2cb77e261#llvmPackages<sub>21</sub>.mlir"
-c ./demo.sh

### TODO<sub>NEXT</sub> Debug flatten-memref crash

- State "TODO<sub>NEXT</sub>" from \[2025-12-27 Sat 21:46\]

1.  TODO<sub>NEXT</sub> dot-cf.mlir:112:3: error: failed to legalize
    operation 'func.func' that was explicitly marked illegal

    - State "TODO<sub>NEXT</sub>" from \[2026-01-02 Fri 20:19\]

    2: memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg3: memref\<f32, strided\<\[\], offset: ?\>\>, %arg4:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg5: memref\<f32, strided \<\[\], offset: ?\>\>, %arg6:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg7: memref\<f32, strided\<\[\], offset: ?\>\>, %arg8:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg 9: memref\<f32, strided\<\[\], offset: ?\>\>, %arg10:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg11: memref\<f32, strided\<\[\], offset: ?\>\>, %arg12:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg13: memref\<f32, strided\<\[\], offset: ?\>\>, %arg14:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg15: memref\<f32, strided\<\[\], offset: ?\>\>, %arg16:
    memref\<1x6xi6 4, strided\<\[?, ?\], offset: ?\>\>, %arg17:
    memref\<1x6x50257xf32\>) { ^ dot-cf.mlir:112:3: note: see current
    operation: "func.func"() \<{function<sub>type</sub> =
    (memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    memref\<f32, strided\<\[\], offset: ?\>\>, memref\<1x1x2048x2048xi1,
    strided\<\[?, ?, ?, ?\], offset: ?\>\>, memref\<f32 , strided\<\[\],
    offset: ?\>\>, memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\],
    offset: ?\>\>, memref\<f32, strided\<\[\], offset: ?\>\>,
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    memref\<f32, stri ded\<\[\], offset: ?\>\>,
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    memref\<f32, strided\<\[\], offset: ?\>\>, memref\<1x1x2048x2048xi1,
    strided\<\[?, ?, ?, ?\], offset: ?\>\>, memref\<f32, strided\<\[\] ,
    offset: ?\>\>, memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\],
    offset: ?\>\>, memref\<f32, strided\<\[\], offset: ?\>\>,
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    memref\<f32, strided\<\[\], offs et: ?\>\>, memref\<1x6xi64,
    strided\<\[?, ?\], offset: ?\>\>, memref\<1x6x50257xf32\>) -\> (),
    sym<sub>name</sub> = "main"}\> ({ <sup>bb0</sup>(%arg0:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg1: memref\<f32, strided\<\[\], offset: ?\>\>, %arg2:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg3: memref\<f32 , strided\<\[\], offset: ?\>\>, %arg4:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg5: memref\<f32, strided\<\[\], offset: ?\>\>, %arg6:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg7: memref\<f32, strided\<\[\], offset: ?\>\>, %arg8:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg9: memref\<f32, strided\<\[\], offset: ?\>\>, %arg10:
    memref\<1x1x2048x2048xi1, strided \<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg11: memref\<f32, strided\<\[\], offset: ?\>\>, %arg12:
    memref\<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>,
    %arg13: memref\<f32, strided\<\[\], offset: ?\>\>, %arg14: memref
    \<1x1x2048x2048xi1, strided\<\[?, ?, ?, ?\], offset: ?\>\>, %arg15:
    memref\<f32, strided\<\[\], offset: ?\>\>, %arg16: memref\<1x6xi64,
    strided\<\[?, ?\], offset: ?\>\>, %arg17: memref\<1x6x50257xf32\>):

2.  <span class="done DONE">DONE</span> keep flatten-memref, fix the
    memref.global + dense<sub>resource</sub> gap

    - State "DONE" from "TODO<sub>NEXT</sub>" \[2026-01-02 Fri 20:18\]
    - State "TODO<sub>NEXT</sub>" from \[2025-12-30 Tue 14:32\]

    1.  <span class="done DONE">DONE</span> Figure out which pass is
        failing, work with tiny.mlir

        - State "DONE" from "TODO<sub>NEXT</sub>" \[2026-01-02 Fri
          20:18\]
        - State "TODO<sub>NEXT</sub>" from \[2025-12-31 Wed 17:10\]

        home/roland/circt/build/bin/circt-opt -verify-each
        -flatten-memref tiny.mlir module { memref.global constant
        @constant<sub>2xf320</sub> : memref\<2xf32\> =
        dense<sub>resource</sub>\<r\> }

        {-# dialect<sub>resources</sub>: { builtin: { r:
        "0x400000003F80000040000000" } } \#-}

        1.  result

            flatten is failing

3.  <span class="done DONE">DONE</span> Try without flatten memref

    - State "DONE" from \[2025-12-30 Tue 14:32\]

    without -flatten-memref \\ -flatten-memref-calls \\

    we get Cannot legalize multi-dimensional memref operation
    memref.copy %alloc<sub>18</sub>, %alloc<sub>19</sub> :
    memref\<1x6x1xf32\> to memref\<1x6x1xf32\>. Please run the memref
    flattening pass before this pass.

    best to keep flatten-memref, fix the memref.global +
    dense<sub>resource</sub> gap

4.  Crash logs with reduced.mlir, with debug symbols

    The full log for this run was intentionally kept short in-repo for
    readability and conversion speed.

    ``` text
    /home/roland/circt/build/bin/circt-opt -verify-each -flatten-memref reduced.mlir
    PLEASE submit a bug report to https://github.com/llvm/circt
    Stack dump (truncated):
    0.  Program arguments: /home/roland/circt/build/bin/circt-opt -verify-each -flatten-memref reduced.mlir
    1.  llvm::sys::PrintStackTrace
    2.  SignalHandler
    3.  mlir::DenseElementsAttr::getNumElements
    4.  mlir::ConversionPattern::matchAndRewrite
    ...
    Segmentation fault (core dumped)
    ```

5.  Crash logs with demo.sh

    This crash reproduces a large backtrace from the same crash family.
    Keep the full stack in local history.

    ``` text
    PLEASE submit a bug report to https://github.com/llvm/circt
    Stack dump (truncated):
    0.  Program arguments: /home/roland/circt-nix/result/bin/circt-opt dot-cf.mlir ...
    1.  llvm::sys::PrintStackTrace
    2.  SignalHandler
    3.  mlir::DenseElementsAttr::getNumElements
    4.  mlir::applyPartialConversion
    ...
    ./demo.sh: Segmentation fault (core dumped)
    ```

6.  Crash logs with reduced.mlir

7.  <span class="done DONE">DONE</span> Reduce the failing file

    - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-12-26 Fri 20:48\]
    - State "TODO<sub>NEXT</sub>" from \[2025-12-26 Fri 19:26\]

    nix shell
    "github:NixOS/nixpkgs/ee09932cedcef15aaf476f9343d1dea2cb77e261#llvmPackages<sub>21</sub>.mlir"
    -c mlir-reduce dot-cf.mlir \\ –test='
    /home/roland/circt-nix/result/bin/circt-opt -flatten-memref' \\ -o
    reduced.mlir

    1.  result

        nix shell nixpkgs#llvmPackages.mlir -c mlir-reduce dot-cf.mlir
        -reduction-tree='traversal-mode=0 test=interesting.sh' -o
        reduced.mlir reduced.mlir, which is 25x times smaller than
        original (129k vs 30M)

    2.  Error

        nix shell
        "github:NixOS/nixpkgs/ee09932cedcef15aaf476f9343d1dea2cb77e261#llvmPackages<sub>21</sub>.mlir"
        -c mlir-reduce –help OVERVIEW: MLIR test case reduction tool.

    3.  Prompt

        Im debugging a mlir pass. The file is very big though, 30MB, so
        I want to reduce it.

8.  <span class="done DONE">DONE</span> Reproduce with latest circt

    - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-12-27 Sat 21:40\]
    - State "TODO<sub>NEXT</sub>" from \[2025-12-26 Fri 20:48\]

    1.  <span class="done DONE">DONE</span> Build latest circt: 1.138.0

        - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-12-27 Sat
          21:40\]
        - State "TODO<sub>NEXT</sub>" from \[2025-12-26 Fri 20:48\]

# <span class="done DONE">DONE</span> 1c-selected<sub>route</sub>

- State "DONE" from \[2025-12-27 Sat 21:39\]

# What is the monkey in this project?

As in monkey reciting Shakespeare on top of a pedestal.

1: Can we translate/lower an LLM to something that can target an FPGA?
There seems to be a path with Torch-MLIR + CIRCT

2: Can the smallest LLM fit into the biggest open source FPGA?

The biggest open source FPGA has been identified: XC7K480T K7-480
Kintex7 The smallest LLM also: tiny stories

The test would be to do 1 first with tiny stories, then use open source
tooling (nextpnr xilinx) to see if it fits.

## <https://hanchenye.com/streamtensor/>

<https://hanchenye.com/streamtensor/>

# <span class="done DONE">DONE</span> 1b-compatibility<sub>check</sub>

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-12-03 Wed 21:05\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-03 Mon 12:02\]

## <span class="done DONE">DONE</span> Table comparison of results

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-12-03 Wed 21:05\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-30 Sun 17:32\]

## <span class="done DONE">DONE</span> Add MLIR + CIRCT to survey table

- State "DONE" from \[2025-11-30 Sun 17:40\]

## <span class="done DONE">DONE</span> First draft

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-30 Sun 17:32\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-03 Mon 16:50\]

### <span class="done DONE">DONE</span> Torch-MLIR + CIRCT

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-30 Sun 17:32\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-23 Sun 15:07\]

1.  Miminal PyTorch: demo of PyTorch + Torch-MLIR + MLIR + CIRCT + Yosys

    <https://github.com/RCoeurjoly/hot-chips-2022-pytorch-circt-hls-demo>

    nix shell
    "github:NixOS/nixpkgs/ee09932cedcef15aaf476f9343d1dea2cb77e261#llvmPackages<sub>21</sub>.mlir"
    -c ./my-demo.sh

2.  CANCELED Fix CIRCT

    - State "CANCELED" from \[2025-11-25 Tue 13:02\]

    build failed nix log
    /nix/store/vkv5q65dmpf7n4xza3kinzgbpalzglwf-circt-1.137.0g20251124<sub>2eb32a1</sub>.drv

3.  <span class="done DONE">DONE</span> Prompt for debugging

    - State "DONE" from "CANCELED" \[2025-11-25 Tue 13:02\]
    - State "CANCELED" from \[2025-11-25 Tue 13:02\]

    My goal is to get Verilog or SystemVerilog out of PyTorch +
    Torch-MLIR + MLIR + CIRCT

    Attached relevant files.

    This is the error I am currently getting:

    How to fix?

4.  <span class="done DONE">DONE</span> my-dot-handshake.mlir:2:3:
    error: 'handshake.func' op expected that block argument \#2 is used
    by an 'extmemory' operation

    - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-24 Mon 18:34\]
    - State "TODO<sub>NEXT</sub>" from \[2025-11-24 Mon 18:18\]
      handshake.func @main(%arg0: memref\<16xi32\>, %arg1:
      memref\<16xi32\>, %arg2: memref\<16xi32\>, %arg3: none, …) -\>
      none attributes {argNames = \["in0", "in1", "in2", "in3"\],
      resNames = \["out0"\]} { ^

    1.  Things tried

        1.  Added –memref-expand and –buffer-deallocation-pipeline \\ to
            step 3

            echo "### 3) Linalg → CF (CIRCT-compatible bufferization)"
            \$MLIR<sub>OPT</sub> my-dot-linalg.mlir \\
            –empty-tensor-to-alloc-tensor \\
            –one-shot-bufferize="bufferize-function-boundaries" \\
            –buffer-deallocation-pipeline \\
            –buffer-results-to-out-params \\ –memref-expand \\
            –convert-linalg-to-affine-loops \\ –lower-affine \\
            –convert-scf-to-cf \\

            Same error

        2.  removing –buffer-results-to-out-params, I get different
            errors

### 4) CF → Handshake

``` text
my-dot-handshake.mlir:121:14: error: unsupported data type memref<16xi32> %alloc = memref.alloc() : memref<16xi32>
... repeated memref alloc failures while lowering to HW ...
circt-opt: /build/source/lib/Conversion/HandshakeToHW/HandshakeToHW.cpp:711: createZeroDataConst assertion failed
Stack dump (truncated):
#0 llvm::sys::PrintStackTrace(...)
#1 SignalHandler(...)
#2 __restore_rt
...
The command was aborted (core dumped)
```

1.  removing -handshake-insert-buffers="strategy=all", I get

    \### 5) Handshake → HW my-dot-handshake.mlir:2:3: error: 'hw.output'
    op output types must match module. In operand 0, expected
    '!esi.channel\<memref\<16xi32\>\>', but got 'memref\<16xi32\>'.
    handshake.func @main(%arg0: memref\<16xi32\>, %arg1:
    memref\<16xi32\>, %arg2: none, …) -\> (memref\<16xi32\>, none)
    attributes {argNames = \["in0", "in1", "in2"\], resNames = \["out0",
    "out1"\]} { ^ my-dot-handshake.mlir:2:3: note: see current
    operation: "hw.output"(%164, %184#1, %9, %6) : (memref\<16xi32\>,
    !esi.channel\<i0\>, !esi.channel\<i4\>, !esi.channel\<i4\>) -\> ()

2.  CANCELED my-dot-cf.mlir:2:19: error: memref's must be both
    statically sized and unidimensional.

    - State "CANCELED" from "TODO<sub>NEXT</sub>" \[2025-11-24 Mon
      18:18\]
    - State "TODO<sub>NEXT</sub>" from \[2025-11-24 Mon 16:14\]
      func.func @main(%arg0: memref\<4x4xi32, strided\<\[?, ?\], offset:
      ?\>\>, %arg1: memref\<4x4xi32, strided\<\[?, ?\], offset: ?\>\>,
      %arg2: memref\<4x4xi32\>) { ^

### <span class="done DONE">DONE</span> LoopLynx: <https://github.com/zjnyly/LoopLynx?tab=readme-ov-file>

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-30 Sun 17:32\]

- State "TODO<sub>NEXT</sub>" from \[2025-11-03 Mon 12:06\] They point
  to <https://github.com/zjnyly/TeraFly?tab=readme-ov-file>

  Which in turn point to llama fpga
  <https://github.com/adamgallas/llama-fpga>

1.  llama fpga

    my board: Kintex7 480T Placa de desarrollo FPGA XC7K480T K7-480
    Kintex7 PCIE X8 4G YZCA-00338 \#T5-

    <https://www.ebay.es/itm/376208176272?chn=ps&norover=1&mkevt=1&mkrid=1185-171098-620544-2&mkcid=2&mkscid=101&itemid=376208176272&targetid=4587643557342507&device=c&mktype=&googleloc=164580&poi=&campaig>
    nid=604142975&mkgroupid=1344705146320125&rlsatarget=pla-4587643557342507&abcId=9410770&merchantid=137185&msclkid=02f7bf9a60b216d587b9d7c5748b647d

2.  TeraFly: <https://github.com/zjnyly/TeraFly>

    multi-node FPGA architecture? I want only one FPGA

### <span class="done DONE">DONE</span> HLSTransform: <https://github.com/HLSTransform/submission>

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-30 Sun 17:32\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-03 Mon 12:06\]

2 years old?

### <span class="done DONE">DONE</span> cornell-zhang/allo

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-30 Sun 17:32\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-03 Mon 12:07\]

### <span class="done DONE">DONE</span> Richielee630/TMMA

- State "DONE" from "WAIT" \[2025-11-03 Mon 16:50\]
- State "WAIT" from "TODO<sub>NEXT</sub>" \[2025-11-03 Mon 16:50\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-03 Mon 12:06\]

### <span class="done DONE">DONE</span> Mase

- State "DONE" from \[2025-11-03 Mon 12:05\]

1.  <span class="done DONE">DONE</span> Deepwok / MASE — elaboration
    attempt + blockage

    - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-03 Mon 12:02\]

    1.  Steps run

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

    2.  Output

        Output summary (truncated):

        - read<sub>slang</sub> elaboration failed with missing top
          source modules.
        - Missing modules: net<sub>0biassource</sub>,
          net<sub>2weightsource</sub>, net<sub>2biassource</sub>.
        - Full command output omitted to keep docs conversion fast.

    3.  Output (summary)

        - Yosys: 0.45+126 (80119386c)
        - Frontend: slang (SystemVerilog)
        - Errors (3): unknown module instances required by top:
          - net<sub>0biassource</sub>
          - net<sub>2weightsource</sub>
          - net<sub>2biassource</sub>
        - Warnings (10): \`\$fatal\` form (“finish argument must be
          0/1/2”) — non-blocking for 1b.

    4.  Diagnosis

        - 'top.sv' instantiates per-net source wrappers for
          weights/biases.
        - Only 'net<sub>0weightsource</sub>.sv' is present under
          \`~/.mase\`:
          - Evidence:
            '~/.mase/top/hardware/rtl/net<sub>0weightsource</sub>.sv'
        - The corresponding bias/weight source modules were **not
          generated** by LLM2FPGA.py in this run, so elaboration halts
          at hierarchy resolution.

2.  <span class="done DONE">DONE</span> Write the steps for deepwok mase

    - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-03 Mon 12:02\]
    - State "TODO<sub>NEXT</sub>" from \[2025-10-08 Wed 16:14\]

    We have created a fork of mase, with a branch called
    RCoeurjoly/flake.

    git clone git@github.com:RCoeurjoly/mase.git cd mase git checkout
    RCoeurjoly/flake

    nix develop source .venv/bin/activate

    python LLM2FPGA.py

    ls ~/.mase

    cd ~/yosys-slang

    yosys -m build/slang.so -p "read<sub>slang</sub>
    /home/roland/mase/src/mase<sub>components</sub>/memory/rtl/fifo.sv
    /home/roland/mase/src/mase<sub>components</sub>/common/rtl/mux.sv
    *home/roland*.mase/top/hardware/rtl/\*.sv /home/r
    oland/mase/src/mase<sub>components</sub>/common/rtl/single<sub>elementrepeat</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/common/rtl/unpacked<sub>registerslice</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/cast/rtl/fixed<sub>roun</sub>
    ding.sv
    /home/roland/mase/src/mase<sub>components</sub>/memory/rtl/input<sub>buffer</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/memory/rtl/unpacked<sub>skidbuffer</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/cast/rtl/fixed<sub>r</sub>
    ound.sv
    /home/roland/mase/src/mase<sub>components</sub>/cast/rtl/fixed<sub>signedcast</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/cast/rtl/signed<sub>clamp</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/cast/rtl/floor<sub>round</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/memory/rtl/blk<sub>memgen0</sub>.sv
    /home/roland/mase/src/mase<sub>components</sub>/memory/rtl/simple<sub>dualportram</sub>.sv
    –top top"

    /—————————————————————————-\\

    |                                    |
    |------------------------------------|
    | yosys – Yosys Open SYnthesis Suite |

    Output summary (truncated):

    - read<sub>slang</sub> elaboration failed with the same top-level
      missing modules.
    - 3 errors, 10 warnings.
    - Full command output intentionally trimmed.

    Those three missing modules (net<sub>0biassource</sub>,
    net<sub>2weightsource</sub> and net<sub>2biassource</sub>) are
    required by the top module but not generated by the LLM2FPGA.py.
    More research is needed to fix those.

3.  <span class="done DONE">DONE</span> Mase

    - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-03 Mon 12:02\]
    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed 18:39\]

    1.  TODO<sub>NEXT</sub> Figure out how the
        ~/.mase/top/hardware/rtl/\*.sv files were created

        - State "TODO<sub>NEXT</sub>" from \[2025-10-20 Mon 21:50\]

    2.  CANCELED Elaborate SystemVerilog with yosys-slang

        - State "CANCELED" from "TODO<sub>NEXT</sub>" \[2025-10-20 Mon
          21:50\]
        - State "TODO<sub>NEXT</sub>" from \[2025-08-19 Tue 13:39\]

        1.  CANCELED Process BERT

            - State "CANCELED" from "TODO<sub>NEXT</sub>" \[2025-10-20
              Mon 21:50\]

            - State "TODO<sub>NEXT</sub>" from \[2025-08-21 Thu 12:58\]
              docs/tutorials/emit<sub>verilogbert</sub>.ipynb

              after jupyter nbconvert –to script
              docs/tutorials/emit<sub>verilogbert</sub>.ipynb, we can
              execute the python script:

              python docs/tutorials/emit<sub>verilogbert</sub>.py

            1.  TODO<sub>NEXT</sub> Fix all errors

                - State "TODO<sub>NEXT</sub>" from \[2025-08-21 Thu
                  13:22\]

                1.  TODO<sub>NEXT</sub> ModuleNotFoundError: No module
                    named 'chop.models.patched'

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-21 Thu
                      13:22\]

        2.  <span class="done DONE">DONE</span> Create yosys script

            - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-08-21 Thu
              12:58\]
            - State "TODO<sub>NEXT</sub>" from \[2025-08-19 Tue 13:39\]

            Emitted SystemVerilog files:
            *home/roland*.mase/top/hardware/rtl/fixed<sub>accumulator</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>addertree</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>addertreelayer</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>cast</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>dotproduct</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>linear</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>mult</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>relu</sub>.sv
            *home/roland*.mase/top/hardware/rtl/fixed<sub>vectormult</sub>.sv
            *home/roland*.mase/top/hardware/rtl/join2.sv
            *home/roland*.mase/top/hardware/rtl/matmul.sv
            *home/roland*.mase/top/hardware/rtl/matrix<sub>accumulator</sub>.sv
            *home/roland*.mase/top/hardware/rtl/matrix<sub>fifo</sub>.sv
            *home/roland*.mase/top/hardware/rtl/matrix<sub>flatten</sub>.sv
            *home/roland*.mase/top/hardware/rtl/matrix<sub>streamtranspose</sub>.sv
            *home/roland*.mase/top/hardware/rtl/matrix<sub>unflatten</sub>.sv
            *home/roland*.mase/top/hardware/rtl/register<sub>slice</sub>.sv
            *home/roland*.mase/top/hardware/rtl/simple<sub>matmul</sub>.sv
            *home/roland*.mase/top/hardware/rtl/skid<sub>buffer</sub>.sv
            *home/roland*.mase/top/hardware/rtl/top.sv
            *home/roland*.mase/top/hardware/rtl/transpose.sv
            *home/roland*.mase/top/hardware/rtl/unpacked<sub>repeatcircularbuffer</sub>.sv

            1.  CANCELED Fix unknown module errors \[12/16\]

                - State "CANCELED" from "TODO<sub>NEXT</sub>"
                  \[2025-08-21 Thu 12:57\]
                - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                  13:58\] Better to use existing workflow from mase.

                1.  logs

                    yosys -m build/slang.so llm2fpga.ys

                    /—————————————————————————-\\

                    Output summary (truncated):

                    - \`yosys -m build/slang.so llm2fpga.ys\` ended with
                      hierarchy errors (19 errors, 10 warnings).
                    - Likely incomplete RTL module emission (e.g.,
                      net<sub>0weightsource</sub>, join2, fifo, mux,
                      fixed<sub>round</sub>, …).
                    - Full output omitted to keep docs conversion fast.

                2.  Notes

                    sv files are also located in
                    *home/roland/mase/src/mase<sub>components</sub>*

                3.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/top.sv:168:1: error:
                    unknown module 'net<sub>0weightsource</sub>'

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\]

                    net<sub>0weightsource</sub> \#(
                    ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                4.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/top.sv:182:1: error:
                    unknown module 'net<sub>0biassource</sub>'

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\]

                    net<sub>0biassource</sub> \#(
                    ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                5.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/top.sv:264:1: error:
                    unknown module 'net<sub>2weightsource</sub>'

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\]

                    net<sub>2weightsource</sub> \#(
                    ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                6.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/top.sv:278:1: error:
                    unknown module 'net<sub>2biassource</sub>'

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\]

                    net<sub>2biassource</sub> \#(
                    ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                7.  <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/matrix<sub>streamtranspose</sub>.sv:115:5:
                    error: unknown module 'fifo'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:58\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] fifo \#( ^\~\~~

                8.  <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/matrix<sub>streamtranspose</sub>.sv:142:7:
                    error: unknown module 'mux'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:50\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] mux \#( ^\~~

                9.  <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/matrix<sub>streamtranspose</sub>.sv:166:7:
                    error: unknown module 'mux'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:50\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] mux \#( ^\~~

                10. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/matrix<sub>streamtranspose</sub>.sv:174:7:
                    error: unknown module 'mux'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:51\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] mux \#( ^\~~

                11. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/matmul.sv:181:7: error:
                    unknown module 'single<sub>elementrepeat</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] single<sub>elementrepeat</sub> \#(
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~ in
                      instance:
                      top.net<sub>2inst</sub>.matmul<sub>i</sub>

                12. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/matmul.sv:208:7: error:
                    unknown module 'unpacked<sub>skidbuffer</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] unpacked<sub>skidbuffer</sub> \#(
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                13. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/matmul.sv:314:5: error:
                    unknown module 'fixed<sub>signedcast</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] fixed<sub>signedcast</sub> \#(
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                14. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/fixed<sub>linear</sub>.sv:186:5:
                    error: unknown module 'input<sub>buffer</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] input<sub>buffer</sub> \#(
                      ^\~\~\~\~\~\~\~\~\~\~~

                15. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/fixed<sub>linear</sub>.sv:205:5:
                    error: unknown module 'fixed<sub>rounding</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] fixed<sub>rounding</sub> \#(
                      ^\~\~\~\~\~\~\~\~\~\~\~\~~

                16. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/fixed<sub>linear</sub>.sv:215:5:
                    error: unknown module
                    'unpacked<sub>registerslice</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] unpacked<sub>registerslice</sub> \#(
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                17. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/fixed<sub>linear</sub>.sv:248:5:
                    error: unknown module 'fixed<sub>cast</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] fixed<sub>cast</sub> \#(
                      ^\~\~\~\~\~\~\~\~~

                18. <span class="done DONE">DONE</span>
                    ../.mase/top/hardware/rtl/simple<sub>matmul</sub>.sv:136:9:
                    error: unknown module 'fixed<sub>round</sub>'

                    - State "DONE" from "TODO<sub>NEXT</sub>"
                      \[2025-08-20 Wed 18:59\]
                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\]

            2.  CANCELED Fix warnings? \[0/10\]

                - State "CANCELED" from "TODO<sub>NEXT</sub>"
                  \[2025-08-21 Thu 12:56\]
                - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                  18:59\]

                1.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matmul.sv:84:17: warning:
                    finish argument must have value of 0, 1, or 2
                    \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("A<sub>TOTALDIM0</sub> must
                      equal B<sub>TOTALDIM1</sub>!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                2.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matmul.sv:86:17: warning:
                    finish argument must have value of 0, 1, or 2
                    \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("A<sub>COMPUTEDIM0</sub> must
                      equal B<sub>COMPUTEDIM1</sub>!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                3.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matmul.sv:90:17: warning:
                    finish argument must have value of 0, 1, or 2
                    \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("A<sub>DIM0</sub> compute is
                      not divisible!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                4.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matmul.sv:92:17: warning:
                    finish argument must have value of 0, 1, or 2
                    \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("A<sub>DIM1</sub> compute is
                      not divisible!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                5.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matmul.sv:94:17: warning:
                    finish argument must have value of 0, 1, or 2
                    \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("B<sub>DIM0</sub> compute is
                      not divisible!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                6.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matmul.sv:96:17: warning:
                    finish argument must have value of 0, 1, or 2
                    \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("B<sub>DIM1</sub> compute is
                      not divisible!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~
                      in instance:
                      top.net<sub>0inst</sub>.matmul<sub>i</sub>

                7.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matrix<sub>streamtranspose</sub>.sv:43:17:
                    warning: finish argument must have value of 0, 1, or
                    2 \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("DIM0 compute is not
                      divisible!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                8.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/matrix<sub>streamtranspose</sub>.sv:45:17:
                    warning: finish argument must have value of 0, 1, or
                    2 \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:45\] else \$fatal("DIM1 compute is not
                      divisible!");
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                9.  TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/simple<sub>matmul</sub>.sv:64:19:
                    warning: finish argument must have value of 0, 1, or
                    2 \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] else \$fatal("OUT<sub>WIDTH</sub> must be
                      %d if OUTPUT<sub>ROUNDING</sub> == 0",
                      ACC<sub>WIDTH</sub>);
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

                10. TODO<sub>NEXT</sub>
                    ../.mase/top/hardware/rtl/simple<sub>matmul</sub>.sv:66:19:
                    warning: finish argument must have value of 0, 1, or
                    2 \[-Wfinish-num\]

                    - State "TODO<sub>NEXT</sub>" from \[2025-08-20 Wed
                      18:46\] else \$fatal("OUT<sub>FRACWIDTH</sub> must
                      be %d if OUTPUT<sub>ROUNDING</sub> == 0",
                      ACC<sub>FRACWIDTH</sub>);
                      ^\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~\~~

        3.  <span class="done DONE">DONE</span> Build yosys-slang

            - State "DONE" from \[2025-08-20 Wed 13:10\] from
              yosys-slang dir, available with yosys -m build/slang.so

    3.  <span class="done DONE">DONE</span> Mase: call
        emit<sub>verilog</sub> function

        - State "DONE" from "TODO<sub>NEXT</sub>" \[2025-08-19 Tue
          13:39\]
        - State "TODO<sub>NEXT</sub>" from \[2025-08-10 Sun 14:18\]
          Steps: nix develop source .venv/bin/activate

        1.  notes

            even though the function is called
            emit<sub>verilogtoptransformpass</sub>, it emits
            SystemVerilog, not Verilog

        2.  CANCELED Setup flake.nix

            - State "CANCELED" from "TODO<sub>NEXT</sub>" \[2025-08-13
              Wed 13:08\]
            - State "TODO<sub>NEXT</sub>" from \[2025-08-10 Sun 14:28\]
              Let's do it later, just emit<sub>verilog</sub>

            1.  CANCELED nix:
                /nix/store/whypqfa83z4bsn43n4byvmw80n4mg3r8-glibc-2.37-45/lib/libc.so.6:
                version \`GLIBC<sub>2</sub>.38' not found (required by
                /nix/store/90yn7340r8yab8kxpb0p7y0c9j3snjam-gcc-13.2.0-lib/li

                b/libstdc++.so.6) CLOSED: \[2025-08-13 Wed 13:08\]

                - State "CANCELED" from "TODO<sub>NEXT</sub>"
                  \[2025-08-13 Wed 13:08\]
                - State "TODO<sub>NEXT</sub>" from \[2025-08-10 Sun
                  14:28\]

                nix develop

        3.  Notes

            The most useful tutorial for LLM2FPGA is not written
            <https://deepwok.github.io/mase/modules/documentation/tutorials/tutorial_8_emit_verilog.html>

## <span class="done DONE">DONE</span> Table with github metrics for each project

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-11-23 Sun 15:07\]
- State "TODO<sub>NEXT</sub>" from \[2025-11-12 Wed 12:59\]

## HLS notes

Look for alternatives to Vitis HLS, open source, able to process Vitis
HLS headers like \#include \<ap<sub>int</sub>.h\> \#include
\<hls<sub>stream</sub>.h\>

<https://chatgpt.com/share/6908e06c-1b24-8008-b02c-3313dc555d0b>

Very promissing: <https://github.com/ferrandi/PandA-bambu>

# <span class="done DONE">DONE</span> subtask 1.a

- State "DONE" from \[2025-11-03 Mon 12:08\]

## <span class="done DONE">DONE</span> Quick AI analysis of all papers to find snags \[0/13\]

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-08-10 Sun 14:17\]
- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:22\]

### TODO<sub>NEXT</sub> TeLLMe (<https://arxiv.org/abs/2504.16266>)

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> <https://arxiv.org/abs/2503.16731>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> TerEffic <https://arxiv.org/abs/2502.16473>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> MEADOW <https://arxiv.org/abs/2503.11663>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> FlightLLM <https://arxiv.org/abs/2401.03868>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> SECDA-LLM <https://arxiv.org/abs/2408.00462>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> MatMul-Free LM <https://arxiv.org/abs/2406.02528>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> LoopLynx <https://arxiv.org/abs/2504.09561>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> On-Device Qwen2.5 <https://arxiv.org/abs/2504.17376>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> HLSTransform <https://arxiv.org/abs/2405.00738>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> <https://arxiv.org/abs/2312.15159>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> AccLLM <https://arxiv.org/abs/2505.03745>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

### TODO<sub>NEXT</sub> MASE <https://arxiv.org/abs/2307.15517v2>

- State "TODO<sub>NEXT</sub>" from \[2025-07-02 Wed 12:25\]

## <span class="done DONE">DONE</span> Create links to all papers analyzed

- State "DONE" from "TODO<sub>NEXT</sub>" \[2025-07-02 Wed 12:21\]
- State "TODO<sub>NEXT</sub>" from \[2025-06-30 Mon 21:13\]
