# Offline tests: providers are mocked, no OVHcloud or GitHub call is made.
mock_provider "ovh" {}
mock_provider "github" {}

variables {
  github_owner = "example-org"
  zone         = "example.dev"
  sites = {
    website = { description = "Main site", subdomain = "" }
    docs    = { description = "Documentation", subdomain = "docs" }
  }
}

run "apex_site" {
  command = plan

  assert {
    condition     = module.site["website"].pages.cname == "example.dev" && module.site["website"].pages.build_type == "workflow"
    error_message = "The apex site must serve the domain apex, published by a workflow."
  }

  assert {
    condition = toset([for r in module.site["website"].dns_records : "${r.type} ${r.subdomain} ${r.target}"]) == toset([
      "A  185.199.108.153", "A  185.199.109.153", "A  185.199.110.153", "A  185.199.111.153",
      "AAAA  2606:50c0:8000::153", "AAAA  2606:50c0:8001::153", "AAAA  2606:50c0:8002::153", "AAAA  2606:50c0:8003::153",
      "CNAME www example-org.github.io.",
    ])
    error_message = "The apex site must have the GitHub Pages addresses on the apex and www as a CNAME, and nothing else."
  }
}

run "subdomain_site" {
  command = plan

  assert {
    condition     = module.site["docs"].pages.cname == "docs.example.dev" && module.site["docs"].url == "https://docs.example.dev"
    error_message = "The subdomain site must serve its subdomain."
  }

  assert {
    condition = toset([for r in module.site["docs"].dns_records : "${r.type} ${r.subdomain} ${r.target}"]) == toset([
      "CNAME docs example-org.github.io.",
    ])
    error_message = "A subdomain site must only add a CNAME for its subdomain."
  }
}

run "two_sites_on_the_same_subdomain_rejected" {
  command = plan

  variables {
    sites = {
      website = { subdomain = "" }
      other   = { subdomain = "" }
    }
  }

  expect_failures = [var.sites]
}
