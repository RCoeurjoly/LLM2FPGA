from pathlib import Path

from mlir.ir import Module

from circt.dialects import hw

from pycde import Input, InputChannel, OutputChannel, esi, module, generator, types
from pycde.constructs import Mux
from pycde.system import System
from pycde.module import import_hw_module

path = Path(__file__).parent / "dot-hw.mlir"
mlir_module = Module.parse(open(path).read())
imported_modules = []
top = None
for op in mlir_module.body:
  if isinstance(op, hw.HWModuleOp):
    imported_module = import_hw_module(op)
    imported_modules.append(imported_module)
    if imported_module._pycde_mod.name == 'forward':
      top = imported_module


@module
class HandshakeToESIWrapper:
  # Control Ports

  ## Generic ports always present
  clock = Input(types.i1)
  reset = Input(types.i1)

  ## Go signal
  go = InputChannel(types.i1)

  ## Done signal
  done = OutputChannel(types.i1)

  # Input 0 Ports

  ## Channels from Memory
  in0_ld_data0 = InputChannel(types.i32)

  ## Channels to Memory
  in0_ld_addr0 = OutputChannel(types.i64)

  # Input 1 Ports

  ## Channels from Memory
  in1_ld_data0 = InputChannel(types.i32)

  ## Channels to Memory
  in1_ld_addr0 = OutputChannel(types.i64)

  # Output 0 Ports

  ## Channels to Host
  result = OutputChannel(types.i32)

  @generator
  def generate(ports):
    # Typedefs
    ctrl_channel_type = types.channel(types.i1)
    i32_channel_type = types.channel(types.i32)
    i64_channel_type = types.channel(types.i64)

    # Instantiate the top-level module to wrap with backedges for most ports.
    wrapped_top = top(clock=ports.clock, reset=ports.reset)

    # Control Ports

    ## Go signal
    _, in_ctrl_valid = ports.go.unwrap(wrapped_top.inCtrl_ready)
    wrapped_top.inCtrl_valid.connect(in_ctrl_valid)

    ## Done signal
    out_ctrl_channel, out_ctrl_ready = ctrl_channel_type.wrap(
        1, wrapped_top.outCtrl_valid)
    wrapped_top.outCtrl_ready.connect(out_ctrl_ready)
    ports.done = out_ctrl_channel

    # Input 0 Ports

    ## Channels from Memory
    in0_ready = wrapped_top.in0_ldData0_ready & wrapped_top.in0_ldDone0_ready

    in0_ld_data0_data, in0_ld_data0_valid = ports.in0_ld_data0.unwrap(in0_ready)
    wrapped_top.in0_ldData0_data.connect(in0_ld_data0_data)
    in0_valid = Mux(in0_ready, types.i1(0), in0_ld_data0_valid)
    wrapped_top.in0_ldData0_valid.connect(in0_valid)
    wrapped_top.in0_ldDone0_valid.connect(in0_valid)

    ## Channels to Memory
    in0_ld_addr0_channel, in0_ld_addr0_ready = i64_channel_type.wrap(
        wrapped_top.in0_ldAddr0_data, wrapped_top.in0_ldAddr0_valid)
    wrapped_top.in0_ldAddr0_ready.connect(in0_ld_addr0_ready)
    ports.in0_ld_addr0 = in0_ld_addr0_channel

    # Input 1 Ports

    ## Channels from Memory
    in1_ready = wrapped_top.in1_ldData0_ready & wrapped_top.in1_ldDone0_ready

    in1_ld_data0_data, in1_ld_data0_valid = ports.in1_ld_data0.unwrap(in1_ready)
    wrapped_top.in1_ldData0_data.connect(in1_ld_data0_data)
    in1_valid = Mux(in0_ready, types.i1(0), in1_ld_data0_valid)
    wrapped_top.in1_ldData0_valid.connect(in1_valid)
    wrapped_top.in1_ldDone0_valid.connect(in1_valid)

    ## Channels to Memory
    in1_ld_addr0_channel, in1_ld_addr0_ready = i64_channel_type.wrap(
        wrapped_top.in1_ldAddr0_data, wrapped_top.in1_ldAddr0_valid)
    wrapped_top.in1_ldAddr0_ready.connect(in1_ld_addr0_ready)
    ports.in1_ld_addr0 = in1_ld_addr0_channel

    # Output 0 Ports
    out0_channel, out0_ready = i32_channel_type.wrap(wrapped_top.out0_data,
                                                     wrapped_top.out0_valid)
    wrapped_top.out0_ready.connect(out0_ready)
    ports.result = out0_channel


@esi.ServiceDecl
class HandshakeServices:
  go = esi.FromServer(types.i1)
  done = esi.ToServer(types.i1)
  read_mem = esi.ToFromServer(to_server_type=types.i64,
                              to_client_type=types.i32)
  result = esi.ToServer(types.i32)


@module
class DotProduct:
  """An ESI-enabled module which only communicates with the host and computes
  dot products."""
  clock = Input(types.i1)
  reset = Input(types.i1)

  @generator
  def generate(ports):
    # Get the 'go' signal from the host.
    go = HandshakeServices.go("dotprod_go")

    # Instantiate the wrapped PyTorch dot product module.
    wrapped_top = HandshakeToESIWrapper(clock=ports.clock,
                                        reset=ports.reset,
                                        go=go)

    # Connect up the channels from the pytorch module.
    HandshakeServices.done("dotprod_done", wrapped_top.done)
    HandshakeServices.result("result", wrapped_top.result)

    # Connect up the memory ports.
    port0_data = HandshakeServices.read_mem("port0", wrapped_top.in0_ld_addr0)
    wrapped_top.in0_ld_data0.connect(port0_data)
    port1_data = HandshakeServices.read_mem("port1", wrapped_top.in1_ld_addr0)
    wrapped_top.in1_ld_data0.connect(port1_data)


@module
class Top:
  clock = Input(types.i1)
  reset = Input(types.i1)

  @generator
  def generate(ports):
    DotProduct(clock=ports.clock, reset=ports.reset)
    esi.Cosim(HandshakeServices, ports.clock, ports.reset)


system = System([Top])
system.import_modules(imported_modules)
system.generate()
system.emit_outputs()
