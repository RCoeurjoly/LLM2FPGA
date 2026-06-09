# SPDX-License-Identifier: MIT

# Constraint file used by nextpnr when building task6 DDR3 rowstream loader
# timing variants. These are conservative naming/targets retained to keep
# timing analysis stable while board clocks match the proven one-byte-lane slow UberDDR3 pnr100 profile.
for name, mhz in [
    ("controller_clk", 66.667),
    ("clk25_raw", 66.667),
    ("clk100_raw", 266.667),
    ("clk100_90_raw", 266.667),
    ("ddr3_clk", 266.667),
    ("ddr3_clk_90", 266.667),
    ("clk200_raw", 200.0),
    ("ref_clk", 200.0),
    ("rowstream_ddr3.controller_clk", 66.667),
    ("rowstream_ddr3.clk25_raw", 66.667),
    ("rowstream_ddr3.clk100_raw", 266.667),
    ("rowstream_ddr3.clk100_90_raw", 266.667),
    ("rowstream_ddr3.ddr3_clk", 266.667),
    ("rowstream_ddr3.ddr3_clk_90", 266.667),
    ("rowstream_ddr3.clk200_raw", 200.0),
    ("rowstream_ddr3.ref_clk", 200.0),
    ("impl.rowstream_ddr3.controller_clk", 66.667),
    ("impl.rowstream_ddr3.clk25_raw", 66.667),
    ("impl.rowstream_ddr3.clk100_raw", 266.667),
    ("impl.rowstream_ddr3.clk100_90_raw", 266.667),
    ("impl.rowstream_ddr3.ddr3_clk", 266.667),
    ("impl.rowstream_ddr3.ddr3_clk_90", 266.667),
    ("impl.rowstream_ddr3.clk200_raw", 200.0),
    ("impl.rowstream_ddr3.ref_clk", 200.0),
    ("pcie_user_clk", 62.5),
    ("impl.pcie_user_clk", 62.5),
    ("pcie_7x_top_aximm_i.pcie_7x_i.in_module_mmcm.pipe_clock_i.userclk1", 62.5),
    ("impl.pcie_7x_top_aximm_i.pcie_7x_i.in_module_mmcm.pipe_clock_i.userclk1", 62.5),
]:
    # Ignore clocks that are not actually present in a given variant.
    # nextpnr prints a warning for missing names.
    ctx.addClock(name, mhz)
