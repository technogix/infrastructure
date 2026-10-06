# 0005. The bootstrap only holds what the CI cannot create

Date: 2026-10-04

## Context

The bootstrap is applied locally with administrator credentials, outside the pull request, plan, approval, apply flow. A repository was once put there for convenience and applied before any review.

## Decision

`bootstrap/` contains only the prerequisites of the pipeline: state bucket, CI identities and their IAM, GitHub environments, their secrets, the infrastructure ruleset. Everything else is a stack applied by the CI. Bootstrap changes are reviewed before being applied.

## Consequences

- Its state is the single copy of every CI secret: back it up after any apply that creates or replaces a secret.
- `tests/bootstrap/` checks it live.
