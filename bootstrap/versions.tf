# Bootstrap: everything the pipeline needs before it can run (state bucket,
# CI identities). Applied locally by an administrator, never by the CI.
# Its state stays local (it holds every CI secret): keep it in a vault.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.21"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}

# Credentials: ~/.ovh.conf (administrator key).
provider "ovh" {
  endpoint = var.ovh_endpoint
}

# Credentials: GITHUB_TOKEN, or the GitHub CLI login (`gh auth login`).
provider "github" {
  owner = var.github_owner
}
