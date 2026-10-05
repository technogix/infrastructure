variable "ovh_endpoint" {
  description = "OVHcloud API endpoint (ovh-eu, ovh-ca, ovh-us)."
  type        = string
  default     = "ovh-eu"
}

variable "github_owner" {
  description = "GitHub organisation owning the website repository."
  type        = string
}

variable "repository" {
  description = "Name of the website repository."
  type        = string
}

variable "description" {
  description = "Description of the website repository."
  type        = string
}

variable "domain" {
  description = "Custom domain of the site (apex), managed by the domain stack."
  type        = string
}
