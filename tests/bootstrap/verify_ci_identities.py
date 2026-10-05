#!/usr/bin/env python3
"""Verify the OVHcloud permissions of the CI identities (OAuth2 service accounts).

Live test, run locally after `terraform apply` in bootstrap/:

    tests/run.sh --live

Credentials are read from the bootstrap outputs (local state). Checks that
need a resource which does not exist yet (e.g. a domain not ordered) are
reported as SKIP.

Side effects: creates empty order carts, which expire on their own. Never
orders, modifies or deletes anything.
"""

import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
API = "https://eu.api.ovh.com/1.0"
# Domain names are read through the v2 API (/v2/domain/name/<domain>).
API_V2 = "https://eu.api.ovh.com/v2"
TOKEN_URL = "https://www.ovh.com/auth/oauth2/token"
SUBSIDIARY = "IE"

counts = {"PASS": 0, "FAIL": 0, "SKIP": 0}


def report(status, label, detail=""):
    counts[status] += 1
    print(f"[{status}] {label}" + (f" ({detail})" if detail else ""))


def token(creds):
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials", "scope": "all",
        "client_id": creds["client_id"], "client_secret": creds["client_secret"],
    }).encode()
    with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=data)) as r:
        return json.load(r)["access_token"]


def call(tok, method, path, body=None, base=API):
    """Returns (HTTP status, parsed body or None)."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers={
        "Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        return e.code, None


def expect_allowed(label, status):
    report("PASS" if 200 <= status < 300 else "FAIL", label, f"HTTP {status}")


def expect_denied(label, status):
    report("PASS" if status in (401, 403) else "FAIL", label, f"HTTP {status}")


def expect_hidden(label, status):
    """OVHcloud answers 404 instead of 403 on an existing resource the
    identity has no right on: it does not even reveal that it exists."""
    report("PASS" if status in (401, 403, 404) else "FAIL", label, f"HTTP {status}")


def expect_allowed_on_resource(label, status):
    """Read of a resource that may not exist yet: 404 means 'cannot tell'."""
    if status == 404:
        report("SKIP", label, "resource does not exist yet")
    else:
        expect_allowed(label, status)


def main():
    out = subprocess.run(["terraform", "output", "-json"], cwd=ROOT / "bootstrap",
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"Cannot read bootstrap outputs:\n{out.stderr}")
    outputs = json.loads(out.stdout)
    creds = outputs["ci_credentials"]["value"]
    project = outputs["cloud_project_id"]["value"]
    domains = outputs["managed_domains"]["value"]

    tokens = {}
    print("== Authentication")
    for env in ("plan", "production"):
        try:
            tokens[env] = token(creds[env])
            report("PASS", f"{env}: obtains an OAuth2 token")
        except urllib.error.HTTPError as e:
            report("FAIL", f"{env}: obtains an OAuth2 token", f"HTTP {e.code}")
    if len(tokens) != 2:
        return 1
    plan, prod = tokens["plan"], tokens["production"]

    print("== plan: read-only")
    for domain in domains:
        expect_allowed_on_resource(f"plan: reads {domain}", call(plan, "GET", f"/domain/name/{domain}", base=API_V2)[0])
    expect_denied("plan: cannot read the account", call(plan, "GET", "/me")[0])
    expect_denied("plan: cannot read payment methods", call(plan, "GET", "/me/payment/method")[0])
    status, cart = call(plan, "POST", "/order/cart", {"ovhSubsidiary": SUBSIDIARY, "description": "ci-check"})
    if cart:
        expect_denied("plan: cannot use an order cart", call(plan, "POST", f"/order/cart/{cart['cartId']}/assign")[0])
    else:
        report("FAIL", "plan: cannot use an order cart", f"cart creation HTTP {status}")

    print("== production: create and update, never delete")
    for domain in domains:
        expect_allowed_on_resource(f"production: reads {domain}", call(prod, "GET", f"/domain/name/{domain}", base=API_V2)[0])
    expect_allowed("production: reads the account", call(prod, "GET", "/me")[0])
    expect_allowed("production: reads payment methods", call(prod, "GET", "/me/payment/method?default=true")[0])
    status, cart = call(prod, "POST", "/order/cart", {"ovhSubsidiary": SUBSIDIARY, "description": "ci-check"})
    if cart:
        expect_allowed("production: can use an order cart", call(prod, "POST", f"/order/cart/{cart['cartId']}/assign")[0])
    else:
        report("FAIL", "production: can use an order cart", f"cart creation HTTP {status}")
    # production may list mailboxes: 200 proves the email offer exists, so the
    # DELETE below must be stopped by IAM (403), not reach "account not found".
    for domain in domains:
        status, _ = call(prod, "GET", f"/email/domain/{domain}/account")
        if status == 404:
            report("SKIP", f"production: cannot delete a mailbox of {domain}", "email offer does not exist yet")
        elif status != 200:
            report("FAIL", f"production: lists mailboxes of {domain}", f"HTTP {status}")
        else:
            expect_denied(f"production: cannot delete a mailbox of {domain}",
                          call(prod, "DELETE", f"/email/domain/{domain}/account/ci-check")[0])

    print("== Isolation: no access outside the managed services")
    for env, tok in tokens.items():
        if project:
            # The project exists: it hosts the state bucket.
            expect_hidden(f"{env}: cannot access the Public Cloud project",
                          call(tok, "GET", f"/cloud/project/{project}")[0])
        expect_denied(f"{env}: cannot manage API credentials", call(tok, "GET", "/me/api/oauth2/client")[0])

    print(f"\n{counts['PASS']} passed, {counts['FAIL']} failed, {counts['SKIP']} skipped.")
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
