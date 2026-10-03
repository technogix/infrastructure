import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import plan_guard  # noqa: E402


def change(address, rtype, actions, mode="managed"):
    return {"address": address, "type": rtype, "mode": mode, "change": {"actions": actions}}


class PlanGuardTest(unittest.TestCase):
    def run_guard(self, *changes):
        with tempfile.TemporaryDirectory() as tmp:
            plan = Path(tmp) / "plan.json"
            plan.write_text(json.dumps({"resource_changes": list(changes)}), encoding="utf-8")
            return plan_guard.main(["plan_guard.py", str(plan)])

    def test_create_and_update_allowed(self):
        self.assertEqual(self.run_guard(
            change("module.a.ovh_email_domain_account.this", "ovh_email_domain_account", ["create"]),
            change("module.d.ovh_domain_name.this", "ovh_domain_name", ["update"]),
        ), 0)

    def test_stateless_replace_allowed(self):
        self.assertEqual(self.run_guard(
            change("ovh_domain_zone_record.www", "ovh_domain_zone_record", ["delete", "create"]),
            change("ovh_cloud_project_instance.web", "ovh_cloud_project_instance", ["create", "delete"]),
        ), 0)

    def test_stateful_delete_refused(self):
        self.assertEqual(self.run_guard(
            change("module.a.ovh_email_domain_account.this", "ovh_email_domain_account", ["delete"]),
        ), 1)

    def test_stateful_replace_refused(self):
        self.assertEqual(self.run_guard(
            change("ovh_cloud_project_database_postgresql_user.u", "ovh_cloud_project_database_postgresql_user",
                   ["delete", "create"]),
        ), 1)

    def test_data_sources_and_noop_ignored(self):
        self.assertEqual(self.run_guard(
            change("data.ovh_me.me", "ovh_me", ["read"], mode="data"),
            change("ovh_domain_name.d", "ovh_domain_name", ["no-op"]),
        ), 0)


if __name__ == "__main__":
    unittest.main()
