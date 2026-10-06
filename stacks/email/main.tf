# Every mailbox is keyed by its address only, whatever its category: moving
# an address between company_mailboxes and users never recreates it.
locals {
  mailboxes = merge(
    { for m in var.company_mailboxes : m.address => {
      description = m.description
      size        = m.size
      category    = "company"
    } },
    { for u in var.users : u.address => {
      description = u.full_name
      size        = u.size
      category    = "user"
    } },
  )
}

module "account" {
  for_each = local.mailboxes

  source       = "../../modules/email-account"
  domain       = var.domain
  account_name = each.key
  description  = each.value.description
  size         = each.value.size
}

# Forwards (MX Plan redirections). The provider cannot manage them, so this
# step runs scripts/sync_email_forwards.py whenever the declared forwards
# change: it makes the redirections of the managed mailboxes match exactly.
# Only a hash shows in plans; targets reach the script through its
# environment, never on its command line.
resource "terraform_data" "email_forwards" {
  triggers_replace = sha256(jsonencode(sort([for f in var.forwards : "${lower(f.from)} ${lower(f.to)}"])))

  provisioner "local-exec" {
    command = "python3 ../../scripts/sync_email_forwards.py ${var.domain}"
    environment = {
      FORWARDS  = jsonencode(var.forwards)
      MAILBOXES = jsonencode(keys(local.mailboxes))
    }
  }

  depends_on = [module.account]

  lifecycle {
    precondition {
      condition     = alltrue([for f in var.forwards : contains(keys(local.mailboxes), lower(f.from))])
      error_message = "A forward must start from a mailbox declared in company_mailboxes or users."
    }
  }
}
