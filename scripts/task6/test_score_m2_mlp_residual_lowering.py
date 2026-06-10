#!/usr/bin/env python3
"""Unit checks for the M2 MLP residual lowering scorer helpers."""

from __future__ import annotations

from score_m2_mlp_residual_lowering import (
    fixed_post_gelu_pwl_q,
    quantize_row_i8,
    round_shift_signed,
    saturate_i8,
)


def test_round_shift_signed() -> None:
    assert round_shift_signed(7, 1) == 4
    assert round_shift_signed(5, 1) == 3
    assert round_shift_signed(-7, 1) == -4
    assert round_shift_signed(-5, 1) == -3
    assert round_shift_signed(123, 0) == 123


def test_saturate_i8() -> None:
    assert saturate_i8(-200) == -127
    assert saturate_i8(-127) == -127
    assert saturate_i8(0) == 0
    assert saturate_i8(127) == 127
    assert saturate_i8(200) == 127


def test_fixed_post_gelu_pwl_q() -> None:
    xs = [-10, 0, 10, 20]
    ys = [-2, 0, 10, 20]
    xs = xs + [xs[-1] + 10 * (index + 1) for index in range(12)]
    ys = ys + [ys[-1] + 10 * (index + 1) for index in range(12)]
    assert fixed_post_gelu_pwl_q(-99, xs, ys) == -2
    assert fixed_post_gelu_pwl_q(99_999, xs, ys) == ys[-1]
    assert fixed_post_gelu_pwl_q(0, xs, ys) == 0
    assert fixed_post_gelu_pwl_q(5, xs, ys) == 5
    assert fixed_post_gelu_pwl_q(15, xs, ys) == 15


def test_quantize_row_i8() -> None:
    q, scale = quantize_row_i8([-2.0, 0.0, 2.0])
    assert scale == 2.0 / 127
    assert q == [-127, 0, 127]
    q_zero, scale_zero = quantize_row_i8([0.0, 0.0])
    assert scale_zero == 1.0
    assert q_zero == [0, 0]


def main() -> None:
    test_round_shift_signed()
    test_saturate_i8()
    test_fixed_post_gelu_pwl_q()
    test_quantize_row_i8()


if __name__ == "__main__":
    main()
