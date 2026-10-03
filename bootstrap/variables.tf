variable "ovh_endpoint" {
  description = "OVHcloud API endpoint."
  type        = string
  default     = "ovh-eu"
}

variable "cloud_project_id" {
  description = "ID of the OVHcloud Public Cloud project hosting the bucket."
  type        = string
}

variable "managed_domains" {
  description = "Domains the CI may manage (domain and email). Must include every domain of stacks/domain."
  type        = list(string)
  default     = ["technogix.dev"]
}

variable "region" {
  description = "Bucket region (must match the endpoint in backend.hcl)."
  type        = string
  default     = "GRA"
}

variable "bucket_name" {
  description = "State bucket name (must match backend.hcl)."
  type        = string
  default     = "technogix-tfstate"
}

variable "github_owner" {
  description = "GitHub organisation owning the repository."
  type        = string
  default     = "technogix"
}

variable "github_repository" {
  description = "Repository running the deploy workflow."
  type        = string
  default     = "infrastructure"
}

variable "sops_age_key_file" {
  description = "Local file holding the age private key used by SOPS (e.g. %AppData%/sops/age/keys.txt on Windows, ~/.config/sops/age/keys.txt on Linux)."
  type        = string
}
