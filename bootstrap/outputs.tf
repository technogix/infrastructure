output "bucket_name" {
  value = ovh_cloud_project_storage.tfstate.name
}

# S3 keys of the state bucket, per usage:
#   terraform output -json s3_credentials
output "s3_credentials" {
  description = "S3 keys per usage (reader -> plan environment, writer -> production)."
  value = {
    for k, c in ovh_cloud_project_user_s3_credential.tfstate : k => {
      access_key_id     = c.access_key_id
      secret_access_key = c.secret_access_key
    }
  }
  sensitive = true
}

# OAuth2 service accounts of the CI, per GitHub environment:
#   terraform output -json ci_credentials
output "ci_credentials" {
  description = "OVHcloud API credentials per GitHub environment (plan, production)."
  value = {
    for k, c in ovh_me_api_oauth2_client.ci : k => {
      client_id     = c.client_id
      client_secret = c.client_secret
    }
  }
  sensitive = true
}

output "cloud_project_id" {
  description = "Public Cloud project hosting the state bucket (used by tests/bootstrap)."
  value       = var.cloud_project_id
}

# Restores the SOPS age key from this state, e.g. on a new machine:
#   terraform output -raw sops_age_key > "$APPDATA/sops/age/keys.txt"
output "sops_age_key" {
  description = "age private key used by SOPS."
  value       = local.sops_age_key
  sensitive   = true
}
