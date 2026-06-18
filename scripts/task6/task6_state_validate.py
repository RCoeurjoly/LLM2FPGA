#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REQUIRED = [
    "milestone",
    "build_variant",
    "next_milestone",
    "latest_green_artifact",
    "current_gap",
    "failure_signature",
    "next_action",
]


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    json_path = repo / "docs" / "task6-crisp-state.json"
    org_path = repo / "docs" / "task6-crisp-state.org"
    payload = json.loads(json_path.read_text())
    missing_json = [key for key in REQUIRED if key not in payload]
    org_text = org_path.read_text()
    missing_org = [key for key in REQUIRED if key not in org_text]
    if missing_json or missing_org:
        if missing_json:
            print(f"missing JSON fields: {', '.join(missing_json)}", file=sys.stderr)
        if missing_org:
            print(f"missing org fields: {', '.join(missing_org)}", file=sys.stderr)
        return 1
    print("task6 crisp state validates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
