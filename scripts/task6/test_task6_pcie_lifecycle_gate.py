#!/usr/bin/env python3
"""Unit checks for Task 6 PCIe lifecycle classification."""

from __future__ import annotations

from task6_pcie_lifecycle_gate import classify, recommendations


def snapshot(config_words: list[str], *, repeat_words: list[str] | None = None) -> dict[str, object]:
    if repeat_words is None:
        repeat_words = config_words
    return {
        "bdf": "0000:42:00.0",
        "bridge_bdf": "0000:41:00.0",
        "bridge_exists": True,
        "config_words": config_words,
        "config_words_repeat": repeat_words,
        "config_stable": config_words == repeat_words,
        "config_decoded": {
            "command": config_words[0] if len(config_words) > 0 else "",
            "vendor": config_words[1] if len(config_words) > 1 else "",
            "device": config_words[2] if len(config_words) > 2 else "",
            "header_type": config_words[3] if len(config_words) > 3 else "",
            "subsystem_device": config_words[4] if len(config_words) > 4 else "",
            "bar0": config_words[5] if len(config_words) > 5 else "",
        },
    }


def test_partial_vendor_all_ones_is_corrupt_config_not_wrong_bdf() -> None:
    classification = classify(snapshot(["0000", "ffff", "0480", "00", "abcd", "00000000"]))
    assert classification == "corrupt_vendor_id"
    advice = "\n".join(recommendations(classification, "0000:42:00.0", "0000:41:00.0"))
    assert "partially corrupt" in advice
    assert "update TASK6_PCIE_ALLOWED_BDF" not in advice


def test_non_xilinx_vendor_is_wrong_bdf() -> None:
    assert classify(snapshot(["0002", "8086", "0480", "00", "abcd", "80000000"])) == "wrong_vendor"


def test_consecutive_config_mismatch_is_unstable_config() -> None:
    first = ["0000", "10ee", "ffff", "ff", "ffff", "ffffffff"]
    second = ["0000", "ffff", "0480", "00", "abcd", "00000000"]
    classification = classify(snapshot(first, repeat_words=second))
    assert classification == "unstable_config"
    advice = "\n".join(recommendations(classification, "0000:42:00.0", "0000:41:00.0"))
    assert "changed between consecutive" in advice
    assert "BAR gates" in advice


def main() -> int:
    test_partial_vendor_all_ones_is_corrupt_config_not_wrong_bdf()
    test_non_xilinx_vendor_is_wrong_bdf()
    test_consecutive_config_mismatch_is_unstable_config()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
