#!/usr/bin/env python3
"""Regression tests for Task 6 rowstream-loader host command semantics."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path, PurePath
from unittest.mock import patch
import sys
import types
import unittest


ROOT = Path(__file__).resolve().parents[2]
LOADER_PATH = ROOT / "scripts" / "task6" / "task6_ddr3_rowstream_loader.py"


def install_jtag_stubs() -> None:
    read_mod = types.ModuleType("read_jtag_debug_ftdi_bitbang")
    read_mod.FTDI_FT232H_PRODUCT = 0
    read_mod.FTDI_VENDOR = 0
    read_mod.FtdiBitbangJtag = object
    read_mod.FtdiMpsseJtag = object
    sys.modules[read_mod.__name__] = read_mod

    xvc_mod = types.ModuleType("read_jtag_debug_xvc")
    xvc_mod.reset_tap = lambda _client: None
    xvc_mod.shift_dr_read = lambda _client, _bits: 0
    xvc_mod.shift_ir = lambda _client, _ir, _ir_len: None
    sys.modules[xvc_mod.__name__] = xvc_mod

    write_mod = types.ModuleType("write_jtag_command_ftdi_bitbang")
    write_mod.shift_dr_write = lambda _client, _command, _bits, _state: None
    sys.modules[write_mod.__name__] = write_mod


def load_module() -> types.ModuleType:
    install_jtag_stubs()
    spec = importlib.util.spec_from_file_location("task6_ddr3_rowstream_loader", LOADER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {LOADER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


loader_mod = load_module()


class FakeRowstreamLoader(loader_mod.RowstreamLoader):
    def __init__(self) -> None:
        self.args = argparse.Namespace(poll_timeout=0.1)
        self.commands: list[tuple[int, int, int, bytes]] = []
        self.ack_count = 0

    def read_debug(self) -> dict[str, int | bool | bytes]:
        return {
            "magic_ok": True,
            "version": loader_mod.DEBUG_VERSION,
            "loader_error": False,
            "loader_state": 1,
            "wb_ack_count": self.ack_count,
            "read_data_chunk": bytes([0x5A]) + bytes(15),
        }

    def send_command(self, opcode: int, chunk: int, addr: int, data: bytes = b"") -> None:
        self.commands.append((opcode, chunk, addr, data))
        self.ack_count += 1

    def wait_ready(self, min_ack_count: int | None = None) -> dict[str, int | bool | bytes]:
        debug = self.read_debug()
        if min_ack_count is not None and self.ack_count < min_ack_count:
            raise AssertionError("test fake did not advance ack count")
        return debug


class RowstreamLoaderHostContractTest(unittest.TestCase):
    def test_lowbyte_write_issues_one_address_ahead(self) -> None:
        loader = FakeRowstreamLoader()
        loader.write_lowbyte(41, 0xA5)
        self.assertEqual(
            loader.commands,
            [(loader_mod.OP_WRITE_LOWBYTE, 0, 42, bytes([0xA5]))],
        )

    def test_lowbyte_read_issues_one_address_ahead(self) -> None:
        loader = FakeRowstreamLoader()
        value, _debug = loader.read_lowbyte(41)
        self.assertEqual(value, 0x5A)
        self.assertEqual(loader.commands, [(loader_mod.OP_READ_LOWBYTE, 0, 42, b"")])

    def test_program_bitstream_reports_missing_usb_bus(self) -> None:
        def usb_only_exists(self: PurePath, /) -> bool:
            return False if str(self) == "/dev/bus/usb" else True

        with patch.object(loader_mod.Path, "exists", usb_only_exists):
            args = argparse.Namespace(
                bitstream=loader_mod.Path("/tmp/fake.bit"),
                run_dir=loader_mod.Path("/tmp"),
                program=True,
                jtag_cable="digilent_hs3",
                serial="210299BF3824",
            )
            with self.assertRaises(SystemExit) as exc:
                loader_mod.program_bitstream(args, loader_mod.Path("/tmp"))
            self.assertIn(
                "FTDI/JTAG interface unavailable in this environment: /dev/bus/usb is not present.",
                str(exc.value),
            )


if __name__ == "__main__":
    unittest.main()
