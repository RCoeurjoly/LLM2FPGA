#!/usr/bin/env python3
"""Unit tests for the Task 6 PCIe recovery orchestrator decision ladder."""

from __future__ import annotations

import json
import unittest

import task6_pcie_recovery_orchestrator as MODULE


class RecoveryDecisionTest(unittest.TestCase):
    def decide(
        self,
        classification: str,
        *,
        recovered_missing_resource0: bool = False,
        tried_bridge_rescan: bool = False,
        tried_safe_helper: bool = False,
        has_then_gate: bool = True,
        allow_delegated_resource0_recovery: bool = False,
    ) -> str:
        return MODULE.next_step(
            classification,
            recovered_missing_resource0=recovered_missing_resource0,
            tried_bridge_rescan=tried_bridge_rescan,
            tried_safe_helper=tried_safe_helper,
            has_then_gate=has_then_gate,
            allow_delegated_resource0_recovery=allow_delegated_resource0_recovery,
        ).action

    def test_ready_runs_gate_when_requested(self) -> None:
        self.assertEqual(self.decide("pcie_ready"), "run_then_gate")

    def test_ready_without_gate_finishes(self) -> None:
        self.assertEqual(self.decide("pcie_ready", has_then_gate=False), "done")

    def test_ready_after_missing_resource0_recovery_requires_power_cycle(self) -> None:
        self.assertEqual(
            self.decide("pcie_ready", recovered_missing_resource0=True),
            "needs_physical_power_cycle",
        )
        self.assertEqual(
            self.decide("pcie_ready", recovered_missing_resource0=True, has_then_gate=False),
            "needs_physical_power_cycle",
        )

    def test_missing_endpoint_power_cycles_by_default(self) -> None:
        self.assertEqual(self.decide("missing_endpoint"), "needs_physical_power_cycle")

    def test_clean_missing_resource0_power_cycles_by_default(self) -> None:
        self.assertEqual(self.decide("missing_resource0"), "needs_physical_power_cycle")
        self.assertEqual(
            self.decide("missing_resource0", allow_delegated_resource0_recovery=True),
            "delegated_recover",
        )
        self.assertEqual(
            self.decide("missing_resource0", recovered_missing_resource0=True),
            "needs_physical_power_cycle",
        )

    def test_permission_and_mem_disabled_use_safe_helper_once(self) -> None:
        for classification in ["resource0_permission", "mem_disabled"]:
            with self.subTest(classification=classification):
                self.assertEqual(self.decide(classification), "safe_root_helper")
                self.assertEqual(
                    self.decide(classification, tried_safe_helper=True),
                    "needs_physical_power_cycle",
                )

    def test_stale_and_corrupt_states_power_cycle_by_default(self) -> None:
        for classification in [
            "stale_bar_all_ones",
            "corrupt_command",
            "corrupt_vendor_id",
            "config_unreadable",
            "unstable_config",
        ]:
            with self.subTest(classification=classification):
                self.assertEqual(self.decide(classification), "needs_physical_power_cycle")

    def test_unknown_classification_stops(self) -> None:
        self.assertEqual(self.decide("surprising_state"), "stop")

    def test_lifecycle_cmd_omits_bar_probe_by_default(self) -> None:
        class Args:
            bdf = "0000:42:00.0"
            bridge_bdf = "0000:41:00.0"

        cmd = MODULE.lifecycle_cmd(Args, "safe-probe")
        self.assertNotIn("--run-bar", cmd)

    def test_lifecycle_cmd_allows_explicit_bar_probe(self) -> None:
        class Args:
            bdf = "0000:42:00.0"
            bridge_bdf = "0000:41:00.0"

        cmd = MODULE.lifecycle_cmd(Args, "bar-probe", run_bar=True)
        self.assertIn("--run-bar", cmd)

    def test_power_provider_urls_are_local_http_shapes(self) -> None:
        self.assertEqual(
            MODULE.power_url("shelly", "http://plug.local/", False),
            "http://plug.local/rpc/Switch.Set?id=0&on=false",
        )
        self.assertEqual(
            MODULE.power_url("tasmota", "http://plug.local", True),
            "http://plug.local/cm?cmnd=Power%20On",
        )

    def test_tapo_p115_command_uses_credentials_and_redacts_password(self) -> None:
        class Args:
            power_url = "192.168.1.10"
            tapo_username = "user@example.com"
            tapo_password = "secret"
            tapo_p115_command = "python3 scripts/task6/task6_tapo_p115_power.py"

        cmd = MODULE.tapo_p115_cmd(Args, False)
        self.assertEqual(
            cmd,
            [
                "python3",
                "scripts/task6/task6_tapo_p115_power.py",
                "--host",
                "192.168.1.10",
                "--username",
                "user@example.com",
                "--password",
                "secret",
                "--state",
                "off",
            ],
        )
        self.assertEqual(MODULE.redact_password("secret", Args), "<redacted>")
        self.assertEqual(
            MODULE.redacted_argv(cmd),
            [
                "python3",
                "scripts/task6/task6_tapo_p115_power.py",
                "--host",
                "192.168.1.10",
                "--username",
                "user@example.com",
                "--password",
                "<redacted>",
                "--state",
                "off",
            ],
        )

    def test_secret_file_loads_tapo_credentials(self) -> None:
        import os
        import tempfile

        old_username = os.environ.pop("TAPO_USERNAME", None)
        old_password = os.environ.pop("TAPO_PASSWORD", None)
        try:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8") as stream:
                stream.write("TAPO_USERNAME=user@example.com\nTAPO_PASSWORD=secret\n")
                stream.flush()
                MODULE.load_secret_file(stream.name)
            self.assertEqual(os.environ["TAPO_USERNAME"], "user@example.com")
            self.assertEqual(os.environ["TAPO_PASSWORD"], "secret")
        finally:
            if old_username is not None:
                os.environ["TAPO_USERNAME"] = old_username
            else:
                os.environ.pop("TAPO_USERNAME", None)
            if old_password is not None:
                os.environ["TAPO_PASSWORD"] = old_password
            else:
                os.environ.pop("TAPO_PASSWORD", None)


if __name__ == "__main__":
    unittest.main()
