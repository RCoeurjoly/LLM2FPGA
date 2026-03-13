#!/usr/bin/env python3
"""Stream-prune Yosys JSON netnames for a selected module.

This is intended for very large Yosys JSON netlists where loading the full file
into memory is not viable. The script rewrites the JSON in a single pass and
only specializes one case:

  modules.<target_module>.netnames

By default it keeps only netname entries whose names match module port names,
plus any explicitly listed with --keep-netname. All other structure is copied
through unchanged.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import TextIO


class ParseError(RuntimeError):
    pass


class JsonStream:
    def __init__(self, fp: TextIO):
        self.fp = fp
        self.buf = ""
        self.pos = 0

    def _fill(self, minimum: int = 1) -> bool:
        while len(self.buf) - self.pos < minimum:
            chunk = self.fp.read(1 << 20)
            if not chunk:
                return len(self.buf) - self.pos >= minimum
            if self.pos:
                self.buf = self.buf[self.pos :] + chunk
                self.pos = 0
            else:
                self.buf += chunk
        return True

    def peek(self) -> str:
        if not self._fill():
            return ""
        return self.buf[self.pos]

    def read(self) -> str:
        ch = self.peek()
        if not ch:
            raise ParseError("unexpected end of file")
        self.pos += 1
        return ch

    def skip_ws(self) -> None:
        while True:
            ch = self.peek()
            if ch and ch in " \t\r\n":
                self.pos += 1
                continue
            return

    def expect(self, token: str) -> None:
        for ch in token:
            got = self.read()
            if got != ch:
                raise ParseError(f"expected {token!r}, got {got!r}")

    def read_string_token(self) -> tuple[str, str]:
        if self.read() != '"':
            raise ParseError("expected string")
        raw = ['"']
        escaped = False
        while True:
            ch = self.read()
            raw.append(ch)
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == '"':
                break
        token = "".join(raw)
        return token, json.loads(token)

    def read_literal_token(self) -> str:
        self.skip_ws()
        ch = self.peek()
        if not ch:
            raise ParseError("unexpected end of file while reading literal")
        if ch in '"[{':
            raise ParseError(f"expected literal, got {ch!r}")
        raw = []
        while True:
            ch = self.peek()
            if not ch or ch in ",]} \t\r\n":
                break
            raw.append(self.read())
        if not raw:
            raise ParseError("empty literal")
        return "".join(raw)


@dataclass
class Stats:
    modules_seen: int = 0
    modules_pruned: int = 0
    pruned_ports_seen: int = 0
    pruned_netnames_seen: int = 0
    pruned_netnames_kept: int = 0
    pruned_netnames_dropped: int = 0
    kept_names: set[str] = field(default_factory=set)


class Rewriter:
    def __init__(
        self,
        stream: JsonStream,
        out: TextIO,
        target_module: str,
        prune_all_modules: bool,
        keep_port_netnames: bool,
        extra_kept_names: set[str],
    ):
        self.stream = stream
        self.out = out
        self.target_module = target_module
        self.prune_all_modules = prune_all_modules
        self.keep_port_netnames = keep_port_netnames
        self.extra_kept_names = set(extra_kept_names)
        self.stats = Stats()

    def rewrite(self) -> None:
        self.stream.skip_ws()
        self._rewrite_value(())
        self.stream.skip_ws()
        if self.stream.peek():
            raise ParseError("unexpected trailing data")

    def _write(self, text: str) -> None:
        self.out.write(text)

    def _rewrite_value(self, path: tuple[str, ...]) -> None:
        self.stream.skip_ws()
        ch = self.stream.peek()
        if ch == "{":
            self._rewrite_object(path)
            return
        if ch == "[":
            self._rewrite_array(path)
            return
        if ch == '"':
            raw, _ = self.stream.read_string_token()
            self._write(raw)
            return
        self._write(self.stream.read_literal_token())

    def _rewrite_array(self, path: tuple[str, ...]) -> None:
        self.stream.expect("[")
        self._write("[")
        self.stream.skip_ws()
        first = True
        while self.stream.peek() != "]":
            if not first:
                self.stream.expect(",")
                self._write(",")
                self.stream.skip_ws()
            self._rewrite_value(path)
            self.stream.skip_ws()
            first = False
        self.stream.expect("]")
        self._write("]")

    def _rewrite_object(self, path: tuple[str, ...]) -> None:
        if path == ("modules",):
            self._rewrite_modules_object(path)
            return
        self._rewrite_generic_object(path)

    def _rewrite_generic_object(self, path: tuple[str, ...]) -> None:
        self.stream.expect("{")
        self._write("{")
        self.stream.skip_ws()
        first = True
        while self.stream.peek() != "}":
            if not first:
                self.stream.expect(",")
                self._write(",")
                self.stream.skip_ws()
            key_raw, key = self.stream.read_string_token()
            self._write(key_raw)
            self.stream.skip_ws()
            self.stream.expect(":")
            self._write(":")
            self._rewrite_value(path + (key,))
            self.stream.skip_ws()
            first = False
        self.stream.expect("}")
        self._write("}")

    def _rewrite_modules_object(self, path: tuple[str, ...]) -> None:
        self.stream.expect("{")
        self._write("{")
        self.stream.skip_ws()
        first = True
        while self.stream.peek() != "}":
            if not first:
                self.stream.expect(",")
                self._write(",")
                self.stream.skip_ws()
            key_raw, key = self.stream.read_string_token()
            self.stats.modules_seen += 1
            self._write(key_raw)
            self.stream.skip_ws()
            self.stream.expect(":")
            self._write(":")
            if self.prune_all_modules or key == self.target_module:
                self._rewrite_pruned_module_object(path + (key,), key)
            else:
                self._rewrite_value(path + (key,))
            self.stream.skip_ws()
            first = False
        self.stream.expect("}")
        self._write("}")

    def _rewrite_pruned_module_object(self, path: tuple[str, ...], module_name: str) -> None:
        port_names: set[str] = set()
        self.stats.modules_pruned += 1
        self.stream.skip_ws()
        self.stream.expect("{")
        self._write("{")
        self.stream.skip_ws()
        first = True
        while self.stream.peek() != "}":
            if not first:
                self.stream.expect(",")
                self._write(",")
                self.stream.skip_ws()
            key_raw, key = self.stream.read_string_token()
            self._write(key_raw)
            self.stream.skip_ws()
            self.stream.expect(":")
            self._write(":")
            child_path = path + (key,)
            if key == "ports":
                self._rewrite_pruned_ports_object(child_path, port_names)
            elif key == "netnames":
                self._rewrite_pruned_netnames_object(child_path, port_names, module_name)
            else:
                self._rewrite_value(child_path)
            self.stream.skip_ws()
            first = False
        self.stream.expect("}")
        self._write("}")

    def _rewrite_pruned_ports_object(self, path: tuple[str, ...], port_names: set[str]) -> None:
        self.stream.skip_ws()
        self.stream.expect("{")
        self._write("{")
        self.stream.skip_ws()
        first = True
        while self.stream.peek() != "}":
            if not first:
                self.stream.expect(",")
                self._write(",")
                self.stream.skip_ws()
            key_raw, key = self.stream.read_string_token()
            self.stats.pruned_ports_seen += 1
            port_names.add(key)
            self.stats.kept_names.add(key)
            self._write(key_raw)
            self.stream.skip_ws()
            self.stream.expect(":")
            self._write(":")
            self._rewrite_value(path + (key,))
            self.stream.skip_ws()
            first = False
        self.stream.expect("}")
        self._write("}")

    def _should_keep_netname(self, name: str, port_names: set[str]) -> bool:
        if name in self.extra_kept_names:
            return True
        if self.keep_port_netnames and name in port_names:
            return True
        return False

    def _rewrite_pruned_netnames_object(
        self, path: tuple[str, ...], port_names: set[str], module_name: str
    ) -> None:
        self.stream.skip_ws()
        self.stream.expect("{")
        self._write("{")
        self.stream.skip_ws()
        first_out = True
        while self.stream.peek() != "}":
            key_raw, key = self.stream.read_string_token()
            self.stream.skip_ws()
            self.stream.expect(":")
            self.stream.skip_ws()
            self.stats.pruned_netnames_seen += 1
            keep = self._should_keep_netname(key, port_names)
            if keep:
                if not first_out:
                    self._write(",")
                self._write(key_raw)
                self._write(":")
                self._rewrite_value(path + (key,))
                self.stats.pruned_netnames_kept += 1
                self.stats.kept_names.add(f"{module_name}:{key}")
                first_out = False
            else:
                self._skip_value()
                self.stats.pruned_netnames_dropped += 1
            self.stream.skip_ws()
            if self.stream.peek() == ",":
                self.stream.expect(",")
                self.stream.skip_ws()
            elif self.stream.peek() != "}":
                raise ParseError("expected ',' or '}' in netnames object")
        self.stream.expect("}")
        self._write("}")

    def _skip_value(self) -> None:
        self.stream.skip_ws()
        ch = self.stream.peek()
        if ch == "{":
            self._skip_object()
            return
        if ch == "[":
            self._skip_array()
            return
        if ch == '"':
            self.stream.read_string_token()
            return
        self.stream.read_literal_token()

    def _skip_array(self) -> None:
        self.stream.expect("[")
        self.stream.skip_ws()
        first = True
        while self.stream.peek() != "]":
            if not first:
                self.stream.expect(",")
                self.stream.skip_ws()
            self._skip_value()
            self.stream.skip_ws()
            first = False
        self.stream.expect("]")

    def _skip_object(self) -> None:
        self.stream.expect("{")
        self.stream.skip_ws()
        first = True
        while self.stream.peek() != "}":
            if not first:
                self.stream.expect(",")
                self.stream.skip_ws()
            self.stream.read_string_token()
            self.stream.skip_ws()
            self.stream.expect(":")
            self.stream.skip_ws()
            self._skip_value()
            self.stream.skip_ws()
            first = False
        self.stream.expect("}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stream-prune Yosys JSON netnames for one module without loading the whole file into memory."
    )
    parser.add_argument("input_json", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument(
        "--module",
        default="main",
        help="module whose netnames object should be pruned (default: %(default)s)",
    )
    parser.add_argument(
        "--all-modules",
        action="store_true",
        help="prune netnames in all modules instead of only --module",
    )
    parser.add_argument(
        "--drop-all-netnames",
        action="store_true",
        help="drop all netnames in the selected module unless explicitly kept with --keep-netname",
    )
    parser.add_argument(
        "--keep-netname",
        action="append",
        default=[],
        help="keep a specific netname in the selected module; may be passed multiple times",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.input_json == args.output_json:
        print("input and output paths must differ", file=sys.stderr)
        return 2

    keep_port_netnames = not args.drop_all_netnames
    rewriter: Rewriter
    with args.input_json.open("r", encoding="utf-8") as infile, args.output_json.open(
        "w", encoding="utf-8"
    ) as outfile:
        rewriter = Rewriter(
            stream=JsonStream(infile),
            out=outfile,
            target_module=args.module,
            prune_all_modules=args.all_modules,
            keep_port_netnames=keep_port_netnames,
            extra_kept_names=set(args.keep_netname),
        )
        rewriter.rewrite()

    print(
        "scope=%s ports=%d netnames_seen=%d kept=%d dropped=%d modules_pruned=%d"
        % (
            "all-modules" if args.all_modules else args.module,
            rewriter.stats.pruned_ports_seen,
            rewriter.stats.pruned_netnames_seen,
            rewriter.stats.pruned_netnames_kept,
            rewriter.stats.pruned_netnames_dropped,
            rewriter.stats.modules_pruned,
        ),
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
