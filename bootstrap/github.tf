# GitHub environments of the deploy workflow, and their secrets. Every secret
# value comes from this bootstrap: no CI credential is ever copied by hand.

data "github_user" "admin" {
  # Empty username: the user authenticated with the GitHub token.
  username = ""
}

# --- plan: pull requests, read-only credentials ------------------------------

resource "github_repository_environment" "plan" {
  repository  = var.github_repository
  environment = "plan"
}

# --- production: main only, after approval -----------------------------------

resource "github_repository_environment" "production" {
  repository  = var.github_repository
  environment = "production"

  # Admins cannot skip the approval either.
  can_admins_bypass = false

  reviewers {
    users = [data.github_user.admin.id]
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# Only main can deploy: a workflow modified in a pull request never sees the
# production secrets.
#
# Provider bug (integrations/github 6.13): if a "main" policy already exists
# (e.g. created by hand), creation silently stores policy_id = 0 instead of
# failing, so the next plan wants to create the policy again
# (tests/run.sh --live reports it as drift). Fix the state, without touching
# GitHub:
#   gh api repos/technogix/infrastructure/environments/production/deployment-branch-policies --jq '.branch_policies[].id'
#   terraform state rm github_repository_environment_deployment_policy.production_main
#   terraform import github_repository_environment_deployment_policy.production_main infrastructure:production:<id>
resource "github_repository_environment_deployment_policy" "production_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}

# --- secrets -----------------------------------------------------------------

locals {
  # age private key decrypting the *.enc.yaml files. Through this secret it is
  # also stored in this state, so the state backup is enough to restore it:
  #   terraform output -raw sops_age_key > <sops key file>
  sops_age_key = sensitive(trimspace(file(pathexpand(var.sops_age_key_file))))

  environments = {
    plan       = { env = github_repository_environment.plan, ovh = "plan", s3 = "reader" }
    production = { env = github_repository_environment.production, ovh = "production", s3 = "writer" }
  }

  environment_secrets = merge([
    for name, e in local.environments : {
      "${name}/OVH_CLIENT_ID"              = { env = e.env.environment, value = ovh_me_api_oauth2_client.ci[e.ovh].client_id }
      "${name}/OVH_CLIENT_SECRET"          = { env = e.env.environment, value = ovh_me_api_oauth2_client.ci[e.ovh].client_secret }
      "${name}/STATE_S3_ACCESS_KEY_ID"     = { env = e.env.environment, value = ovh_cloud_project_user_s3_credential.tfstate[e.s3].access_key_id }
      "${name}/STATE_S3_SECRET_ACCESS_KEY" = { env = e.env.environment, value = ovh_cloud_project_user_s3_credential.tfstate[e.s3].secret_access_key }
      "${name}/SOPS_AGE_KEY"               = { env = e.env.environment, value = local.sops_age_key }
    }
  ]...)
}

resource "github_actions_environment_secret" "ci" {
  for_each = nonsensitive(toset(keys(local.environment_secrets)))

  repository  = var.github_repository
  environment = local.environment_secrets[each.key].env
  secret_name = split("/", each.key)[1]
  value       = local.environment_secrets[each.key].value
}

# --- main branch protection --------------------------------------------------

# main is what is deployed: it only changes through a pull request whose
# checks and plans are green. No approval is required on pull requests (a
# single maintainer cannot approve their own): the human gate is the approval
# of the production environment, just before apply.
resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = var.github_repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      required_approving_review_count = 0
      allowed_merge_methods           = ["squash"]
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      # Job names of .github/workflows/deploy.yml.
      required_check {
        context = "check"
      }
      required_check {
        context = "plan-result"
      }
    }
  }
}
