# Offline tests: providers are mocked, no OVHcloud call is made.
# Plan only: an apply would run the parking cleanup script.
mock_provider "ovh" {}

variables {
  ovh_subsidiary = "IE"
  domains = {
    "example.dev" = {}
    "example.eu"  = { duration = "P2Y" }
  }
}

run "every_domain_is_managed" {
  command = plan

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
    condition     = alltrue([for name, d in module.domain : d.parking_removed_from == name])
    error_message = "Every domain must have its zone cleaned of the OVHcloud parking."
  }
}
