# Terraform state bucket and its S3 users (reader for plan, writer for apply).

resource "ovh_cloud_project_storage" "tfstate" {
  service_name = var.cloud_project_id
  region_name  = var.region
  name         = var.bucket_name

  # Versioning allows restoring a corrupted or overwritten state.
  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }

  # Every state version is undeletable for 30 days, so the bucket can be
  # neither emptied nor deleted, whatever the credentials.
  # Compliance, not governance: OVHcloud lets any key allowed to delete objects
  # bypass governance retention, including the CI writer key (see verify.py).
  # Object Lock can only be set at bucket creation and never disabled.
  object_lock = {
    status = "enabled"
    rule = {
      mode   = "compliance"
      period = "P30D"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  bucket_arns = [
    "arn:aws:s3:::${var.bucket_name}",
    "arn:aws:s3:::${var.bucket_name}/*",
  ]

  s3_users = {
    # Used by `terraform plan` (pull requests): read-only, no lock.
    reader = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    # Used by `terraform apply`: read/write + lock file.
    writer = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
      "s3:GetBucketLocation", "s3:ListMultipartUploadParts",
      "s3:ListBucketMultipartUploads", "s3:AbortMultipartUpload",
    ]
  }
}

resource "ovh_cloud_project_user" "tfstate" {
  for_each = local.s3_users

  service_name = var.cloud_project_id
  description  = "terraform-state-${each.key}"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "tfstate" {
  for_each = local.s3_users

  service_name = var.cloud_project_id
  user_id      = ovh_cloud_project_user.tfstate[each.key].id
}

resource "ovh_cloud_project_user_s3_policy" "tfstate" {
  for_each = local.s3_users

  service_name = var.cloud_project_id
  user_id      = ovh_cloud_project_user.tfstate[each.key].id
  policy = jsonencode({
    Statement = [{
      Sid      = "TerraformState"
      Effect   = "Allow"
      Action   = each.value
      Resource = local.bucket_arns
    }]
  })
}
