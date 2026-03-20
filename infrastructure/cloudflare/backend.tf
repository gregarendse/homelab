# Backend configurations, see: https://developer.hashicorp.com/terraform/language/backend
# https://thegeeklab.de/posts/2022/09/store-terraform-state-on-backblaze-s3/
terraform {
  backend "s3" {
    key = "cloudflare/state.json"

    endpoint = "https://s3.eu-central-003.backblazeb2.com"
    region   = "eu-central-003"

    # Using Backblaze B2 - these validations do not apply
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
