# Offline tests: providers are mocked, no OVHcloud or GitHub call is made.
# Plan only: an apply would run the parking cleanup script.
mock_provider "ovh" {}
mock_provider "github" {}

variables {
  github_owner = "example-org"
  repository   = "website"
  description  = "Example website"
  domain       = "example.dev"
}

run "github_pages_on_the_apex" {
  command = plan

  assert {
    condition     = github_repository_pages.website.cname == "example.dev" && github_repository_pages.website.build_type == "workflow"
    error_message = "Pages must serve the domain apex, published by a workflow."
  }

  assert {
    condition     = github_repository.website.visibility == "public" && github_repository.website.archive_on_destroy
    error_message = "The repository must be public and archived (not deleted) on destroy."
  }
}

run "dns_points_to_github_pages_only" {
  command = plan

  assert {
    condition     = toset([for r in ovh_domain_zone_record.apex_ipv4 : r.target]) == toset(["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"])
    error_message = "The apex must have exactly the four GitHub Pages IPv4 addresses."
  }

  assert {
    condition     = length(ovh_domain_zone_record.apex_ipv6) == 4 && alltrue([for r in ovh_domain_zone_record.apex_ipv6 : r.fieldtype == "AAAA" && r.subdomain == ""])
    error_message = "The apex must have the four GitHub Pages IPv6 addresses."
  }

  assert {
    condition     = ovh_domain_zone_record.www.fieldtype == "CNAME" && ovh_domain_zone_record.www.target == "example-org.github.io."
    error_message = "www must be a CNAME to the organisation's github.io host."
  }

  assert {
    condition     = terraform_data.remove_ovh_parking.input == "example.dev"
    error_message = "The parking cleanup must target the site domain."
  }
}
