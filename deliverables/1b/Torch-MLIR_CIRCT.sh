nix shell "github:NixOS/nixpkgs/ee09932cedcef15aaf476f9343d1dea2cb77e261#llvmPackages_21.mlir" -c ./my-demo.sh

yosys -m ~/yosys-slang/build/slang.so -p "read_slang /home/roland/hot-chips-2022-pytorch-circt-hls-demo/my-dot.sv"
