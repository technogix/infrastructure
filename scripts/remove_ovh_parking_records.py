#!/usr/bin/env python3
"""Remove the parking records OVHcloud puts in every new DNS zone.

Usage: remove_ovh_parking_records.py <zone>

A new OVHcloud zone points its apex and www to the OVHcloud parking page
(A 213.186.33.5) and carries its markers (TXT "1|..." and "3|welcome"). They
conflict with the site records (a CNAME cannot coexist with any other record).
Terraform only deletes what it manages, so the website stack runs this
script once, at apply time, before creating its own records.

Only those exact records are selected: mail records (MX, SPF, DKIM, SRV...)
and any other record are never touched. Idempotent: nothing to remove,
nothing done.

Authenticates with OVH_CLIENT_ID / OVH_CLIENT_SECRET (CI production identity:
dnsZone record/get, record/delete and refresh).
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.request

API = "https://eu.api.ovh.com/1.0"
TOKEN_URL = "https://www.ovh.com/auth/oauth2/token"

PARKING_SUBDOMAINS = {"", "www"}
PARKING_IPV4 = {"213.186.33.5"}
PARKING_TXT = re.compile(r'^"?\d\|')


def is_parking(record):
    """True for an OVHcloud parking record of the apex or www."""
    if record["subDomain"] not in PARKING_SUBDOMAINS:
        return False
    if record["fieldType"] == "A":
        return record["target"] in PARKING_IPV4
    if record["fieldType"] == "TXT":
        return bool(PARKING_TXT.match(record["target"]))
    return False


class Zone:
    def __init__(self, zone, client_id, client_secret):
        data = urllib.parse.urlencode({
            "grant_type": "client_credentials", "scope": "all",
            "client_id": client_id, "client_secret": client_secret,
        }).encode()
        with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=data)) as r:
            self.headers = {"Authorization": f"Bearer {json.load(r)['access_token']}"}
        self.zone = zone

    def _call(self, method, path):
        req = urllib.request.Request(f"{API}/domain/zone/{self.zone}{path}", method=method,
                                     headers=self.headers)
        with urllib.request.urlopen(req) as r:
            body = r.read()
            return json.loads(body) if body else None

    def records(self, subdomain):
        query = urllib.parse.urlencode({"subDomain": subdomain})
        return [self._call("GET", f"/record/{i}") for i in self._call("GET", f"/record?{query}")]

    def delete(self, record_id):
        self._call("DELETE", f"/record/{record_id}")

    def refresh(self):
        self._call("POST", "/refresh")


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    zone = Zone(argv[1], os.environ["OVH_CLIENT_ID"], os.environ["OVH_CLIENT_SECRET"])
    parking = [r for sub in sorted(PARKING_SUBDOMAINS) for r in zone.records(sub) if is_parking(r)]
    for r in parking:
        zone.delete(r["id"])
        print(f"Removed parking record: {r['fieldType']} {r['subDomain'] or '@'} {r['target']}")
    if parking:
        zone.refresh()
    else:
        print("No parking record to remove.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
