"""Clock constraints for the YPCB UberDDR3 rowstream-loader nextpnr build."""

# These names are taken from nextpnr's clock reports for the boot-clean
# rowstream-loader builds.  Missing names are harmless: nextpnr logs a warning
# and ignores that specific constraint.
for name, mhz in [
    ("controller_clk", 25.0),
    ("clk25_raw", 25.0),
    ("clk100_raw", 100.0),
    ("clk100_90_raw", 100.0),
    ("ddr3_clk", 100.0),
    ("ddr3_clk_90", 100.0),
    ("clk200_raw", 200.0),
    ("ref_clk", 200.0),
]:
    ctx.addClock(name, mhz)
