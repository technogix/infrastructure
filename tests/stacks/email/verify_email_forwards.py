#!/usr/bin/env python3
"""Verify that the email forwards at OVHcloud match the configuration.

Live test, run locally (tests/run.sh --live). Read-only. Decrypts
stacks/email/mailboxes.enc.yaml with sops, reads the redirections with the
CI plan identity (which also checks its IAM permission), and compares them
with the same logic as scripts/sync_email_forwards.py. Addresses are never
printed, only counts.
"""

import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

from sync_email_forwards import plan_changes  # noqa: E402

API = "https://eu.api.ovh.com/1.0"
TOKEN_URL = "https://www.ovh.com/auth/oauth2/token"


def main():
    domain = next(line.split('"')[1] for line in
                  (ROOT / "stacks" / "email" / "terraform.tfvars").read_text(encoding="utf-8").splitlines()
                  if line.startswith("domain"))
    try:
        config = json.loads(subprocess.run(
            ["sops", "decrypt", "--output-type", "json", str(ROOT / "stacks" / "email" / "mailboxes.enc.yaml")],
            capture_output=True, text=True, check=True).stdout)
    except (OSError, subprocess.CalledProcessError) as e:
        sys.exit(f"Cannot decrypt the mailbox configuration with sops: {e}")
    mailboxes = [m["address"] for m in config.get("company_mailboxes", []) + config.get("users", [])]
    desired = config.get("forwards", [])

    out = subprocess.run(["terraform", "output", "-json", "ci_credentials"], cwd=ROOT / "bootstrap",
                         capture_output=True, text=True, check=True)
    creds = json.loads(out.stdout)["plan"]
    data = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "all",
                                   "client_id": creds["client_id"], "client_secret": creds["client_secret"]}).encode()
    with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=data)) as r:
        headers = {"Authorization": f"Bearer {json.load(r)['access_token']}"}

    base = f"{API}/email/domain/{domain}/redirection"
    try:
        with urllib.request.urlopen(urllib.request.Request(base, headers=headers)) as r:
            ids = json.load(r)
        existing = []
        for i in ids:
            with urllib.request.urlopen(urllib.request.Request(f"{base}/{i}", headers=headers)) as r:
                existing.append(json.load(r))
    except urllib.error.HTTPError as e:
        print(f"[FAIL] plan identity reads the redirections (HTTP {e.code})")
        return 1
    print("[PASS] plan identity reads the redirections")

    missing, extra = plan_changes(domain, desired, existing, mailboxes)
    ok = not missing and not extra
    print(f"[{'PASS' if ok else 'FAIL'}] forwards match the configuration "
          f"({len(desired)} declared, {len(missing)} missing, {len(extra)} extra)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
