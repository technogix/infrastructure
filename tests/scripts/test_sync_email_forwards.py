import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from sync_email_forwards import plan_changes  # noqa: E402

DOMAIN = "example.dev"
MAILBOXES = ["contact", "alice.martin"]


def redirection(rid, src, dst):
    return {"id": rid, "from": src, "to": dst}


class PlanChangesTest(unittest.TestCase):
    def test_nothing_declared_nothing_existing(self):
        self.assertEqual(plan_changes(DOMAIN, [], [], MAILBOXES), ([], []))

    def test_new_forward_created(self):
        desired = [{"from": "contact", "to": "alice@gmail.com"}]
        self.assertEqual(plan_changes(DOMAIN, desired, [], MAILBOXES),
                         ([("contact@example.dev", "alice@gmail.com")], []))

    def test_existing_forward_and_its_local_copy_kept(self):
        desired = [{"from": "contact", "to": "alice@gmail.com"}]
        existing = [redirection("1", "contact@example.dev", "alice@gmail.com"),
                    redirection("2", "contact@example.dev", "contact@example.dev")]
        self.assertEqual(plan_changes(DOMAIN, desired, existing, MAILBOXES), ([], []))

    def test_removed_forward_and_its_local_copy_deleted(self):
        existing = [redirection("1", "contact@example.dev", "alice@gmail.com"),
                    redirection("2", "contact@example.dev", "contact@example.dev")]
        self.assertEqual(plan_changes(DOMAIN, [], existing, MAILBOXES), ([], ["1", "2"]))

    def test_changed_target_replaces_the_forward(self):
        desired = [{"from": "contact", "to": "new@gmail.com"}]
        existing = [redirection("1", "contact@example.dev", "old@gmail.com"),
                    redirection("2", "contact@example.dev", "contact@example.dev")]
        self.assertEqual(plan_changes(DOMAIN, desired, existing, MAILBOXES),
                         ([("contact@example.dev", "new@gmail.com")], ["1"]))

    def test_redirections_of_unmanaged_addresses_untouched(self):
        existing = [redirection("9", "sales@example.dev", "someone@gmail.com")]
        self.assertEqual(plan_changes(DOMAIN, [], existing, MAILBOXES), ([], []))

    def test_comparison_is_case_insensitive(self):
        desired = [{"from": "Contact", "to": "Alice@Gmail.com"}]
        existing = [redirection("1", "contact@example.dev", "alice@gmail.com")]
        self.assertEqual(plan_changes(DOMAIN, desired, existing, MAILBOXES), ([], []))


if __name__ == "__main__":
    unittest.main()
