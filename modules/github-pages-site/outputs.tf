output "repository" {
  description = "Site repository (owner/name)."
  value       = github_repository.this.full_name
}

output "hostname" {
  description = "Host name of the site."
  value       = local.hostname
}

output "url" {
  description = "Public URL of the site."
  value       = "https://${local.hostname}"
}

output "dns_records" {
  description = "DNS records of the site, as type / subdomain / target."
  value = [
    for r in concat(values(ovh_domain_zone_record.apex_ipv4), values(ovh_domain_zone_record.apex_ipv6), [ovh_domain_zone_record.cname]) :
    { type = r.fieldtype, subdomain = r.subdomain, target = r.target }
  ]
}

output "pages" {
  description = "GitHub Pages settings of the site."
  value = {
    cname      = github_repository_pages.this.cname
    build_type = github_repository_pages.this.build_type
  }
}
