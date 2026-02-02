#map = affine_map<(d0)[s0, s1] -> (d0 * s1 + s0)>
module attributes {torch.debug_module_name = "DotModule"} {
  func.func @forward(%arg0: memref<5xi32, #map>, %arg1: memref<5xi32, #map>) -> i32 {
    %c0_i32 = arith.constant 0 : i32
    %0 = affine.for %arg2 = 0 to 5 iter_args(%arg3 = %c0_i32) -> (i32) {
      %1 = affine.load %arg0[%arg2] : memref<5xi32, #map>
      %2 = affine.load %arg1[%arg2] : memref<5xi32, #map>
      %3 = arith.muli %1, %2 : i32
      %4 = arith.addi %arg3, %3 : i32
      affine.yield %4 : i32
    }
    return %0 : i32
  }
}

