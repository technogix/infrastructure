#!/usr/bin/env python3
"""Fail if a Terraform plan orders a domain that OVHcloud cannot sell as planned.

Usage: check_domain_orders.py <plan.json>
The plan JSON comes from `terraform show -json tfplan`.

For every ovh_domain_name the plan creates (imports are ignored), asks
OVHcloud, through an order cart that is never checked out, whether the
planned pricing mode (e.g. create-default) is orderable. A domain already
registered elsewhere is only offered as a transfer, so the order would fail
at apply time: this catches it in the pull request.

Authenticates with OVH_CLIENT_ID / OVH_CLIENT_SECRET (cart lookups need no
IAM permission, the read-only plan identity is enough).
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://eu.api.ovh.com/1.0"
TOKEN_URL = "https://www.ovh.com/auth/oauth2/token"


def planned_orders(plan):
    """(domain, subsidiary, pricing_mode) of every domain the plan creates."""
    orders = []
    for rc in plan.get("resource_changes", []):
        change = rc["change"]
        if rc["type"] != "ovh_domain_name" or "create" not in change["actions"] or change.get("importing"):
            continue
        after = change["after"]
        plans = after.get("plan") or [{}]
        orders.append((after["domain_name"], after.get("ovh_subsidiary") or "FR",
                       plans[0].get("pricing_mode") or "create-default"))
    return orders


class OvhCart:
    def __init__(self, client_id, client_secret):
        data = urllib.parse.urlencode({
            "grant_type": "client_credentials", "scope": "all",
            "client_id": client_id, "client_secret": client_secret,
        }).encode()
        with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=data)) as r:
            self.headers = {"Authorization": f"Bearer {json.load(r)['access_token']}",
                            "Content-Type": "application/json"}
        self.carts = {}

    def _call(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(API + path, data=data, method=method, headers=self.headers)
        with urllib.request.urlopen(req) as r:
            return json.load(r)

    def offers(self, domain, subsidiary):
        if subsidiary not in self.carts:
            self.carts[subsidiary] = self._call("POST", "/order/cart", {
                "ovhSubsidiary": subsidiary, "description": "CI order check, never checked out"})["cartId"]
        cart = self.carts[subsidiary]
        return self._call("GET", f"/order/cart/{cart}/domain?domain={urllib.parse.quote(domain)}")


def check(orders, offers_of):
    """Returns the list of error messages (empty when every order is possible)."""
    errors = []
    for domain, subsidiary, pricing_mode in orders:
        offers = offers_of(domain, subsidiary)
        orderable = sorted({o.get("pricingMode") for o in offers if o.get("orderable")})
        if pricing_mode in orderable:
            print(f"OK: {domain} can be ordered with {pricing_mode}.")
        else:
            errors.append(f"{domain}: planned {pricing_mode}, but OVHcloud only offers "
                          f"{', '.join(orderable) or 'nothing'}"
                          + (" (the domain is registered elsewhere)" if "transfer-default" in orderable else ""))
    return errors


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    orders = planned_orders(json.loads(Path(argv[1]).read_text(encoding="utf-8")))
    if not orders:
        print("No domain order in this plan.")
        return 0
    cart = OvhCart(os.environ["OVH_CLIENT_ID"], os.environ["OVH_CLIENT_SECRET"])
    errors = check(orders, cart.offers)
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
