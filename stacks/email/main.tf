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
