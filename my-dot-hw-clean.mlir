module {
  hw.module @handshake_fork_1ins_5outs_ctrl(in %in0 : i0, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, in %out2_ready : i1, in %out3_ready : i1, in %out4_ready : i1, out in0_ready : i1, out out0 : i0, out out0_valid : i1, out out1 : i0, out out1_valid : i1, out out2 : i0, out out2_valid : i1, out out3 : i0, out out3_valid : i1, out out4 : i0, out out4_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %35, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %35, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %35, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %in0_valid : i1
    %19 = comb.and %out2_ready, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %35, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %in0_valid : i1
    %26 = comb.and %out3_ready, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %35, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %in0_valid : i1
    %33 = comb.and %out4_ready, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.and %6, %13, %20, %27, %34 {sv.namehint = "allDone"} : i1
    hw.output %35, %in0, %4, %in0, %11, %in0, %18, %in0, %25, %in0, %32 : i1, i0, i1, i0, i1, i0, i1, i0, i1, i0, i1
  }
  hw.module @handshake_memory_out_ui64_id4(in %stData0 : i64, in %stData0_valid : i1, in %stAddr0 : i64, in %stAddr0_valid : i1, in %stData1 : i64, in %stData1_valid : i1, in %stAddr1 : i64, in %stAddr1_valid : i1, in %ldAddr0 : i64, in %ldAddr0_valid : i1, in %ldAddr1 : i64, in %ldAddr1_valid : i1, in %clock : !seq.clock, in %reset : i1, in %ldData0_ready : i1, in %ldData1_ready : i1, in %stDone0_ready : i1, in %stDone1_ready : i1, in %ldDone0_ready : i1, in %ldDone1_ready : i1, out stData0_ready : i1, out stAddr0_ready : i1, out stData1_ready : i1, out stAddr1_ready : i1, out ldAddr0_ready : i1, out ldAddr1_ready : i1, out ldData0 : i64, out ldData0_valid : i1, out ldData1 : i64, out ldData1_valid : i1, out stDone0 : i0, out stDone0_valid : i1, out stDone1 : i0, out stDone1_valid : i1, out ldDone0 : i0, out ldDone0_valid : i1, out ldDone1 : i0, out ldDone1_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %c0_i0 = hw.constant 0 : i0
    %_handshake_memory_4 = seq.hlmem @_handshake_memory_4 %clock, %reset : <1xi64>
    %0 = comb.extract %ldAddr0 from 0 : (i64) -> i0
    %_handshake_memory_4_rdata = seq.read %_handshake_memory_4[%0] rden %ldAddr0_valid {latency = 0 : i64} : !seq.hlmem<1xi64>
    %1 = comb.xor %15, %true : i1
    %2 = comb.and %7, %1 : i1
    %3 = seq.compreg %2, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %4 = comb.xor %3, %true {sv.namehint = "not_emitted_0"} : i1
    %5 = comb.and %4, %ldAddr0_valid : i1
    %6 = comb.and %ldData0_ready, %5 : i1
    %7 = comb.or %6, %3 {sv.namehint = "done0"} : i1
    %8 = comb.xor %15, %true : i1
    %9 = comb.and %14, %8 : i1
    %10 = seq.compreg %9, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %11 = comb.xor %10, %true {sv.namehint = "not_emitted_1"} : i1
    %12 = comb.and %11, %ldAddr0_valid : i1
    %13 = comb.and %ldDone0_ready, %12 : i1
    %14 = comb.or %13, %10 {sv.namehint = "done1"} : i1
    %15 = comb.and %7, %14 {sv.namehint = "allDone"} : i1
    %16 = comb.extract %ldAddr1 from 0 : (i64) -> i0
    %_handshake_memory_4_rdata_0 = seq.read %_handshake_memory_4[%16] rden %ldAddr1_valid {latency = 0 : i64} : !seq.hlmem<1xi64>
    %17 = comb.xor %31, %true : i1
    %18 = comb.and %23, %17 : i1
    %19 = seq.compreg %18, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %20 = comb.xor %19, %true {sv.namehint = "not_emitted_0"} : i1
    %21 = comb.and %20, %ldAddr1_valid : i1
    %22 = comb.and %ldData1_ready, %21 : i1
    %23 = comb.or %22, %19 {sv.namehint = "done0"} : i1
    %24 = comb.xor %31, %true : i1
    %25 = comb.and %30, %24 : i1
    %26 = seq.compreg %25, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %27 = comb.xor %26, %true {sv.namehint = "not_emitted_1"} : i1
    %28 = comb.and %27, %ldAddr1_valid : i1
    %29 = comb.and %ldDone1_ready, %28 : i1
    %30 = comb.or %29, %26 {sv.namehint = "done1"} : i1
    %31 = comb.and %23, %30 {sv.namehint = "allDone"} : i1
    %32 = seq.compreg %37, %clock reset %reset, %false {sv.namehint = "writeValidBuffer"} : i1  
    %33 = comb.and %stDone0_ready, %32 {sv.namehint = "storeCompleted"} : i1
    %34 = comb.xor %32, %true {sv.namehint = "not_writeValidBuffer"} : i1
    %35 = comb.or %34, %33 {sv.namehint = "emptyOrComplete"} : i1
    %36 = comb.and %stAddr0_valid, %stData0_valid {sv.namehint = "writeValid"} : i1
    %37 = comb.mux %35, %36, %32 : i1
    %38 = comb.extract %stAddr0 from 0 : (i64) -> i0
    seq.write %_handshake_memory_4[%38] %stData0 wren %36 {latency = 1 : i64} : !seq.hlmem<1xi64>
    %39 = seq.compreg %44, %clock reset %reset, %false {sv.namehint = "writeValidBuffer"} : i1  
    %40 = comb.and %stDone1_ready, %39 {sv.namehint = "storeCompleted"} : i1
    %41 = comb.xor %39, %true {sv.namehint = "not_writeValidBuffer"} : i1
    %42 = comb.or %41, %40 {sv.namehint = "emptyOrComplete"} : i1
    %43 = comb.and %stAddr1_valid, %stData1_valid {sv.namehint = "writeValid"} : i1
    %44 = comb.mux %42, %43, %39 : i1
    %45 = comb.extract %stAddr1 from 0 : (i64) -> i0
    seq.write %_handshake_memory_4[%45] %stData1 wren %43 {latency = 1 : i64} : !seq.hlmem<1xi64>
    hw.output %35, %35, %42, %42, %15, %31, %_handshake_memory_4_rdata, %5, %_handshake_memory_4_rdata_0, %21, %c0_i0, %32, %c0_i0, %39, %c0_i0, %12, %c0_i0, %28 : i1, i1, i1, i1, i1, i1, i64, i1, i64, i1, i0, i1, i0, i1, i0, i1, i0, i1
  }
  hw.module @handshake_fork_1ins_2outs_ctrl(in %in0 : i0, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, out in0_ready : i1, out out0 : i0, out out0_valid : i1, out out1 : i0, out out1_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %14, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %14, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.and %6, %13 {sv.namehint = "allDone"} : i1
    hw.output %14, %in0, %4, %in0, %11 : i1, i0, i1, i0, i1
  }
  hw.module @handshake_memory_out_ui32_id3(in %stData0 : i32, in %stData0_valid : i1, in %stAddr0 : i64, in %stAddr0_valid : i1, in %ldAddr0 : i64, in %ldAddr0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %ldData0_ready : i1, in %stDone0_ready : i1, in %ldDone0_ready : i1, out stData0_ready : i1, out stAddr0_ready : i1, out ldAddr0_ready : i1, out ldData0 : i32, out ldData0_valid : i1, out stDone0 : i0, out stDone0_valid : i1, out ldDone0 : i0, out ldDone0_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %c0_i0 = hw.constant 0 : i0
    %_handshake_memory_3 = seq.hlmem @_handshake_memory_3 %clock, %reset : <16xi32>
    %0 = comb.extract %ldAddr0 from 0 : (i64) -> i4
    %_handshake_memory_3_rdata = seq.read %_handshake_memory_3[%0] rden %ldAddr0_valid {latency = 0 : i64} : !seq.hlmem<16xi32>
    %1 = comb.xor %15, %true : i1
    %2 = comb.and %7, %1 : i1
    %3 = seq.compreg %2, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %4 = comb.xor %3, %true {sv.namehint = "not_emitted_0"} : i1
    %5 = comb.and %4, %ldAddr0_valid : i1
    %6 = comb.and %ldData0_ready, %5 : i1
    %7 = comb.or %6, %3 {sv.namehint = "done0"} : i1
    %8 = comb.xor %15, %true : i1
    %9 = comb.and %14, %8 : i1
    %10 = seq.compreg %9, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %11 = comb.xor %10, %true {sv.namehint = "not_emitted_1"} : i1
    %12 = comb.and %11, %ldAddr0_valid : i1
    %13 = comb.and %ldDone0_ready, %12 : i1
    %14 = comb.or %13, %10 {sv.namehint = "done1"} : i1
    %15 = comb.and %7, %14 {sv.namehint = "allDone"} : i1
    %16 = seq.compreg %21, %clock reset %reset, %false {sv.namehint = "writeValidBuffer"} : i1  
    %17 = comb.and %stDone0_ready, %16 {sv.namehint = "storeCompleted"} : i1
    %18 = comb.xor %16, %true {sv.namehint = "not_writeValidBuffer"} : i1
    %19 = comb.or %18, %17 {sv.namehint = "emptyOrComplete"} : i1
    %20 = comb.and %stAddr0_valid, %stData0_valid {sv.namehint = "writeValid"} : i1
    %21 = comb.mux %19, %20, %16 : i1
    %22 = comb.extract %stAddr0 from 0 : (i64) -> i4
    seq.write %_handshake_memory_3[%22] %stData0 wren %20 {latency = 1 : i64} : !seq.hlmem<16xi32>
    hw.output %19, %19, %15, %_handshake_memory_3_rdata, %5, %c0_i0, %16, %c0_i0, %12 : i1, i1, i1, i32, i1, i0, i1, i0, i1
  }
  hw.module @arith_index_cast_in_ui64_out_ui0(in %in0 : i64, in %in0_valid : i1, in %out0_ready : i1, out in0_ready : i1, out out0 : i0, out out0_valid : i1) {
    %0 = comb.and %out0_ready, %in0_valid : i1
    %1 = comb.extract %in0 from 0 : (i64) -> i0
    hw.output %0, %1, %in0_valid : i1, i0, i1
  }
  hw.module @hw_struct_create_in_ui0_ui64_out_struct_address_ui0_data_ui64(in %in0 : i0, in %in0_valid : i1, in %in1 : i64, in %in1_valid : i1, in %out0_ready : i1, out in0_ready : i1, out in1_ready : i1, out out0 : !hw.struct<address: i0, data: i64>, out out0_valid : i1) {
    %0 = comb.and %in0_valid, %in1_valid : i1
    %1 = comb.and %out0_ready, %0 : i1
    %2 = hw.struct_create (%in0, %in1) : !hw.struct<address: i0, data: i64>
    hw.output %1, %1, %2, %0 : i1, i1, !hw.struct<address: i0, data: i64>, i1
  }
  hw.module @handshake_fork_in_ui32_out_ui32_ui32(in %in0 : i32, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, out in0_ready : i1, out out0 : i32, out out0_valid : i1, out out1 : i32, out out1_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %14, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %14, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.and %6, %13 {sv.namehint = "allDone"} : i1
    hw.output %14, %in0, %4, %in0, %11 : i1, i32, i1, i32, i1
  }
  hw.module @handshake_join_in_ui32_1ins_1outs_ctrl(in %in0 : i32, in %in0_valid : i1, in %out0_ready : i1, out in0_ready : i1, out out0 : i0, out out0_valid : i1) {
    %c0_i0 = hw.constant 0 : i0
    %0 = comb.and %out0_ready, %in0_valid : i1
    hw.output %0, %c0_i0, %in0_valid : i1, i0, i1
  }
  hw.module @arith_index_cast_in_ui64_out_ui4(in %in0 : i64, in %in0_valid : i1, in %out0_ready : i1, out in0_ready : i1, out out0 : i4, out out0_valid : i1) {
    %0 = comb.and %out0_ready, %in0_valid : i1
    %1 = comb.extract %in0 from 0 : (i64) -> i4
    hw.output %0, %1, %in0_valid : i1, i4, i1
  }
  hw.module @handshake_constant_c1_out_ui64(in %ctrl : i0, in %ctrl_valid : i1, in %out0_ready : i1, out ctrl_ready : i1, out out0 : i64, out out0_valid : i1) {
    %c1_i64 = hw.constant 1 : i64
    hw.output %out0_ready, %c1_i64, %ctrl_valid : i1, i64, i1
  }
  hw.module @handshake_constant_c16_out_ui64(in %ctrl : i0, in %ctrl_valid : i1, in %out0_ready : i1, out ctrl_ready : i1, out out0 : i64, out out0_valid : i1) {
    %c16_i64 = hw.constant 16 : i64
    hw.output %out0_ready, %c16_i64, %ctrl_valid : i1, i64, i1
  }
  hw.module @handshake_constant_c0_out_ui64(in %ctrl : i0, in %ctrl_valid : i1, in %out0_ready : i1, out ctrl_ready : i1, out out0 : i64, out out0_valid : i1) {
    %c0_i64 = hw.constant 0 : i64
    hw.output %out0_ready, %c0_i64, %ctrl_valid : i1, i64, i1
  }
  hw.module @handshake_fork_in_ui64_out_ui64_ui64(in %in0 : i64, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, out in0_ready : i1, out out0 : i64, out out0_valid : i1, out out1 : i64, out out1_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %14, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %14, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.and %6, %13 {sv.namehint = "allDone"} : i1
    hw.output %14, %in0, %4, %in0, %11 : i1, i64, i1, i64, i1
  }
  hw.module @handshake_buffer_in_ui1_out_ui1_1slots_seq_init_0(in %in0 : i1, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, out in0_ready : i1, out out0 : i1, out out0_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = seq.compreg %3, %clock reset %reset, %true {sv.namehint = "valid0_reg"} : i1  
    %1 = comb.xor %0, %true {sv.namehint = "not_valid0_reg"} : i1
    %2 = comb.or %1, %8 : i1
    %3 = comb.mux %2, %in0_valid, %0 : i1
    %4 = comb.mux %2, %in0, %5 : i1
    %5 = seq.compreg %4, %clock reset %reset, %false {sv.namehint = "data0_reg"} : i1  
    %6 = seq.compreg %14, %clock reset %reset, %false {sv.namehint = "ready0_reg"} : i1  
    %7 = comb.mux %6, %6, %0 : i1
    %8 = comb.xor %6, %true {sv.namehint = "not_ready0_reg"} : i1
    %9 = comb.xor %out0_ready, %true : i1
    %10 = comb.and %9, %8 : i1
    %11 = comb.mux %10, %0, %6 : i1
    %12 = comb.and %out0_ready, %6 : i1
    %13 = comb.xor %12, %true : i1
    %14 = comb.and %13, %11 : i1
    %15 = seq.compreg %19, %clock reset %reset, %false {sv.namehint = "ctrl_data0_reg"} : i1  
    %16 = comb.mux %6, %15, %5 : i1
    %17 = comb.mux %10, %5, %15 : i1
    %18 = comb.xor %12, %true : i1
    %19 = comb.and %18, %17 : i1
    hw.output %2, %16, %7 : i1, i1, i1
  }
  hw.module @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1(in %in0 : i1, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, in %out2_ready : i1, in %out3_ready : i1, in %out4_ready : i1, in %out5_ready : i1, out in0_ready : i1, out out0 : i1, out out0_valid : i1, out out1 : i1, out out1_valid : i1, out out2 : i1, out out2_valid : i1, out out3 : i1, out out3_valid : i1, out out4 : i1, out out4_valid : i1, out out5 : i1, out out5_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %42, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %42, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %42, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %in0_valid : i1
    %19 = comb.and %out2_ready, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %42, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %in0_valid : i1
    %26 = comb.and %out3_ready, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %42, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %in0_valid : i1
    %33 = comb.and %out4_ready, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.xor %42, %true : i1
    %36 = comb.and %41, %35 : i1
    %37 = seq.compreg %36, %clock reset %reset, %false {sv.namehint = "emitted_5"} : i1  
    %38 = comb.xor %37, %true {sv.namehint = "not_emitted_5"} : i1
    %39 = comb.and %38, %in0_valid : i1
    %40 = comb.and %out5_ready, %39 : i1
    %41 = comb.or %40, %37 {sv.namehint = "done5"} : i1
    %42 = comb.and %6, %13, %20, %27, %34, %41 {sv.namehint = "allDone"} : i1
    hw.output %42, %in0, %4, %in0, %11, %in0, %18, %in0, %25, %in0, %32, %in0, %39 : i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1
  }
  hw.module @handshake_mux_in_ui1_3ins_1outs_ctrl(in %select : i1, in %select_valid : i1, in %in0 : i0, in %in0_valid : i1, in %in1 : i0, in %in1_valid : i1, in %out0_ready : i1, out select_ready : i1, out in0_ready : i1, out in1_ready : i1, out out0 : i0, out out0_valid : i1) {
    %c1_i2 = hw.constant 1 : i2
    %false = hw.constant false
    %0 = comb.concat %false, %select : i1, i1
    %1 = comb.shl %c1_i2, %0 : i2
    %2 = comb.mux %select, %in1_valid, %in0_valid : i1
    %3 = comb.and %2, %select_valid : i1
    %4 = comb.and %3, %out0_ready : i1
    %5 = comb.extract %1 from 0 : (i2) -> i1
    %6 = comb.and %5, %4 : i1
    %7 = comb.extract %1 from 1 : (i2) -> i1
    %8 = comb.and %7, %4 : i1
    %9 = comb.mux %select, %in1, %in0 : i0
    hw.output %4, %6, %8, %9, %3 : i1, i1, i1, i0, i1
  }
  hw.module @handshake_mux_in_ui1_ui64_ui64_out_ui64(in %select : i1, in %select_valid : i1, in %in0 : i64, in %in0_valid : i1, in %in1 : i64, in %in1_valid : i1, in %out0_ready : i1, out select_ready : i1, out in0_ready : i1, out in1_ready : i1, out out0 : i64, out out0_valid : i1) {
    %c1_i2 = hw.constant 1 : i2
    %false = hw.constant false
    %0 = comb.concat %false, %select : i1, i1
    %1 = comb.shl %c1_i2, %0 : i2
    %2 = comb.mux %select, %in1_valid, %in0_valid : i1
    %3 = comb.and %2, %select_valid : i1
    %4 = comb.and %3, %out0_ready : i1
    %5 = comb.extract %1 from 0 : (i2) -> i1
    %6 = comb.and %5, %4 : i1
    %7 = comb.extract %1 from 1 : (i2) -> i1
    %8 = comb.and %7, %4 : i1
    %9 = comb.mux %select, %in1, %in0 : i64
    hw.output %4, %6, %8, %9, %3 : i1, i1, i1, i64, i1
  }
  hw.module @arith_cmpi_in_ui64_ui64_out_ui1_slt(in %in0 : i64, in %in0_valid : i1, in %in1 : i64, in %in1_valid : i1, in %out0_ready : i1, out in0_ready : i1, out in1_ready : i1, out out0 : i1, out out0_valid : i1) {
    %0 = comb.and %in0_valid, %in1_valid : i1
    %1 = comb.and %out0_ready, %0 : i1
    %2 = comb.icmp slt %in0, %in1 : i64
    hw.output %1, %1, %2, %0 : i1, i1, i1, i1
  }
  hw.module @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1_ui1(in %in0 : i1, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, in %out2_ready : i1, in %out3_ready : i1, in %out4_ready : i1, in %out5_ready : i1, in %out6_ready : i1, out in0_ready : i1, out out0 : i1, out out0_valid : i1, out out1 : i1, out out1_valid : i1, out out2 : i1, out out2_valid : i1, out out3 : i1, out out3_valid : i1, out out4 : i1, out out4_valid : i1, out out5 : i1, out out5_valid : i1, out out6 : i1, out out6_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %49, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %49, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %49, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %in0_valid : i1
    %19 = comb.and %out2_ready, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %49, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %in0_valid : i1
    %26 = comb.and %out3_ready, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %49, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %in0_valid : i1
    %33 = comb.and %out4_ready, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.xor %49, %true : i1
    %36 = comb.and %41, %35 : i1
    %37 = seq.compreg %36, %clock reset %reset, %false {sv.namehint = "emitted_5"} : i1  
    %38 = comb.xor %37, %true {sv.namehint = "not_emitted_5"} : i1
    %39 = comb.and %38, %in0_valid : i1
    %40 = comb.and %out5_ready, %39 : i1
    %41 = comb.or %40, %37 {sv.namehint = "done5"} : i1
    %42 = comb.xor %49, %true : i1
    %43 = comb.and %48, %42 : i1
    %44 = seq.compreg %43, %clock reset %reset, %false {sv.namehint = "emitted_6"} : i1  
    %45 = comb.xor %44, %true {sv.namehint = "not_emitted_6"} : i1
    %46 = comb.and %45, %in0_valid : i1
    %47 = comb.and %out6_ready, %46 : i1
    %48 = comb.or %47, %44 {sv.namehint = "done6"} : i1
    %49 = comb.and %6, %13, %20, %27, %34, %41, %48 {sv.namehint = "allDone"} : i1
    hw.output %49, %in0, %4, %in0, %11, %in0, %18, %in0, %25, %in0, %32, %in0, %39, %in0, %46 : i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1
  }
  hw.module @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(in %cond : i1, in %cond_valid : i1, in %data : i64, in %data_valid : i1, in %outTrue_ready : i1, in %outFalse_ready : i1, out cond_ready : i1, out data_ready : i1, out outTrue : i64, out outTrue_valid : i1, out outFalse : i64, out outFalse_valid : i1) {
    %true = hw.constant true
    %0 = comb.and %cond_valid, %data_valid : i1
    %1 = comb.and %cond, %0 : i1
    %2 = comb.xor %cond, %true : i1
    %3 = comb.and %2, %0 : i1
    %4 = comb.mux %cond, %outTrue_ready, %outFalse_ready : i1
    %5 = comb.and %4, %0 : i1
    hw.output %5, %5, %data, %1, %data, %3 : i1, i1, i64, i1, i64, i1
  }
  hw.module @handshake_sink_in_ui64(in %in0 : i64, in %in0_valid : i1, out in0_ready : i1) {
    %true = hw.constant true
    hw.output %true : i1
  }
  hw.module @handshake_fork_in_ui64_out_ui64_ui64_ui64_ui64(in %in0 : i64, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, in %out2_ready : i1, in %out3_ready : i1, out in0_ready : i1, out out0 : i64, out out0_valid : i1, out out1 : i64, out out1_valid : i1, out out2 : i64, out out2_valid : i1, out out3 : i64, out out3_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %28, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %28, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %28, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %in0_valid : i1
    %19 = comb.and %out2_ready, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %28, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %in0_valid : i1
    %26 = comb.and %out3_ready, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.and %6, %13, %20, %27 {sv.namehint = "allDone"} : i1
    hw.output %28, %in0, %4, %in0, %11, %in0, %18, %in0, %25 : i1, i64, i1, i64, i1, i64, i1, i64, i1
  }
  hw.module @handshake_fork_in_ui64_out_ui64_ui64_ui64(in %in0 : i64, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, in %out2_ready : i1, out in0_ready : i1, out out0 : i64, out out0_valid : i1, out out1 : i64, out out1_valid : i1, out out2 : i64, out out2_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %21, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %21, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %21, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %in0_valid : i1
    %19 = comb.and %out2_ready, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.and %6, %13, %20 {sv.namehint = "allDone"} : i1
    hw.output %21, %in0, %4, %in0, %11, %in0, %18 : i1, i64, i1, i64, i1, i64, i1
  }
  hw.module @handshake_cond_br_in_ui1_2ins_2outs_ctrl(in %cond : i1, in %cond_valid : i1, in %data : i0, in %data_valid : i1, in %outTrue_ready : i1, in %outFalse_ready : i1, out cond_ready : i1, out data_ready : i1, out outTrue : i0, out outTrue_valid : i1, out outFalse : i0, out outFalse_valid : i1) {
    %true = hw.constant true
    %0 = comb.and %cond_valid, %data_valid : i1
    %1 = comb.and %cond, %0 : i1
    %2 = comb.xor %cond, %true : i1
    %3 = comb.and %2, %0 : i1
    %4 = comb.mux %cond, %outTrue_ready, %outFalse_ready : i1
    %5 = comb.and %4, %0 : i1
    hw.output %5, %5, %data, %1, %data, %3 : i1, i1, i0, i1, i0, i1
  }
  hw.module @handshake_fork_1ins_4outs_ctrl(in %in0 : i0, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, in %out2_ready : i1, in %out3_ready : i1, out in0_ready : i1, out out0 : i0, out out0_valid : i1, out out1 : i0, out out1_valid : i1, out out2 : i0, out out2_valid : i1, out out3 : i0, out out3_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %28, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %28, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %28, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %in0_valid : i1
    %19 = comb.and %out2_ready, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %28, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %in0_valid : i1
    %26 = comb.and %out3_ready, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.and %6, %13, %20, %27 {sv.namehint = "allDone"} : i1
    hw.output %28, %in0, %4, %in0, %11, %in0, %18, %in0, %25 : i1, i0, i1, i0, i1, i0, i1, i0, i1
  }
  hw.module @handshake_join_4ins_1outs_ctrl(in %in0 : i0, in %in0_valid : i1, in %in1 : i0, in %in1_valid : i1, in %in2 : i0, in %in2_valid : i1, in %in3 : i0, in %in3_valid : i1, in %out0_ready : i1, out in0_ready : i1, out in1_ready : i1, out in2_ready : i1, out in3_ready : i1, out out0 : i0, out out0_valid : i1) {
    %c0_i0 = hw.constant 0 : i0
    %0 = comb.and %in0_valid, %in1_valid, %in2_valid, %in3_valid : i1
    %1 = comb.and %out0_ready, %0 : i1
    hw.output %1, %1, %1, %1, %c0_i0, %0 : i1, i1, i1, i1, i0, i1
  }
  hw.module @handshake_load_in_ui64_ui32_out_ui32_ui64(in %addrIn0 : i64, in %addrIn0_valid : i1, in %dataFromMem : i32, in %dataFromMem_valid : i1, in %ctrl : i0, in %ctrl_valid : i1, in %dataOut_ready : i1, in %addrOut0_ready : i1, out addrIn0_ready : i1, out dataFromMem_ready : i1, out ctrl_ready : i1, out dataOut : i32, out dataOut_valid : i1, out addrOut0 : i64, out addrOut0_valid : i1) {
    %0 = comb.and %addrIn0_valid, %ctrl_valid : i1
    %1 = comb.and %addrOut0_ready, %0 : i1
    hw.output %1, %dataOut_ready, %1, %dataFromMem, %dataFromMem_valid, %addrIn0, %0 : i1, i1, i1, i32, i1, i64, i1
  }
  hw.module @arith_muli_in_ui32_ui32_out_ui32(in %in0 : i32, in %in0_valid : i1, in %in1 : i32, in %in1_valid : i1, in %out0_ready : i1, out in0_ready : i1, out in1_ready : i1, out out0 : i32, out out0_valid : i1) {
    %0 = comb.and %in0_valid, %in1_valid : i1
    %1 = comb.and %out0_ready, %0 : i1
    %2 = comb.mul %in0, %in1 : i32
    hw.output %1, %1, %2, %0 : i1, i1, i32, i1
  }
  hw.module @handshake_store_in_ui64_ui32_out_ui32_ui64(in %addrIn0 : i64, in %addrIn0_valid : i1, in %dataIn : i32, in %dataIn_valid : i1, in %ctrl : i0, in %ctrl_valid : i1, in %dataToMem_ready : i1, in %addrOut0_ready : i1, out addrIn0_ready : i1, out dataIn_ready : i1, out ctrl_ready : i1, out dataToMem : i32, out dataToMem_valid : i1, out addrOut0 : i64, out addrOut0_valid : i1) {
    %0 = comb.and %dataIn_valid, %addrIn0_valid, %ctrl_valid : i1
    %1 = comb.and %dataToMem_ready, %addrOut0_ready, %0 : i1
    hw.output %1, %1, %1, %dataIn, %0, %addrIn0, %0 : i1, i1, i1, i32, i1, i64, i1
  }
  hw.module @arith_addi_in_ui64_ui64_out_ui64(in %in0 : i64, in %in0_valid : i1, in %in1 : i64, in %in1_valid : i1, in %out0_ready : i1, out in0_ready : i1, out in1_ready : i1, out out0 : i64, out out0_valid : i1) {
    %0 = comb.and %in0_valid, %in1_valid : i1
    %1 = comb.and %out0_ready, %0 : i1
    %2 = comb.add %in0, %in1 : i64
    hw.output %1, %1, %2, %0 : i1, i1, i64, i1
  }
  hw.module @handshake_join_2ins_1outs_ctrl(in %in0 : i0, in %in0_valid : i1, in %in1 : i0, in %in1_valid : i1, in %out0_ready : i1, out in0_ready : i1, out in1_ready : i1, out out0 : i0, out out0_valid : i1) {
    %c0_i0 = hw.constant 0 : i0
    %0 = comb.and %in0_valid, %in1_valid : i1
    %1 = comb.and %out0_ready, %0 : i1
    hw.output %1, %1, %c0_i0, %0 : i1, i1, i0, i1
  }
  hw.module @handshake_store_in_ui64_ui64_out_ui64_ui64(in %addrIn0 : i64, in %addrIn0_valid : i1, in %dataIn : i64, in %dataIn_valid : i1, in %ctrl : i0, in %ctrl_valid : i1, in %dataToMem_ready : i1, in %addrOut0_ready : i1, out addrIn0_ready : i1, out dataIn_ready : i1, out ctrl_ready : i1, out dataToMem : i64, out dataToMem_valid : i1, out addrOut0 : i64, out addrOut0_valid : i1) {
    %0 = comb.and %dataIn_valid, %addrIn0_valid, %ctrl_valid : i1
    %1 = comb.and %dataToMem_ready, %addrOut0_ready, %0 : i1
    hw.output %1, %1, %1, %dataIn, %0, %addrIn0, %0 : i1, i1, i1, i64, i1, i64, i1
  }
  hw.module @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1(in %in0 : i1, in %in0_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %out1_ready : i1, in %out2_ready : i1, in %out3_ready : i1, in %out4_ready : i1, out in0_ready : i1, out out0 : i1, out out0_valid : i1, out out1 : i1, out out1_valid : i1, out out2 : i1, out out2_valid : i1, out out3 : i1, out out3_valid : i1, out out4 : i1, out out4_valid : i1) {
    %true = hw.constant true
    %false = hw.constant false
    %0 = comb.xor %35, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %in0_valid : i1
    %5 = comb.and %out0_ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %35, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %in0_valid : i1
    %12 = comb.and %out1_ready, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %35, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %in0_valid : i1
    %19 = comb.and %out2_ready, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %35, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %in0_valid : i1
    %26 = comb.and %out3_ready, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %35, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %in0_valid : i1
    %33 = comb.and %out4_ready, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.and %6, %13, %20, %27, %34 {sv.namehint = "allDone"} : i1
    hw.output %35, %in0, %4, %in0, %11, %in0, %18, %in0, %25, %in0, %32 : i1, i1, i1, i1, i1, i1, i1, i1, i1, i1, i1
  }
  hw.module @handshake_load_in_ui64_ui64_out_ui64_ui64(in %addrIn0 : i64, in %addrIn0_valid : i1, in %dataFromMem : i64, in %dataFromMem_valid : i1, in %ctrl : i0, in %ctrl_valid : i1, in %dataOut_ready : i1, in %addrOut0_ready : i1, out addrIn0_ready : i1, out dataFromMem_ready : i1, out ctrl_ready : i1, out dataOut : i64, out dataOut_valid : i1, out addrOut0 : i64, out addrOut0_valid : i1) {
    %0 = comb.and %addrIn0_valid, %ctrl_valid : i1
    %1 = comb.and %addrOut0_ready, %0 : i1
    hw.output %1, %dataOut_ready, %1, %dataFromMem, %dataFromMem_valid, %addrIn0, %0 : i1, i1, i1, i64, i1, i64, i1
  }
  hw.module @arith_extsi_in_ui32_out_ui64(in %in0 : i32, in %in0_valid : i1, in %out0_ready : i1, out in0_ready : i1, out out0 : i64, out out0_valid : i1) {
    %0 = comb.and %out0_ready, %in0_valid : i1
    %1 = comb.extract %in0 from 31 : (i32) -> i1
    %2 = comb.replicate %1 : (i1) -> i32
    %3 = comb.concat %2, %in0 : i32, i32
    hw.output %0, %3, %in0_valid : i1, i64, i1
  }
  hw.module @handshake_join_3ins_1outs_ctrl(in %in0 : i0, in %in0_valid : i1, in %in1 : i0, in %in1_valid : i1, in %in2 : i0, in %in2_valid : i1, in %out0_ready : i1, out in0_ready : i1, out in1_ready : i1, out in2_ready : i1, out out0 : i0, out out0_valid : i1) {
    %c0_i0 = hw.constant 0 : i0
    %0 = comb.and %in0_valid, %in1_valid, %in2_valid : i1
    %1 = comb.and %out0_ready, %0 : i1
    hw.output %1, %1, %1, %c0_i0, %0 : i1, i1, i1, i0, i1
  }
  hw.module @main(in %in0_ld0.data : i32, in %in0_ld0.data_valid : i1, in %in1_ld0.data : i32, in %in1_ld0.data_valid : i1, in %in2_st0.done : i0, in %in2_st0.done_valid : i1, in %in3 : i0, in %in3_valid : i1, in %clock : !seq.clock, in %reset : i1, in %out0_ready : i1, in %in0_ld0.addr_ready : i1, in %in1_ld0.addr_ready : i1, in %in2_st0_ready : i1, out in0_ld0.data_ready : i1, out in1_ld0.data_ready : i1, out in2_st0.done_ready : i1, out in3_ready : i1, out out0 : i0, out out0_valid : i1, out in0_ld0.addr : i4, out in0_ld0.addr_valid : i1, out in1_ld0.addr : i4, out in1_ld0.addr_valid : i1, out in2_st0 : !hw.struct<address: i0, data: i64>, out in2_st0_valid : i1) {
    %handshake_fork0.in0_ready, %handshake_fork0.out0, %handshake_fork0.out0_valid, %handshake_fork0.out1, %handshake_fork0.out1_valid, %handshake_fork0.out2, %handshake_fork0.out2_valid, %handshake_fork0.out3, %handshake_fork0.out3_valid, %handshake_fork0.out4, %handshake_fork0.out4_valid = hw.instance "handshake_fork0" @handshake_fork_1ins_5outs_ctrl(in0: %in3: i0, in0_valid: %in3_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_mux0.in0_ready: i1, out1_ready: %handshake_constant3.ctrl_ready: i1, out2_ready: %handshake_constant2.ctrl_ready: i1, out3_ready: %handshake_constant1.ctrl_ready: i1, out4_ready: %handshake_constant0.ctrl_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1, out1: i0, out1_valid: i1, out2: i0, out2_valid: i1, out3: i0, out3_valid: i1, out4: i0, out4_valid: i1)
    %handshake_memory0.stData0_ready, %handshake_memory0.stAddr0_ready, %handshake_memory0.stData1_ready, %handshake_memory0.stAddr1_ready, %handshake_memory0.ldAddr0_ready, %handshake_memory0.ldAddr1_ready, %handshake_memory0.ldData0, %handshake_memory0.ldData0_valid, %handshake_memory0.ldData1, %handshake_memory0.ldData1_valid, %handshake_memory0.stDone0, %handshake_memory0.stDone0_valid, %handshake_memory0.stDone1, %handshake_memory0.stDone1_valid, %handshake_memory0.ldDone0, %handshake_memory0.ldDone0_valid, %handshake_memory0.ldDone1, %handshake_memory0.ldDone1_valid = hw.instance "handshake_memory0" @handshake_memory_out_ui64_id4(stData0: %handshake_store1.dataToMem: i64, stData0_valid: %handshake_store1.dataToMem_valid: i1, stAddr0: %handshake_store1.addrOut0: i64, stAddr0_valid: %handshake_store1.addrOut0_valid: i1, stData1: %handshake_store2.dataToMem: i64, stData1_valid: %handshake_store2.dataToMem_valid: i1, stAddr1: %handshake_store2.addrOut0: i64, stAddr1_valid: %handshake_store2.addrOut0_valid: i1, ldAddr0: %handshake_load3.addrOut0: i64, ldAddr0_valid: %handshake_load3.addrOut0_valid: i1, ldAddr1: %handshake_load4.addrOut0: i64, ldAddr1_valid: %handshake_load4.addrOut0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, ldData0_ready: %handshake_load3.dataFromMem_ready: i1, ldData1_ready: %handshake_load4.dataFromMem_ready: i1, stDone0_ready: %handshake_join3.in1_ready: i1, stDone1_ready: %handshake_join4.in3_ready: i1, ldDone0_ready: %handshake_fork1.in0_ready: i1, ldDone1_ready: %handshake_join6.in2_ready: i1) -> (stData0_ready: i1, stAddr0_ready: i1, stData1_ready: i1, stAddr1_ready: i1, ldAddr0_ready: i1, ldAddr1_ready: i1, ldData0: i64, ldData0_valid: i1, ldData1: i64, ldData1_valid: i1, stDone0: i0, stDone0_valid: i1, stDone1: i0, stDone1_valid: i1, ldDone0: i0, ldDone0_valid: i1, ldDone1: i0, ldDone1_valid: i1)
    %handshake_fork1.in0_ready, %handshake_fork1.out0, %handshake_fork1.out0_valid, %handshake_fork1.out1, %handshake_fork1.out1_valid = hw.instance "handshake_fork1" @handshake_fork_1ins_2outs_ctrl(in0: %handshake_memory0.ldDone0: i0, in0_valid: %handshake_memory0.ldDone0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_join5.in1_ready: i1, out1_ready: %handshake_join4.in2_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1, out1: i0, out1_valid: i1)
    %handshake_memory1.stData0_ready, %handshake_memory1.stAddr0_ready, %handshake_memory1.ldAddr0_ready, %handshake_memory1.ldData0, %handshake_memory1.ldData0_valid, %handshake_memory1.stDone0, %handshake_memory1.stDone0_valid, %handshake_memory1.ldDone0, %handshake_memory1.ldDone0_valid = hw.instance "handshake_memory1" @handshake_memory_out_ui32_id3(stData0: %handshake_store0.dataToMem: i32, stData0_valid: %handshake_store0.dataToMem_valid: i1, stAddr0: %handshake_store0.addrOut0: i64, stAddr0_valid: %handshake_store0.addrOut0_valid: i1, ldAddr0: %handshake_load2.addrOut0: i64, ldAddr0_valid: %handshake_load2.addrOut0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, ldData0_ready: %handshake_load2.dataFromMem_ready: i1, stDone0_ready: %handshake_join2.in3_ready: i1, ldDone0_ready: %handshake_join4.in1_ready: i1) -> (stData0_ready: i1, stAddr0_ready: i1, ldAddr0_ready: i1, ldData0: i32, ldData0_valid: i1, stDone0: i0, stDone0_valid: i1, ldDone0: i0, ldDone0_valid: i1)
    %arith_index_cast0.in0_ready, %arith_index_cast0.out0, %arith_index_cast0.out0_valid = hw.instance "arith_index_cast0" @arith_index_cast_in_ui64_out_ui0(in0: %handshake_store3.addrOut0: i64, in0_valid: %handshake_store3.addrOut0_valid: i1, out0_ready: %hw_struct_create0.in0_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1)
    %hw_struct_create0.in0_ready, %hw_struct_create0.in1_ready, %hw_struct_create0.out0, %hw_struct_create0.out0_valid = hw.instance "hw_struct_create0" @hw_struct_create_in_ui0_ui64_out_struct_address_ui0_data_ui64(in0: %arith_index_cast0.out0: i0, in0_valid: %arith_index_cast0.out0_valid: i1, in1: %handshake_store3.dataToMem: i64, in1_valid: %handshake_store3.dataToMem_valid: i1, out0_ready: %in2_st0_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: !hw.struct<address: i0, data: i64>, out0_valid: i1)
    %handshake_fork2.in0_ready, %handshake_fork2.out0, %handshake_fork2.out0_valid, %handshake_fork2.out1, %handshake_fork2.out1_valid = hw.instance "handshake_fork2" @handshake_fork_in_ui32_out_ui32_ui32(in0: %in1_ld0.data: i32, in0_valid: %in1_ld0.data_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_load1.dataFromMem_ready: i1, out1_ready: %handshake_join0.in0_ready: i1) -> (in0_ready: i1, out0: i32, out0_valid: i1, out1: i32, out1_valid: i1)
    %handshake_join0.in0_ready, %handshake_join0.out0, %handshake_join0.out0_valid = hw.instance "handshake_join0" @handshake_join_in_ui32_1ins_1outs_ctrl(in0: %handshake_fork2.out1: i32, in0_valid: %handshake_fork2.out1_valid: i1, out0_ready: %handshake_join2.in2_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1)
    %arith_index_cast1.in0_ready, %arith_index_cast1.out0, %arith_index_cast1.out0_valid = hw.instance "arith_index_cast1" @arith_index_cast_in_ui64_out_ui4(in0: %handshake_load1.addrOut0: i64, in0_valid: %handshake_load1.addrOut0_valid: i1, out0_ready: %in1_ld0.addr_ready: i1) -> (in0_ready: i1, out0: i4, out0_valid: i1)
    %handshake_fork3.in0_ready, %handshake_fork3.out0, %handshake_fork3.out0_valid, %handshake_fork3.out1, %handshake_fork3.out1_valid = hw.instance "handshake_fork3" @handshake_fork_in_ui32_out_ui32_ui32(in0: %in0_ld0.data: i32, in0_valid: %in0_ld0.data_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_load0.dataFromMem_ready: i1, out1_ready: %handshake_join1.in0_ready: i1) -> (in0_ready: i1, out0: i32, out0_valid: i1, out1: i32, out1_valid: i1)
    %handshake_join1.in0_ready, %handshake_join1.out0, %handshake_join1.out0_valid = hw.instance "handshake_join1" @handshake_join_in_ui32_1ins_1outs_ctrl(in0: %handshake_fork3.out1: i32, in0_valid: %handshake_fork3.out1_valid: i1, out0_ready: %handshake_join2.in1_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1)
    %arith_index_cast2.in0_ready, %arith_index_cast2.out0, %arith_index_cast2.out0_valid = hw.instance "arith_index_cast2" @arith_index_cast_in_ui64_out_ui4(in0: %handshake_load0.addrOut0: i64, in0_valid: %handshake_load0.addrOut0_valid: i1, out0_ready: %in0_ld0.addr_ready: i1) -> (in0_ready: i1, out0: i4, out0_valid: i1)
    %handshake_constant0.ctrl_ready, %handshake_constant0.out0, %handshake_constant0.out0_valid = hw.instance "handshake_constant0" @handshake_constant_c1_out_ui64(ctrl: %handshake_fork0.out4: i0, ctrl_valid: %handshake_fork0.out4_valid: i1, out0_ready: %handshake_mux2.in0_ready: i1) -> (ctrl_ready: i1, out0: i64, out0_valid: i1)
    %handshake_constant1.ctrl_ready, %handshake_constant1.out0, %handshake_constant1.out0_valid = hw.instance "handshake_constant1" @handshake_constant_c16_out_ui64(ctrl: %handshake_fork0.out3: i0, ctrl_valid: %handshake_fork0.out3_valid: i1, out0_ready: %handshake_mux3.in0_ready: i1) -> (ctrl_ready: i1, out0: i64, out0_valid: i1)
    %handshake_constant2.ctrl_ready, %handshake_constant2.out0, %handshake_constant2.out0_valid = hw.instance "handshake_constant2" @handshake_constant_c0_out_ui64(ctrl: %handshake_fork0.out2: i0, ctrl_valid: %handshake_fork0.out2_valid: i1, out0_ready: %handshake_fork4.in0_ready: i1) -> (ctrl_ready: i1, out0: i64, out0_valid: i1)
    %handshake_fork4.in0_ready, %handshake_fork4.out0, %handshake_fork4.out0_valid, %handshake_fork4.out1, %handshake_fork4.out1_valid = hw.instance "handshake_fork4" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_constant2.out0: i64, in0_valid: %handshake_constant2.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_mux4.in0_ready: i1, out1_ready: %handshake_mux1.in0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_constant3.ctrl_ready, %handshake_constant3.out0, %handshake_constant3.out0_valid = hw.instance "handshake_constant3" @handshake_constant_c0_out_ui64(ctrl: %handshake_fork0.out1: i0, ctrl_valid: %handshake_fork0.out1_valid: i1, out0_ready: %handshake_mux5.in0_ready: i1) -> (ctrl_ready: i1, out0: i64, out0_valid: i1)
    %handshake_buffer0.in0_ready, %handshake_buffer0.out0, %handshake_buffer0.out0_valid = hw.instance "handshake_buffer0" @handshake_buffer_in_ui1_out_ui1_1slots_seq_init_0(in0: %handshake_fork8.out6: i1, in0_valid: %handshake_fork8.out6_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_fork5.in0_ready: i1) -> (in0_ready: i1, out0: i1, out0_valid: i1)
    %handshake_fork5.in0_ready, %handshake_fork5.out0, %handshake_fork5.out0_valid, %handshake_fork5.out1, %handshake_fork5.out1_valid, %handshake_fork5.out2, %handshake_fork5.out2_valid, %handshake_fork5.out3, %handshake_fork5.out3_valid, %handshake_fork5.out4, %handshake_fork5.out4_valid, %handshake_fork5.out5, %handshake_fork5.out5_valid = hw.instance "handshake_fork5" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1(in0: %handshake_buffer0.out0: i1, in0_valid: %handshake_buffer0.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_mux5.select_ready: i1, out1_ready: %handshake_mux4.select_ready: i1, out2_ready: %handshake_mux3.select_ready: i1, out3_ready: %handshake_mux2.select_ready: i1, out4_ready: %handshake_mux1.select_ready: i1, out5_ready: %handshake_mux0.select_ready: i1) -> (in0_ready: i1, out0: i1, out0_valid: i1, out1: i1, out1_valid: i1, out2: i1, out2_valid: i1, out3: i1, out3_valid: i1, out4: i1, out4_valid: i1, out5: i1, out5_valid: i1)
    %handshake_mux0.select_ready, %handshake_mux0.in0_ready, %handshake_mux0.in1_ready, %handshake_mux0.out0, %handshake_mux0.out0_valid = hw.instance "handshake_mux0" @handshake_mux_in_ui1_3ins_1outs_ctrl(select: %handshake_fork5.out5: i1, select_valid: %handshake_fork5.out5_valid: i1, in0: %handshake_fork0.out0: i0, in0_valid: %handshake_fork0.out0_valid: i1, in1: %handshake_join2.out0: i0, in1_valid: %handshake_join2.out0_valid: i1, out0_ready: %handshake_cond_br5.data_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i0, out0_valid: i1)
    %handshake_mux1.select_ready, %handshake_mux1.in0_ready, %handshake_mux1.in1_ready, %handshake_mux1.out0, %handshake_mux1.out0_valid = hw.instance "handshake_mux1" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out4: i1, select_valid: %handshake_fork5.out4_valid: i1, in0: %handshake_fork4.out1: i64, in0_valid: %handshake_fork4.out1_valid: i1, in1: %arith_addi0.out0: i64, in1_valid: %arith_addi0.out0_valid: i1, out0_ready: %handshake_fork6.in0_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_fork6.in0_ready, %handshake_fork6.out0, %handshake_fork6.out0_valid, %handshake_fork6.out1, %handshake_fork6.out1_valid = hw.instance "handshake_fork6" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux1.out0: i64, in0_valid: %handshake_mux1.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_cond_br0.data_ready: i1, out1_ready: %arith_cmpi0.in0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_mux2.select_ready, %handshake_mux2.in0_ready, %handshake_mux2.in1_ready, %handshake_mux2.out0, %handshake_mux2.out0_valid = hw.instance "handshake_mux2" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out3: i1, select_valid: %handshake_fork5.out3_valid: i1, in0: %handshake_constant0.out0: i64, in0_valid: %handshake_constant0.out0_valid: i1, in1: %handshake_fork10.out1: i64, in1_valid: %handshake_fork10.out1_valid: i1, out0_ready: %handshake_cond_br1.data_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_mux3.select_ready, %handshake_mux3.in0_ready, %handshake_mux3.in1_ready, %handshake_mux3.out0, %handshake_mux3.out0_valid = hw.instance "handshake_mux3" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out2: i1, select_valid: %handshake_fork5.out2_valid: i1, in0: %handshake_constant1.out0: i64, in0_valid: %handshake_constant1.out0_valid: i1, in1: %handshake_cond_br2.outTrue: i64, in1_valid: %handshake_cond_br2.outTrue_valid: i1, out0_ready: %handshake_fork7.in0_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_fork7.in0_ready, %handshake_fork7.out0, %handshake_fork7.out0_valid, %handshake_fork7.out1, %handshake_fork7.out1_valid = hw.instance "handshake_fork7" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux3.out0: i64, in0_valid: %handshake_mux3.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_cond_br2.data_ready: i1, out1_ready: %arith_cmpi0.in1_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_mux4.select_ready, %handshake_mux4.in0_ready, %handshake_mux4.in1_ready, %handshake_mux4.out0, %handshake_mux4.out0_valid = hw.instance "handshake_mux4" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out1: i1, select_valid: %handshake_fork5.out1_valid: i1, in0: %handshake_fork4.out0: i64, in0_valid: %handshake_fork4.out0_valid: i1, in1: %handshake_cond_br3.outTrue: i64, in1_valid: %handshake_cond_br3.outTrue_valid: i1, out0_ready: %handshake_cond_br3.data_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_mux5.select_ready, %handshake_mux5.in0_ready, %handshake_mux5.in1_ready, %handshake_mux5.out0, %handshake_mux5.out0_valid = hw.instance "handshake_mux5" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out0: i1, select_valid: %handshake_fork5.out0_valid: i1, in0: %handshake_constant3.out0: i64, in0_valid: %handshake_constant3.out0_valid: i1, in1: %handshake_cond_br4.outTrue: i64, in1_valid: %handshake_cond_br4.outTrue_valid: i1, out0_ready: %handshake_cond_br4.data_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %arith_cmpi0.in0_ready, %arith_cmpi0.in1_ready, %arith_cmpi0.out0, %arith_cmpi0.out0_valid = hw.instance "arith_cmpi0" @arith_cmpi_in_ui64_ui64_out_ui1_slt(in0: %handshake_fork6.out1: i64, in0_valid: %handshake_fork6.out1_valid: i1, in1: %handshake_fork7.out1: i64, in1_valid: %handshake_fork7.out1_valid: i1, out0_ready: %handshake_fork8.in0_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i1, out0_valid: i1)
    %handshake_fork8.in0_ready, %handshake_fork8.out0, %handshake_fork8.out0_valid, %handshake_fork8.out1, %handshake_fork8.out1_valid, %handshake_fork8.out2, %handshake_fork8.out2_valid, %handshake_fork8.out3, %handshake_fork8.out3_valid, %handshake_fork8.out4, %handshake_fork8.out4_valid, %handshake_fork8.out5, %handshake_fork8.out5_valid, %handshake_fork8.out6, %handshake_fork8.out6_valid = hw.instance "handshake_fork8" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1_ui1(in0: %arith_cmpi0.out0: i1, in0_valid: %arith_cmpi0.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_cond_br5.cond_ready: i1, out1_ready: %handshake_cond_br4.cond_ready: i1, out2_ready: %handshake_cond_br3.cond_ready: i1, out3_ready: %handshake_cond_br2.cond_ready: i1, out4_ready: %handshake_cond_br1.cond_ready: i1, out5_ready: %handshake_cond_br0.cond_ready: i1, out6_ready: %handshake_buffer0.in0_ready: i1) -> (in0_ready: i1, out0: i1, out0_valid: i1, out1: i1, out1_valid: i1, out2: i1, out2_valid: i1, out3: i1, out3_valid: i1, out4: i1, out4_valid: i1, out5: i1, out5_valid: i1, out6: i1, out6_valid: i1)
    %handshake_cond_br0.cond_ready, %handshake_cond_br0.data_ready, %handshake_cond_br0.outTrue, %handshake_cond_br0.outTrue_valid, %handshake_cond_br0.outFalse, %handshake_cond_br0.outFalse_valid = hw.instance "handshake_cond_br0" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out5: i1, cond_valid: %handshake_fork8.out5_valid: i1, data: %handshake_fork6.out0: i64, data_valid: %handshake_fork6.out0_valid: i1, outTrue_ready: %handshake_fork9.in0_ready: i1, outFalse_ready: %handshake_sink0.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_sink0.in0_ready = hw.instance "handshake_sink0" @handshake_sink_in_ui64(in0: %handshake_cond_br0.outFalse: i64, in0_valid: %handshake_cond_br0.outFalse_valid: i1) -> (in0_ready: i1)
    %handshake_fork9.in0_ready, %handshake_fork9.out0, %handshake_fork9.out0_valid, %handshake_fork9.out1, %handshake_fork9.out1_valid, %handshake_fork9.out2, %handshake_fork9.out2_valid, %handshake_fork9.out3, %handshake_fork9.out3_valid = hw.instance "handshake_fork9" @handshake_fork_in_ui64_out_ui64_ui64_ui64_ui64(in0: %handshake_cond_br0.outTrue: i64, in0_valid: %handshake_cond_br0.outTrue_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %arith_addi0.in0_ready: i1, out1_ready: %handshake_store0.addrIn0_ready: i1, out2_ready: %handshake_load1.addrIn0_ready: i1, out3_ready: %handshake_load0.addrIn0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1, out2: i64, out2_valid: i1, out3: i64, out3_valid: i1)
    %handshake_cond_br1.cond_ready, %handshake_cond_br1.data_ready, %handshake_cond_br1.outTrue, %handshake_cond_br1.outTrue_valid, %handshake_cond_br1.outFalse, %handshake_cond_br1.outFalse_valid = hw.instance "handshake_cond_br1" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out4: i1, cond_valid: %handshake_fork8.out4_valid: i1, data: %handshake_mux2.out0: i64, data_valid: %handshake_mux2.out0_valid: i1, outTrue_ready: %handshake_fork10.in0_ready: i1, outFalse_ready: %handshake_mux8.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_fork10.in0_ready, %handshake_fork10.out0, %handshake_fork10.out0_valid, %handshake_fork10.out1, %handshake_fork10.out1_valid = hw.instance "handshake_fork10" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_cond_br1.outTrue: i64, in0_valid: %handshake_cond_br1.outTrue_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %arith_addi0.in1_ready: i1, out1_ready: %handshake_mux2.in1_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_cond_br2.cond_ready, %handshake_cond_br2.data_ready, %handshake_cond_br2.outTrue, %handshake_cond_br2.outTrue_valid, %handshake_cond_br2.outFalse, %handshake_cond_br2.outFalse_valid = hw.instance "handshake_cond_br2" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out3: i1, cond_valid: %handshake_fork8.out3_valid: i1, data: %handshake_fork7.out0: i64, data_valid: %handshake_fork7.out0_valid: i1, outTrue_ready: %handshake_mux3.in1_ready: i1, outFalse_ready: %handshake_mux9.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_cond_br3.cond_ready, %handshake_cond_br3.data_ready, %handshake_cond_br3.outTrue, %handshake_cond_br3.outTrue_valid, %handshake_cond_br3.outFalse, %handshake_cond_br3.outFalse_valid = hw.instance "handshake_cond_br3" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out2: i1, cond_valid: %handshake_fork8.out2_valid: i1, data: %handshake_mux4.out0: i64, data_valid: %handshake_mux4.out0_valid: i1, outTrue_ready: %handshake_mux4.in1_ready: i1, outFalse_ready: %handshake_fork11.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_fork11.in0_ready, %handshake_fork11.out0, %handshake_fork11.out0_valid, %handshake_fork11.out1, %handshake_fork11.out1_valid, %handshake_fork11.out2, %handshake_fork11.out2_valid = hw.instance "handshake_fork11" @handshake_fork_in_ui64_out_ui64_ui64_ui64(in0: %handshake_cond_br3.outFalse: i64, in0_valid: %handshake_cond_br3.outFalse_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_mux10.in0_ready: i1, out1_ready: %handshake_mux7.in0_ready: i1, out2_ready: %handshake_store1.addrIn0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1, out2: i64, out2_valid: i1)
    %handshake_cond_br4.cond_ready, %handshake_cond_br4.data_ready, %handshake_cond_br4.outTrue, %handshake_cond_br4.outTrue_valid, %handshake_cond_br4.outFalse, %handshake_cond_br4.outFalse_valid = hw.instance "handshake_cond_br4" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out1: i1, cond_valid: %handshake_fork8.out1_valid: i1, data: %handshake_mux5.out0: i64, data_valid: %handshake_mux5.out0_valid: i1, outTrue_ready: %handshake_mux5.in1_ready: i1, outFalse_ready: %handshake_store1.dataIn_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_cond_br5.cond_ready, %handshake_cond_br5.data_ready, %handshake_cond_br5.outTrue, %handshake_cond_br5.outTrue_valid, %handshake_cond_br5.outFalse, %handshake_cond_br5.outFalse_valid = hw.instance "handshake_cond_br5" @handshake_cond_br_in_ui1_2ins_2outs_ctrl(cond: %handshake_fork8.out0: i1, cond_valid: %handshake_fork8.out0_valid: i1, data: %handshake_mux0.out0: i0, data_valid: %handshake_mux0.out0_valid: i1, outTrue_ready: %handshake_fork13.in0_ready: i1, outFalse_ready: %handshake_fork12.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i0, outTrue_valid: i1, outFalse: i0, outFalse_valid: i1)
    %handshake_fork12.in0_ready, %handshake_fork12.out0, %handshake_fork12.out0_valid, %handshake_fork12.out1, %handshake_fork12.out1_valid = hw.instance "handshake_fork12" @handshake_fork_1ins_2outs_ctrl(in0: %handshake_cond_br5.outFalse: i0, in0_valid: %handshake_cond_br5.outFalse_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_store1.ctrl_ready: i1, out1_ready: %handshake_join3.in0_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1, out1: i0, out1_valid: i1)
    %handshake_fork13.in0_ready, %handshake_fork13.out0, %handshake_fork13.out0_valid, %handshake_fork13.out1, %handshake_fork13.out1_valid, %handshake_fork13.out2, %handshake_fork13.out2_valid, %handshake_fork13.out3, %handshake_fork13.out3_valid = hw.instance "handshake_fork13" @handshake_fork_1ins_4outs_ctrl(in0: %handshake_cond_br5.outTrue: i0, in0_valid: %handshake_cond_br5.outTrue_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_store0.ctrl_ready: i1, out1_ready: %handshake_load1.ctrl_ready: i1, out2_ready: %handshake_load0.ctrl_ready: i1, out3_ready: %handshake_join2.in0_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1, out1: i0, out1_valid: i1, out2: i0, out2_valid: i1, out3: i0, out3_valid: i1)
    %handshake_join2.in0_ready, %handshake_join2.in1_ready, %handshake_join2.in2_ready, %handshake_join2.in3_ready, %handshake_join2.out0, %handshake_join2.out0_valid = hw.instance "handshake_join2" @handshake_join_4ins_1outs_ctrl(in0: %handshake_fork13.out3: i0, in0_valid: %handshake_fork13.out3_valid: i1, in1: %handshake_join1.out0: i0, in1_valid: %handshake_join1.out0_valid: i1, in2: %handshake_join0.out0: i0, in2_valid: %handshake_join0.out0_valid: i1, in3: %handshake_memory1.stDone0: i0, in3_valid: %handshake_memory1.stDone0_valid: i1, out0_ready: %handshake_mux0.in1_ready: i1) -> (in0_ready: i1, in1_ready: i1, in2_ready: i1, in3_ready: i1, out0: i0, out0_valid: i1)
    %handshake_load0.addrIn0_ready, %handshake_load0.dataFromMem_ready, %handshake_load0.ctrl_ready, %handshake_load0.dataOut, %handshake_load0.dataOut_valid, %handshake_load0.addrOut0, %handshake_load0.addrOut0_valid = hw.instance "handshake_load0" @handshake_load_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork9.out3: i64, addrIn0_valid: %handshake_fork9.out3_valid: i1, dataFromMem: %handshake_fork3.out0: i32, dataFromMem_valid: %handshake_fork3.out0_valid: i1, ctrl: %handshake_fork13.out2: i0, ctrl_valid: %handshake_fork13.out2_valid: i1, dataOut_ready: %arith_muli0.in0_ready: i1, addrOut0_ready: %arith_index_cast2.in0_ready: i1) -> (addrIn0_ready: i1, dataFromMem_ready: i1, ctrl_ready: i1, dataOut: i32, dataOut_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %handshake_load1.addrIn0_ready, %handshake_load1.dataFromMem_ready, %handshake_load1.ctrl_ready, %handshake_load1.dataOut, %handshake_load1.dataOut_valid, %handshake_load1.addrOut0, %handshake_load1.addrOut0_valid = hw.instance "handshake_load1" @handshake_load_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork9.out2: i64, addrIn0_valid: %handshake_fork9.out2_valid: i1, dataFromMem: %handshake_fork2.out0: i32, dataFromMem_valid: %handshake_fork2.out0_valid: i1, ctrl: %handshake_fork13.out1: i0, ctrl_valid: %handshake_fork13.out1_valid: i1, dataOut_ready: %arith_muli0.in1_ready: i1, addrOut0_ready: %arith_index_cast1.in0_ready: i1) -> (addrIn0_ready: i1, dataFromMem_ready: i1, ctrl_ready: i1, dataOut: i32, dataOut_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %arith_muli0.in0_ready, %arith_muli0.in1_ready, %arith_muli0.out0, %arith_muli0.out0_valid = hw.instance "arith_muli0" @arith_muli_in_ui32_ui32_out_ui32(in0: %handshake_load0.dataOut: i32, in0_valid: %handshake_load0.dataOut_valid: i1, in1: %handshake_load1.dataOut: i32, in1_valid: %handshake_load1.dataOut_valid: i1, out0_ready: %handshake_store0.dataIn_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i32, out0_valid: i1)
    %handshake_store0.addrIn0_ready, %handshake_store0.dataIn_ready, %handshake_store0.ctrl_ready, %handshake_store0.dataToMem, %handshake_store0.dataToMem_valid, %handshake_store0.addrOut0, %handshake_store0.addrOut0_valid = hw.instance "handshake_store0" @handshake_store_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork9.out1: i64, addrIn0_valid: %handshake_fork9.out1_valid: i1, dataIn: %arith_muli0.out0: i32, dataIn_valid: %arith_muli0.out0_valid: i1, ctrl: %handshake_fork13.out0: i0, ctrl_valid: %handshake_fork13.out0_valid: i1, dataToMem_ready: %handshake_memory1.stData0_ready: i1, addrOut0_ready: %handshake_memory1.stAddr0_ready: i1) -> (addrIn0_ready: i1, dataIn_ready: i1, ctrl_ready: i1, dataToMem: i32, dataToMem_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %arith_addi0.in0_ready, %arith_addi0.in1_ready, %arith_addi0.out0, %arith_addi0.out0_valid = hw.instance "arith_addi0" @arith_addi_in_ui64_ui64_out_ui64(in0: %handshake_fork9.out0: i64, in0_valid: %handshake_fork9.out0_valid: i1, in1: %handshake_fork10.out0: i64, in1_valid: %handshake_fork10.out0_valid: i1, out0_ready: %handshake_mux1.in1_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_join3.in0_ready, %handshake_join3.in1_ready, %handshake_join3.out0, %handshake_join3.out0_valid = hw.instance "handshake_join3" @handshake_join_2ins_1outs_ctrl(in0: %handshake_fork12.out1: i0, in0_valid: %handshake_fork12.out1_valid: i1, in1: %handshake_memory0.stDone0: i0, in1_valid: %handshake_memory0.stDone0_valid: i1, out0_ready: %handshake_mux6.in0_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i0, out0_valid: i1)
    %handshake_store1.addrIn0_ready, %handshake_store1.dataIn_ready, %handshake_store1.ctrl_ready, %handshake_store1.dataToMem, %handshake_store1.dataToMem_valid, %handshake_store1.addrOut0, %handshake_store1.addrOut0_valid = hw.instance "handshake_store1" @handshake_store_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork11.out2: i64, addrIn0_valid: %handshake_fork11.out2_valid: i1, dataIn: %handshake_cond_br4.outFalse: i64, dataIn_valid: %handshake_cond_br4.outFalse_valid: i1, ctrl: %handshake_fork12.out0: i0, ctrl_valid: %handshake_fork12.out0_valid: i1, dataToMem_ready: %handshake_memory0.stData0_ready: i1, addrOut0_ready: %handshake_memory0.stAddr0_ready: i1) -> (addrIn0_ready: i1, dataIn_ready: i1, ctrl_ready: i1, dataToMem: i64, dataToMem_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %handshake_buffer1.in0_ready, %handshake_buffer1.out0, %handshake_buffer1.out0_valid = hw.instance "handshake_buffer1" @handshake_buffer_in_ui1_out_ui1_1slots_seq_init_0(in0: %handshake_fork17.out5: i1, in0_valid: %handshake_fork17.out5_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_fork14.in0_ready: i1) -> (in0_ready: i1, out0: i1, out0_valid: i1)
    %handshake_fork14.in0_ready, %handshake_fork14.out0, %handshake_fork14.out0_valid, %handshake_fork14.out1, %handshake_fork14.out1_valid, %handshake_fork14.out2, %handshake_fork14.out2_valid, %handshake_fork14.out3, %handshake_fork14.out3_valid, %handshake_fork14.out4, %handshake_fork14.out4_valid = hw.instance "handshake_fork14" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1(in0: %handshake_buffer1.out0: i1, in0_valid: %handshake_buffer1.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_mux10.select_ready: i1, out1_ready: %handshake_mux9.select_ready: i1, out2_ready: %handshake_mux8.select_ready: i1, out3_ready: %handshake_mux7.select_ready: i1, out4_ready: %handshake_mux6.select_ready: i1) -> (in0_ready: i1, out0: i1, out0_valid: i1, out1: i1, out1_valid: i1, out2: i1, out2_valid: i1, out3: i1, out3_valid: i1, out4: i1, out4_valid: i1)
    %handshake_mux6.select_ready, %handshake_mux6.in0_ready, %handshake_mux6.in1_ready, %handshake_mux6.out0, %handshake_mux6.out0_valid = hw.instance "handshake_mux6" @handshake_mux_in_ui1_3ins_1outs_ctrl(select: %handshake_fork14.out4: i1, select_valid: %handshake_fork14.out4_valid: i1, in0: %handshake_join3.out0: i0, in0_valid: %handshake_join3.out0_valid: i1, in1: %handshake_join4.out0: i0, in1_valid: %handshake_join4.out0_valid: i1, out0_ready: %handshake_cond_br10.data_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i0, out0_valid: i1)
    %handshake_mux7.select_ready, %handshake_mux7.in0_ready, %handshake_mux7.in1_ready, %handshake_mux7.out0, %handshake_mux7.out0_valid = hw.instance "handshake_mux7" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out3: i1, select_valid: %handshake_fork14.out3_valid: i1, in0: %handshake_fork11.out1: i64, in0_valid: %handshake_fork11.out1_valid: i1, in1: %arith_addi2.out0: i64, in1_valid: %arith_addi2.out0_valid: i1, out0_ready: %handshake_fork15.in0_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_fork15.in0_ready, %handshake_fork15.out0, %handshake_fork15.out0_valid, %handshake_fork15.out1, %handshake_fork15.out1_valid = hw.instance "handshake_fork15" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux7.out0: i64, in0_valid: %handshake_mux7.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_cond_br6.data_ready: i1, out1_ready: %arith_cmpi1.in0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_mux8.select_ready, %handshake_mux8.in0_ready, %handshake_mux8.in1_ready, %handshake_mux8.out0, %handshake_mux8.out0_valid = hw.instance "handshake_mux8" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out2: i1, select_valid: %handshake_fork14.out2_valid: i1, in0: %handshake_cond_br1.outFalse: i64, in0_valid: %handshake_cond_br1.outFalse_valid: i1, in1: %handshake_fork19.out1: i64, in1_valid: %handshake_fork19.out1_valid: i1, out0_ready: %handshake_cond_br7.data_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_mux9.select_ready, %handshake_mux9.in0_ready, %handshake_mux9.in1_ready, %handshake_mux9.out0, %handshake_mux9.out0_valid = hw.instance "handshake_mux9" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out1: i1, select_valid: %handshake_fork14.out1_valid: i1, in0: %handshake_cond_br2.outFalse: i64, in0_valid: %handshake_cond_br2.outFalse_valid: i1, in1: %handshake_cond_br8.outTrue: i64, in1_valid: %handshake_cond_br8.outTrue_valid: i1, out0_ready: %handshake_fork16.in0_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_fork16.in0_ready, %handshake_fork16.out0, %handshake_fork16.out0_valid, %handshake_fork16.out1, %handshake_fork16.out1_valid = hw.instance "handshake_fork16" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux9.out0: i64, in0_valid: %handshake_mux9.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_cond_br8.data_ready: i1, out1_ready: %arith_cmpi1.in1_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_mux10.select_ready, %handshake_mux10.in0_ready, %handshake_mux10.in1_ready, %handshake_mux10.out0, %handshake_mux10.out0_valid = hw.instance "handshake_mux10" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out0: i1, select_valid: %handshake_fork14.out0_valid: i1, in0: %handshake_fork11.out0: i64, in0_valid: %handshake_fork11.out0_valid: i1, in1: %handshake_fork20.out2: i64, in1_valid: %handshake_fork20.out2_valid: i1, out0_ready: %handshake_cond_br9.data_ready: i1) -> (select_ready: i1, in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %arith_cmpi1.in0_ready, %arith_cmpi1.in1_ready, %arith_cmpi1.out0, %arith_cmpi1.out0_valid = hw.instance "arith_cmpi1" @arith_cmpi_in_ui64_ui64_out_ui1_slt(in0: %handshake_fork15.out1: i64, in0_valid: %handshake_fork15.out1_valid: i1, in1: %handshake_fork16.out1: i64, in1_valid: %handshake_fork16.out1_valid: i1, out0_ready: %handshake_fork17.in0_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i1, out0_valid: i1)
    %handshake_fork17.in0_ready, %handshake_fork17.out0, %handshake_fork17.out0_valid, %handshake_fork17.out1, %handshake_fork17.out1_valid, %handshake_fork17.out2, %handshake_fork17.out2_valid, %handshake_fork17.out3, %handshake_fork17.out3_valid, %handshake_fork17.out4, %handshake_fork17.out4_valid, %handshake_fork17.out5, %handshake_fork17.out5_valid = hw.instance "handshake_fork17" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1(in0: %arith_cmpi1.out0: i1, in0_valid: %arith_cmpi1.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_cond_br10.cond_ready: i1, out1_ready: %handshake_cond_br9.cond_ready: i1, out2_ready: %handshake_cond_br8.cond_ready: i1, out3_ready: %handshake_cond_br7.cond_ready: i1, out4_ready: %handshake_cond_br6.cond_ready: i1, out5_ready: %handshake_buffer1.in0_ready: i1) -> (in0_ready: i1, out0: i1, out0_valid: i1, out1: i1, out1_valid: i1, out2: i1, out2_valid: i1, out3: i1, out3_valid: i1, out4: i1, out4_valid: i1, out5: i1, out5_valid: i1)
    %handshake_cond_br6.cond_ready, %handshake_cond_br6.data_ready, %handshake_cond_br6.outTrue, %handshake_cond_br6.outTrue_valid, %handshake_cond_br6.outFalse, %handshake_cond_br6.outFalse_valid = hw.instance "handshake_cond_br6" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out4: i1, cond_valid: %handshake_fork17.out4_valid: i1, data: %handshake_fork15.out0: i64, data_valid: %handshake_fork15.out0_valid: i1, outTrue_ready: %handshake_fork18.in0_ready: i1, outFalse_ready: %handshake_sink1.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_sink1.in0_ready = hw.instance "handshake_sink1" @handshake_sink_in_ui64(in0: %handshake_cond_br6.outFalse: i64, in0_valid: %handshake_cond_br6.outFalse_valid: i1) -> (in0_ready: i1)
    %handshake_fork18.in0_ready, %handshake_fork18.out0, %handshake_fork18.out0_valid, %handshake_fork18.out1, %handshake_fork18.out1_valid = hw.instance "handshake_fork18" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_cond_br6.outTrue: i64, in0_valid: %handshake_cond_br6.outTrue_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %arith_addi2.in0_ready: i1, out1_ready: %handshake_load2.addrIn0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_cond_br7.cond_ready, %handshake_cond_br7.data_ready, %handshake_cond_br7.outTrue, %handshake_cond_br7.outTrue_valid, %handshake_cond_br7.outFalse, %handshake_cond_br7.outFalse_valid = hw.instance "handshake_cond_br7" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out3: i1, cond_valid: %handshake_fork17.out3_valid: i1, data: %handshake_mux8.out0: i64, data_valid: %handshake_mux8.out0_valid: i1, outTrue_ready: %handshake_fork19.in0_ready: i1, outFalse_ready: %handshake_sink2.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_sink2.in0_ready = hw.instance "handshake_sink2" @handshake_sink_in_ui64(in0: %handshake_cond_br7.outFalse: i64, in0_valid: %handshake_cond_br7.outFalse_valid: i1) -> (in0_ready: i1)
    %handshake_fork19.in0_ready, %handshake_fork19.out0, %handshake_fork19.out0_valid, %handshake_fork19.out1, %handshake_fork19.out1_valid = hw.instance "handshake_fork19" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_cond_br7.outTrue: i64, in0_valid: %handshake_cond_br7.outTrue_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %arith_addi2.in1_ready: i1, out1_ready: %handshake_mux8.in1_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_cond_br8.cond_ready, %handshake_cond_br8.data_ready, %handshake_cond_br8.outTrue, %handshake_cond_br8.outTrue_valid, %handshake_cond_br8.outFalse, %handshake_cond_br8.outFalse_valid = hw.instance "handshake_cond_br8" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out2: i1, cond_valid: %handshake_fork17.out2_valid: i1, data: %handshake_fork16.out0: i64, data_valid: %handshake_fork16.out0_valid: i1, outTrue_ready: %handshake_mux9.in1_ready: i1, outFalse_ready: %handshake_sink3.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_sink3.in0_ready = hw.instance "handshake_sink3" @handshake_sink_in_ui64(in0: %handshake_cond_br8.outFalse: i64, in0_valid: %handshake_cond_br8.outFalse_valid: i1) -> (in0_ready: i1)
    %handshake_cond_br9.cond_ready, %handshake_cond_br9.data_ready, %handshake_cond_br9.outTrue, %handshake_cond_br9.outTrue_valid, %handshake_cond_br9.outFalse, %handshake_cond_br9.outFalse_valid = hw.instance "handshake_cond_br9" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out1: i1, cond_valid: %handshake_fork17.out1_valid: i1, data: %handshake_mux10.out0: i64, data_valid: %handshake_mux10.out0_valid: i1, outTrue_ready: %handshake_fork20.in0_ready: i1, outFalse_ready: %handshake_sink4.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i64, outTrue_valid: i1, outFalse: i64, outFalse_valid: i1)
    %handshake_sink4.in0_ready = hw.instance "handshake_sink4" @handshake_sink_in_ui64(in0: %handshake_cond_br9.outFalse: i64, in0_valid: %handshake_cond_br9.outFalse_valid: i1) -> (in0_ready: i1)
    %handshake_fork20.in0_ready, %handshake_fork20.out0, %handshake_fork20.out0_valid, %handshake_fork20.out1, %handshake_fork20.out1_valid, %handshake_fork20.out2, %handshake_fork20.out2_valid = hw.instance "handshake_fork20" @handshake_fork_in_ui64_out_ui64_ui64_ui64(in0: %handshake_cond_br9.outTrue: i64, in0_valid: %handshake_cond_br9.outTrue_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_store2.addrIn0_ready: i1, out1_ready: %handshake_load3.addrIn0_ready: i1, out2_ready: %handshake_mux10.in1_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1, out2: i64, out2_valid: i1)
    %handshake_cond_br10.cond_ready, %handshake_cond_br10.data_ready, %handshake_cond_br10.outTrue, %handshake_cond_br10.outTrue_valid, %handshake_cond_br10.outFalse, %handshake_cond_br10.outFalse_valid = hw.instance "handshake_cond_br10" @handshake_cond_br_in_ui1_2ins_2outs_ctrl(cond: %handshake_fork17.out0: i1, cond_valid: %handshake_fork17.out0_valid: i1, data: %handshake_mux6.out0: i0, data_valid: %handshake_mux6.out0_valid: i1, outTrue_ready: %handshake_fork22.in0_ready: i1, outFalse_ready: %handshake_fork21.in0_ready: i1) -> (cond_ready: i1, data_ready: i1, outTrue: i0, outTrue_valid: i1, outFalse: i0, outFalse_valid: i1)
    %handshake_fork21.in0_ready, %handshake_fork21.out0, %handshake_fork21.out0_valid, %handshake_fork21.out1, %handshake_fork21.out1_valid, %handshake_fork21.out2, %handshake_fork21.out2_valid, %handshake_fork21.out3, %handshake_fork21.out3_valid = hw.instance "handshake_fork21" @handshake_fork_1ins_4outs_ctrl(in0: %handshake_cond_br10.outFalse: i0, in0_valid: %handshake_cond_br10.outFalse_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_store3.ctrl_ready: i1, out1_ready: %handshake_load4.ctrl_ready: i1, out2_ready: %handshake_constant4.ctrl_ready: i1, out3_ready: %handshake_join6.in0_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1, out1: i0, out1_valid: i1, out2: i0, out2_valid: i1, out3: i0, out3_valid: i1)
    %handshake_fork22.in0_ready, %handshake_fork22.out0, %handshake_fork22.out0_valid, %handshake_fork22.out1, %handshake_fork22.out1_valid, %handshake_fork22.out2, %handshake_fork22.out2_valid, %handshake_fork22.out3, %handshake_fork22.out3_valid = hw.instance "handshake_fork22" @handshake_fork_1ins_4outs_ctrl(in0: %handshake_cond_br10.outTrue: i0, in0_valid: %handshake_cond_br10.outTrue_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_join5.in0_ready: i1, out1_ready: %handshake_load3.ctrl_ready: i1, out2_ready: %handshake_load2.ctrl_ready: i1, out3_ready: %handshake_join4.in0_ready: i1) -> (in0_ready: i1, out0: i0, out0_valid: i1, out1: i0, out1_valid: i1, out2: i0, out2_valid: i1, out3: i0, out3_valid: i1)
    %handshake_join4.in0_ready, %handshake_join4.in1_ready, %handshake_join4.in2_ready, %handshake_join4.in3_ready, %handshake_join4.out0, %handshake_join4.out0_valid = hw.instance "handshake_join4" @handshake_join_4ins_1outs_ctrl(in0: %handshake_fork22.out3: i0, in0_valid: %handshake_fork22.out3_valid: i1, in1: %handshake_memory1.ldDone0: i0, in1_valid: %handshake_memory1.ldDone0_valid: i1, in2: %handshake_fork1.out1: i0, in2_valid: %handshake_fork1.out1_valid: i1, in3: %handshake_memory0.stDone1: i0, in3_valid: %handshake_memory0.stDone1_valid: i1, out0_ready: %handshake_mux6.in1_ready: i1) -> (in0_ready: i1, in1_ready: i1, in2_ready: i1, in3_ready: i1, out0: i0, out0_valid: i1)
    %handshake_load2.addrIn0_ready, %handshake_load2.dataFromMem_ready, %handshake_load2.ctrl_ready, %handshake_load2.dataOut, %handshake_load2.dataOut_valid, %handshake_load2.addrOut0, %handshake_load2.addrOut0_valid = hw.instance "handshake_load2" @handshake_load_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork18.out1: i64, addrIn0_valid: %handshake_fork18.out1_valid: i1, dataFromMem: %handshake_memory1.ldData0: i32, dataFromMem_valid: %handshake_memory1.ldData0_valid: i1, ctrl: %handshake_fork22.out2: i0, ctrl_valid: %handshake_fork22.out2_valid: i1, dataOut_ready: %arith_extsi0.in0_ready: i1, addrOut0_ready: %handshake_memory1.ldAddr0_ready: i1) -> (addrIn0_ready: i1, dataFromMem_ready: i1, ctrl_ready: i1, dataOut: i32, dataOut_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %handshake_load3.addrIn0_ready, %handshake_load3.dataFromMem_ready, %handshake_load3.ctrl_ready, %handshake_load3.dataOut, %handshake_load3.dataOut_valid, %handshake_load3.addrOut0, %handshake_load3.addrOut0_valid = hw.instance "handshake_load3" @handshake_load_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork20.out1: i64, addrIn0_valid: %handshake_fork20.out1_valid: i1, dataFromMem: %handshake_memory0.ldData0: i64, dataFromMem_valid: %handshake_memory0.ldData0_valid: i1, ctrl: %handshake_fork22.out1: i0, ctrl_valid: %handshake_fork22.out1_valid: i1, dataOut_ready: %arith_addi1.in1_ready: i1, addrOut0_ready: %handshake_memory0.ldAddr0_ready: i1) -> (addrIn0_ready: i1, dataFromMem_ready: i1, ctrl_ready: i1, dataOut: i64, dataOut_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %arith_extsi0.in0_ready, %arith_extsi0.out0, %arith_extsi0.out0_valid = hw.instance "arith_extsi0" @arith_extsi_in_ui32_out_ui64(in0: %handshake_load2.dataOut: i32, in0_valid: %handshake_load2.dataOut_valid: i1, out0_ready: %arith_addi1.in0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1)
    %arith_addi1.in0_ready, %arith_addi1.in1_ready, %arith_addi1.out0, %arith_addi1.out0_valid = hw.instance "arith_addi1" @arith_addi_in_ui64_ui64_out_ui64(in0: %arith_extsi0.out0: i64, in0_valid: %arith_extsi0.out0_valid: i1, in1: %handshake_load3.dataOut: i64, in1_valid: %handshake_load3.dataOut_valid: i1, out0_ready: %handshake_store2.dataIn_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_join5.in0_ready, %handshake_join5.in1_ready, %handshake_join5.out0, %handshake_join5.out0_valid = hw.instance "handshake_join5" @handshake_join_2ins_1outs_ctrl(in0: %handshake_fork22.out0: i0, in0_valid: %handshake_fork22.out0_valid: i1, in1: %handshake_fork1.out0: i0, in1_valid: %handshake_fork1.out0_valid: i1, out0_ready: %handshake_store2.ctrl_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i0, out0_valid: i1)
    %handshake_store2.addrIn0_ready, %handshake_store2.dataIn_ready, %handshake_store2.ctrl_ready, %handshake_store2.dataToMem, %handshake_store2.dataToMem_valid, %handshake_store2.addrOut0, %handshake_store2.addrOut0_valid = hw.instance "handshake_store2" @handshake_store_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork20.out0: i64, addrIn0_valid: %handshake_fork20.out0_valid: i1, dataIn: %arith_addi1.out0: i64, dataIn_valid: %arith_addi1.out0_valid: i1, ctrl: %handshake_join5.out0: i0, ctrl_valid: %handshake_join5.out0_valid: i1, dataToMem_ready: %handshake_memory0.stData1_ready: i1, addrOut0_ready: %handshake_memory0.stAddr1_ready: i1) -> (addrIn0_ready: i1, dataIn_ready: i1, ctrl_ready: i1, dataToMem: i64, dataToMem_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %arith_addi2.in0_ready, %arith_addi2.in1_ready, %arith_addi2.out0, %arith_addi2.out0_valid = hw.instance "arith_addi2" @arith_addi_in_ui64_ui64_out_ui64(in0: %handshake_fork18.out0: i64, in0_valid: %handshake_fork18.out0_valid: i1, in1: %handshake_fork19.out0: i64, in1_valid: %handshake_fork19.out0_valid: i1, out0_ready: %handshake_mux7.in1_ready: i1) -> (in0_ready: i1, in1_ready: i1, out0: i64, out0_valid: i1)
    %handshake_join6.in0_ready, %handshake_join6.in1_ready, %handshake_join6.in2_ready, %handshake_join6.out0, %handshake_join6.out0_valid = hw.instance "handshake_join6" @handshake_join_3ins_1outs_ctrl(in0: %handshake_fork21.out3: i0, in0_valid: %handshake_fork21.out3_valid: i1, in1: %in2_st0.done: i0, in1_valid: %in2_st0.done_valid: i1, in2: %handshake_memory0.ldDone1: i0, in2_valid: %handshake_memory0.ldDone1_valid: i1, out0_ready: %out0_ready: i1) -> (in0_ready: i1, in1_ready: i1, in2_ready: i1, out0: i0, out0_valid: i1)
    %handshake_constant4.ctrl_ready, %handshake_constant4.out0, %handshake_constant4.out0_valid = hw.instance "handshake_constant4" @handshake_constant_c0_out_ui64(ctrl: %handshake_fork21.out2: i0, ctrl_valid: %handshake_fork21.out2_valid: i1, out0_ready: %handshake_fork23.in0_ready: i1) -> (ctrl_ready: i1, out0: i64, out0_valid: i1)
    %handshake_fork23.in0_ready, %handshake_fork23.out0, %handshake_fork23.out0_valid, %handshake_fork23.out1, %handshake_fork23.out1_valid = hw.instance "handshake_fork23" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_constant4.out0: i64, in0_valid: %handshake_constant4.out0_valid: i1, clock: %clock: !seq.clock, reset: %reset: i1, out0_ready: %handshake_store3.addrIn0_ready: i1, out1_ready: %handshake_load4.addrIn0_ready: i1) -> (in0_ready: i1, out0: i64, out0_valid: i1, out1: i64, out1_valid: i1)
    %handshake_load4.addrIn0_ready, %handshake_load4.dataFromMem_ready, %handshake_load4.ctrl_ready, %handshake_load4.dataOut, %handshake_load4.dataOut_valid, %handshake_load4.addrOut0, %handshake_load4.addrOut0_valid = hw.instance "handshake_load4" @handshake_load_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork23.out1: i64, addrIn0_valid: %handshake_fork23.out1_valid: i1, dataFromMem: %handshake_memory0.ldData1: i64, dataFromMem_valid: %handshake_memory0.ldData1_valid: i1, ctrl: %handshake_fork21.out1: i0, ctrl_valid: %handshake_fork21.out1_valid: i1, dataOut_ready: %handshake_store3.dataIn_ready: i1, addrOut0_ready: %handshake_memory0.ldAddr1_ready: i1) -> (addrIn0_ready: i1, dataFromMem_ready: i1, ctrl_ready: i1, dataOut: i64, dataOut_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    %handshake_store3.addrIn0_ready, %handshake_store3.dataIn_ready, %handshake_store3.ctrl_ready, %handshake_store3.dataToMem, %handshake_store3.dataToMem_valid, %handshake_store3.addrOut0, %handshake_store3.addrOut0_valid = hw.instance "handshake_store3" @handshake_store_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork23.out0: i64, addrIn0_valid: %handshake_fork23.out0_valid: i1, dataIn: %handshake_load4.dataOut: i64, dataIn_valid: %handshake_load4.dataOut_valid: i1, ctrl: %handshake_fork21.out0: i0, ctrl_valid: %handshake_fork21.out0_valid: i1, dataToMem_ready: %hw_struct_create0.in1_ready: i1, addrOut0_ready: %arith_index_cast0.in0_ready: i1) -> (addrIn0_ready: i1, dataIn_ready: i1, ctrl_ready: i1, dataToMem: i64, dataToMem_valid: i1, addrOut0: i64, addrOut0_valid: i1)
    hw.output %handshake_fork3.in0_ready, %handshake_fork2.in0_ready, %handshake_join6.in1_ready, %handshake_fork0.in0_ready, %handshake_join6.out0, %handshake_join6.out0_valid, %arith_index_cast2.out0, %arith_index_cast2.out0_valid, %arith_index_cast1.out0, %arith_index_cast1.out0_valid, %hw_struct_create0.out0, %hw_struct_create0.out0_valid : i1, i1, i1, i1, i0, i1, i4, i1, i4, i1, !hw.struct<address: i0, data: i64>, i1
  }
}

