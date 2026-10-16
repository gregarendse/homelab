#	all provider blocks and configuration

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.26.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.3"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = ">= 0.22.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet
}
