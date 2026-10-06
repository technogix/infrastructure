variable "ovh_endpoint" {
  description = "OVHcloud API endpoint (ovh-eu, ovh-ca, ovh-us)."
  type        = string
  default     = "ovh-eu"
}

variable "github_owner" {
  description = "GitHub organisation owning the site repositories."
  type        = string
}

variable "zone" {
  description = "Domain serving the sites (managed by the domain stack)."
  type        = string
}

variable "sites" {
  description = "Sites, keyed by repository name. subdomain = \"\" serves the site on the apex (and www)."
  type = map(object({
    description = optional(string, "")
    subdomain   = optional(string, "")
  }))

  validation {
    condition     = length(distinct([for s in values(var.sites) : s.subdomain])) == length(var.sites)
    error_message = "Two sites cannot share a subdomain (at most one site on the apex)."
  }
}
