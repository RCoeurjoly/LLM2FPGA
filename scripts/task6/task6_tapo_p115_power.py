#!/usr/bin/env python3
"""Control a TP-Link Tapo P115 plug for Task 6 chassis power recovery."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from typing import Any


def credential_pair(args: argparse.Namespace) -> tuple[str, str]:
    username = args.username or os.environ.get("TAPO_USERNAME", "")
    password = args.password or os.environ.get("TAPO_PASSWORD", "")
    if not username or not password:
        raise SystemExit("Tapo P115 control requires --username/--password or TAPO_USERNAME/TAPO_PASSWORD")
    return username, password


def protocol_attempts(args: argparse.Namespace) -> list[tuple[str | None, int | None]]:
    if args.encryption_type:
        return [(args.encryption_type, args.encryption_version)]
    return [
        (None, None),
        ("aes", None),
        ("klap", 2),
        ("klap", 1),
    ]


def normalize_info(info: Any) -> dict[str, Any]:
    if isinstance(info, str):
        try:
            decoded = json.loads(info)
            return decoded if isinstance(decoded, dict) else {"raw": decoded}
        except json.JSONDecodeError:
            return {"raw": info}
    if isinstance(info, dict):
        return info
    values = getattr(info, "__dict__", None)
    if isinstance(values, dict):
        return values
    return {"raw": str(info)}


async def run_tapo_backend(args: argparse.Namespace) -> dict[str, Any]:
    from tapo import ApiClient

    username, password = credential_pair(args)
    client = ApiClient(username, password, timeout_s=int(args.timeout))
    plug = await client.p115(args.host)
    if args.state == "on":
        await plug.on()
    elif args.state == "off":
        await plug.off()

    if hasattr(plug, "get_device_info_json"):
        info = normalize_info(await plug.get_device_info_json())
    else:
        info = normalize_info(await plug.get_device_info())
    return {
        "backend": "tapo",
        "host": args.host,
        "action": args.state,
        "model": info.get("model"),
        "nickname": info.get("nickname"),
        "device_on": info.get("device_on"),
        "firmware_version": info.get("fw_ver"),
        "hardware_version": info.get("hw_ver"),
        "raw_info": info if args.include_raw else None,
    }


async def try_plugp100_connect(
    args: argparse.Namespace,
    session: Any,
    creds: Any,
    encryption_type: str | None,
    encryption_version: int | None,
) -> tuple[Any | None, str | None]:
    from plugp100.new.device_factory import DeviceConnectConfiguration, connect

    config = DeviceConnectConfiguration(
        host=args.host,
        port=args.port,
        credentials=creds,
        device_type=args.device_type or None,
        encryption_type=encryption_type,
        encryption_version=encryption_version,
    )
    try:
        device = await connect(config, session=session)
        await device.update()
        return device, None
    except Exception as exc:  # noqa: BLE001 - report library-specific handshake failures uniformly.
        return None, f"{type(exc).__name__}: {exc}"


async def run_plugp100_backend(args: argparse.Namespace) -> dict[str, Any]:
    import aiohttp
    from plugp100.common.credentials import AuthCredential

    username, password = credential_pair(args)
    timeout = aiohttp.ClientTimeout(total=args.timeout)
    creds = AuthCredential(username, password)
    errors: list[dict[str, Any]] = []
    async with aiohttp.ClientSession(timeout=timeout) as session:
        for encryption_type, encryption_version in protocol_attempts(args):
            device, error = await try_plugp100_connect(args, session, creds, encryption_type, encryption_version)
            attempt = {"encryption_type": encryption_type, "encryption_version": encryption_version}
            if device is None:
                errors.append({**attempt, "error": error})
                continue

            if args.state == "on":
                await device.turn_on()
                await device.update()
            elif args.state == "off":
                await device.turn_off()
                await device.update()

            return {
                "backend": "plugp100",
                "host": args.host,
                "action": args.state,
                "protocol": getattr(device, "protocol_version", None),
                "device_type": str(getattr(device, "device_type", "")),
                "model": getattr(device, "model", None),
                "nickname": getattr(device, "nickname", None),
                "firmware_version": getattr(device, "firmware_version", None),
                "hardware_version": getattr(device, "hardware_version", None),
                "is_on": getattr(device, "is_on", None),
                "connected_with": attempt,
            }
    raise RuntimeError(json.dumps({"error": "all plugp100 protocol attempts failed", "attempts": errors}))


async def run(args: argparse.Namespace) -> int:
    errors: list[dict[str, str]] = []
    backends = [args.backend] if args.backend != "auto" else ["tapo", "plugp100"]
    for backend in backends:
        try:
            if backend == "tapo":
                summary = await run_tapo_backend(args)
            elif backend == "plugp100":
                summary = await run_plugp100_backend(args)
            else:
                raise ValueError(f"unsupported backend: {backend}")
            print(json.dumps({key: value for key, value in summary.items() if value is not None}, indent=2, sort_keys=True))
            return 0
        except Exception as exc:  # noqa: BLE001 - keep backend errors visible to recovery logs.
            errors.append({"backend": backend, "error": f"{type(exc).__name__}: {exc}"})

    print(
        json.dumps(
            {
                "host": args.host,
                "action": args.state,
                "error": "all Tapo P115 control backends failed",
                "attempts": errors,
            },
            indent=2,
            sort_keys=True,
        ),
        file=sys.stderr,
    )
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=80)
    parser.add_argument("--state", choices=["status", "on", "off"], required=True)
    parser.add_argument("--username", default="", help="Tapo/TP-Link account email; TAPO_USERNAME is also accepted")
    parser.add_argument("--password", default="", help="Tapo/TP-Link password; TAPO_PASSWORD is also accepted")
    parser.add_argument("--backend", choices=["auto", "tapo", "plugp100"], default="auto")
    parser.add_argument("--device-type", default="", help="optional plugp100 device type override")
    parser.add_argument("--encryption-type", choices=["aes", "klap"])
    parser.add_argument("--encryption-version", type=int)
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--include-raw", action="store_true")
    args = parser.parse_args()
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
