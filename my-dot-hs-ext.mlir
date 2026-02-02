module {
  handshake.func @main(%arg0: i32, %arg1: i32, %arg2: none, %arg3: none, ...) -> (none, i4, i4, !hw.struct<address: i0, data: i64>) attributes {argNames = ["in0_ld0.data", "in1_ld0.data", "in2_st0.done", "in3"], resNames = ["out0", "in0_ld0.addr", "in1_ld0.addr", "in2_st0"]} {
    %0:5 = fork [5] %arg3 : none
    %1:6 = memory[ld = 2, st = 2] (%dataResult_13, %addressResult_14, %dataResult_29, %addressResult_30, %addressResults_28, %addressResults_32) {id = 4 : i32, lsq = false} : memref<1xi64>, (i64, index, i64, index, index, index) -> (i64, i64, none, none, none, none)
    %2:2 = fork [2] %1#4 : none
    %3:3 = memory[ld = 1, st = 1] (%dataResult_12, %addressResult, %addressResults_26) {id = 3 : i32, lsq = false} : memref<16xi32>, (i32, index, index) -> (i32, none, none)
    %4 = arith.index_cast %addressResult_34 : index to i0
    %5 = hw.struct_create (%4, %dataResult_33) : !hw.struct<address: i0, data: i64>
    %6:2 = fork [2] %arg1 : i32
    %7 = join %6#1 : i32
    %8 = arith.index_cast %addressResults_11 : index to i4
    %9:2 = fork [2] %arg0 : i32
    %10 = join %9#1 : i32
    %11 = arith.index_cast %addressResults : index to i4
    %12 = constant %0#4 {value = 1 : index} : index
    %13 = constant %0#3 {value = 16 : index} : index
    %14 = constant %0#2 {value = 0 : index} : index
    %15:2 = fork [2] %14 : index
    %16 = constant %0#1 {value = 0 : i64} : i64
    %17 = buffer [1] seq %28#6 {initValues = [0]} : i1
    %18:6 = fork [6] %17 : i1
    %19 = mux %18#5 [%0#0, %34] : i1, none
    %20 = mux %18#4 [%15#1, %36] : i1, index
    %21:2 = fork [2] %20 : index
    %22 = mux %18#3 [%12, %30#1] : i1, index
    %23 = mux %18#2 [%13, %trueResult_2] : i1, index
    %24:2 = fork [2] %23 : index
    %25 = mux %18#1 [%15#0, %trueResult_4] : i1, index
    %26 = mux %18#0 [%16, %trueResult_6] : i1, i64
    %27 = arith.cmpi slt, %21#1, %24#1 : index
    %28:7 = fork [7] %27 : i1
    %trueResult, %falseResult = cond_br %28#5, %21#0 : index
    sink %falseResult : index
    %29:4 = fork [4] %trueResult : index
    %trueResult_0, %falseResult_1 = cond_br %28#4, %22 : index
    %30:2 = fork [2] %trueResult_0 : index
    %trueResult_2, %falseResult_3 = cond_br %28#3, %24#0 : index
    %trueResult_4, %falseResult_5 = cond_br %28#2, %25 : index
    %31:3 = fork [3] %falseResult_5 : index
    %trueResult_6, %falseResult_7 = cond_br %28#1, %26 : i64
    %trueResult_8, %falseResult_9 = cond_br %28#0, %19 : none
    %32:2 = fork [2] %falseResult_9 : none
    %33:4 = fork [4] %trueResult_8 : none
    %34 = join %33#3, %10, %7, %3#1 : none, none, none, none
    %dataResult, %addressResults = load [%29#3] %9#0, %33#2 : index, i32
    %dataResult_10, %addressResults_11 = load [%29#2] %6#0, %33#1 : index, i32
    %35 = arith.muli %dataResult, %dataResult_10 : i32
    %dataResult_12, %addressResult = store [%29#1] %35, %33#0 : index, i32
    %36 = arith.addi %29#0, %30#0 : index
    %37 = join %32#1, %1#2 : none, none
    %dataResult_13, %addressResult_14 = store [%31#2] %falseResult_7, %32#0 : index, i64
    %38 = buffer [1] seq %48#5 {initValues = [0]} : i1
    %39:5 = fork [5] %38 : i1
    %40 = mux %39#4 [%37, %54] : i1, none
    %41 = mux %39#3 [%31#1, %58] : i1, index
    %42:2 = fork [2] %41 : index
    %43 = mux %39#2 [%falseResult_1, %50#1] : i1, index
    %44 = mux %39#1 [%falseResult_3, %trueResult_19] : i1, index
    %45:2 = fork [2] %44 : index
    %46 = mux %39#0 [%31#0, %51#2] : i1, index
    %47 = arith.cmpi slt, %42#1, %45#1 : index
    %48:6 = fork [6] %47 : i1
    %trueResult_15, %falseResult_16 = cond_br %48#4, %42#0 : index
    sink %falseResult_16 : index
    %49:2 = fork [2] %trueResult_15 : index
    %trueResult_17, %falseResult_18 = cond_br %48#3, %43 : index
    sink %falseResult_18 : index
    %50:2 = fork [2] %trueResult_17 : index
    %trueResult_19, %falseResult_20 = cond_br %48#2, %45#0 : index
    sink %falseResult_20 : index
    %trueResult_21, %falseResult_22 = cond_br %48#1, %46 : index
    sink %falseResult_22 : index
    %51:3 = fork [3] %trueResult_21 : index
    %trueResult_23, %falseResult_24 = cond_br %48#0, %40 : none
    %52:4 = fork [4] %falseResult_24 : none
    %53:4 = fork [4] %trueResult_23 : none
    %54 = join %53#3, %3#2, %2#1, %1#3 : none, none, none, none
    %dataResult_25, %addressResults_26 = load [%49#1] %3#0, %53#2 : index, i32
    %dataResult_27, %addressResults_28 = load [%51#1] %1#0, %53#1 : index, i64
    %55 = arith.extsi %dataResult_25 : i32 to i64
    %56 = arith.addi %55, %dataResult_27 : i64
    %57 = join %53#0, %2#0 : none, none
    %dataResult_29, %addressResult_30 = store [%51#0] %56, %57 : index, i64
    %58 = arith.addi %49#0, %50#0 : index
    %59 = join %52#3, %arg2, %1#5 : none, none, none
    %60 = constant %52#2 {value = 0 : index} : index
    %61:2 = fork [2] %60 : index
    %dataResult_31, %addressResults_32 = load [%61#1] %1#1, %52#1 : index, i64
    %dataResult_33, %addressResult_34 = store [%61#0] %dataResult_31, %52#0 : index, i64
    return %59, %11, %8, %5 : none, i4, i4, !hw.struct<address: i0, data: i64>
  }
}

