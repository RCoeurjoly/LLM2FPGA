#!/usr/bin/env python3
"""Software-first Task 6 PCIe recovery orchestrator.

The orchestrator deliberately separates lifecycle classification from recovery
actions. It does not treat delegated recovery from missing BAR0/resource0 as
BAR-safe, even if the next config-space lifecycle probe reports pcie_ready; that
state has repeatedly produced all-ones BAR reads and host freezes. Use a real
chassis power-cycle before BAR gates after that recovery path.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import shlex
import sys
import time
import urllib.request
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNS_ROOT = ROOT / "artifacts" / "task6" / "runs"
DEFAULT_BDF = "0000:42:00.0"
DEFAULT_BRIDGE_BDF = "0000:41:00.0"
DEFAULT_ROOT_HELPER = str(ROOT / "scripts/task6/task6_pcie_gate_root.sh")


SOFTWARE_RECOVERY_CLASSES = {
    "stale_bar_all_ones",
    "corrupt_command",
    "config_unreadable",
    "corrupt_device_id",
    "corrupt_header_type",
}


@dataclass(frozen=True)
class Step:
    action: str
    reason: str
    command: list[str] | None = None


def iso_stamp() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def make_run_dir(label: str) -> Path:
    base = RUNS_ROOT / f"{iso_stamp()}-{label}"
    for suffix in [""] + [f"-{index:02d}" for index in range(1, 100)]:
        path = Path(str(base) + suffix)
        try:
            path.mkdir(parents=True, exist_ok=False)
            return path
        except FileExistsError:
            continue
    raise SystemExit(f"could not allocate unique run directory for label: {label}")


def redacted_argv(cmd: list[str]) -> list[str]:
    redacted: list[str] = []
    redact_next = False
    for arg in cmd:
        if redact_next:
            redacted.append("<redacted>")
            redact_next = False
            continue
        redacted.append(arg)
        if arg in {"--password", "--tapo-password"}:
            redact_next = True
    return redacted


def run(cmd: list[str], *, timeout: float, run_dir: Path, name: str, dry_run: bool) -> dict[str, Any]:
    result: dict[str, Any] = {
        "argv": redacted_argv(cmd),
        "name": name,
        "dry_run": dry_run,
    }
    if dry_run:
        result.update({"returncode": 0, "stdout": "", "stderr": "", "timeout": False})
        return result
    try:
        proc = subprocess.run(
            cmd,
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        result.update(
            {
                "returncode": proc.returncode,
                "stdout": proc.stdout,
                "stderr": proc.stderr,
                "timeout": False,
            }
        )
    except subprocess.TimeoutExpired as exc:
        result.update(
            {
                "returncode": None,
                "stdout": exc.stdout or "",
                "stderr": exc.stderr or "",
                "timeout": True,
            }
        )
    (run_dir / f"{name}.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def parse_lifecycle_stdout(stdout: str) -> tuple[str | None, Path | None]:
    classification: str | None = None
    run_dir: Path | None = None
    for line in stdout.splitlines():
        if line.startswith("classification:"):
            classification = line.split(":", 1)[1].strip()
        elif line.startswith("run_dir:"):
            run_dir = Path(line.split(":", 1)[1].strip())
    return classification, run_dir


def load_lifecycle_json(lifecycle_run_dir: Path | None) -> dict[str, Any] | None:
    if lifecycle_run_dir is None:
        return None
    path = lifecycle_run_dir / "pcie-lifecycle.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def classify_from_snapshot(snapshot: dict[str, Any]) -> str:
    return str(snapshot.get("classification", "unknown"))


def next_step(
    classification: str,
    *,
    recovered_missing_resource0: bool,
    tried_bridge_rescan: bool,
    tried_root_recovery: bool,
    has_then_gate: bool,
    allow_root_recovery: bool = False,
) -> Step:
    if classification == "pcie_ready":
        if recovered_missing_resource0:
            return Step(
                "needs_physical_power_cycle",
                "delegated missing_resource0 recovery restored config space but BAR access is unsafe",
            )
        if has_then_gate:
            return Step("run_then_gate", "PCIe lifecycle and BAR preflight are ready")
        return Step("done", "PCIe lifecycle and BAR preflight are ready")

    if classification == "missing_endpoint" and not tried_bridge_rescan:
        return Step("bridge_rescan", "endpoint is absent but the upstream bridge may rescan it")

    if classification == "missing_resource0" and not recovered_missing_resource0:
        return Step("delegated_recover", "endpoint identity is present but BAR0/resource0 is missing")

    if (
        classification in SOFTWARE_RECOVERY_CLASSES
        or classification == "missing_resource0"
        or (classification == "missing_endpoint" and tried_bridge_rescan)
    ) and allow_root_recovery and not tried_root_recovery:
        return Step("root_recovery", "bounded root PCIe/Thunderbolt reset ladder was explicitly enabled")

    if classification in SOFTWARE_RECOVERY_CLASSES or classification in {"missing_resource0", "missing_endpoint"}:
        return Step("needs_physical_power_cycle", "software recovery did not produce a live BAR")

    return Step("stop", f"unsupported lifecycle classification: {classification}")


def lifecycle_cmd(args: argparse.Namespace, label: str, *, run_bar: bool = False) -> list[str]:
    cmd = [
        "scripts/task6/task6_pcie_user_gate.sh",
        "lifecycle",
        args.bdf,
        "--bridge-bdf",
        args.bridge_bdf,
        "--label",
        label,
    ]
    if run_bar:
        cmd.append("--run-bar")
    return cmd


def step_command(step: Step, args: argparse.Namespace) -> list[str] | None:
    if step.action == "bridge_rescan":
        return ["scripts/task6/task6_pcie_user_gate.sh", "bridge-rescan", args.bdf, args.bridge_bdf]
    if step.action == "delegated_recover":
        return [
            "scripts/task6/task6_pcie_user_gate.sh",
            "recover",
            args.bdf,
            "--reset-first",
            "--timeout",
            str(args.recover_timeout),
        ]
    if step.action == "root_recovery":
        return [*shlex.split(args.sudo), args.root_helper, "prepare", args.bdf]
    if step.action == "run_then_gate":
        return ["scripts/task6/task6_pcie_user_gate.sh", *args.then]
    return None


def power_url(provider: str, base_url: str, on: bool) -> str:
    base = base_url.rstrip("/")
    if provider == "shelly":
        value = "true" if on else "false"
        return f"{base}/rpc/Switch.Set?id=0&on={value}"
    if provider == "tasmota":
        value = "On" if on else "Off"
        return f"{base}/cm?cmnd=Power%20{value}"
    raise ValueError(f"unsupported power provider: {provider}")


def tapo_credentials(args: argparse.Namespace) -> tuple[str, str]:
    username = args.tapo_username or os.environ.get("TAPO_USERNAME", "")
    password = args.tapo_password or os.environ.get("TAPO_PASSWORD", "")
    if not username or not password:
        raise SystemExit("Tapo provider requires --tapo-username/--tapo-password or TAPO_USERNAME/TAPO_PASSWORD")
    return username, password


def tapo_p115_cmd(args: argparse.Namespace, on: bool) -> list[str]:
    username, password = tapo_credentials(args)
    state = "on" if on else "off"
    return [
        *shlex.split(args.tapo_p115_command),
        "--host",
        args.power_url,
        "--username",
        username,
        "--password",
        password,
        "--state",
        state,
    ]


def redact_password(arg: str, args: argparse.Namespace) -> str:
    password = args.tapo_password or os.environ.get("TAPO_PASSWORD", "")
    return "<redacted>" if password and arg == password else arg


def http_get(url: str, timeout: float) -> str:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def power_cycle(args: argparse.Namespace, run_dir: Path, dry_run: bool) -> dict[str, Any]:
    result: dict[str, Any] = {
        "provider": args.power_provider,
        "target": args.power_url,
        "dry_run": dry_run,
        "off_wait_s": args.power_off_wait,
        "on_wait_s": args.power_on_wait,
    }
    if args.power_provider == "tapo-p115":
        off_cmd = tapo_p115_cmd(args, False)
        on_cmd = tapo_p115_cmd(args, True)
        result["off_command"] = [redact_password(arg, args) for arg in off_cmd]
        result["on_command"] = [redact_password(arg, args) for arg in on_cmd]
        if dry_run:
            return result
        off = run(off_cmd, timeout=args.power_http_timeout, run_dir=run_dir, name="power-off", dry_run=False)
        time.sleep(args.power_off_wait)
        on = run(on_cmd, timeout=args.power_http_timeout, run_dir=run_dir, name="power-on", dry_run=False)
        time.sleep(args.power_on_wait)
        result["off_returncode"] = off.get("returncode")
        result["on_returncode"] = on.get("returncode")
        (run_dir / "power-cycle.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        return result
    off_url = power_url(args.power_provider, args.power_url, False)
    on_url = power_url(args.power_provider, args.power_url, True)
    if dry_run:
        result["actions"] = [off_url, on_url]
        return result
    result["off_url"] = off_url
    result["off_response"] = http_get(off_url, args.power_http_timeout)
    time.sleep(args.power_off_wait)
    result["on_url"] = on_url
    result["on_response"] = http_get(on_url, args.power_http_timeout)
    time.sleep(args.power_on_wait)
    (run_dir / "power-cycle.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result

def load_fixture(path: str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bdf", default=DEFAULT_BDF)
    parser.add_argument("--bridge-bdf", default=DEFAULT_BRIDGE_BDF)
    parser.add_argument("--label", default="pcie-recovery-orchestrator")
    parser.add_argument("--root-helper", default=DEFAULT_ROOT_HELPER)
    parser.add_argument("--sudo", default="sudo -n")
    parser.add_argument("--recover-timeout", type=float, default=20.0)
    parser.add_argument("--command-timeout", type=float, default=120.0)
    parser.add_argument("--max-actions", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--allow-bar-probe",
        action="store_true",
        help=(
            "allow lifecycle probes to touch BAR0 MMIO; disabled by default because "
            "stale PCIe/BAR state can wedge the host below userspace timeouts"
        ),
    )
    parser.add_argument("--allow-power-cycle", action="store_true", help="allow configured smart-plug power cycle after software recovery fails")
    parser.add_argument("--allow-root-recovery", action="store_true", help="allow root PCIe/Thunderbolt reset ladder; disabled by default because it previously froze the host")
    parser.add_argument("--power-provider", choices=["shelly", "tasmota", "tapo-p115"], default="shelly")
    parser.add_argument("--power-url", default="", help="HTTP base URL for Shelly/Tasmota, or host/IP for tapo-p115")
    parser.add_argument("--power-off-wait", type=float, default=10.0)
    parser.add_argument("--power-on-wait", type=float, default=30.0)
    parser.add_argument("--power-http-timeout", type=float, default=30.0)
    parser.add_argument("--tapo-username", default="", help="Tapo/TP-Link account email; TAPO_USERNAME is also accepted")
    parser.add_argument("--tapo-password", default="", help="Tapo/TP-Link password; TAPO_PASSWORD is also accepted")
    parser.add_argument(
        "--tapo-p115-command",
        default=(
            "nix shell nixpkgs#uv -c uv run --with tapo "
            "python3 scripts/task6/task6_tapo_p115_power.py --backend tapo"
        ),
    )
    parser.add_argument("--fixture-json", help="read one lifecycle snapshot and print the selected next action")
    parser.add_argument(
        "--then",
        nargs=argparse.REMAINDER,
        default=[],
        help="gate command after pcie_ready, beginning with the task6_pcie_user_gate.sh mode",
    )
    args = parser.parse_args()

    run_dir = make_run_dir(args.label)
    transcript: list[dict[str, Any]] = []

    fixture = load_fixture(args.fixture_json)
    if fixture is not None:
        step = next_step(
            classify_from_snapshot(fixture),
            recovered_missing_resource0=False,
            tried_bridge_rescan=False,
            tried_root_recovery=False,
            has_then_gate=bool(args.then),
            allow_root_recovery=args.allow_root_recovery,
        )
        selected = {**step.__dict__, "command": step_command(step, args)}
        summary = {"run_dir": str(run_dir), "fixture": args.fixture_json, "selected": selected}
        (run_dir / "orchestrator-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, indent=2))
        return 0

    recovered_missing_resource0 = False
    tried_bridge_rescan = False
    tried_root_recovery = False
    last_classification = "unknown"
    power_cycled = False

    for action_index in range(args.max_actions + 1):
        life = run(
            lifecycle_cmd(args, f"{args.label}-lifecycle-{action_index}", run_bar=args.allow_bar_probe),
            timeout=args.command_timeout,
            run_dir=run_dir,
            name=f"lifecycle-{action_index}",
            dry_run=args.dry_run,
        )
        classification, lifecycle_run_dir = parse_lifecycle_stdout(str(life.get("stdout", "")))
        snapshot = load_lifecycle_json(lifecycle_run_dir)
        if args.dry_run and classification is None:
            classification = "unknown"
        if snapshot is not None:
            classification = classify_from_snapshot(snapshot)
        last_classification = classification or "unknown"
        transcript.append(
            {
                "action": "lifecycle",
                "classification": last_classification,
                "lifecycle_run_dir": str(lifecycle_run_dir) if lifecycle_run_dir else None,
            }
        )

        step = next_step(
            last_classification,
            recovered_missing_resource0=recovered_missing_resource0,
            tried_bridge_rescan=tried_bridge_rescan,
            tried_root_recovery=tried_root_recovery,
            has_then_gate=bool(args.then),
            allow_root_recovery=args.allow_root_recovery,
        )
        cmd = step_command(step, args)
        transcript.append({"action": step.action, "reason": step.reason, "command": cmd})

        if step.action == "needs_physical_power_cycle" and args.allow_power_cycle and args.power_url and not power_cycled:
            cycle = power_cycle(args, run_dir, args.dry_run)
            transcript.append({"action": "power_cycle", "result": cycle})
            power_cycled = True
            recovered_missing_resource0 = False
            tried_bridge_rescan = False
            tried_root_recovery = False
            continue
        if step.action in {"done", "needs_physical_power_cycle", "stop"}:
            break
        if cmd is None:
            break
        result = run(
            cmd,
            timeout=args.command_timeout,
            run_dir=run_dir,
            name=f"{step.action}-{action_index}",
            dry_run=args.dry_run,
        )
        if step.action == "bridge_rescan":
            tried_bridge_rescan = True
        elif step.action == "delegated_recover":
            recovered_missing_resource0 = True
        elif step.action == "root_recovery":
            if result.get("returncode") != 0:
                stderr = str(result.get("stderr", ""))
                failed_action = "root_recovery_unavailable" if "sudo:" in stderr else "needs_physical_power_cycle"
                transcript.append({"action": failed_action, "reason": stderr.strip()})
                break
            tried_root_recovery = True
            tried_root_recovery = True
        elif step.action == "run_then_gate":
            summary = {
                "run_dir": str(run_dir),
                "final_classification": last_classification,
                "final_action": step.action,
                "then_returncode": result.get("returncode"),
                "transcript": transcript,
            }
            (run_dir / "orchestrator-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(summary, indent=2))
            return 0 if result.get("returncode") == 0 else 1

    final_action = transcript[-1]["action"] if transcript else "none"
    summary = {
        "run_dir": str(run_dir),
        "final_classification": last_classification,
        "final_action": final_action,
        "transcript": transcript,
    }
    (run_dir / "orchestrator-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if final_action == "done" else 1


if __name__ == "__main__":
    sys.exit(main())
