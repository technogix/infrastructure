variable "ovh_endpoint" {
  description = "OVHcloud API endpoint (ovh-eu, ovh-ca, ovh-us)."
  type        = string
  default     = "ovh-eu"
}

variable "ovh_subsidiary" {
  description = "OVHcloud subsidiary used for orders."
  type        = string
  default     = "FR"
}

variable "domains" {
  description = "Domain names to manage, keyed by name."
  type = map(object({
    duration = optional(string, "P1Y")
  }))
}
