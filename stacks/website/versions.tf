terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    key = "website/terraform.tfstate"
  }

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

# Credentials: OVH_CLIENT_ID / OVH_CLIENT_SECRET (CI service accounts, see bootstrap/)
# or ~/.ovh.conf (local admin key).
provider "ovh" {
  endpoint = var.ovh_endpoint
}

# Credentials: GITHUB_TOKEN. In the CI, an installation token of the
# environment's GitHub App (see the deploy workflow); locally, `gh auth token`.
provider "github" {
  owner = var.github_owner
}
