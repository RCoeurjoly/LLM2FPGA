#!/usr/bin/env python3
"""Run litex_term under a PTY and capture bounded JTAG-UART output."""

from __future__ import annotations

import argparse
import os
import pty
import select
import signal
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument(
        "--send",
        action="append",
        default=[],
        help="Text to send as seconds:text, for example 3:\\r or 5:help\\r.",
    )
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command:
        parser.error("missing command")

    sends: list[tuple[float, bytes]] = []
    for item in args.send:
        when_s, text = item.split(":", 1)
        sends.append((float(when_s), text.encode("utf-8").decode("unicode_escape").encode("utf-8")))
    sends.sort(key=lambda pair: pair[0])

    master_fd, slave_fd = pty.openpty()
    child = subprocess.Popen(
        args.command,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        start_new_session=True,
        close_fds=True,
    )
    os.close(slave_fd)

    deadline = time.monotonic() + args.timeout
    start = time.monotonic()
    send_index = 0

    try:
        while True:
            now = time.monotonic()
            while send_index < len(sends) and now - start >= sends[send_index][0]:
                os.write(master_fd, sends[send_index][1])
                send_index += 1

            exit_status = child.poll()
            if exit_status is not None:
                break

            if now >= deadline:
                os.killpg(child.pid, signal.SIGTERM)
                time.sleep(0.2)
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                return 124

            readable, _, _ = select.select([master_fd], [], [], min(0.2, deadline - now))
            if readable:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    data = b""
                if not data:
                    break
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
    finally:
        try:
            os.close(master_fd)
        except OSError:
            pass

    return 0 if exit_status is None else exit_status


if __name__ == "__main__":
    raise SystemExit(main())
