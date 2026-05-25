#!/usr/bin/env python3
"""No-sudo physical/link-training probe for YPCB PCIe bring-up."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PORTS = ["0000:40:00.0", "0000:41:00.0", "0000:41:01.0", "0000:41:02.0", "0000:41:03.0"]
SYSFS_FIELDS = [
    "vendor", "device", "class", "revision", "current_link_speed", "current_link_width",
    "max_link_speed", "max_link_width", "secondary_bus_number", "subordinate_bus_number",
    "ari_enabled", "enable", "power_state", "removable", "aer_dev_correctable",
    "aer_dev_nonfatal", "aer_dev_fatal", "reset_method",
]
PCIE_SPEEDS = {
    1: "2.5 GT/s",
    2: "5.0 GT/s",
    3: "8.0 GT/s",
    4: "16.0 GT/s",
    5: "32.0 GT/s",
    6: "64.0 GT/s",
}


def run(cmd: list[str], *, cwd: Path = ROOT, timeout: int = 12) -> dict:
    try:
        completed = subprocess.run(
            cmd,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        return {"cmd": cmd, "returncode": completed.returncode, "output": completed.stdout}
    except subprocess.TimeoutExpired as exc:
        return {"cmd": cmd, "returncode": 124, "output": (exc.stdout or "") + "\nTIMEOUT\n"}
    except FileNotFoundError as exc:
        return {"cmd": cmd, "returncode": 127, "output": str(exc)}


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(errors="replace").strip()
    except OSError:
        return None


def read_config(path: Path) -> bytes | None:
    try:
        return path.read_bytes()[:256]
    except OSError:
        return None


def decode_pcie_cap(config: bytes | None) -> dict:
    if not config or len(config) < 0x40:
        return {"readable": False}
    status = config[0x06]
    if not (status & 0x10):
        return {"readable": True, "has_cap_list": False}
    cap = config[0x34]
    seen: set[int] = set()
    while cap and cap not in seen and cap + 0x14 <= len(config):
        seen.add(cap)
        cap_id = config[cap]
        nxt = config[cap + 1]
        if cap_id == 0x10:
            link_cap = int.from_bytes(config[cap + 0x0c:cap + 0x10], "little")
            link_ctl = int.from_bytes(config[cap + 0x10:cap + 0x12], "little")
            link_sta = int.from_bytes(config[cap + 0x12:cap + 0x14], "little")
            speed = link_sta & 0x0f
            width = (link_sta >> 4) & 0x3f
            return {
                "readable": True,
                "cap_offset": cap,
                "link_cap_raw": f"0x{link_cap:08x}",
                "link_control_raw": f"0x{link_ctl:04x}",
                "link_status_raw": f"0x{link_sta:04x}",
                "link_status_speed_code": speed,
                "link_status_speed": PCIE_SPEEDS.get(speed, f"unknown-{speed}"),
                "link_status_width": width,
                "link_training": bool(link_sta & (1 << 11)),
                "slot_clock_config": bool(link_sta & (1 << 12)),
                "data_link_layer_active": bool(link_sta & (1 << 13)),
            }
        cap = nxt
    return {"readable": True, "pcie_cap_found": False}


def probe_port(bdf: str) -> dict:
    base = Path("/sys/bus/pci/devices") / bdf
    item = {"bdf": bdf, "present": base.exists(), "sysfs": {}, "pcie_cap": {}}
    if not base.exists():
        return item
    for field in SYSFS_FIELDS:
        value = read_text(base / field)
        if value is not None:
            item["sysfs"][field] = value
    config = read_config(base / "config")
    if config:
        item["config_header_hex"] = config[:64].hex()
    item["pcie_cap"] = decode_pcie_cap(config)
    return item


def parse_xdc(xdc_path: Path) -> dict:
    ports: dict[str, dict[str, str]] = {}
    if not xdc_path.exists():
        return {"path": str(xdc_path), "exists": False, "ports": ports}
    pin_re = re.compile(r"set_property\s+PACKAGE_PIN\s+(\S+)\s+\[get_ports\s+\{?([^}\]]+)\}?\]")
    prop_re = re.compile(r"set_property\s+(IOSTANDARD|PULLUP)\s+(\S+)\s+\[get_ports\s+\{?([^}\]]+)\}?\]")
    for line in xdc_path.read_text(errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        pin_m = pin_re.search(stripped)
        if pin_m:
            pin, port = pin_m.groups()
            ports.setdefault(port.strip(), {})["PACKAGE_PIN"] = pin
            continue
        prop_m = prop_re.search(stripped)
        if prop_m:
            prop, value, port = prop_m.groups()
            ports.setdefault(port.strip(), {})[prop] = value
    expected = ["sys_clk_p", "sys_clk_n", "pci_exp_rxp", "pci_exp_rxn", "pci_exp_txp", "pci_exp_txn", "sys_rst_n"]
    return {
        "path": str(xdc_path),
        "exists": True,
        "ports": {name: ports.get(name, {}) for name in expected},
        "all_ports": ports,
    }


def resolve_xdc(explicit: str | None) -> Path | None:
    if explicit:
        return Path(explicit)
    result = run(["nix", "build", ".#task6-pcie7x-source", "--impure", "--print-out-paths"], timeout=60)
    outputs = [line.strip() for line in result["output"].splitlines() if line.strip().startswith("/nix/store/")]
    if outputs:
        return Path(outputs[-1]) / "pcie_7x_ypcb_k480t.xdc"
    return None


def write_log(path: Path, result: dict) -> None:
    path.write_text("$ " + " ".join(result["cmd"]) + "\n" + result["output"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", default="")
    parser.add_argument("--ports", nargs="*", default=DEFAULT_PORTS)
    parser.add_argument("--xdc", default="")
    parser.add_argument("--skip-jtag-status", action="store_true")
    args = parser.parse_args()

    if args.run_dir:
        run_dir = Path(args.run_dir)
    else:
        ts = datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")
        run_dir = ROOT / "artifacts" / "task6" / "runs" / f"{ts}-pcie-physical-link-probe"
    if not run_dir.is_absolute():
        run_dir = ROOT / run_dir
    run_dir.mkdir(parents=True, exist_ok=True)

    commands = {
        "boltctl.log": ["boltctl"],
        "lspci-Dnn.log": ["lspci", "-Dnn"],
        "lspci-tv.log": ["lspci", "-tv"],
    }
    for bdf in args.ports:
        commands[f"lspci-vvv-{bdf.replace(':', '_')}.log"] = ["lspci", "-vvv", "-s", bdf]
    for name, cmd in commands.items():
        write_log(run_dir / name, run(cmd))

    jtag_status = None
    if not args.skip_jtag_status:
        jtag_result = run(["scripts/task6/read_pcie_jtag_status.py", "--json-only"], timeout=20)
        write_log(run_dir / "pcie-jtag-status.log", jtag_result)
        if jtag_result["returncode"] == 0:
            try:
                jtag_status = json.loads(jtag_result["output"])
            except json.JSONDecodeError:
                jtag_status = {"json_error": True}

    xdc_path = resolve_xdc(args.xdc or None)
    xdc_audit = parse_xdc(xdc_path) if xdc_path else {"exists": False, "path": None}
    ports = [probe_port(bdf) for bdf in args.ports]

    summary = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "run_dir": str(run_dir),
        "sudo": "not used",
        "ports": ports,
        "xdc_audit": xdc_audit,
        "pcie_jtag_status": jtag_status.get("pcie") if isinstance(jtag_status, dict) else None,
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

    slot = next((p for p in ports if p["bdf"] == "0000:41:00.0"), ports[0] if ports else {})
    sysfs = slot.get("sysfs", {})
    cap = slot.get("pcie_cap", {})
    pcie = summary.get("pcie_jtag_status") or {}
    print(json.dumps({
        "run_dir": str(run_dir),
        "slot_bdf": slot.get("bdf"),
        "slot_current_link_speed": sysfs.get("current_link_speed"),
        "slot_current_link_width": sysfs.get("current_link_width"),
        "slot_pcie_cap_link_status": cap,
        "fpga_magic_ok": pcie.get("magic_ok"),
        "fpga_sys_rst_n": (pcie.get("flags") or {}).get("sys_rst_n"),
        "fpga_pipe_mmcm_lock": (pcie.get("flags") or {}).get("pipe_mmcm_lock"),
        "fpga_user_lnk_up": (pcie.get("flags") or {}).get("user_lnk_up"),
        "fpga_ltssm": pcie.get("pl_ltssm_state"),
        "fpga_link_up_seen_count": pcie.get("link_up_seen_count"),
        "xdc_ports": xdc_audit.get("ports"),
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
