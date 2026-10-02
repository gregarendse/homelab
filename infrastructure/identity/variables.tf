#   Auth0 tenant domain, e.g. arendse.uk.auth0.com
variable "auth0_domain" {
  description = "Auth0 tenant domain (e.g. <tenant>.<region>.auth0.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9.-]+\\.auth0\\.com$", var.auth0_domain))
    error_message = "Invalid Auth0 domain, expected: <tenant>.<region>.auth0.com"
  }
}

#   Populated by environment variable TF_VAR_auth0_client_id
#   Client ID of the Machine-to-Machine app authorized for the Auth0 Management API
variable "auth0_client_id" {
  description = "Client ID of the M2M application used to manage the Auth0 tenant"
  type        = string

  validation {
    condition     = length(var.auth0_client_id) > 0
    error_message = "Auth0 Management API client ID must not be empty"
  }
}

#   Populated by environment variable TF_VAR_auth0_client_secret
#   Client Secret of the Management API M2M app
variable "auth0_client_secret" {
  description = "Client Secret of the M2M application used to manage the Auth0 tenant"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.auth0_client_secret) > 0
    error_message = "Auth0 Management API client secret must not be empty"
  }
}

variable "zitadel_domain" {
  description = "Zitadel domain"
  type        = string

  validation {
    condition     = length(var.zitadel_domain) > 0
    error_message = "Zitadel domain must not be empty"
  }
}
variable "zitadel_access_token" {
  description = "Zitadel access token"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.zitadel_access_token) > 0
    error_message = "Zitadel access token must not be empty"
  }
}

#   ID of the PRE-EXISTING Zitadel organization that owns the homelab project
#   and OIDC apps (the "arendse" org). Terraform reads this org via a data
#   source rather than creating one, so the PAT only needs ORG_OWNER instead of
#   an instance-level IAM_OWNER.
#
#   Find it in the Console: select the org, then read the numeric ID from the
#   URL (or the org detail page). It is an identifier, not a secret.
variable "zitadel_org_id" {
  description = "ID of the existing Zitadel organization to create the project/apps in"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.zitadel_org_id))
    error_message = "Zitadel org ID must be a numeric string copied from the Console URL"
  }
}

#   Public base domain that homelab apps are served under. Used to build the
#   OIDC redirect/logout URLs in zitadel.tf.
variable "base_domain" {
  description = "Public base domain homelab apps are served under (e.g. arendse.nom.za)"
  type        = string
  default     = "arendse.nom.za"

  validation {
    condition     = length(var.base_domain) > 0
    error_message = "base_domain must not be empty"
  }
}
