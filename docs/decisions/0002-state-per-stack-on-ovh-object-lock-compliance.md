# 0002. One state per stack, on OVHcloud Object Storage with Object Lock in compliance mode

Date: 2026-10-03

## Context

States must be remote for the CI, protected against loss and deletion, and a mistake in one area must not touch the others. A test showed that on OVHcloud any key allowed to delete objects can bypass governance retention, including the CI writer key.

## Decision

- One remote state per stack (`stacks/<name>`), in the `technogix-tfstate` bucket, with native S3 locking (`use_lockfile`).
- Versioning, and Object Lock in **compliance** mode for 30 days: no state version can be deleted by anyone, so the bucket can be neither emptied nor deleted.
- Separate S3 keys: `reader` (plans, no lock) and `writer` (applies).

## Consequences

- Deleting the bucket on purpose needs 30 days without writes.
- `tests/bootstrap/verify_state_bucket.py` checks the protection live, bypass attempt included.
