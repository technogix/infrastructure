# Sites published on GitHub Pages: one module instance per site.
module "site" {
  for_each = var.sites

  source       = "../../modules/github-pages-site"
  github_owner = var.github_owner
  zone         = var.zone
  repository   = each.key
  description  = each.value.description
  subdomain    = each.value.subdomain
}
