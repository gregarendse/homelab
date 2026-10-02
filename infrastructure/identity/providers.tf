#	all provider blocks and configuration

terraform {
  required_providers {
    auth0 = {
      source  = "auth0/auth0"
      version = ">= 1.7.0"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = ">= 3"
    }
  }
}

# Auth0 Management API. Authenticates as a Machine-to-Machine application
# authorized for the Auth0 Management API (scopes: read/create/update/delete on
# clients, resource_servers, connections, etc.). Credentials come from
# TF_VAR_auth0_* / .auto.tfvars (git-ignored). See README-auth0.md.
provider "auth0" {
  domain        = var.auth0_domain
  client_id     = var.auth0_client_id
  client_secret = var.auth0_client_secret
}

provider "zitadel" {
  domain       = var.zitadel_domain
  access_token = var.zitadel_access_token
}
