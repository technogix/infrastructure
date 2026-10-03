# Shared S3 backend settings (OVHcloud Object Storage).
# Each stack only declares its own `key` and is initialised with:
#   terraform init -backend-config=../../backend.hcl
# S3 credentials are read from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
bucket = "technogix-tfstate"
region = "gra"

endpoints = {
  s3 = "https://s3.gra.io.cloud.ovh.net"
}

use_path_style              = true
use_lockfile                = true
skip_credentials_validation = true
skip_region_validation      = true
skip_requesting_account_id  = true
skip_s3_checksum            = true
