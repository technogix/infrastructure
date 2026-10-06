terraform {
  required_providers {
    ovh = {
      source = "ovh/ovh"
    }
    github = {
      source = "integrations/github"
    }
  }
}

# A site: GitHub repository published on GitHub Pages, served either on the
# apex of the zone (and www) or on a subdomain, through its own records in
# the OVHcloud zone. The site code and its publishing workflow live in the
# repository (git).

locals {
  at_apex  = var.subdomain == ""
  hostname = local.at_apex ? var.zone : "${var.subdomain}.${var.zone}"

  # https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site
  github_pages_ipv4 = local.at_apex ? toset(["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"]) : toset([])
  github_pages_ipv6 = local.at_apex ? toset(["2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"]) : toset([])

  # Apex site: www points to it. Subdomain site: the subdomain itself.
  cname_subdomain = local.at_apex ? "www" : var.subdomain
}

# --- repository --------------------------------------------------------------

resource "github_repository" "this" {
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

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
}

resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = github_repository.this.name
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

# Published by a GitHub Actions workflow of the repository. The DNS records
# come first, so that GitHub can issue the HTTPS certificate.
resource "github_repository_pages" "this" {
  repository = github_repository.this.name
  build_type = "workflow"
  cname      = local.hostname

  depends_on = [
    ovh_domain_zone_record.apex_ipv4,
    ovh_domain_zone_record.apex_ipv6,
    ovh_domain_zone_record.cname,
  ]
}

# --- DNS: the site's own records ---------------------------------------------

resource "ovh_domain_zone_record" "apex_ipv4" {
  for_each = local.github_pages_ipv4

  zone      = var.zone
  subdomain = ""
  fieldtype = "A"
  ttl       = var.ttl
  target    = each.value
}

resource "ovh_domain_zone_record" "apex_ipv6" {
  for_each = local.github_pages_ipv6

  zone      = var.zone
  subdomain = ""
  fieldtype = "AAAA"
  ttl       = var.ttl
  target    = each.value
}

resource "ovh_domain_zone_record" "cname" {
  zone      = var.zone
  subdomain = local.cname_subdomain
  fieldtype = "CNAME"
  ttl       = var.ttl
  target    = "${var.github_owner}.github.io."
}
