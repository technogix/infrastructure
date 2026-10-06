output "sites" {
  description = "Public URL of each site, keyed by repository."
  value       = { for name, s in module.site : name => s.url }
}
