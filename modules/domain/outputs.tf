output "domain_name" {
  description = "Ordered domain name."
  value       = ovh_domain_name.this.domain_name
}

output "dnssec_status" {
  description = "DNSSEC status of the domain's DNS zone."
  value       = ovh_domain_zone_dnssec.this.status
}
