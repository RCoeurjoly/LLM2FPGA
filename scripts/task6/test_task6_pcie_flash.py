#!/usr/bin/env python3
"""Unit checks for the guarded Task 6 flash wrapper."""

from __future__ import annotations

from task6_pcie_flash import classify_config_words, flash_write_allowed


def test_classify_ready_config() -> None:
    assert classify_config_words(["0002", "10ee", "0480", "00", "abcd", "80000000"]) == "pcie_ready"


def test_classify_corrupt_command() -> None:
    assert classify_config_words(["ffff", "10ee", "ffff", "ff", "ffff", "00000000"]) == "corrupt_command"


def test_classify_missing_bar() -> None:
    assert classify_config_words(["0002", "10ee", "0480", "00", "abcd", "00000000"]) == "missing_resource0"


def test_flash_write_override_policy() -> None:
    assert flash_write_allowed("pcie_ready", False)
    assert not flash_write_allowed("corrupt_command", False)
    assert flash_write_allowed("corrupt_command", True)


def main() -> int:
    test_classify_ready_config()
    test_classify_corrupt_command()
    test_classify_missing_bar()
    test_flash_write_override_policy()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
