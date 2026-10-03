output "company_emails" {
  description = "Company email addresses."
  value       = [for k, a in module.account : a.email if local.mailboxes[k].category == "company"]
}

output "user_emails" {
  description = "Personal email addresses."
  value       = [for k, a in module.account : a.email if local.mailboxes[k].category == "user"]
}

# Read with: terraform output -json initial_passwords
output "initial_passwords" {
  description = "Initial passwords, keyed by address."
  value       = { for a in module.account : a.email => a.initial_password }
  sensitive   = true
}
