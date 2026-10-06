# Offline tests: providers are mocked, no OVHcloud call is made.
# Fictional data only: this file is public, unlike mailboxes.enc.yaml.
mock_provider "ovh" {}
mock_provider "random" {}

variables {
  domain = "example.com"
  company_mailboxes = [
    { address = "contact", description = "Contact address" },
    { address = "sales", description = "Sales address" },
  ]
  users = [
    { address = "alice.martin", full_name = "Alice Martin" },
  ]
}

run "initial_mailboxes" {
  command = apply

  assert {
    condition     = toset(keys(module.account)) == toset(["contact", "sales", "alice.martin"])
    error_message = "Unexpected set of mailboxes."
  }

  assert {
    condition     = local.mailboxes["alice.martin"].category == "user" && local.mailboxes["sales"].category == "company"
    error_message = "Mailbox categories are wrong."
  }
}

# Onboarding: adding a user on top of the existing state only adds a mailbox.
run "onboard_user" {
  command = apply

  variables {
    users = [
      { address = "alice.martin", full_name = "Alice Martin" },
      { address = "john.doe", full_name = "John Doe" },
    ]
  }

  assert {
    condition     = length(module.account) == 4
    error_message = "Onboarding should add exactly one mailbox."
  }

  # Same password as in the previous run: the existing mailbox was not recreated.
  assert {
    condition     = module.account["alice.martin"].initial_password == run.initial_mailboxes.initial_passwords[module.account["alice.martin"].email]
    error_message = "An existing mailbox was recreated."
  }
}

# Reordering the list or moving an address to another category changes nothing.
run "reorder_and_recategorise" {
  command = apply

  variables {
    company_mailboxes = [
      { address = "contact", description = "Contact address" },
    ]
    users = [
      { address = "john.doe", full_name = "John Doe" },
      { address = "sales", full_name = "Sales address" },
      { address = "alice.martin", full_name = "Alice Martin" },
    ]
  }

  assert {
    condition     = module.account["sales"].initial_password == run.initial_mailboxes.initial_passwords[module.account["sales"].email]
    error_message = "Moving a mailbox between categories recreated it."
  }
}

run "address_in_both_categories_rejected" {
  command = plan

  variables {
    users = [
      { address = "contact", full_name = "Someone" },
    ]
  }

  expect_failures = [var.users]
}

run "accented_address_rejected" {
  command = plan

  variables {
    users = [
      { address = "agnès.dupré", full_name = "Agnès Dupré" },
    ]
  }

  expect_failures = [var.users]
}

# OVHcloud only accepts a fixed list of sizes (decimal units): 5 GiB is not one.
run "size_not_allowed_by_ovh_rejected" {
  command = plan

  variables {
    users = [
      { address = "alice.martin", full_name = "Alice Martin", size = 5368709120 },
    ]
  }

  expect_failures = [var.users]
}

run "forward_from_a_declared_mailbox" {
  command   = plan
  state_key = "forwards" # independent of the mailbox runs above

  variables {
    forwards = [{ from = "contact", to = "someone@example.org" }]
  }
}

run "forward_from_an_unknown_mailbox_rejected" {
  command   = plan
  state_key = "forwards" # independent of the mailbox runs above

  variables {
    forwards = [{ from = "nobody", to = "someone@example.org" }]
  }

  expect_failures = [terraform_data.email_forwards]
}

run "forward_to_something_else_than_an_address_rejected" {
  command   = plan
  state_key = "forwards" # independent of the mailbox runs above

  variables {
    forwards = [{ from = "contact", to = "not-an-address" }]
  }

  expect_failures = [var.forwards]
}
