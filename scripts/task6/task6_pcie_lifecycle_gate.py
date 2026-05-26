#!/usr/bin/env python3
"""Classify Task 6 PCIe lifecycle health and optionally run BAR/debug gates."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
RUNS_ROOT = ROOT / "artifacts" / "task6" / "runs"
EXPECTED_BDF = "0000:42:00.0"
EXPECTED_BRIDGE = "0000:41:00.0"


def iso_stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def run(cmd: list[str], timeout: float = 10.0) -> dict[str, object]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return {
            "argv": cmd,
            "returncode": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "timeout": False,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "argv": cmd,
            "returncode": None,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
            "timeout": True,
        }


def write_one(path: Path) -> tuple[bool, str | None]:
    try:
        path.write_text("1\n", encoding="ascii")
        return True, None
    except OSError as exc:
        return False, str(exc)


def sysfs_file(path: Path) -> dict[str, object]:
    item: dict[str, object] = {"path": str(path), "exists": path.exists()}
    if path.exists():
        stat = path.stat()
        item.update(
            {
                "mode": oct(stat.st_mode & 0o777),
                "uid": stat.st_uid,
                "gid": stat.st_gid,
                "readable": os.access(path, os.R_OK),
                "writable": os.access(path, os.W_OK),
            }
        )
    return item


def setpci_words(bdf: str) -> dict[str, object]:
    result = run(["setpci", "-s", bdf, "COMMAND", "VENDOR_ID", "DEVICE_ID", "HEADER_TYPE"], timeout=3)
    words = (result["stdout"] or "").split()
    return {"result": result, "words": words}


def classify(snapshot: dict[str, object]) -> str:
    bdf = str(snapshot["bdf"])
    device = Path("/sys/bus/pci/devices") / bdf
    resource0 = device / "resource0"
    config_words = snapshot["config_words"]

    if not bool(snapshot["bridge_exists"]):
        return "missing_bridge"
    if not device.exists():
        return "missing_endpoint"
    if len(config_words) < 4:
        return "config_unreadable"
    command, vendor, device_id, header_type = [str(x).lower() for x in config_words[:4]]
    if command == "ffff":
        return "corrupt_command"
    if vendor != "10ee":
        return "wrong_vendor"
    if device_id != "0480":
        return "corrupt_device_id"
    if header_type not in ("00", "0000"):
        return "corrupt_header_type"
    if not resource0.exists():
        return "missing_resource0"
    if not os.access(resource0, os.R_OK | os.W_OK):
        return "resource0_permission"
    if (int(command, 16) & 0x0002) == 0:
        return "mem_disabled"
    return "pcie_ready"


def recommendations(classification: str, bdf: str, bridge_bdf: str) -> list[str]:
    lifecycle_probe = f"scripts/task6/task6_pcie_user_gate.sh lifecycle {bdf}"
    lifecycle_bar = f"scripts/task6/task6_pcie_user_gate.sh lifecycle {bdf} --run-bar --run-debug"
    recover = f"scripts/task6/task6_pcie_user_gate.sh recover {bdf} --reset-first --timeout 20"
    bar = f"scripts/task6/task6_pcie_user_gate.sh bar {bdf} --mode header"
    top1 = f"scripts/task6/task6_pcie_user_gate.sh rowstream-top1 {bdf} --sample-count 1"
    bridge_rescan = f"scripts/task6/task6_pcie_user_gate.sh bridge-rescan {bridge_bdf}"
    install_rules = "/home/roland/.local/bin/install-task6-pcie-rules.sh"

    table = {
        "missing_bridge": [
            "Reconnect or power-cycle the Thunderbolt chassis, then run the non-BAR lifecycle probe without rescan: " + lifecycle_probe,
        ],
        "missing_endpoint": [
            "Ensure the FPGA booted from BPI flash before host PCIe enumeration, then run the non-BAR lifecycle probe without rescan: " + lifecycle_probe,
            "If the bridge is present but the endpoint is absent, try one rootless bridge rescan: " + bridge_rescan,
        ],
        "config_unreadable": [
            "Config space is not readable yet; wait briefly or power-cycle the chassis, then run the non-BAR lifecycle probe: " + lifecycle_probe,
        ],
        "corrupt_command": [
            "Config space is returning 0xffff; stop PCIe probing and re-enumerate with the FPGA already configured from BPI flash.",
            "After chassis or host re-enumeration, run only the non-BAR lifecycle probe first: " + lifecycle_probe,
        ],
        "wrong_vendor": [
            "The BDF no longer points at the expected Xilinx endpoint; inspect lspci and update TASK6_PCIE_ALLOWED_BDF only if the endpoint moved.",
        ],
        "corrupt_device_id": [
            "The endpoint partially enumerated but device ID is wrong; power-cycle the chassis and rerun the non-BAR lifecycle probe: " + lifecycle_probe,
        ],
        "corrupt_header_type": [
            "The endpoint header is corrupt; power-cycle the chassis after flash boot and rerun the non-BAR lifecycle probe: " + lifecycle_probe,
        ],
        "missing_resource0": [
            "The endpoint is present without BAR0; stop PCIe probing and re-enumerate with the FPGA already configured.",
            "Delegated endpoint recovery is now a deliberate experiment only: " + recover + " --force-dead-config",
        ],
        "resource0_permission": [
            "Reinstall/trigger the Task 6 udev rule, then replug or rescan: " + install_rules,
        ],
        "mem_disabled": [
            "PCI memory space is disabled; reinstall/trigger the udev rule, then rerun the non-BAR lifecycle probe: " + lifecycle_probe,
        ],
        "pcie_ready": [
            "BAR0 is usable; run BAR/debug lifecycle: " + lifecycle_bar,
            "Or run the standalone BAR gate: " + bar,
            "After BAR/debug are stable, run the first board top1 gate: " + top1,
        ],
    }
    return table.get(classification, ["Unknown lifecycle classification; inspect pcie-lifecycle.json in the run directory."])


def snapshot(bdf: str, bridge_bdf: str) -> dict[str, object]:
    device = Path("/sys/bus/pci/devices") / bdf
    bridge = Path("/sys/bus/pci/devices") / bridge_bdf
    cfg = setpci_words(bdf)
    snap: dict[str, object] = {
        "created_at": datetime.now().astimezone().isoformat(),
        "bdf": bdf,
        "bridge_bdf": bridge_bdf,
        "endpoint_exists": device.exists(),
        "bridge_exists": bridge.exists(),
        "config_words": cfg["words"],
        "config_probe": cfg["result"],
        "resource": sysfs_file(device / "resource"),
        "resource0": sysfs_file(device / "resource0"),
        "endpoint_remove": sysfs_file(device / "remove"),
        "endpoint_rescan": sysfs_file(device / "rescan"),
        "endpoint_reset": sysfs_file(device / "reset"),
        "bridge_rescan": sysfs_file(bridge / "rescan"),
        "lspci_endpoint": run(["lspci", "-Dnn", "-s", bdf], timeout=3),
        "lspci_bridge": run(["lspci", "-Dnn", "-s", bridge_bdf], timeout=3),
    }
    snap["classification"] = classify(snap)
    return snap


def read_bar_word(path: Path, offset: int) -> str | None:
    try:
        with path.open("rb", buffering=0) as handle:
            handle.seek(offset)
            return handle.read(4).hex()
    except OSError:
        return None


def maybe_run_bar_checks(snap: dict[str, object], run_dir: Path, args: argparse.Namespace) -> None:
    if snap["classification"] != "pcie_ready":
        return
    resource0 = Path("/sys/bus/pci/devices") / args.bdf / "resource0"
    snap["bar0_magic"] = read_bar_word(resource0, 0)
    snap["debug_magic"] = read_bar_word(resource0, 0x200)
    if args.run_bar:
        bar = run(["scripts/task6/task6_pcie_user_gate.sh", "bar", args.bdf, "--mode", "header"], timeout=10)
        snap["bar_gate"] = bar
        (run_dir / "bar-gate.stdout").write_text(str(bar["stdout"]), encoding="utf-8")
        (run_dir / "bar-gate.stderr").write_text(str(bar["stderr"]), encoding="utf-8")
    if args.run_debug:
        debug = run(["scripts/task6/task6_pcie_user_gate.sh", "debug-dump", args.bdf, "--samples", "4"], timeout=10)
        snap["debug_gate"] = debug
        (run_dir / "debug-dump.stdout").write_text(str(debug["stdout"]), encoding="utf-8")
        (run_dir / "debug-dump.stderr").write_text(str(debug["stderr"]), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bdf", nargs="?", default=EXPECTED_BDF)
    parser.add_argument("--bridge-bdf", default=EXPECTED_BRIDGE)
    parser.add_argument("--label", default="pcie-lifecycle")
    parser.add_argument("--rescan", action="store_true", help="write the delegated bridge rescan before probing")
    parser.add_argument(
        "--force-rescan",
        action="store_true",
        help="write bridge rescan even when a pre-snapshot classifies the endpoint as present or stale",
    )
    parser.add_argument("--wait", type=float, default=0.5, help="seconds to wait after rescan")
    parser.add_argument("--run-bar", action="store_true")
    parser.add_argument("--run-debug", action="store_true")
    args = parser.parse_args()

    run_dir = RUNS_ROOT / f"{iso_stamp()}-{args.label}"
    run_dir.mkdir(parents=True, exist_ok=False)

    bridge = Path("/sys/bus/pci/devices") / args.bridge_bdf
    snap: dict[str, object] | None = None
    if args.rescan:
        pre_snap = snapshot(args.bdf, args.bridge_bdf)
        pre_classification = str(pre_snap["classification"])
        if not args.force_rescan and pre_classification != "missing_endpoint":
            (run_dir / "bridge-rescan.json").write_text(
                json.dumps(
                    {
                        "ok": False,
                        "skipped": True,
                        "pre_classification": pre_classification,
                        "reason": (
                            "bridge rescan is skipped unless the endpoint is missing; "
                            "use --force-rescan only for a deliberate PCIe recovery experiment"
                        ),
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            snap = pre_snap
        else:
            ok, err = write_one(bridge / "rescan")
            (run_dir / "bridge-rescan.json").write_text(
                json.dumps(
                    {
                        "ok": ok,
                        "error": err,
                        "forced": bool(args.force_rescan),
                        "pre_classification": pre_classification,
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
            time.sleep(args.wait)

    if snap is None:
        snap = snapshot(args.bdf, args.bridge_bdf)
    snap["recommendations"] = recommendations(str(snap["classification"]), args.bdf, args.bridge_bdf)
    maybe_run_bar_checks(snap, run_dir, args)
    (run_dir / "pcie-lifecycle.json").write_text(json.dumps(snap, indent=2) + "\n", encoding="utf-8")

    print(f"classification: {snap['classification']}")
    print(f"run_dir: {run_dir}")
    print("next:")
    for item in snap["recommendations"]:
        print(f"- {item}")
    if snap.get("bar0_magic"):
        print(f"bar0_magic: {snap['bar0_magic']}")
    if snap.get("debug_magic"):
        print(f"debug_magic: {snap['debug_magic']}")
    return 0 if snap["classification"] == "pcie_ready" else 1


if __name__ == "__main__":
    sys.exit(main())
