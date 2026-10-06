#!/usr/bin/env python3
"""Verify the sites: DNS, GitHub Pages and HTTPS.

Live test, run locally (tests/run.sh --live). Read-only. For each site of
stacks/website/terraform.tfvars.json:
  - public DNS (Cloudflare DNS over HTTPS): an apex site resolves only to the
    GitHub Pages addresses (no OVHcloud parking left) and www is a CNAME to
    <owner>.github.io; a subdomain site is a CNAME to <owner>.github.io;
  - GitHub Pages: custom domain set, published by a workflow, certificate;
  - the site answers over HTTPS on the apex and www.
Needs GITHUB_TOKEN (taken from the GitHub CLI login by run.sh).
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DOH = "https://cloudflare-dns.com/dns-query"
GITHUB_PAGES_IPV4 = {"185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"}
GITHUB_PAGES_IPV6 = {"2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"}

results = []


def check(label, ok, detail=""):
    results.append(ok)
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f" ({detail})" if detail else ""))


def tfvars():
    return json.loads((ROOT / "stacks" / "website" / "terraform.tfvars.json").read_text(encoding="utf-8"))


def dns(name, rtype):
    query = urllib.parse.urlencode({"name": name, "type": rtype})
    req = urllib.request.Request(f"{DOH}?{query}", headers={"Accept": "application/dns-json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        answers = json.load(r).get("Answer", [])
    type_code = {"A": 1, "AAAA": 28, "CNAME": 5}[rtype]
    return {a["data"].rstrip(".").lower() for a in answers if a["type"] == type_code}


def github(path):
    req = urllib.request.Request(f"https://api.github.com/{path}", headers={
        "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}", "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": e.code}


def https_status(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=15) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except (urllib.error.URLError, TimeoutError) as e:
        return str(getattr(e, "reason", e))


def main():
    if not os.environ.get("GITHUB_TOKEN"):
        sys.exit("GITHUB_TOKEN is not set (run through tests/run.sh --live, or `gh auth login`).")
    v = tfvars()
    zone, owner = v["zone"], v["github_owner"]
    github_io = f"{owner}.github.io".lower()

    for repo, site in v["sites"].items():
        subdomain = site.get("subdomain", "")
        hostname = f"{subdomain}.{zone}" if subdomain else zone
        print(f"== {repo}: {hostname}")

        if subdomain:
            cname = dns(hostname, "CNAME")
            check(f"{hostname} is a CNAME to {github_io}", cname == {github_io}, ", ".join(cname))
            urls = [f"https://{hostname}/"]
        else:
            a, aaaa = dns(zone, "A"), dns(zone, "AAAA")
            check("apex A records are exactly the GitHub Pages addresses", a == GITHUB_PAGES_IPV4, ", ".join(sorted(a)))
            check("apex AAAA records are exactly the GitHub Pages addresses", aaaa == GITHUB_PAGES_IPV6, ", ".join(sorted(aaaa)))
            cname = dns(f"www.{zone}", "CNAME")
            check(f"www is a CNAME to {github_io}", cname == {github_io}, ", ".join(cname))
            urls = [f"https://{zone}/", f"https://www.{zone}/"]

        pages = github(f"repos/{owner}/{repo}/pages")
        check("GitHub Pages: custom domain set", pages.get("cname") == hostname, pages.get("cname") or str(pages.get("error")))
        check("GitHub Pages: published by a workflow", pages.get("build_type") == "workflow", pages.get("build_type"))
        check("GitHub Pages: HTTPS enforced", pages.get("https_enforced") is True, str(pages.get("https_enforced")))
        for url in urls:
            status = https_status(url)
            check(f"{url} answers", status == 200, str(status))

    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} checks passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
