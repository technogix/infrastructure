# 0006. technogix.dev, and checking domain orders in every plan

Date: 2026-10-05

## Context

`technogix.io` was registered at another registrar (expired, in its renewal grace period): it could only be transferred, and a transfer is a one-off operation, not a state of the infrastructure. The first plan did not notice it.

## Decision

- The domain is `technogix.dev`: cheap, available, on the HSTS preload list.
- `scripts/check_domain_orders.py` asks OVHcloud, in every plan and before every apply, whether each domain to create can be ordered as planned.
- A domain that already exists (delivered after a failed apply, or bought by hand) is adopted with a one-off `terraform import`, not with transitional code.

## Consequences

- An order can take about 48 hours to be verified, longer than the provider waits: never apply again before delivery.
- Adding a domain also needs `managed_domains` in the bootstrap (IAM).
