terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    key = "domain/terraform.tfstate"
  }

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.21"
    }
  }
}

# Credentials: OVH_CLIENT_ID / OVH_CLIENT_SECRET (CI service accounts, see bootstrap/)
# or ~/.ovh.conf (local admin key).
provider "ovh" {
  endpoint = var.ovh_endpoint
}
