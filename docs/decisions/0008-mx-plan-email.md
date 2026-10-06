# 0008. MX Plan for email

Date: 2026-10-05

## Context

A domain only comes with the `redirect` email offer, which has no mailbox. Zimbra is the newer OVHcloud offer, with self-service passwords, but the provider has no resource for its accounts.

## Decision

MX Plan (MX005, 5 mailboxes), ordered by hand once; mailboxes managed by Terraform (`modules/email-account`). Terraform sets the initial password and never touches it again. Forwards to personal addresses always keep a local copy.

## Consequences

- With the Roundcube webmail, users cannot change their password themselves.
- Forwarded mail is not authenticated by the target: part of it goes to spam (Gmail filter). For a real team, Zimbra Pro, Exchange or Google Workspace / Microsoft 365 will be reconsidered.
