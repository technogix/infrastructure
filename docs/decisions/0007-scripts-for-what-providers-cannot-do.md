# 0007. Scripts, driven by Terraform, for what the providers cannot do

Date: 2026-10-05

## Context

Two needs have no provider resource: removing the parking records of a new OVHcloud zone, and MX Plan redirections. The criterion: if everything is lost, rerun as automatically as possible and get back the same state.

## Decision

A `terraform_data` resource runs a script with `local-exec`, at apply time only:
- `modules/domain` runs `scripts/remove_ovh_parking_records.py` once per domain;
- `stacks/email` runs `scripts/sync_email_forwards.py` whenever the declared forwards change; it reconciles exactly, and only for the managed mailboxes.

Each script is idempotent, unit-tested, and checked live.

## Consequences

- These are the only imperative parts of the code.
- `terraform test` runs provisioners: `tests/run.sh` sets `INFRA_OFFLINE_TESTS=1`, which the scripts honour.
