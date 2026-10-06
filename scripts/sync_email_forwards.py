#!/usr/bin/env python3
"""Make the email redirections of a domain match the declared forwards.

Usage: sync_email_forwards.py <domain>
Desired forwards come from the FORWARDS environment variable, a JSON list of
{"from": "<local part>", "to": "<address>"}, and MAILBOXES, a JSON list of
the local parts managed by the email stack.

The Terraform provider cannot manage MX Plan redirections, so the email
stack runs this script whenever the declared forwards change. It only
touches redirections whose source is a managed mailbox: any other
redirection is left alone. Every forward keeps a local copy in the mailbox
(OVHcloud stores it as a redirection of the address to itself).

Authenticates with OVH_CLIENT_ID / OVH_CLIENT_SECRET (CI production identity:
emailDomain redirection/get, create and delete).
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://eu.api.ovh.com/1.0"
TOKEN_URL = "https://www.ovh.com/auth/oauth2/token"


def plan_changes(domain, desired, existing, mailboxes):
    """What to create and delete so that the managed redirections match.

    desired:   [{"from": local part, "to": address}]
    existing:  [{"id", "from": address, "to": address}] (as read from OVHcloud)
    mailboxes: local parts managed by the email stack
    Returns (to_create, to_delete): [(from address, to address)], [existing ids].
    """
    managed = {f"{m}@{domain}".lower() for m in mailboxes}
    wanted = {(f"{f['from']}@{domain}".lower(), f["to"].lower()) for f in desired}
    current = [r for r in existing if r["from"].lower() in managed]

    # Local copies (address redirected to itself) are kept for the addresses
    # that still have a forward, removed otherwise.
    keep_copy = {src for src, _ in wanted}
    current_pairs = {(r["from"].lower(), r["to"].lower()): r["id"] for r in current}

    to_create = sorted(p for p in wanted if p not in current_pairs)
    to_delete = sorted(
        rid for (src, dst), rid in current_pairs.items()
        if (src, dst) not in wanted and not (src == dst and src in keep_copy)
    )
    return to_create, to_delete


class Redirections:
    def __init__(self, domain, client_id, client_secret):
        data = urllib.parse.urlencode({
            "grant_type": "client_credentials", "scope": "all",
            "client_id": client_id, "client_secret": client_secret,
        }).encode()
        with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=data)) as r:
            self.headers = {"Authorization": f"Bearer {json.load(r)['access_token']}",
                            "Content-Type": "application/json"}
        self.base = f"{API}/email/domain/{domain}/redirection"

    def _call(self, method, url, body=None):
        data = json.dumps(body).encode() if body is not None else None
        with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method,
                                                           headers=self.headers)) as r:
            raw = r.read()
            return json.loads(raw) if raw else None

    def list(self):
        return [self._call("GET", f"{self.base}/{i}") for i in self._call("GET", self.base)]

    def create(self, src, dst):
        self._call("POST", self.base, {"from": src, "to": dst, "localCopy": True})

    def delete(self, rid):
        self._call("DELETE", f"{self.base}/{rid}")


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    if os.environ.get("INFRA_OFFLINE_TESTS") == "1":
        # Set by tests/run.sh only: `terraform test` cannot skip provisioners.
        print("Offline tests: email forwards not synchronised.")
        return 0
    domain = argv[1]
    desired = json.loads(os.environ.get("FORWARDS", "[]"))
    mailboxes = json.loads(os.environ["MAILBOXES"])
    api = Redirections(domain, os.environ["OVH_CLIENT_ID"], os.environ["OVH_CLIENT_SECRET"])

    to_create, to_delete = plan_changes(domain, desired, api.list(), mailboxes)
    for rid in to_delete:
        api.delete(rid)
    for src, dst in to_create:
        api.create(src, dst)
    # Addresses are private: only counts are printed (the CI logs are public).
    print(f"Email forwards: {len(to_create)} created, {len(to_delete)} deleted.")

    # Creations are asynchronous tasks: wait until OVHcloud shows them.
    for _ in range(30):
        missing, extra = plan_changes(domain, desired, api.list(), mailboxes)
        if not missing and not extra:
            print("Email forwards match the configuration.")
            return 0
        time.sleep(10)
    print(f"ERROR: still {len(missing)} missing and {len(extra)} extra forward(s) after 5 minutes.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
