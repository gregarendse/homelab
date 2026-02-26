# Data source to read remote state from network project
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    key = "network/state.json"

    endpoints = {
            s3 = "https://s3.eu-central-003.backblazeb2.com"
    }

    region   = "eu-central-003"

    bucket     = var.s3_backend_bucket
    access_key = var.s3_backend_access_key
    secret_key = var.s3_backend_secret_key

    # Using Backblaze B2 - these validations do not apply
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
