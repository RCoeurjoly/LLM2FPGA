#map = affine_map<(d0) -> (d0)>
#map1 = affine_map<(d0) -> ()>
module {
  func.func @main(%arg0: tensor<16xi32>, %arg1: tensor<16xi32>) -> tensor<i64> {
    %c0_i64 = arith.constant 0 : i64
    %0 = tensor.empty() : tensor<16xi32>
    %1 = linalg.generic {indexing_maps = [#map, #map, #map], iterator_types = ["parallel"]} ins(%arg0, %arg1 : tensor<16xi32>, tensor<16xi32>) outs(%0 : tensor<16xi32>) {
    ^bb0(%in: i32, %in_0: i32, %out: i32):
      %5 = arith.muli %in, %in_0 : i32
      linalg.yield %5 : i32
    } -> tensor<16xi32>
    %2 = tensor.empty() : tensor<i64>
    %3 = linalg.fill ins(%c0_i64 : i64) outs(%2 : tensor<i64>) -> tensor<i64>
    %4 = linalg.generic {indexing_maps = [#map, #map1], iterator_types = ["reduction"]} ins(%1 : tensor<16xi32>) outs(%3 : tensor<i64>) {
    ^bb0(%in: i32, %out: i64):
      %5 = arith.extsi %in : i32 to i64
      %6 = arith.addi %5, %out : i64
      linalg.yield %6 : i64
    } -> tensor<i64>
    return %4 : tensor<i64>
  }
}

