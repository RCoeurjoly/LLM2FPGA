module {
  memref.global constant @bad : memref<1x2xf32>
    = dense_resource<r>
}

{-#
  dialect_resources: {
    builtin: {
      r: "0x400000003f800000"
    }
  }
#-}
