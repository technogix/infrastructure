# Website: GitHub repository published on GitHub Pages, served on the apex of
# the domain (and www) through records of its OVHcloud DNS zone.
# The site code and its publishing workflow live in the repository (git).

locals {
  # https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site
  github_pages_ipv4 = ["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"]
  github_pages_ipv6 = ["2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"]
}

# --- repository --------------------------------------------------------------

resource "github_repository" "website" {
  name        = var.repository
  description = var.description
  visibility  = "public"

  # Creates main with a README, so that Pages and the ruleset have a branch.
  auto_init = true

  has_issues      = true
  has_discussions = false
  has_projects    = false
  has_wiki        = false

  # Merge methods are enforced by the ruleset below: with GitHub App
  # authentication, reading the repository merge settings would require
  # contents:write even for the read-only plan identity.
  delete_branch_on_merge = true

  # The repository holds the site code and its history: never deleted.
  # Even if prevent_destroy were removed, destroy would only archive it.
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "website" {
  repository = github_repository.website.name
}

resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = github_repository.website.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      required_approving_review_count = 0
      allowed_merge_methods           = ["squash"]
    }
  }
}

# --- GitHub Pages ------------------------------------------------------------

# Published by a GitHub Actions workflow of the website repository. The DNS
# records come first, so that GitHub can issue the HTTPS certificate.
# .dev domains are on the HSTS preload list: browsers always use HTTPS.
resource "github_repository_pages" "website" {
  repository = github_repository.website.name
  build_type = "workflow"
  cname      = var.domain

  depends_on = [
    ovh_domain_zone_record.apex_ipv4,
    ovh_domain_zone_record.apex_ipv6,
    ovh_domain_zone_record.www,
  ]
}

# --- DNS (OVHcloud zone of the domain) ---------------------------------------

# A new OVHcloud zone points the apex and www to the OVHcloud parking page.
# Terraform cannot delete records it does not manage, so this step removes
# them (and only them) once, at apply time, before the site records are
# created. On a rebuild from scratch, it runs again on the new zone.
resource "terraform_data" "remove_ovh_parking" {
  input = var.domain

  provisioner "local-exec" {
    command = "python3 ../../scripts/remove_ovh_parking_records.py ${var.domain}"
  }
}

resource "ovh_domain_zone_record" "apex_ipv4" {
  depends_on = [terraform_data.remove_ovh_parking]

  for_each = toset(local.github_pages_ipv4)

  zone      = var.domain
  subdomain = ""
  fieldtype = "A"
  ttl       = 3600
  target    = each.value
}

resource "ovh_domain_zone_record" "apex_ipv6" {
  depends_on = [terraform_data.remove_ovh_parking]

  for_each = toset(local.github_pages_ipv6)

  zone      = var.domain
  subdomain = ""
  fieldtype = "AAAA"
  ttl       = 3600
  target    = each.value
}

resource "ovh_domain_zone_record" "www" {
  depends_on = [terraform_data.remove_ovh_parking]

  zone      = var.domain
  subdomain = "www"
  fieldtype = "CNAME"
  ttl       = 3600
  target    = "${var.github_owner}.github.io."
}
