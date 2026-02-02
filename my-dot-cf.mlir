module {
  func.func @main(%arg0: memref<16xi32, strided<[?], offset: ?>>, %arg1: memref<16xi32, strided<[?], offset: ?>>, %arg2: memref<i64>) {
    %c1 = arith.constant 1 : index
    %c16 = arith.constant 16 : index
    %c0 = arith.constant 0 : index
    %c0_i64 = arith.constant 0 : i64
    %alloc = memref.alloc() {alignment = 64 : i64} : memref<16xi32>
    cf.br ^bb1(%c0 : index)
  ^bb1(%0: index):  // 2 preds: ^bb0, ^bb2
    %1 = arith.cmpi slt, %0, %c16 : index
    cf.cond_br %1, ^bb2, ^bb3
  ^bb2:  // pred: ^bb1
    %2 = memref.load %arg0[%0] : memref<16xi32, strided<[?], offset: ?>>
    %3 = memref.load %arg1[%0] : memref<16xi32, strided<[?], offset: ?>>
    %4 = arith.muli %2, %3 : i32
    memref.store %4, %alloc[%0] : memref<16xi32>
    %5 = arith.addi %0, %c1 : index
    cf.br ^bb1(%5 : index)
  ^bb3:  // pred: ^bb1
    %alloc_0 = memref.alloc() {alignment = 64 : i64} : memref<i64>
    memref.store %c0_i64, %alloc_0[] : memref<i64>
    cf.br ^bb4(%c0 : index)
  ^bb4(%6: index):  // 2 preds: ^bb3, ^bb5
    %7 = arith.cmpi slt, %6, %c16 : index
    cf.cond_br %7, ^bb5, ^bb6
  ^bb5:  // pred: ^bb4
    %8 = memref.load %alloc[%6] : memref<16xi32>
    %9 = memref.load %alloc_0[] : memref<i64>
    %10 = arith.extsi %8 : i32 to i64
    %11 = arith.addi %10, %9 : i64
    memref.store %11, %alloc_0[] : memref<i64>
    %12 = arith.addi %6, %c1 : index
    cf.br ^bb4(%12 : index)
  ^bb6:  // pred: ^bb4
    memref.copy %alloc_0, %arg2 : memref<i64> to memref<i64>
    return
  }
}

