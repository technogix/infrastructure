# OVHcloud identities of the CI: OAuth2 service accounts (client credentials
# flow) with IAM policies. Each policy lists the exact API actions the stacks
# need, taken from the `iamActions` of the OVHcloud API schemas.
#
# Deliberately NOT granted to any CI identity, so that OVHcloud itself refuses
# to destroy data even if the pipeline guard were bypassed:
#   - emailDomain:apiovh:account/delete  (deleting a mailbox)
#   - service termination                (/services/{id}/terminate)

data "ovh_me" "account" {}

locals {
  account_urn = data.ovh_me.account.urn

  domain_urns       = [for d in var.managed_domains : "urn:v1:eu:resource:domain:${d}"]
  email_domain_urns = [for d in var.managed_domains : "urn:v1:eu:resource:emailDomain:${d}"]
}

resource "ovh_me_api_oauth2_client" "ci" {
  for_each = toset(["plan", "production"])

  name        = "infrastructure-ci-${each.key}"
  description = "GitHub Actions, ${each.key} environment (managed by bootstrap/)"
  flow        = "CLIENT_CREDENTIALS"
}

# --- plan: read-only ---------------------------------------------------------

resource "ovh_iam_policy" "ci_plan_read" {
  name        = "infrastructure-ci-plan-read"
  description = "CI plan: read domains and mailboxes (managed by bootstrap/)"
  identities  = [ovh_me_api_oauth2_client.ci["plan"].identity]
  resources   = concat(local.domain_urns, local.email_domain_urns)

  allow = [
    "domain:apiovh:name/get",
    "emailDomain:apiovh:account/get",
  ]
}

# --- production: create and update, never delete -----------------------------

resource "ovh_iam_policy" "ci_production_domains" {
  name        = "infrastructure-ci-production-domains"
  description = "CI production: manage domains and mailboxes, no deletion (managed by bootstrap/)"
  identities  = [ovh_me_api_oauth2_client.ci["production"].identity]
  resources   = concat(local.domain_urns, local.email_domain_urns)

  allow = [
    "domain:apiovh:name/get",
    "domain:apiovh:name/edit",
    "emailDomain:apiovh:account/get",
    "emailDomain:apiovh:account/create",
    "emailDomain:apiovh:account/edit",
    "emailDomain:apiovh:account/changePassword",
  ]
}

# Ordering (domains today, more services later) is an account-level action.
resource "ovh_iam_policy" "ci_production_orders" {
  name        = "infrastructure-ci-production-orders"
  description = "CI production: order services with the default payment method (managed by bootstrap/)"
  identities  = [ovh_me_api_oauth2_client.ci["production"].identity]
  resources   = [local.account_urn]

  allow = [
    "order:apiovh:cart/assign",
    "order:apiovh:cart/checkout/execute",
    "account:apiovh:me/get",
    "account:apiovh:me/payment/method/get",
    "account:apiovh:me/order/get",
    "account:apiovh:me/order/status/get",
    "account:apiovh:me/order/details/get",
    "account:apiovh:me/order/details/extension/get",
    "account:apiovh:me/order/pay",
    "account:apiovh:me/order/payWithRegisteredPaymentMean",
  ]
}
