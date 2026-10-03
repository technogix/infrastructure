# Technogix infrastructure

[![plan](https://img.shields.io/github/actions/workflow/status/technogix/infrastructure/deploy.yml?event=pull_request&label=plan&logo=terraform)](https://github.com/technogix/infrastructure/actions/workflows/deploy.yml?query=event%3Apull_request)
[![production](https://img.shields.io/github/actions/workflow/status/technogix/infrastructure/deploy.yml?branch=main&event=push&label=production&logo=githubactions)](https://github.com/technogix/infrastructure/actions/workflows/deploy.yml?query=branch%3Amain+event%3Apush)

Terraform code for the Technogix infrastructure on OVHcloud, deployed by GitHub Actions.

- **plan**: last pull request run (checks, tests, read-only plan of every stack).
- **production**: last run on `main` (plan, approval, apply).

## Layout

```
bootstrap/        One-time setup: Terraform state bucket + S3 keys (local state)
modules/          Reusable building blocks (domain, email-account, ...)
stacks/           Deployable units, one remote state each
  domain/         Domain names
  email/          Mailboxes
  stacks.json     Apply order of the stacks
policy/           Resource types the pipeline must never destroy
scripts/          Repository tooling, used by the CI and locally (plan guard, decryption)
tests/            All tests, run by tests/run.sh
backend.hcl       Shared S3 backend settings
.sops.yaml        Who can decrypt the private configuration
```

Each stack has its own state (`<stack>/terraform.tfstate` in the bucket). A mistake in one stack cannot touch the others, and plans stay small.

### Adding a component

- **New mailbox**: see [Mailboxes](#mailboxes).
- **New domain**: add an entry to `domains` in `stacks/domain/terraform.tfvars`.
- **New stack** (website, VM network, ...): create `stacks/<name>/` with its own `backend "s3" { key = "<name>/terraform.tfstate" }`, then add `<name>` to `stacks/stacks.json` at the right position in the apply order.
- **New resource type that holds data**: add it to `policy/protected-resource-types.txt` and set `prevent_destroy = true` on it in its module.

## Private configuration

This repository is public, and so are its GitHub Actions logs. Data that should not be public, such as mailbox addresses and staff names, is committed **encrypted** with [SOPS](https://github.com/getsops/sops) and [age](https://github.com/FiloSottile/age):

- `*.enc.yaml` files are encrypted. Their keys stay readable, their values do not.
- `.sops.yaml` lists the age public keys allowed to decrypt them.
- `scripts/decrypt-config.sh` decrypts each `stacks/**/<name>.enc.yaml` into a gitignored `<name>.auto.tfvars.json`, which Terraform loads automatically. In CI, it first registers every decrypted value as a mask, so the logs show `***` instead.
- The job summary only shows change counts, never the plan itself.

Editing requires the age private key, in the default sops location (`%AppData%\sops\age\keys.txt` on Windows) or in `SOPS_AGE_KEY_FILE`:

```powershell
sops edit stacks/email/mailboxes.enc.yaml
```

**The age private key is the only way to read this configuration: back it up in a password manager.** To give a collaborator access, add their public key to `.sops.yaml`, then run `sops updatekeys stacks/email/mailboxes.enc.yaml`.

## Mailboxes

Mailboxes are declared in `stacks/email/mailboxes.enc.yaml` (encrypted, see above), in two lists:

| List | Content | Example |
|---|---|---|
| `company_mailboxes` | Addresses of the company itself | `contact@`, `sales@` |
| `users` | Personal addresses, one per person | `firstname.lastname@` |

Both lists share a single namespace keyed by the address. The category only affects outputs. Reordering the lists, or moving an address from one list to the other, never recreates a mailbox.

**Onboarding**: add one entry to `users` and open a pull request. The plan must show only additions (`N to create, 0 to delete`).

```yaml
users:
  - address: alice.martin
    full_name: Alice Martin
  - address: john.doe
    full_name: John Doe
```

After the apply, give the new person their initial password, then ask them to change it from the webmail. Terraform never overwrites a password changed by its user.

```powershell
terraform output -json initial_passwords
```

**Never remove or rename an entry.** Either change would delete a mailbox and its emails, so the pipeline refuses it. Addresses use lowercase letters without accents (`agnes`, not `agnès`); the validation rejects anything else.

**Offboarding**: replace the entry with a `removed` block. Terraform then stops managing the mailbox but keeps it and its data. Archive or delete it later from the OVHcloud control panel.

```hcl
# stacks/email/offboarding.tf
removed {
  from = module.account["john.doe"]
  lifecycle {
    destroy = false
  }
}
```

The offline tests in `tests/stacks/email/` check these rules on every pull request, without calling OVHcloud.

## Deployment safety

The pipeline follows one rule: **a service that holds data is kept, everything else can be recreated.**

| Situation | Behaviour |
|---|---|
| Service missing (never created, or deleted manually) | Terraform creates it |
| Stateless service drifted or needing replacement | Terraform replaces it |
| Stateful service (domain, mailbox, bucket, database, volume, ...) would be destroyed or replaced | **The pipeline fails before applying** |
| Service already exists in OVHcloud but not in the state | Add an `import` block (see below); otherwise Terraform tries to create it again |

Three layers enforce this:

1. `prevent_destroy = true` on every stateful resource in the modules.
2. `scripts/plan_guard.py` reads the plan before every apply and fails if a type listed in `policy/protected-resource-types.txt` would be deleted or replaced. This also catches a resource removed from the code, which `prevent_destroy` alone does not.
3. Applies run only on `main`, after a human approves the `production` environment.

**Retiring a stateful resource on purpose**: replace its block with a `removed` block so that Terraform stops managing it without destroying it, then delete it from the OVHcloud console:

```hcl
removed {
  from = module.account["old"]
  lifecycle {
    destroy = false
  }
}
```

**Adopting an existing service** (for example a domain bought by hand):

```hcl
import {
  to = module.domain["example.com"].ovh_domain_name.this
  id = "example.com"
}
```

## CI/CD pipeline

`.github/workflows/deploy.yml`:

| Event | Jobs |
|---|---|
| Pull request to `main` | `check` (fmt, validate and offline tests, no secrets) then `plan` for each stack, with read-only credentials. The plan is in the job log, with private values masked; the job summary shows the change counts and the guard result. |
| Push to `main` | Same as above, then `apply`: waits for approval, then re-plans, re-checks and applies each stack in the order of `stacks.json`. |

### Making a change

1. Create a branch from `main` (`feat/...`, `fix/...`) and push it.
2. Open a pull request, as a draft while the work is in progress. Every push runs `check` and `plan`; review the plan in the job log.
3. When everything is green and the plan is what you expect, squash-merge.
4. On `main`, the workflow plans again, waits for the approval of the `production` environment, then applies.

`main` is protected by a ruleset (`bootstrap/github.tf`): changes only through a pull request, `check` and `plan-result` must pass, squash merges only, no force push, no deletion.

Runs on `main` are queued and never cancelled mid-apply. The state is also locked through the S3 lock file.

### Secrets

Secrets live only in **GitHub environments**, never in the repository. The two environments use the same secret names with different values:

| Secret | `plan` environment | `production` environment |
|---|---|---|
| `OVH_CLIENT_ID` / `OVH_CLIENT_SECRET` | `plan` service account (read-only) | `production` service account |
| `STATE_S3_ACCESS_KEY_ID` / `STATE_S3_SECRET_ACCESS_KEY` | `reader` S3 key | `writer` S3 key |
| `SOPS_AGE_KEY` | age private key (the `AGE-SECRET-KEY-...` line) | same |

The environments and every secret are created by `bootstrap/github.tf`: nobody copies a credential by hand. The `production` environment:

- requires an approval, which admins cannot bypass;
- only accepts deployments from `main`. A workflow modified in a pull request can then never read the write credentials.

### CI identities on OVHcloud

The CI authenticates as two OAuth2 service accounts (`bootstrap/ci_identities.tf`), whose IAM policies list the exact API actions each environment needs, on the managed domains only (`managed_domains` in `bootstrap/`):

| Identity | Can | Cannot |
|---|---|---|
| `infrastructure-ci-plan` | Read domains and mailboxes | Anything else: no write, no account data, no orders |
| `infrastructure-ci-production` | Order services, update domains, create and update mailboxes | **Delete a mailbox, terminate a service**, access the Public Cloud project or API credentials |

Deletion of data is refused by OVHcloud itself, on top of the pipeline guard. A new domain must be added to `managed_domains`, and the bootstrap re-applied, before the pipeline can manage it. The action names come from the `iamActions` of the [OVHcloud API schemas](https://eu.api.ovh.com/1.0/email/domain.json).

`tests/bootstrap/verify_ci_identities.py` (`tests/run.sh --live`) checks these permissions against OVHcloud.

Other notes on secrets:

- Mailbox passwords are generated by Terraform and stored only in the encrypted, versioned state.
- Never commit a secret in a `.tfvars` file. Committed `terraform.tfvars` files contain only public values; private ones go in a `.enc.yaml` file.

## First-time setup

Prerequisites:

- Terraform >= 1.10
- An OVHcloud account with a **default payment method** (SEPA direct debit or card). Domain orders are paid with it.
- An OVHcloud **Public Cloud project**, which hosts the state bucket and later the VMs.

1. **Bootstrap** (once, locally, then after any change to `bootstrap/`). It creates the state bucket, the CI identities, the GitHub environments and all their secrets. It needs:
   - the OVH admin key in `~/.ovh.conf` (`GET`, `POST`, `PUT`, `DELETE` on `/*`);
   - a GitHub login with admin rights on the repository: `gh auth login`;
   - the gitignored `bootstrap/bootstrap.auto.tfvars`:

     ```hcl
     cloud_project_id  = "<public cloud project id>"
     sops_age_key_file = "~/AppData/Roaming/sops/age/keys.txt"
     ```

   ```powershell
   cd bootstrap
   terraform init
   terraform plan -out tfplan
   terraform apply tfplan
   ```

   **Back up `bootstrap/terraform.tfstate` after every apply** (password manager or vault). It is the single copy of every CI secret, including the SOPS age key, and is not committed. To restore the age key on a new machine, restore the state, then:

   ```powershell
   terraform output -raw sops_age_key | Set-Content -NoNewline "$env:APPDATA/sops/age/keys.txt"
   ```

2. **Verify the state bucket** (see [State bucket protection](#state-bucket-protection)):

   ```powershell
   python -m pip install -r tests/requirements.txt
   tests/run.sh --live
   ```

3. **Open a pull request**, review the plan in the job log, merge, then approve the `production` deployment.

## Tests

```bash
tests/run.sh          # offline: plan guard + Terraform tests with mocked providers
tests/run.sh --live   # offline, then live checks against OVHcloud (local only)
```

| Directory | Content | Run by |
|---|---|---|
| `tests/scripts/` | Unit tests of the CI scripts (plan guard) | CI and local |
| `tests/stacks/<stack>/` | `terraform test` files of a stack, with mocked providers | CI and local |
| `tests/bootstrap/` | Live checks of the bootstrap: state bucket (real Terraform backend cycle, forbidden operations), CI identities (IAM permissions) and GitHub environments (protection rules, secret names) | Local only (`--live`) |

The live checks need the OVH admin key and the local bootstrap state, so they never run in CI. Terraform only accepts tests inside a configuration directory: `run.sh` copies `tests/stacks/<stack>/` into a temporary, gitignored `stacks/<stack>/.tests/` while it runs.

## State bucket protection

The `technogix-tfstate` bucket holds every Terraform state. It is protected in depth:

| Layer | Protects against |
|---|---|
| `prevent_destroy` in `bootstrap/` | A Terraform change that would delete the bucket |
| Versioning | An overwritten or corrupted state: every previous version is kept |
| Object Lock, **compliance** mode, 30 days | Any deletion of a state version, by anyone (CI keys, admin, OVHcloud console). A non-empty bucket cannot be deleted. |
| Restricted S3 keys | `reader` can only read; `writer` can write but not delete the bucket or change its lock |

Governance mode was rejected: on OVHcloud, any key allowed to delete objects can bypass governance retention, including the CI `writer` key. Consequences of compliance mode:

- To delete the bucket on purpose, wait 30 days after the last state write.
- Each `apply` leaves a version of a few KB for at least 30 days.

`tests/bootstrap/verify_state_bucket.py` checks all of this against the real bucket (`tests/run.sh --live`). Run it after any change to `bootstrap/` or `backend.hcl`, or when in doubt. It runs a real Terraform backend cycle with the `writer` and `reader` keys, then tries every forbidden operation. Its test objects live under `_healthcheck/` and remain locked for 30 days.

Not covered: deleting the whole Public Cloud project. Replicating the bucket to another region or project would cover it.

## Running locally

Requires `sops` and the age private key (see [Private configuration](#private-configuration)). From Git Bash:

```bash
scripts/decrypt-config.sh
cd stacks/email
terraform init -backend-config=../../backend.hcl
terraform plan
terraform output -json initial_passwords
```

## Notes

- **Cost**: applying the `domain` stack places a real, paid order.
- **Email offer**: mailboxes are created on the `/email/domain/<domain>` service (MX Plan / Zimbra). OVHcloud normally includes it with the domain. If the `email` stack fails on the first run, enable the email offer in the OVHcloud control panel and run the pipeline again.
