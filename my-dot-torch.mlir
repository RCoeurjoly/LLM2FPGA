module {
  func.func @main(%arg0: !torch.vtensor<[16],si32>, %arg1: !torch.vtensor<[16],si32>) -> !torch.vtensor<[],si64> {
    %0 = torch.aten.mul.Tensor %arg0, %arg1 : !torch.vtensor<[16],si32>, !torch.vtensor<[16],si32> -> !torch.vtensor<[16],si32>
    %none = torch.constant.none
    %1 = torch.aten.sum %0, %none : !torch.vtensor<[16],si32>, !torch.none -> !torch.vtensor<[],si64>
    return %1 : !torch.vtensor<[],si64>
  }
}

