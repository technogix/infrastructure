output "email" {
  description = "Full email address."
  value       = ovh_email_domain_account.this.email
}

output "initial_password" {
  description = "Initial password of the mailbox."
  value       = random_password.this.result
  sensitive   = true
}
