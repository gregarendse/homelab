#	all provider blocks and configuration

terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = ">= 3"
    }
  }
}

provider "zitadel" {
  domain       = var.zitadel_domain
  access_token = var.zitadel_access_token
}
