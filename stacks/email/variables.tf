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
    size        = optional(number, 5000000000)
  }))

  validation {
    condition     = alltrue([for m in var.company_mailboxes : contains([2500000, 5000000, 25000000, 50000000, 100000000, 250000000, 500000000, 1000000000, 1500000000, 2000000000, 5000000000], m.size)])
    error_message = "Size must be one of the MX Plan sizes: 2.5 MB, 5 MB, 25 MB, 50 MB, 100 MB, 250 MB, 500 MB, 1 GB, 1.5 GB, 2 GB or 5 GB (in bytes, decimal units)."
  }

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
    size      = optional(number, 5000000000)
  }))

  validation {
    condition     = alltrue([for m in var.users : contains([2500000, 5000000, 25000000, 50000000, 100000000, 250000000, 500000000, 1000000000, 1500000000, 2000000000, 5000000000], m.size)])
    error_message = "Size must be one of the MX Plan sizes: 2.5 MB, 5 MB, 25 MB, 50 MB, 100 MB, 250 MB, 500 MB, 1 GB, 1.5 GB, 2 GB or 5 GB (in bytes, decimal units)."
  }

  validation {
    condition     = alltrue([for u in var.users : can(regex("^[a-z0-9]+([.-][a-z0-9]+)*$", u.address))])
    error_message = "Addresses must be lowercase letters and digits, separated by '.' or '-' (no accents)."
  }

  validation {
    condition     = length(distinct(concat(var.users[*].address, var.company_mailboxes[*].address))) == length(var.users) + length(var.company_mailboxes)
    error_message = "Each address must appear only once across company_mailboxes and users."
  }
}

variable "forwards" {
  description = "Forwards of managed mailboxes to other addresses (a local copy is always kept). From mailboxes.enc.yaml: targets are private."
  type = list(object({
    from = string
    to   = string
  }))
  default = []

  validation {
    condition     = alltrue([for f in var.forwards : can(regex("^[^@ ]+@[^@ ]+[.][^@ ]+$", f.to))])
    error_message = "Each forward target must be an email address."
  }

  validation {
    condition     = length(distinct([for f in var.forwards : "${lower(f.from)} ${lower(f.to)}"])) == length(var.forwards)
    error_message = "A forward is declared twice."
  }
}
