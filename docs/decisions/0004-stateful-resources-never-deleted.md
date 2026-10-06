# 0004. Stateful resources are never deleted by the pipeline

Date: 2026-10-03

## Context

Mailboxes, domains, repositories and buckets hold data or history that cannot be recreated. Everything else (DNS records, settings, forwards) can be replaced freely.

## Decision

Three independent layers:
- `prevent_destroy` on every stateful resource;
- `scripts/plan_guard.py`, which fails any plan destroying or replacing a type listed in `policy/protected-resource-types.txt` (it also catches a resource removed from the code);
- IAM: the CI identities cannot delete these resources at all.

## Consequences

- Retiring a stateful resource is deliberate: a `removed` block with `destroy = false`, then a manual deletion.
- DNS records, forwards and settings are configuration: the CI may delete and recreate them.
