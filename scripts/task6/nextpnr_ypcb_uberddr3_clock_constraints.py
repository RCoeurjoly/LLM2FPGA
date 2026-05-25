# SPDX-License-Identifier: MIT

# Constraint file used by nextpnr when building task6 DDR3 rowstream loader
# timing variants. These are conservative naming/targets retained to keep
# timing analysis stable while board clocks remain high-speed in RTL.
for name, mhz in [
    ("controller_clk", 25.0),
    ("clk25_raw", 83.333),
    ("clk100_raw", 333.333),
    ("clk100_90_raw", 333.333),
    ("ddr3_clk", 333.333),
    ("ddr3_clk_90", 333.333),
    ("clk200_raw", 200.0),
    ("ref_clk", 200.0),
    ("rowstream_ddr3.controller_clk", 25.0),
    ("rowstream_ddr3.clk25_raw", 83.333),
    ("rowstream_ddr3.clk100_raw", 333.333),
    ("rowstream_ddr3.clk100_90_raw", 333.333),
    ("rowstream_ddr3.ddr3_clk", 333.333),
    ("rowstream_ddr3.ddr3_clk_90", 333.333),
    ("rowstream_ddr3.clk200_raw", 200.0),
    ("rowstream_ddr3.ref_clk", 200.0),
]:
    # Ignore clocks that are not actually present in a given variant.
    # nextpnr prints a warning for missing names.
    ctx.addClock(name, mhz)
