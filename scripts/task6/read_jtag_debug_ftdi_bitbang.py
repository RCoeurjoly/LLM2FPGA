#!/usr/bin/env python3
"""Read the Task 6 self-test debug payload directly through an FTDI JTAG cable."""

import argparse
import ctypes
import json
import time

from read_jtag_debug_xvc import (
    DEFAULT_BITS,
    decode_payload,
    print_summary,
    reset_tap,
    shift_dr_read,
    shift_ir,
)


FTDI_VENDOR = 0x0403
FTDI_FT232H_PRODUCT = 0x6014
BITMODE_RESET = 0x00
BITMODE_BITBANG = 0x01
BITMODE_MPSSE = 0x02
FTDI_INTERFACE_A = 1

MPSSE_WRITE_NEG = 0x01
MPSSE_BITMODE = 0x02
MPSSE_LSB = 0x08
MPSSE_DO_WRITE = 0x10
MPSSE_DO_READ = 0x20
MPSSE_WRITE_TMS = 0x40
SET_BITS_LOW = 0x80
SET_BITS_HIGH = 0x82
TCK_DIVISOR = 0x86
SEND_IMMEDIATE = 0x87
DIS_DIV_5 = 0x8A

PIN_TCK = 0x01
PIN_TDI = 0x02
PIN_TDO = 0x04
PIN_TMS = 0x08
PIN_OUTPUT_MASK = PIN_TCK | PIN_TDI | PIN_TMS

HS3_LOW_VALUE = 0x88
HS3_LOW_DIRECTION = 0x8B
HS3_HIGH_VALUE = 0x20
HS3_HIGH_DIRECTION = 0x30


class FtdiError(RuntimeError):
    pass


class FtdiBitbangJtag:
    def __init__(self, serial, vid, pid, delay_s):
        self.delay_s = delay_s
        self.lib = ctypes.CDLL("libftdi1.so")
        self._configure_signatures()
        self.ctx = self.lib.ftdi_new()
        if not self.ctx:
            raise FtdiError("ftdi_new failed")

        serial_bytes = serial.encode("ascii") if serial else None
        rc = self.lib.ftdi_usb_open_desc_index(
            self.ctx,
            vid,
            pid,
            None,
            ctypes.c_char_p(serial_bytes) if serial_bytes else None,
            0,
        )
        self._check(rc, "ftdi_usb_open_desc_index")
        self._check(self.lib.ftdi_usb_reset(self.ctx), "ftdi_usb_reset")
        self._check(self.lib.ftdi_usb_purge_buffers(self.ctx), "ftdi_usb_purge_buffers")
        self._check(self.lib.ftdi_set_latency_timer(self.ctx, 1), "ftdi_set_latency_timer")
        self._check(self.lib.ftdi_set_bitmode(self.ctx, 0x00, BITMODE_RESET), "reset bitmode")
        self._check(
            self.lib.ftdi_set_bitmode(self.ctx, PIN_OUTPUT_MASK, BITMODE_BITBANG),
            "enable bitbang",
        )
        self._write_pin_byte(PIN_TMS)

    def _configure_signatures(self):
        self.lib.ftdi_new.restype = ctypes.c_void_p
        self.lib.ftdi_free.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_set_interface.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.ftdi_set_interface.restype = ctypes.c_int
        self.lib.ftdi_usb_open_desc_index.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        self.lib.ftdi_usb_open_desc_index.restype = ctypes.c_int
        self.lib.ftdi_usb_close.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_close.restype = ctypes.c_int
        self.lib.ftdi_usb_reset.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_reset.restype = ctypes.c_int
        self.lib.ftdi_usb_purge_buffers.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_purge_buffers.restype = ctypes.c_int
        self.lib.ftdi_set_latency_timer.argtypes = [ctypes.c_void_p, ctypes.c_ubyte]
        self.lib.ftdi_set_latency_timer.restype = ctypes.c_int
        self.lib.ftdi_set_bitmode.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ubyte,
            ctypes.c_ubyte,
        ]
        self.lib.ftdi_set_bitmode.restype = ctypes.c_int
        self.lib.ftdi_write_data.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.c_int,
        ]
        self.lib.ftdi_write_data.restype = ctypes.c_int
        self.lib.ftdi_read_pins.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ubyte)]
        self.lib.ftdi_read_pins.restype = ctypes.c_int
        self.lib.ftdi_get_error_string.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_get_error_string.restype = ctypes.c_char_p

    def _error_string(self):
        raw = self.lib.ftdi_get_error_string(self.ctx)
        return raw.decode("utf-8", errors="replace") if raw else "unknown error"

    def _check(self, rc, what):
        if rc < 0:
            raise FtdiError(f"{what} failed: {rc}: {self._error_string()}")

    def _write_pin_byte(self, value):
        data = (ctypes.c_ubyte * 1)(value)
        rc = self.lib.ftdi_write_data(self.ctx, data, 1)
        if rc != 1:
            raise FtdiError(f"ftdi_write_data failed: {rc}: {self._error_string()}")
        if self.delay_s:
            time.sleep(self.delay_s)

    def _read_pin_byte(self):
        value = ctypes.c_ubyte()
        self._check(self.lib.ftdi_read_pins(self.ctx, ctypes.byref(value)), "ftdi_read_pins")
        return value.value

    def close(self):
        if self.ctx:
            self.lib.ftdi_set_bitmode(self.ctx, 0x00, BITMODE_RESET)
            self.lib.ftdi_usb_close(self.ctx)
            self.lib.ftdi_free(self.ctx)
            self.ctx = None

    def shift(self, tms_bits, tdi_bits):
        if len(tms_bits) != len(tdi_bits):
            raise ValueError("TMS and TDI vectors must have the same length")

        tdo_bits = []
        for tms, tdi in zip(tms_bits, tdi_bits):
            low = (PIN_TMS if tms else 0) | (PIN_TDI if tdi else 0)
            self._write_pin_byte(low)
            self._write_pin_byte(low | PIN_TCK)
            tdo_bits.append(1 if (self._read_pin_byte() & PIN_TDO) else 0)
            self._write_pin_byte(low)
        return tdo_bits


class FtdiMpsseJtag:
    def __init__(self, serial, vid, pid, freq_hz, tdo_bit):
        self.tdo_bit = tdo_bit
        self.lib = ctypes.CDLL("libftdi1.so")
        self._configure_signatures()
        self.ctx = self.lib.ftdi_new()
        if not self.ctx:
            raise FtdiError("ftdi_new failed")

        serial_bytes = serial.encode("ascii") if serial else None
        self._check(self.lib.ftdi_set_interface(self.ctx, FTDI_INTERFACE_A), "ftdi_set_interface")
        rc = self.lib.ftdi_usb_open_desc_index(
            self.ctx,
            vid,
            pid,
            None,
            ctypes.c_char_p(serial_bytes) if serial_bytes else None,
            0,
        )
        self._check(rc, "ftdi_usb_open_desc_index")
        self._check(self.lib.ftdi_usb_reset(self.ctx), "ftdi_usb_reset")
        self._check(self.lib.ftdi_set_bitmode(self.ctx, 0x00, BITMODE_RESET), "reset bitmode")
        self._check(self.lib.ftdi_usb_purge_buffers(self.ctx), "ftdi_usb_purge_buffers")
        self._check(self.lib.ftdi_set_latency_timer(self.ctx, 1), "ftdi_set_latency_timer")
        self._check(self.lib.ftdi_set_bitmode(self.ctx, 0xFB, BITMODE_MPSSE), "enable mpsse")
        self._read_available(5)
        self._configure_clock(freq_hz)
        self._write(
            bytes(
                [
                    SET_BITS_LOW,
                    HS3_LOW_VALUE,
                    HS3_LOW_DIRECTION,
                    SET_BITS_HIGH,
                    HS3_HIGH_VALUE,
                    HS3_HIGH_DIRECTION,
                    SEND_IMMEDIATE,
                ]
            )
        )
        self._read_available(2)

    def _configure_signatures(self):
        self.lib.ftdi_new.restype = ctypes.c_void_p
        self.lib.ftdi_free.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_set_interface.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.ftdi_set_interface.restype = ctypes.c_int
        self.lib.ftdi_usb_open_desc_index.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        self.lib.ftdi_usb_open_desc_index.restype = ctypes.c_int
        self.lib.ftdi_usb_close.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_close.restype = ctypes.c_int
        self.lib.ftdi_usb_reset.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_reset.restype = ctypes.c_int
        self.lib.ftdi_usb_purge_buffers.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_usb_purge_buffers.restype = ctypes.c_int
        self.lib.ftdi_set_latency_timer.argtypes = [ctypes.c_void_p, ctypes.c_ubyte]
        self.lib.ftdi_set_latency_timer.restype = ctypes.c_int
        self.lib.ftdi_set_bitmode.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ubyte,
            ctypes.c_ubyte,
        ]
        self.lib.ftdi_set_bitmode.restype = ctypes.c_int
        self.lib.ftdi_write_data.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.c_int,
        ]
        self.lib.ftdi_write_data.restype = ctypes.c_int
        self.lib.ftdi_read_data.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.c_int,
        ]
        self.lib.ftdi_read_data.restype = ctypes.c_int
        self.lib.ftdi_get_error_string.argtypes = [ctypes.c_void_p]
        self.lib.ftdi_get_error_string.restype = ctypes.c_char_p

    def _error_string(self):
        raw = self.lib.ftdi_get_error_string(self.ctx)
        return raw.decode("utf-8", errors="replace") if raw else "unknown error"

    def _check(self, rc, what):
        if rc < 0:
            raise FtdiError(f"{what} failed: {rc}: {self._error_string()}")

    def _write(self, data_bytes):
        data = (ctypes.c_ubyte * len(data_bytes)).from_buffer_copy(data_bytes)
        rc = self.lib.ftdi_write_data(self.ctx, data, len(data_bytes))
        if rc != len(data_bytes):
            raise FtdiError(f"ftdi_write_data failed: {rc}: {self._error_string()}")

    def _read_exact(self, byte_count):
        result = bytearray()
        deadline = time.monotonic() + 5.0
        while len(result) < byte_count:
            remaining = byte_count - len(result)
            buf = (ctypes.c_ubyte * remaining)()
            rc = self.lib.ftdi_read_data(self.ctx, buf, remaining)
            if rc < 0:
                raise FtdiError(f"ftdi_read_data failed: {rc}: {self._error_string()}")
            if rc:
                result.extend(bytes(buf[:rc]))
                continue
            if time.monotonic() > deadline:
                raise FtdiError(f"timed out reading {byte_count} MPSSE byte(s)")
            time.sleep(0.001)
        return bytes(result)

    def _read_available(self, byte_count):
        buf = (ctypes.c_ubyte * byte_count)()
        rc = self.lib.ftdi_read_data(self.ctx, buf, byte_count)
        if rc < 0:
            raise FtdiError(f"ftdi_read_data failed: {rc}: {self._error_string()}")
        return bytes(buf[:rc])

    def _configure_clock(self, freq_hz):
        base_hz = 60_000_000
        divisor = max(0, int((base_hz / freq_hz - 1) / 2))
        self._write(bytes([DIS_DIV_5, TCK_DIVISOR, divisor & 0xFF, (divisor >> 8) & 0xFF]))
        self._read_available(4)

    def close(self):
        if self.ctx:
            self.lib.ftdi_set_bitmode(self.ctx, 0x00, BITMODE_RESET)
            self.lib.ftdi_usb_close(self.ctx)
            self.lib.ftdi_free(self.ctx)
            self.ctx = None

    def shift(self, tms_bits, tdi_bits):
        if len(tms_bits) != len(tdi_bits):
            raise ValueError("TMS and TDI vectors must have the same length")

        tdo_bits = []
        chunk_bits = 32
        for offset in range(0, len(tms_bits), chunk_bits):
            tdo_bits.extend(
                self._shift_chunk(
                    tms_bits[offset : offset + chunk_bits],
                    tdi_bits[offset : offset + chunk_bits],
                )
            )
        return tdo_bits

    def _shift_chunk(self, tms_bits, tdi_bits):
        cmd = bytearray()
        op = MPSSE_WRITE_TMS | MPSSE_LSB | MPSSE_BITMODE | MPSSE_WRITE_NEG | MPSSE_DO_READ
        for tms, tdi in zip(tms_bits, tdi_bits):
            cmd.extend([op, 0x00, (0x80 if tdi else 0x00) | (0x01 if tms else 0x00)])
        cmd.append(SEND_IMMEDIATE)
        self._write(bytes(cmd))
        raw = self._read_exact(len(tms_bits))
        return [(byte >> self.tdo_bit) & 1 for byte in raw]


def read_payload(client, ir_len, user_ir, bit_count):
    reset_tap(client)
    shift_ir(client, user_ir, ir_len)
    return shift_dr_read(client, bit_count)


def read_idcode(client, ir_len, idcode_ir):
    reset_tap(client)
    shift_ir(client, idcode_ir, ir_len)
    return shift_dr_read(client, 32)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="210299BF3824")
    parser.add_argument("--vid", type=lambda value: int(value, 0), default=FTDI_VENDOR)
    parser.add_argument("--pid", type=lambda value: int(value, 0), default=FTDI_FT232H_PRODUCT)
    parser.add_argument("--backend", choices=("mpsse", "bitbang"), default="mpsse")
    parser.add_argument("--freq-hz", type=int, default=1_000_000)
    parser.add_argument("--tdo-bit", type=int, choices=(0, 7), default=0)
    parser.add_argument("--bits", type=int, default=DEFAULT_BITS)
    parser.add_argument("--ir-len", type=int, default=6)
    parser.add_argument("--user-ir", type=lambda value: int(value, 0), default=0x02)
    parser.add_argument("--idcode-ir", type=lambda value: int(value, 0), default=0x09)
    parser.add_argument("--poll", action="store_true")
    parser.add_argument("--poll-count", type=int, default=50)
    parser.add_argument("--poll-interval", type=float, default=0.1)
    parser.add_argument("--bit-delay-us", type=float, default=0.0)
    parser.add_argument("--idcode-only", action="store_true")
    parser.add_argument("--json-only", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.backend == "mpsse":
        client = FtdiMpsseJtag(
            serial=args.serial,
            vid=args.vid,
            pid=args.pid,
            freq_hz=args.freq_hz,
            tdo_bit=args.tdo_bit,
        )
    else:
        client = FtdiBitbangJtag(
            serial=args.serial,
            vid=args.vid,
            pid=args.pid,
            delay_s=args.bit_delay_us / 1_000_000.0,
        )
    try:
        if args.idcode_only:
            idcode = read_idcode(client, args.ir_len, args.idcode_ir)
            result = {
                "backend": f"ftdi-{args.backend}",
                "serial": args.serial,
                "idcode": idcode,
                "idcode_hex": f"0x{idcode:08x}",
            }
            print(json.dumps(result, indent=2, sort_keys=True))
            return

        decoded = None
        attempts = args.poll_count if args.poll else 1
        for attempt in range(attempts):
            payload = read_payload(client, args.ir_len, args.user_ir, args.bits)
            decoded = decode_payload(payload, args.bits)
            status = decoded["decoded"]["status"]
            if not args.poll or status["pass"] or status["fail"]:
                break
            if attempt + 1 < attempts:
                time.sleep(args.poll_interval)

        result = {
            "backend": f"ftdi-{args.backend}",
            "serial": args.serial,
            "attempts": attempt + 1,
            **decoded,
        }
        if not args.json_only:
            print_summary(result)
        print(json.dumps(result, indent=2, sort_keys=True))
    finally:
        client.close()


if __name__ == "__main__":
    main()
