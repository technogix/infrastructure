#!/usr/bin/env python3
"""Verify DNSSEC on every managed domain.

Live test, run locally (tests/run.sh --live). Read-only. For each domain of
the bootstrap `managed_domains` output:
  - OVHcloud reports DNSSEC enabled on its DNS zone (read with the CI plan
    identity, which also checks its IAM permission);
  - public validating resolvers (Cloudflare and Google, DNS over HTTPS)
    return authenticated answers (AD flag): the chain of trust from the
    registry down to the zone actually works.
"""

import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
API = "https://eu.api.ovh.com/1.0"
TOKEN_URL = "https://www.ovh.com/auth/oauth2/token"
RESOLVERS = {
    "Cloudflare": "https://cloudflare-dns.com/dns-query",
    "Google": "https://dns.google/resolve",
}

results = []


def check(label, ok, detail=""):
    results.append(ok)
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f" ({detail})" if detail else ""))


def plan_token(creds):
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials", "scope": "all",
        "client_id": creds["client_id"], "client_secret": creds["client_secret"],
    }).encode()
    with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=data)) as r:
        return json.load(r)["access_token"]


def dnssec_status(token, domain):
    req = urllib.request.Request(f"{API}/domain/zone/{domain}/dnssec",
                                 headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r).get("status")
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code}"


def resolver_answer(url, domain):
    """Parsed JSON answer, or None if the resolver cannot be reached."""
    query = urllib.parse.urlencode({"name": domain, "type": "SOA", "do": "1"})
    req = urllib.request.Request(f"{url}?{query}", headers={"Accept": "application/dns-json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"       {url}: {e}")
        return None


def main():
    out = subprocess.run(["terraform", "output", "-json"], cwd=ROOT / "bootstrap",
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"Cannot read bootstrap outputs:\n{out.stderr}")
    outputs = json.loads(out.stdout)
    token = plan_token(outputs["ci_credentials"]["value"]["plan"])

    for domain in outputs["managed_domains"]["value"]:
        print(f"== {domain}")
        status = dnssec_status(token, domain)
        check("OVHcloud: DNSSEC enabled on the zone (read by the plan identity)", status == "enabled", status)
        for name, url in RESOLVERS.items():
            answer = resolver_answer(url, domain) or {}
            check(f"{name} resolver validates the answer (NOERROR + AD flag)",
                  answer.get("Status") == 0 and answer.get("AD") is True,
                  f"status {answer.get('Status')}, AD {answer.get('AD')}" if answer else "unreachable")

    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} checks passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
