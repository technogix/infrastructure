# 0001. Public repository, private data encrypted

Date: 2026-10-03

## Context

The repository is the maintainer's showcase, and private repositories would make environment protection rules (required reviewers) paid. It must stay public. But mailbox addresses, staff names and forward targets must not be public, and the GitHub Actions logs of a public repository are public too.

## Decision

- Private values live in `*.enc.yaml` files encrypted with SOPS and age (`.sops.yaml`). Keys stay readable, values are encrypted; data that would reveal names is stored as list values, never as keys.
- The CI decrypts them with `scripts/decrypt-config.sh`, which registers every decrypted value with `::add-mask::` before Terraform runs.
- Scripts print counts, never addresses. The job summary shows change counts only.

## Consequences

- Editing private data needs the age key (`sops edit`). The bootstrap pushes it to the CI, and it can be restored from the bootstrap state.
- Values that are public anyway (the domain, `contact@`) stay in clear.
