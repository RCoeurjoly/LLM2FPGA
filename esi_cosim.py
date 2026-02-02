#!/usr/bin/python3

import capnp

import os
import re
import socket
import time


class CosimBase:
  """Provides a base class for cosim tests"""

  def __init__(self, schemaPath, hostPort):
    """Load the schema and connect to the RPC server"""
    self.schema = capnp.load(schemaPath)
    self.rpc_client = capnp.TwoPartyClient(hostPort)
    self.cosim = self.rpc_client.bootstrap().cast_as(self.schema.CosimDpiServer)

  def openEP(self, epNum=1, sendType=None, recvType=None):
    """Open the endpoint, optionally checking the send and recieve types"""
    ifaces = self.cosim.list().wait().ifaces
    for iface in ifaces:
      if iface.endpointID == epNum:
        # Optionally check that the type IDs match.
        # print(f"SendTypeId: {iface.sendTypeID:x}")
        # print(f"RecvTypeId: {iface.recvTypeID:x}")
        if sendType is not None:
          assert (iface.sendTypeID == sendType.schema.node.id)
        if recvType is not None:
          assert (iface.recvTypeID == recvType.schema.node.id)

        openResp = self.cosim.open(iface).wait()
        assert openResp.iface is not None
        return openResp.iface
    assert False, "Could not find specified EndpointID"

  def readMsg(self, ep, expectedType):
    """Try to read, return None if a message was not immediately available"""
    recvResp = ep.recv(False).wait()
    if not recvResp.hasData:
      return None
    return recvResp.resp.as_struct(expectedType)


class HandshakeCosimBase(CosimBase):

  def __init__(self, port):
    super().__init__("PyCDESystem/schema.capnp", f"{os.uname()[1]}:{port}")
    self.done = self.openEP(1001,
                            sendType=self.schema.I1,
                            recvType=self.schema.I1)
    self.memory_ports = [
        self.openEP(1003, sendType=self.schema.I64, recvType=self.schema.I32),
        self.openEP(1004, sendType=self.schema.I64, recvType=self.schema.I32)
    ]
    self.result = self.openEP(1002,
                              sendType=self.schema.I32,
                              recvType=self.schema.I1)
    self.go_chan = self.openEP(1005,
                               sendType=self.schema.I1,
                               recvType=self.schema.I1)
    self.memories = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]

  def go(self):
    self.go_chan.send(self.schema.I1.new_message(i=False))

    while self.readMsg(self.done, self.schema.I1) is None:
      self.service_memories()
      time.sleep(0.01)

  def read_result(self):
    result = None
    while result is None:
      result = self.readMsg(self.result, self.schema.I32)
      time.sleep(0.01)
    return result.i

  def service_memories(self):

    def service(mem, port):
      addr = self.readMsg(port, self.schema.I64)
      if addr is not None:
        port.send(self.schema.I64.new_message(i=mem[addr.i]))

    for port, mem in zip(self.memory_ports, self.memories):
      service(mem, port)


def isPortOpen(port):
  sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  result = sock.connect_ex(('127.0.0.1', port))
  sock.close()
  return True if result == 0 else False


def get_cosim_port():
  portFileName = "cosim.cfg"
  checkCount = 0
  port = -1
  while not os.path.exists(portFileName):
    time.sleep(0.05)
    checkCount += 1
    if checkCount > 200:
      raise Exception(f"Cosim never wrote cfg file: {portFileName}")

  portFile = open(portFileName, "r")
  for line in portFile.readlines():
    m = re.match("port: (\\d+)", line)
    if m is not None:
      port = int(m.group(1))
      portFile.close()

  assert (port != -1)

  checkCount = 0
  while not isPortOpen(port):
    checkCount += 1
    if checkCount > 200:
      raise Exception(f"Cosim RPC port ({port}) never opened")
    time.sleep(0.05)

  return port
