# 0003. CI identities: OVHcloud service accounts and GitHub Apps, least privilege

Date: 2026-10-04

## Context

Classic OVHcloud API keys need a browser validation and are scoped by API path on the whole account. GitHub personal tokens are tied to a person and expire.

## Decision

- OVHcloud: two OAuth2 service accounts (`plan`, `production`) created by the bootstrap, with IAM policies listing the exact API actions each stack needs, on the managed domains only. No CI identity may delete a mailbox, disable DNSSEC or terminate a service.
- GitHub: two GitHub Apps (`technogix-infra-plan`, read-only, and `technogix-infra-production`), created by hand: GitHub has no API for it. Each job mints a 1-hour installation token with `actions/create-github-app-token`.
- Secrets live only in the `plan` and `production` environments, pushed by the bootstrap; `production` only accepts `main` and requires an approval.

## Consequences

- A new kind of resource usually needs new IAM actions in `bootstrap/ci_identities.tf` (names from the `iamActions` of the OVHcloud API schemas).
- The production App, installed on all repositories, could change this repository's settings: accepted, since it only runs on `main` after approval.
