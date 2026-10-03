variable "ovh_endpoint" {
  description = "OVHcloud API endpoint (ovh-eu, ovh-ca, ovh-us)."
  type        = string
  default     = "ovh-eu"
}

variable "domain" {
  description = "Domain of the email offer (must be managed by the domain stack)."
  type        = string
}

# The two lists below come from mailboxes.enc.yaml (SOPS-encrypted), decrypted
# by scripts/decrypt-config.sh into mailboxes.auto.tfvars.json.

variable "company_mailboxes" {
  description = "Mailboxes of the company itself (contact, sales, ...)."
  type = list(object({
    address     = string
    description = string
    size        = optional(number, 5368709120)
  }))

  validation {
    condition     = alltrue([for m in var.company_mailboxes : can(regex("^[a-z0-9]+([.-][a-z0-9]+)*$", m.address))])
    error_message = "Addresses must be lowercase letters and digits, separated by '.' or '-'."
  }
}

variable "users" {
  description = "Personal mailboxes (address = firstname.lastname)."
  type = list(object({
    address   = string
    full_name = string
    size      = optional(number, 5368709120)
  }))

  validation {
    condition     = alltrue([for u in var.users : can(regex("^[a-z0-9]+([.-][a-z0-9]+)*$", u.address))])
    error_message = "Addresses must be lowercase letters and digits, separated by '.' or '-' (no accents)."
  }

  validation {
    condition     = length(distinct(concat(var.users[*].address, var.company_mailboxes[*].address))) == length(var.users) + length(var.company_mailboxes)
    error_message = "Each address must appear only once across company_mailboxes and users."
  }
}
