#!/usr/bin/env python3
"""Write a YPCB LiteDRAM/LiteX DDR3 configuration bundle.

This gate intentionally stays on the open LiteDRAM/LiteX path.  It uses the
open board UCF/XML metadata for pins and clocks, and it does not use Vivado MIG
files to generate or validate the controller.
"""

from __future__ import annotations

import argparse
import datetime as dt
import inspect
import json
import re
import textwrap
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from litedram import modules as litedram_modules
from litedram.phy import s7ddrphy


UCF_RE = re.compile(
    r'NET\s+"(?P<net>[^"]+)"\s+LOC\s+=\s+"(?P<loc>[^"]+)"'
)
INDEXED_NET_RE = re.compile(r"(?P<base>[^\[]+)\[(?P<index>[0-9]+)\]$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--memory-ch0-ucf", required=True, type=Path)
    parser.add_argument("--memory-ch0-ucf-artifact-label")
    parser.add_argument("--part0-pins-xml", required=True, type=Path)
    parser.add_argument("--part0-pins-xml-artifact-label")
    parser.add_argument("--board-xml", required=True, type=Path)
    parser.add_argument("--board-xml-artifact-label")
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--date", default=dt.date.today().isoformat())
    parser.add_argument("--artifact-name", default="h2-ypcb-litedram-config")
    parser.add_argument("--payload-byte-lanes", default=8, type=int)
    parser.add_argument(
        "--sdram-phy",
        default="K7DDRPHY",
        choices=["A7DDRPHY", "K7DDRPHY", "V7DDRPHY"],
    )
    return parser.parse_args()


def parse_ucf(path: Path) -> dict[str, Any]:
    indexed: dict[str, dict[int, str]] = {}
    scalars: dict[str, str] = {}
    raw_nets: dict[str, str] = {}

    for line in path.read_text(encoding="utf-8").splitlines():
        match = UCF_RE.search(line)
        if match is None:
            continue
        net = match.group("net")
        loc = match.group("loc")
        raw_nets[net] = loc
        indexed_match = INDEXED_NET_RE.fullmatch(net)
        if indexed_match is not None:
            base = indexed_match.group("base")
            index = int(indexed_match.group("index"))
            indexed.setdefault(base, {})[index] = loc
        else:
            scalars[net] = loc

    return {
        "indexed": indexed,
        "scalars": scalars,
        "raw_nets": raw_nets,
        "counts_by_net": {
            **{key: len(value) for key, value in indexed.items()},
            **{key: 1 for key in scalars},
        },
    }


def pins_for(indices: dict[int, str], count: int) -> list[str]:
    missing = [index for index in range(count) if index not in indices]
    if missing:
        raise ValueError(f"missing indexed pins: {missing}")
    return [indices[index] for index in range(count)]


def parse_part0_pins(path: Path) -> dict[str, dict[str, str]]:
    root = ET.parse(path).getroot()
    pins: dict[str, dict[str, str]] = {}
    for pin in root.findall(".//pin"):
        name = pin.attrib.get("name")
        if name:
            pins[name] = dict(pin.attrib)
    return pins


def parse_clock_summary(path: Path) -> dict[str, Any]:
    root = ET.parse(path).getroot()
    clocks: dict[str, dict[str, Any]] = {}
    for component in root.findall(".//component"):
        name = component.attrib.get("name", "")
        if "clk" not in name:
            continue
        params: dict[str, str] = {}
        for parameter in component.findall(".//parameter"):
            param_name = parameter.attrib.get("name")
            value = parameter.attrib.get("value")
            if param_name and value:
                params[param_name] = value
        clocks[name] = {
            "display_name": component.attrib.get("display_name"),
            "sub_type": component.attrib.get("sub_type"),
            "parameters": params,
        }
    return clocks


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def format_pin_list(pins: list[str]) -> str:
    return " ".join(pins)


def build_litedram_config(sdram_phy: str) -> dict[str, Any]:
    return {
        "speedgrade": -1,
        "cpu": None,
        "memtype": "DDR3",
        "uart": "rs232",
        "cmd_latency": 0,
        "sdram_module": "MT41K256M8",
        "sdram_module_nb": 8,
        "sdram_rank_nb": 1,
        "sdram_phy": sdram_phy,
        "rtt_nom": "60ohm",
        "rtt_wr": "60ohm",
        "ron": "34ohm",
        "input_clk_freq": "200e6",
        "sys_clk_freq": "100e6",
        "iodelay_clk_freq": "200e6",
        "cmd_buffer_depth": 16,
        "user_ports": {
            "native_0": {
                "type": "native",
                "data_width": 64,
            },
            "axi_0": {
                "type": "axi",
                "data_width": 64,
                "id_width": 4,
            },
        },
    }


def render_litedram_yaml(config: dict[str, Any]) -> str:
    def render_value(value: Any, indent: int = 0) -> str:
        pad = " " * indent
        if isinstance(value, dict):
            lines = ["{"]
            items = list(value.items())
            for key, child in items:
                rendered = render_value(child, indent + 4)
                lines.append(f'{pad}    "{key}": {rendered},')
            lines.append(f"{pad}}}")
            return "\n".join(lines)
        if value is None:
            return "None"
        if isinstance(value, bool):
            return "True" if value else "False"
        if isinstance(value, (int, float)):
            return str(value)
        if isinstance(value, str) and re.fullmatch(r"[0-9]+e[0-9]+", value):
            return value
        return json.dumps(value)

    lines = [
        "# Generated by scripts/task6/write_ypcb_litedram_config.py",
        "# Logical LiteDRAM config for the YPCB DDR3 CH0 64-bit payload lane.",
        "# The stock standalone generator exposes ddram_dm ports; the board-ready",
        "# path for this board should use the generated custom LiteX IO skeleton",
        "# that omits dm until open board metadata for DM pins is located.",
        render_value(config),
        "",
    ]
    return "\n".join(lines)


def render_platform_io_py(
    ddram: dict[str, list[str] | str],
    clock_p: str,
    clock_n: str,
    reset_pin: str,
) -> str:
    return textwrap.dedent(
        f"""\
        # Generated by scripts/task6/write_ypcb_litedram_config.py
        # Open LiteX IO skeleton for YPCB-00338-1P1 DDR3 CH0.
        #
        # This intentionally omits a ddram.dm Subsignal because the open CH0 UCF
        # used for this gate does not expose DDR3 data-mask pins. LiteDRAM's S7
        # PHY guards DM generation with hasattr(pads, "dm"), so the next gate is
        # a custom LiteX target instantiation using these pads rather than the
        # stock standalone YAML generator.

        from litex.build.generic_platform import IOStandard, Pins, Subsignal


        _io = [
            ("clk200", 0,
                Subsignal("p", Pins("{clock_p}")),
                Subsignal("n", Pins("{clock_n}")),
                IOStandard("LVDS")),
            ("cpu_reset", 0, Pins("{reset_pin}"), IOStandard("LVCMOS18")),
            ("ddram", 0,
                Subsignal("a",       Pins("{format_pin_list(ddram["a"])}")),
                Subsignal("ba",      Pins("{format_pin_list(ddram["ba"])}")),
                Subsignal("ras_n",   Pins("{ddram["ras_n"]}")),
                Subsignal("cas_n",   Pins("{ddram["cas_n"]}")),
                Subsignal("we_n",    Pins("{ddram["we_n"]}")),
                Subsignal("cs_n",    Pins("{format_pin_list(ddram["cs_n"])}")),
                Subsignal("dq",      Pins("{format_pin_list(ddram["dq"])}")),
                Subsignal("dqs_p",   Pins("{format_pin_list(ddram["dqs_p"])}")),
                Subsignal("dqs_n",   Pins("{format_pin_list(ddram["dqs_n"])}")),
                Subsignal("clk_p",   Pins("{format_pin_list(ddram["clk_p"])}")),
                Subsignal("clk_n",   Pins("{format_pin_list(ddram["clk_n"])}")),
                Subsignal("cke",     Pins("{format_pin_list(ddram["cke"])}")),
                Subsignal("odt",     Pins("{format_pin_list(ddram["odt"])}")),
                Subsignal("reset_n", Pins("{ddram["reset_n"]}")),
                IOStandard("SSTL15")),
        ]
        """
    )


def render_xdc(ddram: dict[str, list[str] | str], clock_p: str, clock_n: str, reset_pin: str) -> str:
    lines = [
        "# Generated by scripts/task6/write_ypcb_litedram_config.py",
        "# Constraint skeleton for the custom no-dm LiteDRAM/LiteX target.",
        "# No Vivado MIG files were used to generate this mapping.",
        f"set_property PACKAGE_PIN {clock_p} [get_ports clk200_p]",
        "set_property IOSTANDARD LVDS [get_ports clk200_p]",
        f"set_property PACKAGE_PIN {clock_n} [get_ports clk200_n]",
        "set_property IOSTANDARD LVDS [get_ports clk200_n]",
        f"set_property PACKAGE_PIN {reset_pin} [get_ports cpu_reset]",
        "set_property IOSTANDARD LVCMOS18 [get_ports cpu_reset]",
    ]

    indexed_ports = {
        "ddram_a": ddram["a"],
        "ddram_ba": ddram["ba"],
        "ddram_dq": ddram["dq"],
        "ddram_dqs_p": ddram["dqs_p"],
        "ddram_dqs_n": ddram["dqs_n"],
        "ddram_clk_p": ddram["clk_p"],
        "ddram_clk_n": ddram["clk_n"],
        "ddram_cke": ddram["cke"],
        "ddram_cs_n": ddram["cs_n"],
        "ddram_odt": ddram["odt"],
    }
    for port, pins in indexed_ports.items():
        assert isinstance(pins, list)
        for index, pin in enumerate(pins):
            lines.append(f"set_property PACKAGE_PIN {pin} [get_ports {{{port}[{index}]}}]")
    scalar_ports = {
        "ddram_ras_n": ddram["ras_n"],
        "ddram_cas_n": ddram["cas_n"],
        "ddram_we_n": ddram["we_n"],
        "ddram_reset_n": ddram["reset_n"],
    }
    for port, pin in scalar_ports.items():
        assert isinstance(pin, str)
        lines.append(f"set_property PACKAGE_PIN {pin} [get_ports {port}]")

    for port in sorted({*indexed_ports.keys(), *scalar_ports.keys()}):
        lines.append(f"set_property IOSTANDARD SSTL15 [get_ports {port}*]")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    if args.payload_byte_lanes != 8:
        raise SystemExit("Only the 64-bit/eight-byte-lane payload config is defined")

    ucf = parse_ucf(args.memory_ch0_ucf)
    part0_pins = parse_part0_pins(args.part0_pins_xml)
    clocks = parse_clock_summary(args.board_xml)

    indexed = ucf["indexed"]
    scalars = ucf["scalars"]
    ddram: dict[str, list[str] | str] = {
        "dq": pins_for(indexed["ddr3_dq"], 64),
        "spare_ecc_dq": pins_for(indexed["ddr3_dq"], 72)[64:72],
        "dqs_p": pins_for(indexed["ddr3_dqs_p"], 8),
        "dqs_n": pins_for(indexed["ddr3_dqs_n"], 8),
        "spare_ecc_dqs_p": pins_for(indexed["ddr3_dqs_p"], 9)[8:9],
        "spare_ecc_dqs_n": pins_for(indexed["ddr3_dqs_n"], 9)[8:9],
        "a": pins_for(indexed["ddr3_addr"], 15),
        "ba": pins_for(indexed["ddr3_ba"], 3),
        "ras_n": scalars["ddr3_ras_n"],
        "cas_n": scalars["ddr3_cas_n"],
        "we_n": scalars["ddr3_we_n"],
        "reset_n": scalars["ddr3_reset_n"],
        "clk_p": pins_for(indexed["ddr3_ck_p"], 1),
        "clk_n": pins_for(indexed["ddr3_ck_n"], 1),
        "cke": pins_for(indexed["ddr3_cke"], 1),
        "cs_n": pins_for(indexed["ddr3_cs_n"], 1),
        "odt": pins_for(indexed["ddr3_odt"], 1),
    }

    clock_pins = {
        name: attrs
        for name, attrs in part0_pins.items()
        if name.startswith("default_200mhz_clk1")
    }
    clock_p = clock_pins["default_200mhz_clk1_p"]["loc"]
    clock_n = clock_pins["default_200mhz_clk1_n"]["loc"]
    reset_pin = part0_pins["SW_RESET"]["loc"]

    litedram_config = build_litedram_config(args.sdram_phy)
    s7ddrphy_source = inspect.getsource(s7ddrphy.S7DDRPHY)
    dm_optional_in_s7_phy = 'hasattr(pads, "dm")' in s7ddrphy_source
    has_module = hasattr(litedram_modules, litedram_config["sdram_module"])
    has_phy = hasattr(s7ddrphy, litedram_config["sdram_phy"])
    dm_pin_count = ucf["counts_by_net"].get("ddr3_dm", 0)

    validation = {
        "litedram_module_exists": has_module,
        "kintex7_phy_exists": has_phy,
        "open_ucf_has_64_payload_dq": len(ddram["dq"]) == 64,
        "open_ucf_has_8_payload_dqs_pairs": (
            len(ddram["dqs_p"]) == 8 and len(ddram["dqs_n"]) == 8
        ),
        "open_ucf_has_ecc_spare_lane": (
            len(ddram["spare_ecc_dq"]) == 8
            and len(ddram["spare_ecc_dqs_p"]) == 1
            and len(ddram["spare_ecc_dqs_n"]) == 1
        ),
        "open_ucf_has_dm_pins": dm_pin_count > 0,
        "litedram_s7_phy_dm_optional": dm_optional_in_s7_phy,
    }
    status = (
        "PASS"
        if all(
            [
                validation["litedram_module_exists"],
                validation["kintex7_phy_exists"],
                validation["open_ucf_has_64_payload_dq"],
                validation["open_ucf_has_8_payload_dqs_pairs"],
                validation["open_ucf_has_ecc_spare_lane"],
                validation["litedram_s7_phy_dm_optional"],
            ]
        )
        else "PARTIAL"
    )

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    write_text(out_dir / "ypcb_litedram_64bit_payload.yml", render_litedram_yaml(litedram_config))
    write_text(
        out_dir / "ypcb_litedram_open_io.py",
        render_platform_io_py(ddram, clock_p, clock_n, reset_pin),
    )
    write_text(
        out_dir / "ypcb_litedram_open_io.xdc",
        render_xdc(ddram, clock_p, clock_n, reset_pin),
    )

    payload = {
        "artifact_name": args.artifact_name,
        "status": status,
        "date": args.date,
        "hypothesis": (
            "YPCB DDR3 CH0 can move to an open LiteDRAM/LiteX controller gate "
            "using eight x8 MT41K256M8 byte lanes as a 64-bit payload path, "
            "with the ninth byte lane reserved for ECC/spare follow-up."
        ),
        "source_artifacts": {
            "memory_ch0_ucf": (
                args.memory_ch0_ucf_artifact_label or str(args.memory_ch0_ucf)
            ),
            "part0_pins_xml": (
                args.part0_pins_xml_artifact_label or str(args.part0_pins_xml)
            ),
            "board_xml": args.board_xml_artifact_label or str(args.board_xml),
            "baseline_bundle": (
                "artifacts/task6/baselines/"
                "tiny-stories-1m-baseline-float-selftest-all-memory-utilization"
            ),
        },
        "policy": {
            "vivado_mig_lane": "rejected",
            "controller_path": "LiteDRAM/LiteX only",
            "mig_files_used_for_controller_generation": False,
        },
        "generated_files": {
            "logical_litedram_config": "ypcb_litedram_64bit_payload.yml",
            "custom_litex_io_skeleton": "ypcb_litedram_open_io.py",
            "constraint_skeleton": "ypcb_litedram_open_io.xdc",
            "summary": "summary.json",
        },
        "litedram_config": litedram_config,
        "ypcb_open_board_facts": {
            "selected_input_clock": {
                "name": "default_200mhz_clk1",
                "p": clock_p,
                "n": clock_n,
            },
            "reset": {
                "name": "SW_RESET",
                "pin": reset_pin,
            },
            "clock_components": clocks,
            "ucf_counts_by_net": ucf["counts_by_net"],
            "payload_byte_lanes": 8,
            "spare_ecc_byte_lanes": 1,
            "ddr3_pin_mapping": ddram,
        },
        "validation": validation,
        "open_issues": [
            (
                "Open MEMORY_CH0.ucf does not expose DDR3 dm pins; the custom "
                "LiteX target must omit ddram.dm or a later open board metadata "
                "source must locate these pins."
            ),
            (
                "The generated YAML is a logical LiteDRAM config. The stock "
                "standalone generator is not board-ready for this UCF because "
                "its default DDR3 IO helper emits dm ports."
            ),
        ],
        "decision": {
            "verdict": "promote-custom-litex-target-instantiation"
            if status == "PASS"
            else "continue-config-reduction",
            "next_gate": (
                "Instantiate a minimal custom LiteX/YPCB K7DDRPHY target with "
                "the generated no-dm DDR3 pads and emit LiteDRAM controller RTL "
                "without invoking Vivado or MIG."
            ),
        },
    }
    write_text(out_dir / "summary.json", json.dumps(payload, indent=2) + "\n")
    if status != "PASS":
        raise SystemExit("YPCB LiteDRAM config bundle is incomplete")


if __name__ == "__main__":
    main()
