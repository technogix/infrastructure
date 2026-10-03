import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import check_domain_orders as cdo  # noqa: E402


def domain_change(name, actions, pricing_mode="create-default", importing=None):
    change = {"actions": actions, "after": {
        "domain_name": name, "ovh_subsidiary": "IE",
        "plan": [{"pricing_mode": pricing_mode, "plan_code": "dev", "duration": "P1Y"}]}}
    if importing:
        change["importing"] = importing
    return {"type": "ovh_domain_name", "address": f'module.domain["{name}"].ovh_domain_name.this',
            "change": change}


def offers(*pricing_modes, orderable=True):
    return [{"pricingMode": m, "orderable": orderable} for m in pricing_modes]


class PlannedOrdersTest(unittest.TestCase):
    def test_only_created_domains(self):
        plan = {"resource_changes": [
            domain_change("new.dev", ["create"]),
            domain_change("existing.dev", ["no-op"]),
            domain_change("adopted.io", ["no-op"], importing={"id": "adopted.io"}),
            {"type": "ovh_email_domain_account", "change": {"actions": ["create"], "after": {}}},
        ]}
        self.assertEqual(cdo.planned_orders(plan), [("new.dev", "IE", "create-default")])


class CheckTest(unittest.TestCase):
    def test_available_domain(self):
        errors = cdo.check([("new.dev", "IE", "create-default")],
                           lambda d, s: offers("create-default"))
        self.assertEqual(errors, [])

    def test_domain_registered_elsewhere(self):
        errors = cdo.check([("taken.io", "IE", "create-default")],
                           lambda d, s: offers("transfer-default"))
        self.assertEqual(len(errors), 1)
        self.assertIn("registered elsewhere", errors[0])

    def test_not_orderable(self):
        errors = cdo.check([("blocked.dev", "IE", "create-default")],
                           lambda d, s: offers("create-default", orderable=False))
        self.assertEqual(len(errors), 1)


if __name__ == "__main__":
    unittest.main()
