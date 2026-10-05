output "domains" {
  description = "Managed domain names."
  value       = [for d in module.domain : d.domain_name]
}

output "dnssec_status" {
  description = "DNSSEC status per domain."
  value       = { for name, d in module.domain : name => d.dnssec_status }
}
