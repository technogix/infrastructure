output "domains" {
  description = "Managed domain names."
  value       = [for d in module.domain : d.domain_name]
}
