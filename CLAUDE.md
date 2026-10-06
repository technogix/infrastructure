# CLAUDE.md

Guidance for Claude Code (and any newcomer) working in this repository. The README explains how things work; this file lists the rules and the traps. The reasons behind the main choices are in `docs/decisions/`.

## Rules

- **Never write outside the local machine without the maintainer's explicit approval for that specific action**: `git push`, pull requests, `gh` commands that modify something (workflow runs included), any `terraform apply` / `import` / `state` command on a remote or bootstrap state, any OVHcloud API call that changes something. Local commits, plans, read-only API calls and tests are fine. Show what would change, then ask.
- **Everything Terraform can manage is in Terraform.** Manual steps only when no provider can do it (GitHub Apps, MX Plan order), and they are documented in the README.
- **`bootstrap/` only holds prerequisites the CI cannot create** (state bucket, CI identities, GitHub environments and secrets, the infrastructure ruleset). Applied locally by an administrator, after review. Anything else goes in a stack under `stacks/`, applied by the CI.
- **A module adds its own resources, and only them.** A site adds its own DNS records; the domain module delivers a clean zone.
- **Stateful resources are never deleted** (domains, mailboxes, repositories, buckets...): `prevent_destroy`, the pipeline guard (`policy/protected-resource-types.txt`) and IAM (the CI cannot delete them). To retire one, use a `removed` block with `destroy = false`.
- **The repository and its CI logs are public.** No secret, no personal data in clear: private values go in `*.enc.yaml` (SOPS), are masked in the CI, and scripts print counts, never addresses.
- **Repository content in English.** The maintainer speaks French.

## Commands

```bash
tests/run.sh          # offline: unit tests + terraform test with mocked providers (what the CI runs)
tests/run.sh --live   # + live checks against OVHcloud and GitHub (needs ~/.ovh.conf, gh login, bootstrap state, sops)
scripts/decrypt-config.sh   # decrypt *.enc.yaml before a local plan of the email stack
```

Local plan of a stack, read-only: S3 `reader` key from `terraform -chdir=bootstrap output -json s3_credentials`, then `terraform init -backend-config=../../backend.hcl` and `terraform plan -lock=false`. Use a scratch `TF_DATA_DIR` to avoid touching the stack's `.terraform`.

## Traps already met

- **OVHcloud IAM answers 404, not 403**, on an existing resource the identity has no right on.
- **Domain names are read through the v2 API** (`/v2/domain/name/<domain>`); `/1.0/domain/name/...` does not exist.
- **`~/.ovh.conf` conflicts with `OVH_CLIENT_ID`/`OVH_CLIENT_SECRET`** in the provider ("multiple authentication methods"), and is found even with `HOME` overridden.
- **A domain comes with the `redirect` email offer** (no mailbox): an MX Plan must be ordered by hand. **Mailbox sizes are a fixed decimal list** (5 GB = `5000000000`).
- **A new zone has OVHcloud parking records**: removed once by `modules/domain` (`scripts/remove_ovh_parking_records.py`).
- **Some settings only apply once the resource exists** (GitHub Pages custom domain, HTTPS enforcement): the deploy job applies until the plan is empty, at most twice.
- **GitHub App + repository merge settings**: reading them needs `contents:write`; they are set at creation and ignored afterwards, the ruleset enforces squash merges.
- **`terraform test` runs provisioners**: `tests/run.sh` sets `INFRA_OFFLINE_TESTS=1`, which the provisioner scripts honour.
- **Domain orders**: OVHcloud may take ~48 h to verify an order, longer than the provider waits (30 min). A failed apply does not cancel the order: do not apply again before delivery, then `terraform import` the domain.
- **Windows**: `python3` may be a Microsoft Store placeholder (`tests/run.sh` checks the interpreter); PowerShell 5.1 `>` writes UTF-16 (use `Set-Content`).
