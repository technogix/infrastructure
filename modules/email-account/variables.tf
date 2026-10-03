variable "domain" {
  description = "Domain of the email offer (e.g. technogix.io)."
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
  description = "Mailbox size in bytes."
  type        = number
  default     = 5368709120
}
