# Offline tests: providers are mocked, no OVHcloud call is made.
mock_provider "ovh" {}

variables {
  ovh_subsidiary = "IE"
  domains = {
    "example.dev" = {}
    "example.eu"  = { duration = "P2Y" }
  }
}

run "every_domain_has_dnssec" {
  command = apply

  assert {
    condition     = toset(keys(module.domain)) == toset(["example.dev", "example.eu"])
    error_message = "Unexpected set of domains."
  }

  assert {
    condition = alltrue([
      for name, d in module.domain : d.domain_name == name
    ])
    error_message = "A module instance manages the wrong domain."
  }

  assert {
    condition     = module.domain["example.dev"].dnssec_status != null && module.domain["example.eu"].dnssec_status != null
    error_message = "DNSSEC is not managed for every domain."
  }
}
