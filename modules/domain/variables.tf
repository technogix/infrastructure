variable "domain_name" {
  description = "Domain name to order."
  type        = string
}

variable "ovh_subsidiary" {
  description = "OVHcloud subsidiary used for the order (FR, GB, DE, ...)."
  type        = string
  default     = "FR"
}

variable "duration" {
  description = "Commitment duration (ISO 8601, e.g. P1Y)."
  type        = string
  default     = "P1Y"
}
