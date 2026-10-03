module "domain" {
  for_each = var.domains

  source         = "../../modules/domain"
  domain_name    = each.key
  ovh_subsidiary = var.ovh_subsidiary
  duration       = each.value.duration
}
