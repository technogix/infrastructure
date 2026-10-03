terraform {
  required_providers {
    ovh = {
      source = "ovh/ovh"
    }
  }
}

# Orders a domain name. The plan_code of an OVHcloud domain is its TLD
# ("dev" for technogix.dev); payment uses the account's default payment method.
resource "ovh_domain_name" "this" {
  domain_name    = var.domain_name
  ovh_subsidiary = var.ovh_subsidiary

  plan = [
    {
      plan_code    = regex("[^.]+$", var.domain_name)
      duration     = var.duration
      pricing_mode = "create-default"
    }
  ]

  lifecycle {
    # Stateful resource: never destroyed or replaced by Terraform.
    prevent_destroy = true
    # Order parameters only apply to the initial order: changing them later
    # (e.g. duration) would show an update that renews nothing.
    ignore_changes = [plan, ovh_subsidiary]
  }
}
