output "repository" {
  description = "Website repository."
  value       = github_repository.website.full_name
}

output "url" {
  description = "Public URL of the site."
  value       = "https://${var.domain}"
}
