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

# DNSSEC on the domain's OVHcloud DNS zone (created with the domain). OVHcloud
# publishes the DS record at the registry itself.
resource "ovh_domain_zone_dnssec" "this" {
  zone_name = ovh_domain_name.this.domain_name
}

# A new OVHcloud zone points the apex and www to the OVHcloud parking page.
# The module that orders the domain delivers a clean zone: this step removes
# the parking records (and only them) once, at apply time. Terraform cannot
# delete records it does not manage, hence a script; on a rebuild from
# scratch, it runs again on the new zone. Sites then add their own records.
resource "terraform_data" "remove_ovh_parking" {
  input = ovh_domain_name.this.domain_name

  provisioner "local-exec" {
    command = "python3 ${path.module}/../../scripts/remove_ovh_parking_records.py ${self.input}"
  }
}
