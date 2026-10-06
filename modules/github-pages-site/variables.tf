variable "github_owner" {
  description = "GitHub organisation owning the repository."
  type        = string
}

variable "repository" {
  description = "Name of the site repository."
  type        = string
}

variable "description" {
  description = "Description of the site repository."
  type        = string
  default     = ""
}

variable "zone" {
  description = "OVHcloud DNS zone (domain) serving the site."
  type        = string
}

variable "subdomain" {
  description = "Subdomain of the site; empty for the apex (then www points to it too)."
  type        = string
  default     = ""

  validation {
    condition     = var.subdomain != "www"
    error_message = "www is already used by the apex site: use subdomain = \"\" for it."
  }
}

variable "ttl" {
  description = "TTL of the site's DNS records, in seconds."
  type        = number
  default     = 3600
}
