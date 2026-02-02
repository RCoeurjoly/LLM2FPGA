module {
  handshake.func @main(%arg0: memref<16xi32, strided<[?], offset: ?>>, %arg1: memref<16xi32, strided<[?], offset: ?>>, %arg2: memref<1xi64>, %arg3: none, ...) -> none attributes {argNames = ["in0", "in1", "in2", "in3"], resNames = ["out0"]} {
    %0:6 = memory[ld = 2, st = 2] (%dataResult_13, %addressResult_14, %dataResult_29, %addressResult_30, %addressResults_28, %addressResults_32) {id = 4 : i32, lsq = false} : memref<1xi64>, (i64, index, i64, index, index, index) -> (i64, i64, none, none, none, none)
    %1:3 = memory[ld = 1, st = 1] (%dataResult_12, %addressResult, %addressResults_26) {id = 3 : i32, lsq = false} : memref<16xi32>, (i32, index, index) -> (i32, none, none)
    %2 = extmemory[ld = 0, st = 1] (%arg2 : memref<1xi64>) (%dataResult_33, %addressResult_34) {id = 2 : i32} : (i64, index) -> none
    %3:2 = extmemory[ld = 1, st = 0] (%arg1 : memref<16xi32, strided<[?], offset: ?>>) (%addressResults_11) {id = 1 : i32} : (index) -> (i32, none)
    %4:2 = extmemory[ld = 1, st = 0] (%arg0 : memref<16xi32, strided<[?], offset: ?>>) (%addressResults) {id = 0 : i32} : (index) -> (i32, none)
    %5 = constant %arg3 {value = 1 : index} : index
    %6 = constant %arg3 {value = 16 : index} : index
    %7 = constant %arg3 {value = 0 : index} : index
    %8 = constant %arg3 {value = 0 : i64} : i64
    %9 = buffer [1] seq %16 {initValues = [0]} : i1
    %10 = mux %9 [%arg3, %17] : i1, none
    %11 = mux %9 [%7, %19] : i1, index
    %12 = mux %9 [%5, %trueResult_0] : i1, index
    %13 = mux %9 [%6, %trueResult_2] : i1, index
    %14 = mux %9 [%7, %trueResult_4] : i1, index
    %15 = mux %9 [%8, %trueResult_6] : i1, i64
    %16 = arith.cmpi slt, %11, %13 : index
    %trueResult, %falseResult = cond_br %16, %11 : index
    %trueResult_0, %falseResult_1 = cond_br %16, %12 : index
    %trueResult_2, %falseResult_3 = cond_br %16, %13 : index
    %trueResult_4, %falseResult_5 = cond_br %16, %14 : index
    %trueResult_6, %falseResult_7 = cond_br %16, %15 : i64
    %trueResult_8, %falseResult_9 = cond_br %16, %10 : none
    %17 = join %trueResult_8, %4#1, %3#1, %1#1 : none, none, none, none
    %dataResult, %addressResults = load [%trueResult] %4#0, %trueResult_8 : index, i32
    %dataResult_10, %addressResults_11 = load [%trueResult] %3#0, %trueResult_8 : index, i32
    %18 = arith.muli %dataResult, %dataResult_10 : i32
    %dataResult_12, %addressResult = store [%trueResult] %18, %trueResult_8 : index, i32
    %19 = arith.addi %trueResult, %trueResult_0 : index
    %20 = join %falseResult_9, %0#2 : none, none
    %dataResult_13, %addressResult_14 = store [%falseResult_5] %falseResult_7, %falseResult_9 : index, i64
    %21 = buffer [1] seq %27 {initValues = [0]} : i1
    %22 = mux %21 [%20, %28] : i1, none
    %23 = mux %21 [%falseResult_5, %32] : i1, index
    %24 = mux %21 [%falseResult_1, %trueResult_17] : i1, index
    %25 = mux %21 [%falseResult_3, %trueResult_19] : i1, index
    %26 = mux %21 [%falseResult_5, %trueResult_21] : i1, index
    %27 = arith.cmpi slt, %23, %25 : index
    %trueResult_15, %falseResult_16 = cond_br %27, %23 : index
    %trueResult_17, %falseResult_18 = cond_br %27, %24 : index
    %trueResult_19, %falseResult_20 = cond_br %27, %25 : index
    %trueResult_21, %falseResult_22 = cond_br %27, %26 : index
    %trueResult_23, %falseResult_24 = cond_br %27, %22 : none
    %28 = join %trueResult_23, %1#2, %0#4, %0#3 : none, none, none, none
    %dataResult_25, %addressResults_26 = load [%trueResult_15] %1#0, %trueResult_23 : index, i32
    %dataResult_27, %addressResults_28 = load [%trueResult_21] %0#0, %trueResult_23 : index, i64
    %29 = arith.extsi %dataResult_25 : i32 to i64
    %30 = arith.addi %29, %dataResult_27 : i64
    %31 = join %trueResult_23, %0#4 : none, none
    %dataResult_29, %addressResult_30 = store [%trueResult_21] %30, %31 : index, i64
    %32 = arith.addi %trueResult_15, %trueResult_17 : index
    %33 = join %falseResult_24, %2, %0#5 : none, none, none
    %34 = constant %falseResult_24 {value = 0 : index} : index
    %dataResult_31, %addressResults_32 = load [%34] %0#1, %falseResult_24 : index, i64
    %dataResult_33, %addressResult_34 = store [%34] %dataResult_31, %falseResult_24 : index, i64
    return %33 : none
  }
}

