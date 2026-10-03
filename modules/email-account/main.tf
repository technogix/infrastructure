terraform {
  required_providers {
    ovh = {
      source = "ovh/ovh"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

resource "random_password" "this" {
  length           = 20
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%&*()-_=+"
}

# Mailbox on the domain's email offer (MX Plan / Zimbra).
resource "ovh_email_domain_account" "this" {
  domain       = var.domain
  account_name = var.account_name
  password     = random_password.this.result
  description  = var.description
  size         = var.size

  lifecycle {
    # Stateful resource: never destroyed or replaced by Terraform.
    prevent_destroy = true
    # Users may change their password from the webmail: Terraform must not
    # overwrite it.
    ignore_changes = [password]
  }
}
