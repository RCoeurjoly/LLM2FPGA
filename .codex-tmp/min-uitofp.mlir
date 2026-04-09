module {
  handshake.func @main(%arg0: i32) -> (f32) {
    %0 = arith.uitofp %arg0 : i32 to f32
    return %0 : f32
  }
}
