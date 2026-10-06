# Technogix infrastructure

[![plan](https://img.shields.io/github/actions/workflow/status/technogix/infrastructure/deploy.yml?event=pull_request&label=plan&logo=terraform)](https://github.com/technogix/infrastructure/actions/workflows/deploy.yml?query=event%3Apull_request)
[![production](https://img.shields.io/github/actions/workflow/status/technogix/infrastructure/deploy.yml?branch=main&event=push&label=production&logo=githubactions)](https://github.com/technogix/infrastructure/actions/workflows/deploy.yml?query=branch%3Amain+event%3Apush)

Terraform code for the Technogix infrastructure on OVHcloud, deployed by GitHub Actions.

- **plan**: last pull request run (checks, tests, read-only plan of every stack).
- **production**: last run on `main` (plan, approval, apply).

## Layout

```
bootstrap/        Prerequisites the CI cannot create, applied locally: state bucket, CI identities,
                  GitHub environments and their secrets, infrastructure ruleset
modules/          Reusable building blocks: domain, email-account, github-pages-site
stacks/           Deployable units applied by the CI, one remote state each
  domain/         Domain names (DNSSEC, clean zone)
  email/          Mailboxes and forwards
  website/        Sites published on GitHub Pages, with their DNS records
  stacks.json     Apply order of the stacks
policy/           Resource types the pipeline must never destroy
scripts/          Repository tooling, used by the CI and locally (guard, checks, decryption, sync)
tests/            All tests, run by tests/run.sh
docs/decisions/   Architecture decisions: why things are the way they are
backend.hcl       Shared S3 backend settings
.sops.yaml        Who can decrypt the private configuration
CLAUDE.md         Rules and traps, for Claude Code and newcomers
.claude/          Shared Claude Code settings: sensitive files unreadable, confirmation
                  before any write outside the machine
```

Each stack has its own state (`<stack>/terraform.tfstate` in the bucket). A mistake in one stack cannot touch the others, and plans stay small.

### Adding a component

- **New mailbox**: see [Mailboxes](#mailboxes).
- **New domain**: add an entry to `domains` in `stacks/domain/terraform.tfvars`. DNSSEC is enabled on every managed domain.
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

**Forwards**: `forwards` in the same encrypted file sends the mail of a mailbox to another address, keeping a local copy in the mailbox:

```yaml
forwards:
  - from: contact
    to: someone@example.org
```

The provider cannot manage MX Plan redirections, so the email stack runs `scripts/sync_email_forwards.py` whenever the list changes (a `terraform_data` step): it makes the redirections of the managed mailboxes match exactly, and leaves any other redirection alone. Targets are private (encrypted, masked in the CI logs, never printed). Forwarded mail can be classified as spam by the target when its original sender has a strict DMARC policy.

**Reading forwarded mail in Gmail**: OVHcloud forwards mail without rewriting its sender, so the target cannot authenticate it (SPF, then DMARC of the original sender): Gmail classifies part of it as spam, and may refuse it when the sender's DMARC policy is `reject`. Nothing is lost: the local copy keeps every message in the OVHcloud mailbox. In Gmail, create a filter on `deliveredto:<address>` with "Never send it to Spam".

Gmail does not show in the inbox a message you sent yourself to an address it does not know as yours, when it comes back through a forward (it is already in Sent). To test a forward, write from an address that is not linked to the Gmail account.

**Address roles**: `contact@` only receives; replies are sent from the nominative address.

**Sending from Gmail as a managed address** is a setting of the Gmail account, outside this infrastructure: Gmail > Settings > Accounts and Import > Send mail as > Add another email address, SMTP server `ssl0.ovh.net`, port 465, SSL, the full address and the mailbox password. Mail is then sent through OVHcloud: SPF and DKIM of the domain stay valid.

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

Four layers enforce this:

1. `prevent_destroy = true` on every stateful resource in the modules.
2. `scripts/plan_guard.py` reads the plan before every apply and fails if a type listed in `policy/protected-resource-types.txt` would be deleted or replaced. This also catches a resource removed from the code, which `prevent_destroy` alone does not.
3. Applies run only on `main`, after a human approves the `production` environment.
4. `scripts/check_domain_orders.py` asks OVHcloud, in every plan, whether each domain to order can be ordered as planned. A domain already registered elsewhere can only be transferred: the pull request fails instead of the apply.

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
| Push to `main` | Same as above, then `apply`: waits for approval, then re-plans, re-checks and applies each stack in the order of `stacks.json`, until its plan is empty (at most two applies: some provider settings, like the GitHub Pages custom domain, only apply once the resource exists; a stack still not converged fails the job). |

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
| `GH_APP_ID` / `GH_APP_PRIVATE_KEY` | GitHub App `technogix-infra-plan` (read-only) | GitHub App `technogix-infra-production` |

The environments and every secret are created by `bootstrap/github.tf`: nobody copies a credential by hand. The `production` environment:

- requires an approval, which admins cannot bypass;
- only accepts deployments from `main`. A workflow modified in a pull request can then never read the write credentials.

### CI identities on GitHub

The `github` provider of the stacks authenticates as a GitHub App, through an installation token (valid 1 hour) minted in each job by `actions/create-github-app-token`. GitHub cannot create Apps through its API: both are a **manual prerequisite**, created once in the organisation settings (Developer settings > GitHub Apps), installed on all repositories, webhook disabled:

| App | Repository permissions |
|---|---|
| `technogix-infra-plan` | Administration, Contents, Pages, Dependabot alerts: read-only |
| `technogix-infra-production` | Administration, Contents, Pages, Dependabot alerts: read and write |

Their App IDs and the paths of their private keys go in `github_apps` of the gitignored `bootstrap/bootstrap.auto.tfvars`; the bootstrap pushes them into the environments. Accepted risk: installed on all repositories (required to create repositories), the production App could also change this repository's settings; it only runs on `main`, after approval.

### CI identities on OVHcloud

The CI authenticates as two OAuth2 service accounts (`bootstrap/ci_identities.tf`), whose IAM policies list the exact API actions each environment needs, on the managed domains only (`managed_domains` in `bootstrap/`):

| Identity | Can | Cannot |
|---|---|---|
| `infrastructure-ci-plan` | Read domains, DNSSEC status and mailboxes | Anything else: no write, no account data, no orders |
| `infrastructure-ci-production` | Order services, update domains, enable DNSSEC, create and update mailboxes | **Delete a mailbox, disable DNSSEC, terminate a service**, access the Public Cloud project or API credentials |

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

   `bootstrap/terraform.tfstate` is not committed and is the single copy of every CI secret, including the SOPS age key. Keep a backup in a password manager or vault:

   - **Mandatory** after an apply that creates or replaces a secret, i.e. when the plan creates or replaces an `ovh_me_api_oauth2_client`, an `ovh_cloud_project_user_s3_credential` or a `github_actions_environment_secret`. An older backup would hold values that no longer work.
   - **Recommended** after any other apply (IAM policies, ruleset, outputs...). An older backup loses nothing: the code stays the reference and the next plan restores the rest, at worst after re-importing a resource created since.

   To restore the age key on a new machine, restore the state, then:

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
| `tests/stacks/<stack>/verify_*.py` | Live checks of a stack (e.g. DNSSEC validated by public resolvers) | Local only (`--live`) |
| `tests/bootstrap/` | Live checks of the bootstrap: state bucket (real Terraform backend cycle, forbidden operations), CI identities (IAM permissions) and GitHub environments (protection rules, secret names) | Local only (`--live`) |

The live checks need the OVH admin key and the local bootstrap state, so they never run in CI. Terraform only accepts tests inside a configuration directory: `run.sh` copies `tests/stacks/<stack>/` into a temporary, gitignored `stacks/<stack>/.tests/` while it runs.

## Website

Sites are GitHub repositories published on GitHub Pages, one instance of `modules/github-pages-site` each. `stacks/website` (applied by the CI) lists them in `terraform.tfvars.json`:

```json
"sites": {
  "website": { "description": "Technogix website", "subdomain": "" },
  "docs":    { "description": "Documentation",     "subdomain": "docs" }
}
```

Each site adds its own resources, and only them:

- repository (keyed by its name): public, squash merges only (enforced by the ruleset; the repository merge settings are set at creation and then ignored, because the read-only plan App cannot read them), branches deleted after merge, never deleted (`prevent_destroy`, `archive_on_destroy`, protected type of the pipeline guard);
- GitHub Pages: published by a workflow of the site repository, custom domain set, HTTPS enforced (both only apply once Pages exists and the certificate is issued: the deploy job applies again until convergence). `.dev` is on the HSTS preload list anyway;
- DNS records in the OVHcloud zone: an apex site (`subdomain = ""`) gets four `A` and four `AAAA` records to GitHub Pages and `www` as a `CNAME` to `technogix.github.io`; a subdomain site gets a single `CNAME`.

A new OVHcloud zone points the apex and `www` to the OVHcloud parking page. The parking comes with the domain order, so `modules/domain` delivers a clean zone: it runs `scripts/remove_ovh_parking_records.py` once at apply time (a `terraform_data` step). Terraform cannot delete records it does not manage, hence a script; on a rebuild from scratch, it runs again on the new zone. It only selects the parking records (`A 213.186.33.5`, `TXT "1|..."`, `TXT "3|welcome"` on the apex and `www`); mail records are never touched (unit tests in `tests/scripts/`).

The site content and its publishing workflow live in the site repository and are pushed with git.

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
- **Email offer (manual prerequisite)**: a domain comes with the free `redirect` email offer, which has no mailbox. Mailboxes need an MX Plan (MX005: 5 mailboxes), ordered once from the OVHcloud control panel (Web Cloud > Emails > the domain > change offer): the Terraform provider cannot order or upgrade email offers. Mailbox sizes must be one of the MX Plan sizes, in decimal units (5 GB = `5000000000`); the email stack rejects any other size at plan time.
