module {
  hw.module @handshake_fork_1ins_5outs_ctrl(in %in0 : !esi.channel<i0>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i0>, out out1 : !esi.channel<i0>, out out2 : !esi.channel<i0>, out out3 : !esi.channel<i0>, out out4 : !esi.channel<i0>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %35 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i0
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i0
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput, %18 : i0
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %25 : i0
    %chanOutput_6, %ready_7 = esi.wrap.vr %rawOutput, %32 : i0
    %0 = comb.xor %35, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %35, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %35, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %valid : i1
    %19 = comb.and %ready_3, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %35, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %valid : i1
    %26 = comb.and %ready_5, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %35, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %valid : i1
    %33 = comb.and %ready_7, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.and %6, %13, %20, %27, %34 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0, %chanOutput_2, %chanOutput_4, %chanOutput_6 : !esi.channel<i0>, !esi.channel<i0>, !esi.channel<i0>, !esi.channel<i0>, !esi.channel<i0>
  }
  hw.module @handshake_memory_out_ui64_id4(in %stData0 : !esi.channel<i64>, in %stAddr0 : !esi.channel<i64>, in %stData1 : !esi.channel<i64>, in %stAddr1 : !esi.channel<i64>, in %ldAddr0 : !esi.channel<i64>, in %ldAddr1 : !esi.channel<i64>, in %clock : !seq.clock, in %reset : i1, out ldData0 : !esi.channel<i64>, out ldData1 : !esi.channel<i64>, out stDone0 : !esi.channel<i0>, out stDone1 : !esi.channel<i0>, out ldDone0 : !esi.channel<i0>, out ldDone1 : !esi.channel<i0>) {
    %true = hw.constant true
    %false = hw.constant false
    %c0_i0 = hw.constant 0 : i0
    %rawOutput, %valid = esi.unwrap.vr %stData0, %35 : i64
    %rawOutput_0, %valid_1 = esi.unwrap.vr %stAddr0, %35 : i64
    %rawOutput_2, %valid_3 = esi.unwrap.vr %stData1, %42 : i64
    %rawOutput_4, %valid_5 = esi.unwrap.vr %stAddr1, %42 : i64
    %rawOutput_6, %valid_7 = esi.unwrap.vr %ldAddr0, %15 : i64
    %rawOutput_8, %valid_9 = esi.unwrap.vr %ldAddr1, %31 : i64
    %chanOutput, %ready = esi.wrap.vr %_handshake_memory_4_rdata, %5 : i64
    %chanOutput_10, %ready_11 = esi.wrap.vr %_handshake_memory_4_rdata_20, %21 : i64
    %chanOutput_12, %ready_13 = esi.wrap.vr %c0_i0, %32 : i0
    %chanOutput_14, %ready_15 = esi.wrap.vr %c0_i0, %39 : i0
    %chanOutput_16, %ready_17 = esi.wrap.vr %c0_i0, %12 : i0
    %chanOutput_18, %ready_19 = esi.wrap.vr %c0_i0, %28 : i0
    %_handshake_memory_4 = seq.hlmem @_handshake_memory_4 %clock, %reset : <1xi64>
    %0 = comb.extract %rawOutput_6 from 0 : (i64) -> i0
    %_handshake_memory_4_rdata = seq.read %_handshake_memory_4[%0] rden %valid_7 {latency = 0 : i64} : !seq.hlmem<1xi64>
    %1 = comb.xor %15, %true : i1
    %2 = comb.and %7, %1 : i1
    %3 = seq.compreg %2, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %4 = comb.xor %3, %true {sv.namehint = "not_emitted_0"} : i1
    %5 = comb.and %4, %valid_7 : i1
    %6 = comb.and %ready, %5 : i1
    %7 = comb.or %6, %3 {sv.namehint = "done0"} : i1
    %8 = comb.xor %15, %true : i1
    %9 = comb.and %14, %8 : i1
    %10 = seq.compreg %9, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %11 = comb.xor %10, %true {sv.namehint = "not_emitted_1"} : i1
    %12 = comb.and %11, %valid_7 : i1
    %13 = comb.and %ready_17, %12 : i1
    %14 = comb.or %13, %10 {sv.namehint = "done1"} : i1
    %15 = comb.and %7, %14 {sv.namehint = "allDone"} : i1
    %16 = comb.extract %rawOutput_8 from 0 : (i64) -> i0
    %_handshake_memory_4_rdata_20 = seq.read %_handshake_memory_4[%16] rden %valid_9 {latency = 0 : i64} : !seq.hlmem<1xi64>
    %17 = comb.xor %31, %true : i1
    %18 = comb.and %23, %17 : i1
    %19 = seq.compreg %18, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %20 = comb.xor %19, %true {sv.namehint = "not_emitted_0"} : i1
    %21 = comb.and %20, %valid_9 : i1
    %22 = comb.and %ready_11, %21 : i1
    %23 = comb.or %22, %19 {sv.namehint = "done0"} : i1
    %24 = comb.xor %31, %true : i1
    %25 = comb.and %30, %24 : i1
    %26 = seq.compreg %25, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %27 = comb.xor %26, %true {sv.namehint = "not_emitted_1"} : i1
    %28 = comb.and %27, %valid_9 : i1
    %29 = comb.and %ready_19, %28 : i1
    %30 = comb.or %29, %26 {sv.namehint = "done1"} : i1
    %31 = comb.and %23, %30 {sv.namehint = "allDone"} : i1
    %32 = seq.compreg %37, %clock reset %reset, %false {sv.namehint = "writeValidBuffer"} : i1  
    %33 = comb.and %ready_13, %32 {sv.namehint = "storeCompleted"} : i1
    %34 = comb.xor %32, %true {sv.namehint = "not_writeValidBuffer"} : i1
    %35 = comb.or %34, %33 {sv.namehint = "emptyOrComplete"} : i1
    %36 = comb.and %valid_1, %valid {sv.namehint = "writeValid"} : i1
    %37 = comb.mux %35, %36, %32 : i1
    %38 = comb.extract %rawOutput_0 from 0 : (i64) -> i0
    seq.write %_handshake_memory_4[%38] %rawOutput wren %36 {latency = 1 : i64} : !seq.hlmem<1xi64>
    %39 = seq.compreg %44, %clock reset %reset, %false {sv.namehint = "writeValidBuffer"} : i1  
    %40 = comb.and %ready_15, %39 {sv.namehint = "storeCompleted"} : i1
    %41 = comb.xor %39, %true {sv.namehint = "not_writeValidBuffer"} : i1
    %42 = comb.or %41, %40 {sv.namehint = "emptyOrComplete"} : i1
    %43 = comb.and %valid_5, %valid_3 {sv.namehint = "writeValid"} : i1
    %44 = comb.mux %42, %43, %39 : i1
    %45 = comb.extract %rawOutput_4 from 0 : (i64) -> i0
    seq.write %_handshake_memory_4[%45] %rawOutput_2 wren %43 {latency = 1 : i64} : !seq.hlmem<1xi64>
    hw.output %chanOutput, %chanOutput_10, %chanOutput_12, %chanOutput_14, %chanOutput_16, %chanOutput_18 : !esi.channel<i64>, !esi.channel<i64>, !esi.channel<i0>, !esi.channel<i0>, !esi.channel<i0>, !esi.channel<i0>
  }
  hw.module @handshake_fork_1ins_2outs_ctrl(in %in0 : !esi.channel<i0>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i0>, out out1 : !esi.channel<i0>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %14 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i0
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i0
    %0 = comb.xor %14, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %14, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.and %6, %13 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0 : !esi.channel<i0>, !esi.channel<i0>
  }
  hw.module @handshake_memory_out_ui32_id3(in %stData0 : !esi.channel<i32>, in %stAddr0 : !esi.channel<i64>, in %ldAddr0 : !esi.channel<i64>, in %clock : !seq.clock, in %reset : i1, out ldData0 : !esi.channel<i32>, out stDone0 : !esi.channel<i0>, out ldDone0 : !esi.channel<i0>) {
    %true = hw.constant true
    %false = hw.constant false
    %c0_i0 = hw.constant 0 : i0
    %rawOutput, %valid = esi.unwrap.vr %stData0, %19 : i32
    %rawOutput_0, %valid_1 = esi.unwrap.vr %stAddr0, %19 : i64
    %rawOutput_2, %valid_3 = esi.unwrap.vr %ldAddr0, %15 : i64
    %chanOutput, %ready = esi.wrap.vr %_handshake_memory_3_rdata, %5 : i32
    %chanOutput_4, %ready_5 = esi.wrap.vr %c0_i0, %16 : i0
    %chanOutput_6, %ready_7 = esi.wrap.vr %c0_i0, %12 : i0
    %_handshake_memory_3 = seq.hlmem @_handshake_memory_3 %clock, %reset : <16xi32>
    %0 = comb.extract %rawOutput_2 from 0 : (i64) -> i4
    %_handshake_memory_3_rdata = seq.read %_handshake_memory_3[%0] rden %valid_3 {latency = 0 : i64} : !seq.hlmem<16xi32>
    %1 = comb.xor %15, %true : i1
    %2 = comb.and %7, %1 : i1
    %3 = seq.compreg %2, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %4 = comb.xor %3, %true {sv.namehint = "not_emitted_0"} : i1
    %5 = comb.and %4, %valid_3 : i1
    %6 = comb.and %ready, %5 : i1
    %7 = comb.or %6, %3 {sv.namehint = "done0"} : i1
    %8 = comb.xor %15, %true : i1
    %9 = comb.and %14, %8 : i1
    %10 = seq.compreg %9, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %11 = comb.xor %10, %true {sv.namehint = "not_emitted_1"} : i1
    %12 = comb.and %11, %valid_3 : i1
    %13 = comb.and %ready_7, %12 : i1
    %14 = comb.or %13, %10 {sv.namehint = "done1"} : i1
    %15 = comb.and %7, %14 {sv.namehint = "allDone"} : i1
    %16 = seq.compreg %21, %clock reset %reset, %false {sv.namehint = "writeValidBuffer"} : i1  
    %17 = comb.and %ready_5, %16 {sv.namehint = "storeCompleted"} : i1
    %18 = comb.xor %16, %true {sv.namehint = "not_writeValidBuffer"} : i1
    %19 = comb.or %18, %17 {sv.namehint = "emptyOrComplete"} : i1
    %20 = comb.and %valid_1, %valid {sv.namehint = "writeValid"} : i1
    %21 = comb.mux %19, %20, %16 : i1
    %22 = comb.extract %rawOutput_0 from 0 : (i64) -> i4
    seq.write %_handshake_memory_3[%22] %rawOutput wren %20 {latency = 1 : i64} : !seq.hlmem<16xi32>
    hw.output %chanOutput, %chanOutput_4, %chanOutput_6 : !esi.channel<i32>, !esi.channel<i0>, !esi.channel<i0>
  }
  hw.module @arith_index_cast_in_ui64_out_ui0(in %in0 : !esi.channel<i64>, out out0 : !esi.channel<i0>) {
    %rawOutput, %valid = esi.unwrap.vr %in0, %0 : i64
    %chanOutput, %ready = esi.wrap.vr %1, %valid : i0
    %0 = comb.and %ready, %valid : i1
    %1 = comb.extract %rawOutput from 0 : (i64) -> i0
    hw.output %chanOutput : !esi.channel<i0>
  }
  hw.module @hw_struct_create_in_ui0_ui64_out_struct_address_ui0_data_ui64(in %in0 : !esi.channel<i0>, in %in1 : !esi.channel<i64>, out out0 : !esi.channel<!hw.struct<address: i0, data: i64>>) {
    %rawOutput, %valid = esi.unwrap.vr %in0, %1 : i0
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in1, %1 : i64
    %chanOutput, %ready = esi.wrap.vr %2, %0 : !hw.struct<address: i0, data: i64>
    %0 = comb.and %valid, %valid_1 : i1
    %1 = comb.and %ready, %0 : i1
    %2 = hw.struct_create (%rawOutput, %rawOutput_0) : !hw.struct<address: i0, data: i64>
    hw.output %chanOutput : !esi.channel<!hw.struct<address: i0, data: i64>>
  }
  hw.module @handshake_fork_in_ui32_out_ui32_ui32(in %in0 : !esi.channel<i32>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i32>, out out1 : !esi.channel<i32>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %14 : i32
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i32
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i32
    %0 = comb.xor %14, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %14, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.and %6, %13 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0 : !esi.channel<i32>, !esi.channel<i32>
  }
  hw.module @handshake_join_in_ui32_1ins_1outs_ctrl(in %in0 : !esi.channel<i32>, out out0 : !esi.channel<i0>) {
    %c0_i0 = hw.constant 0 : i0
    %rawOutput, %valid = esi.unwrap.vr %in0, %0 : i32
    %chanOutput, %ready = esi.wrap.vr %c0_i0, %valid : i0
    %0 = comb.and %ready, %valid : i1
    hw.output %chanOutput : !esi.channel<i0>
  }
  hw.module @arith_index_cast_in_ui64_out_ui4(in %in0 : !esi.channel<i64>, out out0 : !esi.channel<i4>) {
    %rawOutput, %valid = esi.unwrap.vr %in0, %0 : i64
    %chanOutput, %ready = esi.wrap.vr %1, %valid : i4
    %0 = comb.and %ready, %valid : i1
    %1 = comb.extract %rawOutput from 0 : (i64) -> i4
    hw.output %chanOutput : !esi.channel<i4>
  }
  hw.module @handshake_constant_c1_out_ui64(in %ctrl : !esi.channel<i0>, out out0 : !esi.channel<i64>) {
    %c1_i64 = hw.constant 1 : i64
    %rawOutput, %valid = esi.unwrap.vr %ctrl, %ready : i0
    %chanOutput, %ready = esi.wrap.vr %c1_i64, %valid : i64
    hw.output %chanOutput : !esi.channel<i64>
  }
  hw.module @handshake_constant_c16_out_ui64(in %ctrl : !esi.channel<i0>, out out0 : !esi.channel<i64>) {
    %c16_i64 = hw.constant 16 : i64
    %rawOutput, %valid = esi.unwrap.vr %ctrl, %ready : i0
    %chanOutput, %ready = esi.wrap.vr %c16_i64, %valid : i64
    hw.output %chanOutput : !esi.channel<i64>
  }
  hw.module @handshake_constant_c0_out_ui64(in %ctrl : !esi.channel<i0>, out out0 : !esi.channel<i64>) {
    %c0_i64 = hw.constant 0 : i64
    %rawOutput, %valid = esi.unwrap.vr %ctrl, %ready : i0
    %chanOutput, %ready = esi.wrap.vr %c0_i64, %valid : i64
    hw.output %chanOutput : !esi.channel<i64>
  }
  hw.module @handshake_fork_in_ui64_out_ui64_ui64(in %in0 : !esi.channel<i64>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i64>, out out1 : !esi.channel<i64>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %14 : i64
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i64
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i64
    %0 = comb.xor %14, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %14, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.and %6, %13 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0 : !esi.channel<i64>, !esi.channel<i64>
  }
  hw.module @handshake_buffer_in_ui1_out_ui1_1slots_seq_init_0(in %in0 : !esi.channel<i1>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i1>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %2 : i1
    %chanOutput, %ready = esi.wrap.vr %16, %7 : i1
    %0 = seq.compreg %3, %clock reset %reset, %true {sv.namehint = "valid0_reg"} : i1  
    %1 = comb.xor %0, %true {sv.namehint = "not_valid0_reg"} : i1
    %2 = comb.or %1, %8 : i1
    %3 = comb.mux %2, %valid, %0 : i1
    %4 = comb.mux %2, %rawOutput, %5 : i1
    %5 = seq.compreg %4, %clock reset %reset, %false {sv.namehint = "data0_reg"} : i1  
    %6 = seq.compreg %14, %clock reset %reset, %false {sv.namehint = "ready0_reg"} : i1  
    %7 = comb.mux %6, %6, %0 : i1
    %8 = comb.xor %6, %true {sv.namehint = "not_ready0_reg"} : i1
    %9 = comb.xor %ready, %true : i1
    %10 = comb.and %9, %8 : i1
    %11 = comb.mux %10, %0, %6 : i1
    %12 = comb.and %ready, %6 : i1
    %13 = comb.xor %12, %true : i1
    %14 = comb.and %13, %11 : i1
    %15 = seq.compreg %19, %clock reset %reset, %false {sv.namehint = "ctrl_data0_reg"} : i1  
    %16 = comb.mux %6, %15, %5 : i1
    %17 = comb.mux %10, %5, %15 : i1
    %18 = comb.xor %12, %true : i1
    %19 = comb.and %18, %17 : i1
    hw.output %chanOutput : !esi.channel<i1>
  }
  hw.module @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1(in %in0 : !esi.channel<i1>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i1>, out out1 : !esi.channel<i1>, out out2 : !esi.channel<i1>, out out3 : !esi.channel<i1>, out out4 : !esi.channel<i1>, out out5 : !esi.channel<i1>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %42 : i1
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i1
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i1
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput, %18 : i1
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %25 : i1
    %chanOutput_6, %ready_7 = esi.wrap.vr %rawOutput, %32 : i1
    %chanOutput_8, %ready_9 = esi.wrap.vr %rawOutput, %39 : i1
    %0 = comb.xor %42, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %42, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %42, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %valid : i1
    %19 = comb.and %ready_3, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %42, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %valid : i1
    %26 = comb.and %ready_5, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %42, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %valid : i1
    %33 = comb.and %ready_7, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.xor %42, %true : i1
    %36 = comb.and %41, %35 : i1
    %37 = seq.compreg %36, %clock reset %reset, %false {sv.namehint = "emitted_5"} : i1  
    %38 = comb.xor %37, %true {sv.namehint = "not_emitted_5"} : i1
    %39 = comb.and %38, %valid : i1
    %40 = comb.and %ready_9, %39 : i1
    %41 = comb.or %40, %37 {sv.namehint = "done5"} : i1
    %42 = comb.and %6, %13, %20, %27, %34, %41 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0, %chanOutput_2, %chanOutput_4, %chanOutput_6, %chanOutput_8 : !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>
  }
  hw.module @handshake_mux_in_ui1_3ins_1outs_ctrl(in %select : !esi.channel<i1>, in %in0 : !esi.channel<i0>, in %in1 : !esi.channel<i0>, out out0 : !esi.channel<i0>) {
    %c1_i2 = hw.constant 1 : i2
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %select, %4 : i1
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in0, %6 : i0
    %rawOutput_2, %valid_3 = esi.unwrap.vr %in1, %8 : i0
    %chanOutput, %ready = esi.wrap.vr %9, %3 : i0
    %0 = comb.concat %false, %rawOutput : i1, i1
    %1 = comb.shl %c1_i2, %0 : i2
    %2 = comb.mux %rawOutput, %valid_3, %valid_1 : i1
    %3 = comb.and %2, %valid : i1
    %4 = comb.and %3, %ready : i1
    %5 = comb.extract %1 from 0 : (i2) -> i1
    %6 = comb.and %5, %4 : i1
    %7 = comb.extract %1 from 1 : (i2) -> i1
    %8 = comb.and %7, %4 : i1
    %9 = comb.mux %rawOutput, %rawOutput_2, %rawOutput_0 : i0
    hw.output %chanOutput : !esi.channel<i0>
  }
  hw.module @handshake_mux_in_ui1_ui64_ui64_out_ui64(in %select : !esi.channel<i1>, in %in0 : !esi.channel<i64>, in %in1 : !esi.channel<i64>, out out0 : !esi.channel<i64>) {
    %c1_i2 = hw.constant 1 : i2
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %select, %4 : i1
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in0, %6 : i64
    %rawOutput_2, %valid_3 = esi.unwrap.vr %in1, %8 : i64
    %chanOutput, %ready = esi.wrap.vr %9, %3 : i64
    %0 = comb.concat %false, %rawOutput : i1, i1
    %1 = comb.shl %c1_i2, %0 : i2
    %2 = comb.mux %rawOutput, %valid_3, %valid_1 : i1
    %3 = comb.and %2, %valid : i1
    %4 = comb.and %3, %ready : i1
    %5 = comb.extract %1 from 0 : (i2) -> i1
    %6 = comb.and %5, %4 : i1
    %7 = comb.extract %1 from 1 : (i2) -> i1
    %8 = comb.and %7, %4 : i1
    %9 = comb.mux %rawOutput, %rawOutput_2, %rawOutput_0 : i64
    hw.output %chanOutput : !esi.channel<i64>
  }
  hw.module @arith_cmpi_in_ui64_ui64_out_ui1_slt(in %in0 : !esi.channel<i64>, in %in1 : !esi.channel<i64>, out out0 : !esi.channel<i1>) {
    %rawOutput, %valid = esi.unwrap.vr %in0, %1 : i64
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in1, %1 : i64
    %chanOutput, %ready = esi.wrap.vr %2, %0 : i1
    %0 = comb.and %valid, %valid_1 : i1
    %1 = comb.and %ready, %0 : i1
    %2 = comb.icmp slt %rawOutput, %rawOutput_0 : i64
    hw.output %chanOutput : !esi.channel<i1>
  }
  hw.module @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1_ui1(in %in0 : !esi.channel<i1>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i1>, out out1 : !esi.channel<i1>, out out2 : !esi.channel<i1>, out out3 : !esi.channel<i1>, out out4 : !esi.channel<i1>, out out5 : !esi.channel<i1>, out out6 : !esi.channel<i1>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %49 : i1
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i1
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i1
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput, %18 : i1
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %25 : i1
    %chanOutput_6, %ready_7 = esi.wrap.vr %rawOutput, %32 : i1
    %chanOutput_8, %ready_9 = esi.wrap.vr %rawOutput, %39 : i1
    %chanOutput_10, %ready_11 = esi.wrap.vr %rawOutput, %46 : i1
    %0 = comb.xor %49, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %49, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %49, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %valid : i1
    %19 = comb.and %ready_3, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %49, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %valid : i1
    %26 = comb.and %ready_5, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %49, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %valid : i1
    %33 = comb.and %ready_7, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.xor %49, %true : i1
    %36 = comb.and %41, %35 : i1
    %37 = seq.compreg %36, %clock reset %reset, %false {sv.namehint = "emitted_5"} : i1  
    %38 = comb.xor %37, %true {sv.namehint = "not_emitted_5"} : i1
    %39 = comb.and %38, %valid : i1
    %40 = comb.and %ready_9, %39 : i1
    %41 = comb.or %40, %37 {sv.namehint = "done5"} : i1
    %42 = comb.xor %49, %true : i1
    %43 = comb.and %48, %42 : i1
    %44 = seq.compreg %43, %clock reset %reset, %false {sv.namehint = "emitted_6"} : i1  
    %45 = comb.xor %44, %true {sv.namehint = "not_emitted_6"} : i1
    %46 = comb.and %45, %valid : i1
    %47 = comb.and %ready_11, %46 : i1
    %48 = comb.or %47, %44 {sv.namehint = "done6"} : i1
    %49 = comb.and %6, %13, %20, %27, %34, %41, %48 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0, %chanOutput_2, %chanOutput_4, %chanOutput_6, %chanOutput_8, %chanOutput_10 : !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>
  }
  hw.module @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(in %cond : !esi.channel<i1>, in %data : !esi.channel<i64>, out outTrue : !esi.channel<i64>, out outFalse : !esi.channel<i64>) {
    %true = hw.constant true
    %rawOutput, %valid = esi.unwrap.vr %cond, %5 : i1
    %rawOutput_0, %valid_1 = esi.unwrap.vr %data, %5 : i64
    %chanOutput, %ready = esi.wrap.vr %rawOutput_0, %1 : i64
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput_0, %3 : i64
    %0 = comb.and %valid, %valid_1 : i1
    %1 = comb.and %rawOutput, %0 : i1
    %2 = comb.xor %rawOutput, %true : i1
    %3 = comb.and %2, %0 : i1
    %4 = comb.mux %rawOutput, %ready, %ready_3 : i1
    %5 = comb.and %4, %0 : i1
    hw.output %chanOutput, %chanOutput_2 : !esi.channel<i64>, !esi.channel<i64>
  }
  hw.module @handshake_sink_in_ui64(in %in0 : !esi.channel<i64>) {
    %true = hw.constant true
    %rawOutput, %valid = esi.unwrap.vr %in0, %true : i64
    hw.output
  }
  hw.module @handshake_fork_in_ui64_out_ui64_ui64_ui64_ui64(in %in0 : !esi.channel<i64>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i64>, out out1 : !esi.channel<i64>, out out2 : !esi.channel<i64>, out out3 : !esi.channel<i64>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %28 : i64
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i64
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i64
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput, %18 : i64
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %25 : i64
    %0 = comb.xor %28, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %28, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %28, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %valid : i1
    %19 = comb.and %ready_3, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %28, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %valid : i1
    %26 = comb.and %ready_5, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.and %6, %13, %20, %27 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0, %chanOutput_2, %chanOutput_4 : !esi.channel<i64>, !esi.channel<i64>, !esi.channel<i64>, !esi.channel<i64>
  }
  hw.module @handshake_fork_in_ui64_out_ui64_ui64_ui64(in %in0 : !esi.channel<i64>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i64>, out out1 : !esi.channel<i64>, out out2 : !esi.channel<i64>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %21 : i64
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i64
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i64
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput, %18 : i64
    %0 = comb.xor %21, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %21, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %21, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %valid : i1
    %19 = comb.and %ready_3, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.and %6, %13, %20 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0, %chanOutput_2 : !esi.channel<i64>, !esi.channel<i64>, !esi.channel<i64>
  }
  hw.module @handshake_cond_br_in_ui1_2ins_2outs_ctrl(in %cond : !esi.channel<i1>, in %data : !esi.channel<i0>, out outTrue : !esi.channel<i0>, out outFalse : !esi.channel<i0>) {
    %true = hw.constant true
    %rawOutput, %valid = esi.unwrap.vr %cond, %5 : i1
    %rawOutput_0, %valid_1 = esi.unwrap.vr %data, %5 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput_0, %1 : i0
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput_0, %3 : i0
    %0 = comb.and %valid, %valid_1 : i1
    %1 = comb.and %rawOutput, %0 : i1
    %2 = comb.xor %rawOutput, %true : i1
    %3 = comb.and %2, %0 : i1
    %4 = comb.mux %rawOutput, %ready, %ready_3 : i1
    %5 = comb.and %4, %0 : i1
    hw.output %chanOutput, %chanOutput_2 : !esi.channel<i0>, !esi.channel<i0>
  }
  hw.module @handshake_fork_1ins_4outs_ctrl(in %in0 : !esi.channel<i0>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i0>, out out1 : !esi.channel<i0>, out out2 : !esi.channel<i0>, out out3 : !esi.channel<i0>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %28 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i0
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i0
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput, %18 : i0
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %25 : i0
    %0 = comb.xor %28, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %28, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %28, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %valid : i1
    %19 = comb.and %ready_3, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %28, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %valid : i1
    %26 = comb.and %ready_5, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.and %6, %13, %20, %27 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0, %chanOutput_2, %chanOutput_4 : !esi.channel<i0>, !esi.channel<i0>, !esi.channel<i0>, !esi.channel<i0>
  }
  hw.module @handshake_join_4ins_1outs_ctrl(in %in0 : !esi.channel<i0>, in %in1 : !esi.channel<i0>, in %in2 : !esi.channel<i0>, in %in3 : !esi.channel<i0>, out out0 : !esi.channel<i0>) {
    %c0_i0 = hw.constant 0 : i0
    %rawOutput, %valid = esi.unwrap.vr %in0, %1 : i0
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in1, %1 : i0
    %rawOutput_2, %valid_3 = esi.unwrap.vr %in2, %1 : i0
    %rawOutput_4, %valid_5 = esi.unwrap.vr %in3, %1 : i0
    %chanOutput, %ready = esi.wrap.vr %c0_i0, %0 : i0
    %0 = comb.and %valid, %valid_1, %valid_3, %valid_5 : i1
    %1 = comb.and %ready, %0 : i1
    hw.output %chanOutput : !esi.channel<i0>
  }
  hw.module @handshake_load_in_ui64_ui32_out_ui32_ui64(in %addrIn0 : !esi.channel<i64>, in %dataFromMem : !esi.channel<i32>, in %ctrl : !esi.channel<i0>, out dataOut : !esi.channel<i32>, out addrOut0 : !esi.channel<i64>) {
    %rawOutput, %valid = esi.unwrap.vr %addrIn0, %1 : i64
    %rawOutput_0, %valid_1 = esi.unwrap.vr %dataFromMem, %ready : i32
    %rawOutput_2, %valid_3 = esi.unwrap.vr %ctrl, %1 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput_0, %valid_1 : i32
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %0 : i64
    %0 = comb.and %valid, %valid_3 : i1
    %1 = comb.and %ready_5, %0 : i1
    hw.output %chanOutput, %chanOutput_4 : !esi.channel<i32>, !esi.channel<i64>
  }
  hw.module @arith_muli_in_ui32_ui32_out_ui32(in %in0 : !esi.channel<i32>, in %in1 : !esi.channel<i32>, out out0 : !esi.channel<i32>) {
    %rawOutput, %valid = esi.unwrap.vr %in0, %1 : i32
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in1, %1 : i32
    %chanOutput, %ready = esi.wrap.vr %2, %0 : i32
    %0 = comb.and %valid, %valid_1 : i1
    %1 = comb.and %ready, %0 : i1
    %2 = comb.mul %rawOutput, %rawOutput_0 : i32
    hw.output %chanOutput : !esi.channel<i32>
  }
  hw.module @handshake_store_in_ui64_ui32_out_ui32_ui64(in %addrIn0 : !esi.channel<i64>, in %dataIn : !esi.channel<i32>, in %ctrl : !esi.channel<i0>, out dataToMem : !esi.channel<i32>, out addrOut0 : !esi.channel<i64>) {
    %rawOutput, %valid = esi.unwrap.vr %addrIn0, %1 : i64
    %rawOutput_0, %valid_1 = esi.unwrap.vr %dataIn, %1 : i32
    %rawOutput_2, %valid_3 = esi.unwrap.vr %ctrl, %1 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput_0, %0 : i32
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %0 : i64
    %0 = comb.and %valid_1, %valid, %valid_3 : i1
    %1 = comb.and %ready, %ready_5, %0 : i1
    hw.output %chanOutput, %chanOutput_4 : !esi.channel<i32>, !esi.channel<i64>
  }
  hw.module @arith_addi_in_ui64_ui64_out_ui64(in %in0 : !esi.channel<i64>, in %in1 : !esi.channel<i64>, out out0 : !esi.channel<i64>) {
    %rawOutput, %valid = esi.unwrap.vr %in0, %1 : i64
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in1, %1 : i64
    %chanOutput, %ready = esi.wrap.vr %2, %0 : i64
    %0 = comb.and %valid, %valid_1 : i1
    %1 = comb.and %ready, %0 : i1
    %2 = comb.add %rawOutput, %rawOutput_0 : i64
    hw.output %chanOutput : !esi.channel<i64>
  }
  hw.module @handshake_join_2ins_1outs_ctrl(in %in0 : !esi.channel<i0>, in %in1 : !esi.channel<i0>, out out0 : !esi.channel<i0>) {
    %c0_i0 = hw.constant 0 : i0
    %rawOutput, %valid = esi.unwrap.vr %in0, %1 : i0
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in1, %1 : i0
    %chanOutput, %ready = esi.wrap.vr %c0_i0, %0 : i0
    %0 = comb.and %valid, %valid_1 : i1
    %1 = comb.and %ready, %0 : i1
    hw.output %chanOutput : !esi.channel<i0>
  }
  hw.module @handshake_store_in_ui64_ui64_out_ui64_ui64(in %addrIn0 : !esi.channel<i64>, in %dataIn : !esi.channel<i64>, in %ctrl : !esi.channel<i0>, out dataToMem : !esi.channel<i64>, out addrOut0 : !esi.channel<i64>) {
    %rawOutput, %valid = esi.unwrap.vr %addrIn0, %1 : i64
    %rawOutput_0, %valid_1 = esi.unwrap.vr %dataIn, %1 : i64
    %rawOutput_2, %valid_3 = esi.unwrap.vr %ctrl, %1 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput_0, %0 : i64
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %0 : i64
    %0 = comb.and %valid_1, %valid, %valid_3 : i1
    %1 = comb.and %ready, %ready_5, %0 : i1
    hw.output %chanOutput, %chanOutput_4 : !esi.channel<i64>, !esi.channel<i64>
  }
  hw.module @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1(in %in0 : !esi.channel<i1>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i1>, out out1 : !esi.channel<i1>, out out2 : !esi.channel<i1>, out out3 : !esi.channel<i1>, out out4 : !esi.channel<i1>) {
    %true = hw.constant true
    %false = hw.constant false
    %rawOutput, %valid = esi.unwrap.vr %in0, %35 : i1
    %chanOutput, %ready = esi.wrap.vr %rawOutput, %4 : i1
    %chanOutput_0, %ready_1 = esi.wrap.vr %rawOutput, %11 : i1
    %chanOutput_2, %ready_3 = esi.wrap.vr %rawOutput, %18 : i1
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %25 : i1
    %chanOutput_6, %ready_7 = esi.wrap.vr %rawOutput, %32 : i1
    %0 = comb.xor %35, %true : i1
    %1 = comb.and %6, %0 : i1
    %2 = seq.compreg %1, %clock reset %reset, %false {sv.namehint = "emitted_0"} : i1  
    %3 = comb.xor %2, %true {sv.namehint = "not_emitted_0"} : i1
    %4 = comb.and %3, %valid : i1
    %5 = comb.and %ready, %4 : i1
    %6 = comb.or %5, %2 {sv.namehint = "done0"} : i1
    %7 = comb.xor %35, %true : i1
    %8 = comb.and %13, %7 : i1
    %9 = seq.compreg %8, %clock reset %reset, %false {sv.namehint = "emitted_1"} : i1  
    %10 = comb.xor %9, %true {sv.namehint = "not_emitted_1"} : i1
    %11 = comb.and %10, %valid : i1
    %12 = comb.and %ready_1, %11 : i1
    %13 = comb.or %12, %9 {sv.namehint = "done1"} : i1
    %14 = comb.xor %35, %true : i1
    %15 = comb.and %20, %14 : i1
    %16 = seq.compreg %15, %clock reset %reset, %false {sv.namehint = "emitted_2"} : i1  
    %17 = comb.xor %16, %true {sv.namehint = "not_emitted_2"} : i1
    %18 = comb.and %17, %valid : i1
    %19 = comb.and %ready_3, %18 : i1
    %20 = comb.or %19, %16 {sv.namehint = "done2"} : i1
    %21 = comb.xor %35, %true : i1
    %22 = comb.and %27, %21 : i1
    %23 = seq.compreg %22, %clock reset %reset, %false {sv.namehint = "emitted_3"} : i1  
    %24 = comb.xor %23, %true {sv.namehint = "not_emitted_3"} : i1
    %25 = comb.and %24, %valid : i1
    %26 = comb.and %ready_5, %25 : i1
    %27 = comb.or %26, %23 {sv.namehint = "done3"} : i1
    %28 = comb.xor %35, %true : i1
    %29 = comb.and %34, %28 : i1
    %30 = seq.compreg %29, %clock reset %reset, %false {sv.namehint = "emitted_4"} : i1  
    %31 = comb.xor %30, %true {sv.namehint = "not_emitted_4"} : i1
    %32 = comb.and %31, %valid : i1
    %33 = comb.and %ready_7, %32 : i1
    %34 = comb.or %33, %30 {sv.namehint = "done4"} : i1
    %35 = comb.and %6, %13, %20, %27, %34 {sv.namehint = "allDone"} : i1
    hw.output %chanOutput, %chanOutput_0, %chanOutput_2, %chanOutput_4, %chanOutput_6 : !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>, !esi.channel<i1>
  }
  hw.module @handshake_load_in_ui64_ui64_out_ui64_ui64(in %addrIn0 : !esi.channel<i64>, in %dataFromMem : !esi.channel<i64>, in %ctrl : !esi.channel<i0>, out dataOut : !esi.channel<i64>, out addrOut0 : !esi.channel<i64>) {
    %rawOutput, %valid = esi.unwrap.vr %addrIn0, %1 : i64
    %rawOutput_0, %valid_1 = esi.unwrap.vr %dataFromMem, %ready : i64
    %rawOutput_2, %valid_3 = esi.unwrap.vr %ctrl, %1 : i0
    %chanOutput, %ready = esi.wrap.vr %rawOutput_0, %valid_1 : i64
    %chanOutput_4, %ready_5 = esi.wrap.vr %rawOutput, %0 : i64
    %0 = comb.and %valid, %valid_3 : i1
    %1 = comb.and %ready_5, %0 : i1
    hw.output %chanOutput, %chanOutput_4 : !esi.channel<i64>, !esi.channel<i64>
  }
  hw.module @arith_extsi_in_ui32_out_ui64(in %in0 : !esi.channel<i32>, out out0 : !esi.channel<i64>) {
    %rawOutput, %valid = esi.unwrap.vr %in0, %0 : i32
    %chanOutput, %ready = esi.wrap.vr %3, %valid : i64
    %0 = comb.and %ready, %valid : i1
    %1 = comb.extract %rawOutput from 31 : (i32) -> i1
    %2 = comb.replicate %1 : (i1) -> i32
    %3 = comb.concat %2, %rawOutput : i32, i32
    hw.output %chanOutput : !esi.channel<i64>
  }
  hw.module @handshake_join_3ins_1outs_ctrl(in %in0 : !esi.channel<i0>, in %in1 : !esi.channel<i0>, in %in2 : !esi.channel<i0>, out out0 : !esi.channel<i0>) {
    %c0_i0 = hw.constant 0 : i0
    %rawOutput, %valid = esi.unwrap.vr %in0, %1 : i0
    %rawOutput_0, %valid_1 = esi.unwrap.vr %in1, %1 : i0
    %rawOutput_2, %valid_3 = esi.unwrap.vr %in2, %1 : i0
    %chanOutput, %ready = esi.wrap.vr %c0_i0, %0 : i0
    %0 = comb.and %valid, %valid_1, %valid_3 : i1
    %1 = comb.and %ready, %0 : i1
    hw.output %chanOutput : !esi.channel<i0>
  }
  hw.module @main(in %in0_ld0.data : !esi.channel<i32>, in %in1_ld0.data : !esi.channel<i32>, in %in2_st0.done : !esi.channel<i0>, in %in3 : !esi.channel<i0>, in %clock : !seq.clock, in %reset : i1, out out0 : !esi.channel<i0>, out in0_ld0.addr : !esi.channel<i4>, out in1_ld0.addr : !esi.channel<i4>, out in2_st0 : !esi.channel<!hw.struct<address: i0, data: i64>>) {
    %handshake_fork0.out0, %handshake_fork0.out1, %handshake_fork0.out2, %handshake_fork0.out3, %handshake_fork0.out4 = hw.instance "handshake_fork0" @handshake_fork_1ins_5outs_ctrl(in0: %in3: !esi.channel<i0>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i0>, out1: !esi.channel<i0>, out2: !esi.channel<i0>, out3: !esi.channel<i0>, out4: !esi.channel<i0>)
    %handshake_memory0.ldData0, %handshake_memory0.ldData1, %handshake_memory0.stDone0, %handshake_memory0.stDone1, %handshake_memory0.ldDone0, %handshake_memory0.ldDone1 = hw.instance "handshake_memory0" @handshake_memory_out_ui64_id4(stData0: %handshake_store1.dataToMem: !esi.channel<i64>, stAddr0: %handshake_store1.addrOut0: !esi.channel<i64>, stData1: %handshake_store2.dataToMem: !esi.channel<i64>, stAddr1: %handshake_store2.addrOut0: !esi.channel<i64>, ldAddr0: %handshake_load3.addrOut0: !esi.channel<i64>, ldAddr1: %handshake_load4.addrOut0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (ldData0: !esi.channel<i64>, ldData1: !esi.channel<i64>, stDone0: !esi.channel<i0>, stDone1: !esi.channel<i0>, ldDone0: !esi.channel<i0>, ldDone1: !esi.channel<i0>)
    %handshake_fork1.out0, %handshake_fork1.out1 = hw.instance "handshake_fork1" @handshake_fork_1ins_2outs_ctrl(in0: %handshake_memory0.ldDone0: !esi.channel<i0>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i0>, out1: !esi.channel<i0>)
    %handshake_memory1.ldData0, %handshake_memory1.stDone0, %handshake_memory1.ldDone0 = hw.instance "handshake_memory1" @handshake_memory_out_ui32_id3(stData0: %handshake_store0.dataToMem: !esi.channel<i32>, stAddr0: %handshake_store0.addrOut0: !esi.channel<i64>, ldAddr0: %handshake_load2.addrOut0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (ldData0: !esi.channel<i32>, stDone0: !esi.channel<i0>, ldDone0: !esi.channel<i0>)
    %arith_index_cast0.out0 = hw.instance "arith_index_cast0" @arith_index_cast_in_ui64_out_ui0(in0: %handshake_store3.addrOut0: !esi.channel<i64>) -> (out0: !esi.channel<i0>)
    %hw_struct_create0.out0 = hw.instance "hw_struct_create0" @hw_struct_create_in_ui0_ui64_out_struct_address_ui0_data_ui64(in0: %arith_index_cast0.out0: !esi.channel<i0>, in1: %handshake_store3.dataToMem: !esi.channel<i64>) -> (out0: !esi.channel<!hw.struct<address: i0, data: i64>>)
    %handshake_fork2.out0, %handshake_fork2.out1 = hw.instance "handshake_fork2" @handshake_fork_in_ui32_out_ui32_ui32(in0: %in1_ld0.data: !esi.channel<i32>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i32>, out1: !esi.channel<i32>)
    %handshake_join0.out0 = hw.instance "handshake_join0" @handshake_join_in_ui32_1ins_1outs_ctrl(in0: %handshake_fork2.out1: !esi.channel<i32>) -> (out0: !esi.channel<i0>)
    %arith_index_cast1.out0 = hw.instance "arith_index_cast1" @arith_index_cast_in_ui64_out_ui4(in0: %handshake_load1.addrOut0: !esi.channel<i64>) -> (out0: !esi.channel<i4>)
    %handshake_fork3.out0, %handshake_fork3.out1 = hw.instance "handshake_fork3" @handshake_fork_in_ui32_out_ui32_ui32(in0: %in0_ld0.data: !esi.channel<i32>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i32>, out1: !esi.channel<i32>)
    %handshake_join1.out0 = hw.instance "handshake_join1" @handshake_join_in_ui32_1ins_1outs_ctrl(in0: %handshake_fork3.out1: !esi.channel<i32>) -> (out0: !esi.channel<i0>)
    %arith_index_cast2.out0 = hw.instance "arith_index_cast2" @arith_index_cast_in_ui64_out_ui4(in0: %handshake_load0.addrOut0: !esi.channel<i64>) -> (out0: !esi.channel<i4>)
    %handshake_constant0.out0 = hw.instance "handshake_constant0" @handshake_constant_c1_out_ui64(ctrl: %handshake_fork0.out4: !esi.channel<i0>) -> (out0: !esi.channel<i64>)
    %handshake_constant1.out0 = hw.instance "handshake_constant1" @handshake_constant_c16_out_ui64(ctrl: %handshake_fork0.out3: !esi.channel<i0>) -> (out0: !esi.channel<i64>)
    %handshake_constant2.out0 = hw.instance "handshake_constant2" @handshake_constant_c0_out_ui64(ctrl: %handshake_fork0.out2: !esi.channel<i0>) -> (out0: !esi.channel<i64>)
    %handshake_fork4.out0, %handshake_fork4.out1 = hw.instance "handshake_fork4" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_constant2.out0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_constant3.out0 = hw.instance "handshake_constant3" @handshake_constant_c0_out_ui64(ctrl: %handshake_fork0.out1: !esi.channel<i0>) -> (out0: !esi.channel<i64>)
    %handshake_buffer0.out0 = hw.instance "handshake_buffer0" @handshake_buffer_in_ui1_out_ui1_1slots_seq_init_0(in0: %handshake_fork8.out6: !esi.channel<i1>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i1>)
    %handshake_fork5.out0, %handshake_fork5.out1, %handshake_fork5.out2, %handshake_fork5.out3, %handshake_fork5.out4, %handshake_fork5.out5 = hw.instance "handshake_fork5" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1(in0: %handshake_buffer0.out0: !esi.channel<i1>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i1>, out1: !esi.channel<i1>, out2: !esi.channel<i1>, out3: !esi.channel<i1>, out4: !esi.channel<i1>, out5: !esi.channel<i1>)
    %handshake_mux0.out0 = hw.instance "handshake_mux0" @handshake_mux_in_ui1_3ins_1outs_ctrl(select: %handshake_fork5.out5: !esi.channel<i1>, in0: %handshake_fork0.out0: !esi.channel<i0>, in1: %handshake_join2.out0: !esi.channel<i0>) -> (out0: !esi.channel<i0>)
    %handshake_mux1.out0 = hw.instance "handshake_mux1" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out4: !esi.channel<i1>, in0: %handshake_fork4.out1: !esi.channel<i64>, in1: %arith_addi0.out0: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_fork6.out0, %handshake_fork6.out1 = hw.instance "handshake_fork6" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux1.out0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_mux2.out0 = hw.instance "handshake_mux2" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out3: !esi.channel<i1>, in0: %handshake_constant0.out0: !esi.channel<i64>, in1: %handshake_fork10.out1: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_mux3.out0 = hw.instance "handshake_mux3" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out2: !esi.channel<i1>, in0: %handshake_constant1.out0: !esi.channel<i64>, in1: %handshake_cond_br2.outTrue: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_fork7.out0, %handshake_fork7.out1 = hw.instance "handshake_fork7" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux3.out0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_mux4.out0 = hw.instance "handshake_mux4" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out1: !esi.channel<i1>, in0: %handshake_fork4.out0: !esi.channel<i64>, in1: %handshake_cond_br3.outTrue: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_mux5.out0 = hw.instance "handshake_mux5" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork5.out0: !esi.channel<i1>, in0: %handshake_constant3.out0: !esi.channel<i64>, in1: %handshake_cond_br4.outTrue: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %arith_cmpi0.out0 = hw.instance "arith_cmpi0" @arith_cmpi_in_ui64_ui64_out_ui1_slt(in0: %handshake_fork6.out1: !esi.channel<i64>, in1: %handshake_fork7.out1: !esi.channel<i64>) -> (out0: !esi.channel<i1>)
    %handshake_fork8.out0, %handshake_fork8.out1, %handshake_fork8.out2, %handshake_fork8.out3, %handshake_fork8.out4, %handshake_fork8.out5, %handshake_fork8.out6 = hw.instance "handshake_fork8" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1_ui1(in0: %arith_cmpi0.out0: !esi.channel<i1>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i1>, out1: !esi.channel<i1>, out2: !esi.channel<i1>, out3: !esi.channel<i1>, out4: !esi.channel<i1>, out5: !esi.channel<i1>, out6: !esi.channel<i1>)
    %handshake_cond_br0.outTrue, %handshake_cond_br0.outFalse = hw.instance "handshake_cond_br0" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out5: !esi.channel<i1>, data: %handshake_fork6.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    hw.instance "handshake_sink0" @handshake_sink_in_ui64(in0: %handshake_cond_br0.outFalse: !esi.channel<i64>) -> ()
    %handshake_fork9.out0, %handshake_fork9.out1, %handshake_fork9.out2, %handshake_fork9.out3 = hw.instance "handshake_fork9" @handshake_fork_in_ui64_out_ui64_ui64_ui64_ui64(in0: %handshake_cond_br0.outTrue: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>, out2: !esi.channel<i64>, out3: !esi.channel<i64>)
    %handshake_cond_br1.outTrue, %handshake_cond_br1.outFalse = hw.instance "handshake_cond_br1" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out4: !esi.channel<i1>, data: %handshake_mux2.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    %handshake_fork10.out0, %handshake_fork10.out1 = hw.instance "handshake_fork10" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_cond_br1.outTrue: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_cond_br2.outTrue, %handshake_cond_br2.outFalse = hw.instance "handshake_cond_br2" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out3: !esi.channel<i1>, data: %handshake_fork7.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    %handshake_cond_br3.outTrue, %handshake_cond_br3.outFalse = hw.instance "handshake_cond_br3" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out2: !esi.channel<i1>, data: %handshake_mux4.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    %handshake_fork11.out0, %handshake_fork11.out1, %handshake_fork11.out2 = hw.instance "handshake_fork11" @handshake_fork_in_ui64_out_ui64_ui64_ui64(in0: %handshake_cond_br3.outFalse: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>, out2: !esi.channel<i64>)
    %handshake_cond_br4.outTrue, %handshake_cond_br4.outFalse = hw.instance "handshake_cond_br4" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork8.out1: !esi.channel<i1>, data: %handshake_mux5.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    %handshake_cond_br5.outTrue, %handshake_cond_br5.outFalse = hw.instance "handshake_cond_br5" @handshake_cond_br_in_ui1_2ins_2outs_ctrl(cond: %handshake_fork8.out0: !esi.channel<i1>, data: %handshake_mux0.out0: !esi.channel<i0>) -> (outTrue: !esi.channel<i0>, outFalse: !esi.channel<i0>)
    %handshake_fork12.out0, %handshake_fork12.out1 = hw.instance "handshake_fork12" @handshake_fork_1ins_2outs_ctrl(in0: %handshake_cond_br5.outFalse: !esi.channel<i0>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i0>, out1: !esi.channel<i0>)
    %handshake_fork13.out0, %handshake_fork13.out1, %handshake_fork13.out2, %handshake_fork13.out3 = hw.instance "handshake_fork13" @handshake_fork_1ins_4outs_ctrl(in0: %handshake_cond_br5.outTrue: !esi.channel<i0>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i0>, out1: !esi.channel<i0>, out2: !esi.channel<i0>, out3: !esi.channel<i0>)
    %handshake_join2.out0 = hw.instance "handshake_join2" @handshake_join_4ins_1outs_ctrl(in0: %handshake_fork13.out3: !esi.channel<i0>, in1: %handshake_join1.out0: !esi.channel<i0>, in2: %handshake_join0.out0: !esi.channel<i0>, in3: %handshake_memory1.stDone0: !esi.channel<i0>) -> (out0: !esi.channel<i0>)
    %handshake_load0.dataOut, %handshake_load0.addrOut0 = hw.instance "handshake_load0" @handshake_load_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork9.out3: !esi.channel<i64>, dataFromMem: %handshake_fork3.out0: !esi.channel<i32>, ctrl: %handshake_fork13.out2: !esi.channel<i0>) -> (dataOut: !esi.channel<i32>, addrOut0: !esi.channel<i64>)
    %handshake_load1.dataOut, %handshake_load1.addrOut0 = hw.instance "handshake_load1" @handshake_load_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork9.out2: !esi.channel<i64>, dataFromMem: %handshake_fork2.out0: !esi.channel<i32>, ctrl: %handshake_fork13.out1: !esi.channel<i0>) -> (dataOut: !esi.channel<i32>, addrOut0: !esi.channel<i64>)
    %arith_muli0.out0 = hw.instance "arith_muli0" @arith_muli_in_ui32_ui32_out_ui32(in0: %handshake_load0.dataOut: !esi.channel<i32>, in1: %handshake_load1.dataOut: !esi.channel<i32>) -> (out0: !esi.channel<i32>)
    %handshake_store0.dataToMem, %handshake_store0.addrOut0 = hw.instance "handshake_store0" @handshake_store_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork9.out1: !esi.channel<i64>, dataIn: %arith_muli0.out0: !esi.channel<i32>, ctrl: %handshake_fork13.out0: !esi.channel<i0>) -> (dataToMem: !esi.channel<i32>, addrOut0: !esi.channel<i64>)
    %arith_addi0.out0 = hw.instance "arith_addi0" @arith_addi_in_ui64_ui64_out_ui64(in0: %handshake_fork9.out0: !esi.channel<i64>, in1: %handshake_fork10.out0: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_join3.out0 = hw.instance "handshake_join3" @handshake_join_2ins_1outs_ctrl(in0: %handshake_fork12.out1: !esi.channel<i0>, in1: %handshake_memory0.stDone0: !esi.channel<i0>) -> (out0: !esi.channel<i0>)
    %handshake_store1.dataToMem, %handshake_store1.addrOut0 = hw.instance "handshake_store1" @handshake_store_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork11.out2: !esi.channel<i64>, dataIn: %handshake_cond_br4.outFalse: !esi.channel<i64>, ctrl: %handshake_fork12.out0: !esi.channel<i0>) -> (dataToMem: !esi.channel<i64>, addrOut0: !esi.channel<i64>)
    %handshake_buffer1.out0 = hw.instance "handshake_buffer1" @handshake_buffer_in_ui1_out_ui1_1slots_seq_init_0(in0: %handshake_fork17.out5: !esi.channel<i1>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i1>)
    %handshake_fork14.out0, %handshake_fork14.out1, %handshake_fork14.out2, %handshake_fork14.out3, %handshake_fork14.out4 = hw.instance "handshake_fork14" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1(in0: %handshake_buffer1.out0: !esi.channel<i1>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i1>, out1: !esi.channel<i1>, out2: !esi.channel<i1>, out3: !esi.channel<i1>, out4: !esi.channel<i1>)
    %handshake_mux6.out0 = hw.instance "handshake_mux6" @handshake_mux_in_ui1_3ins_1outs_ctrl(select: %handshake_fork14.out4: !esi.channel<i1>, in0: %handshake_join3.out0: !esi.channel<i0>, in1: %handshake_join4.out0: !esi.channel<i0>) -> (out0: !esi.channel<i0>)
    %handshake_mux7.out0 = hw.instance "handshake_mux7" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out3: !esi.channel<i1>, in0: %handshake_fork11.out1: !esi.channel<i64>, in1: %arith_addi2.out0: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_fork15.out0, %handshake_fork15.out1 = hw.instance "handshake_fork15" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux7.out0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_mux8.out0 = hw.instance "handshake_mux8" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out2: !esi.channel<i1>, in0: %handshake_cond_br1.outFalse: !esi.channel<i64>, in1: %handshake_fork19.out1: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_mux9.out0 = hw.instance "handshake_mux9" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out1: !esi.channel<i1>, in0: %handshake_cond_br2.outFalse: !esi.channel<i64>, in1: %handshake_cond_br8.outTrue: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_fork16.out0, %handshake_fork16.out1 = hw.instance "handshake_fork16" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_mux9.out0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_mux10.out0 = hw.instance "handshake_mux10" @handshake_mux_in_ui1_ui64_ui64_out_ui64(select: %handshake_fork14.out0: !esi.channel<i1>, in0: %handshake_fork11.out0: !esi.channel<i64>, in1: %handshake_fork20.out2: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %arith_cmpi1.out0 = hw.instance "arith_cmpi1" @arith_cmpi_in_ui64_ui64_out_ui1_slt(in0: %handshake_fork15.out1: !esi.channel<i64>, in1: %handshake_fork16.out1: !esi.channel<i64>) -> (out0: !esi.channel<i1>)
    %handshake_fork17.out0, %handshake_fork17.out1, %handshake_fork17.out2, %handshake_fork17.out3, %handshake_fork17.out4, %handshake_fork17.out5 = hw.instance "handshake_fork17" @handshake_fork_in_ui1_out_ui1_ui1_ui1_ui1_ui1_ui1(in0: %arith_cmpi1.out0: !esi.channel<i1>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i1>, out1: !esi.channel<i1>, out2: !esi.channel<i1>, out3: !esi.channel<i1>, out4: !esi.channel<i1>, out5: !esi.channel<i1>)
    %handshake_cond_br6.outTrue, %handshake_cond_br6.outFalse = hw.instance "handshake_cond_br6" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out4: !esi.channel<i1>, data: %handshake_fork15.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    hw.instance "handshake_sink1" @handshake_sink_in_ui64(in0: %handshake_cond_br6.outFalse: !esi.channel<i64>) -> ()
    %handshake_fork18.out0, %handshake_fork18.out1 = hw.instance "handshake_fork18" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_cond_br6.outTrue: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_cond_br7.outTrue, %handshake_cond_br7.outFalse = hw.instance "handshake_cond_br7" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out3: !esi.channel<i1>, data: %handshake_mux8.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    hw.instance "handshake_sink2" @handshake_sink_in_ui64(in0: %handshake_cond_br7.outFalse: !esi.channel<i64>) -> ()
    %handshake_fork19.out0, %handshake_fork19.out1 = hw.instance "handshake_fork19" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_cond_br7.outTrue: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_cond_br8.outTrue, %handshake_cond_br8.outFalse = hw.instance "handshake_cond_br8" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out2: !esi.channel<i1>, data: %handshake_fork16.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    hw.instance "handshake_sink3" @handshake_sink_in_ui64(in0: %handshake_cond_br8.outFalse: !esi.channel<i64>) -> ()
    %handshake_cond_br9.outTrue, %handshake_cond_br9.outFalse = hw.instance "handshake_cond_br9" @handshake_cond_br_in_ui1_ui64_out_ui64_ui64(cond: %handshake_fork17.out1: !esi.channel<i1>, data: %handshake_mux10.out0: !esi.channel<i64>) -> (outTrue: !esi.channel<i64>, outFalse: !esi.channel<i64>)
    hw.instance "handshake_sink4" @handshake_sink_in_ui64(in0: %handshake_cond_br9.outFalse: !esi.channel<i64>) -> ()
    %handshake_fork20.out0, %handshake_fork20.out1, %handshake_fork20.out2 = hw.instance "handshake_fork20" @handshake_fork_in_ui64_out_ui64_ui64_ui64(in0: %handshake_cond_br9.outTrue: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>, out2: !esi.channel<i64>)
    %handshake_cond_br10.outTrue, %handshake_cond_br10.outFalse = hw.instance "handshake_cond_br10" @handshake_cond_br_in_ui1_2ins_2outs_ctrl(cond: %handshake_fork17.out0: !esi.channel<i1>, data: %handshake_mux6.out0: !esi.channel<i0>) -> (outTrue: !esi.channel<i0>, outFalse: !esi.channel<i0>)
    %handshake_fork21.out0, %handshake_fork21.out1, %handshake_fork21.out2, %handshake_fork21.out3 = hw.instance "handshake_fork21" @handshake_fork_1ins_4outs_ctrl(in0: %handshake_cond_br10.outFalse: !esi.channel<i0>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i0>, out1: !esi.channel<i0>, out2: !esi.channel<i0>, out3: !esi.channel<i0>)
    %handshake_fork22.out0, %handshake_fork22.out1, %handshake_fork22.out2, %handshake_fork22.out3 = hw.instance "handshake_fork22" @handshake_fork_1ins_4outs_ctrl(in0: %handshake_cond_br10.outTrue: !esi.channel<i0>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i0>, out1: !esi.channel<i0>, out2: !esi.channel<i0>, out3: !esi.channel<i0>)
    %handshake_join4.out0 = hw.instance "handshake_join4" @handshake_join_4ins_1outs_ctrl(in0: %handshake_fork22.out3: !esi.channel<i0>, in1: %handshake_memory1.ldDone0: !esi.channel<i0>, in2: %handshake_fork1.out1: !esi.channel<i0>, in3: %handshake_memory0.stDone1: !esi.channel<i0>) -> (out0: !esi.channel<i0>)
    %handshake_load2.dataOut, %handshake_load2.addrOut0 = hw.instance "handshake_load2" @handshake_load_in_ui64_ui32_out_ui32_ui64(addrIn0: %handshake_fork18.out1: !esi.channel<i64>, dataFromMem: %handshake_memory1.ldData0: !esi.channel<i32>, ctrl: %handshake_fork22.out2: !esi.channel<i0>) -> (dataOut: !esi.channel<i32>, addrOut0: !esi.channel<i64>)
    %handshake_load3.dataOut, %handshake_load3.addrOut0 = hw.instance "handshake_load3" @handshake_load_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork20.out1: !esi.channel<i64>, dataFromMem: %handshake_memory0.ldData0: !esi.channel<i64>, ctrl: %handshake_fork22.out1: !esi.channel<i0>) -> (dataOut: !esi.channel<i64>, addrOut0: !esi.channel<i64>)
    %arith_extsi0.out0 = hw.instance "arith_extsi0" @arith_extsi_in_ui32_out_ui64(in0: %handshake_load2.dataOut: !esi.channel<i32>) -> (out0: !esi.channel<i64>)
    %arith_addi1.out0 = hw.instance "arith_addi1" @arith_addi_in_ui64_ui64_out_ui64(in0: %arith_extsi0.out0: !esi.channel<i64>, in1: %handshake_load3.dataOut: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_join5.out0 = hw.instance "handshake_join5" @handshake_join_2ins_1outs_ctrl(in0: %handshake_fork22.out0: !esi.channel<i0>, in1: %handshake_fork1.out0: !esi.channel<i0>) -> (out0: !esi.channel<i0>)
    %handshake_store2.dataToMem, %handshake_store2.addrOut0 = hw.instance "handshake_store2" @handshake_store_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork20.out0: !esi.channel<i64>, dataIn: %arith_addi1.out0: !esi.channel<i64>, ctrl: %handshake_join5.out0: !esi.channel<i0>) -> (dataToMem: !esi.channel<i64>, addrOut0: !esi.channel<i64>)
    %arith_addi2.out0 = hw.instance "arith_addi2" @arith_addi_in_ui64_ui64_out_ui64(in0: %handshake_fork18.out0: !esi.channel<i64>, in1: %handshake_fork19.out0: !esi.channel<i64>) -> (out0: !esi.channel<i64>)
    %handshake_join6.out0 = hw.instance "handshake_join6" @handshake_join_3ins_1outs_ctrl(in0: %handshake_fork21.out3: !esi.channel<i0>, in1: %in2_st0.done: !esi.channel<i0>, in2: %handshake_memory0.ldDone1: !esi.channel<i0>) -> (out0: !esi.channel<i0>)
    %handshake_constant4.out0 = hw.instance "handshake_constant4" @handshake_constant_c0_out_ui64(ctrl: %handshake_fork21.out2: !esi.channel<i0>) -> (out0: !esi.channel<i64>)
    %handshake_fork23.out0, %handshake_fork23.out1 = hw.instance "handshake_fork23" @handshake_fork_in_ui64_out_ui64_ui64(in0: %handshake_constant4.out0: !esi.channel<i64>, clock: %clock: !seq.clock, reset: %reset: i1) -> (out0: !esi.channel<i64>, out1: !esi.channel<i64>)
    %handshake_load4.dataOut, %handshake_load4.addrOut0 = hw.instance "handshake_load4" @handshake_load_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork23.out1: !esi.channel<i64>, dataFromMem: %handshake_memory0.ldData1: !esi.channel<i64>, ctrl: %handshake_fork21.out1: !esi.channel<i0>) -> (dataOut: !esi.channel<i64>, addrOut0: !esi.channel<i64>)
    %handshake_store3.dataToMem, %handshake_store3.addrOut0 = hw.instance "handshake_store3" @handshake_store_in_ui64_ui64_out_ui64_ui64(addrIn0: %handshake_fork23.out0: !esi.channel<i64>, dataIn: %handshake_load4.dataOut: !esi.channel<i64>, ctrl: %handshake_fork21.out0: !esi.channel<i0>) -> (dataToMem: !esi.channel<i64>, addrOut0: !esi.channel<i64>)
    hw.output %handshake_join6.out0, %arith_index_cast2.out0, %arith_index_cast1.out0, %hw_struct_create0.out0 : !esi.channel<i0>, !esi.channel<i4>, !esi.channel<i4>, !esi.channel<!hw.struct<address: i0, data: i64>>
  }
}

