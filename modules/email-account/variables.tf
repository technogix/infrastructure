variable "domain" {
  description = "Domain of the email offer (e.g. technogix.dev)."
  type        = string
}

variable "account_name" {
  description = "Local part of the address (e.g. contact)."
  type        = string
}

variable "description" {
  description = "Description of the mailbox."
  type        = string
  default     = ""
}

variable "size" {
  description = "Mailbox size in bytes, one of the sizes allowed by the MX Plan (decimal units: 5 GB = 5000000000)."
  type        = number
  default     = 5000000000

  validation {
    # GET /email/domain/{domain} -> allowedAccountSize
    condition     = contains([2500000, 5000000, 25000000, 50000000, 100000000, 250000000, 500000000, 1000000000, 1500000000, 2000000000, 5000000000], var.size)
    error_message = "Size must be one of the MX Plan sizes: 2.5 MB, 5 MB, 25 MB, 50 MB, 100 MB, 250 MB, 500 MB, 1 GB, 1.5 GB, 2 GB or 5 GB (in bytes, decimal units)."
  }
}
