# ─────────────────────────────────────────────────────────────────────────────
# Zitadel Cloud — homelab identity configuration (Terraform).
#
# Unlike auth0.tf (which *imports* a hand-built tenant), this is a GREENFIELD
# declarative config: it creates the project and OIDC applications from scratch
# inside an EXISTING organization. It mirrors the Auth0 applications in
# generated.tf so a later cutover is a like-for-like swap.
#
# What Terraform manages here:
#   • the "homelab" project (inside the pre-existing org)
#   • one OIDC application per SSO integration (oauth2-proxy, grafana, argocd …)
#
# What it does NOT manage: the organization itself. The org is referenced purely
# by ID (var.zitadel_org_id), deliberately WITHOUT a `data "zitadel_org"` lookup.
# Both *creating* an org and *reading* one through that data source go via
# ZITADEL's instance-level Admin API (AddOrganization / GetOrgByID +
# GetDefaultOrg), which requires IAM_OWNER. Creating a project and applications
# inside an existing org only needs ORG_OWNER on that org, so passing the ID
# straight through keeps the PAT's grant as small as possible.
#
# What it does NOT manage: the runtime client_id/client_secret consumed by the
# workloads still live in externally-managed Kubernetes Secrets. Terraform only
# *generates* them (see outputs.tf) — copy the values into those Secrets once.
#
# Provider auth: a Personal Access Token of a Zitadel service user (see
# README-zitadel.md). ORG_OWNER on the target org is sufficient for everything
# in this file — no instance-level IAM_OWNER required.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Public hosts that will authenticate against Zitadel. These mirror the Auth0
  # clients in generated.tf. During the PoC only the oauth2-proxy-zitadel host is
  # live; pre-registering the production callbacks now makes the eventual cutover
  # a no-op (no dashboard clicking, no re-issued secrets).
  oidc_apps = {
    oauth2_proxy = {
      name = "oauth2-proxy"
      redirect_uris = [
        # Production edge SSO (swap the main oauth2-proxy issuer at cutover).
        "https://auth.${var.base_domain}/oauth2/callback",
        # Isolated PoC proxy (applications/oauth2-proxy-zitadel).
        "https://auth-zitadel.${var.base_domain}/oauth2/callback",
      ]
      post_logout_redirect_uris = [
        "https://auth.${var.base_domain}",
        "https://auth-zitadel.${var.base_domain}",
      ]
    }

    grafana = {
      name                      = "grafana"
      redirect_uris             = ["https://grafana.${var.base_domain}/login/generic_oauth"]
      post_logout_redirect_uris = ["https://grafana.${var.base_domain}/login"]
    }

    argocd_trinity = {
      name                      = "argocd-trinity"
      redirect_uris             = ["https://trinity.argocd.${var.base_domain}/auth/callback"]
      post_logout_redirect_uris = ["https://trinity.argocd.${var.base_domain}"]
    }

    argocd_oci = {
      name = "argocd-oci"
      redirect_uris = [
        "https://argocd.${var.base_domain}/auth/callback",
        "https://oci.argocd.${var.base_domain}/auth/callback",
      ]
      post_logout_redirect_uris = [
        "https://argocd.${var.base_domain}",
        "https://oci.argocd.${var.base_domain}",
      ]
    }
  }
}

# The existing organization that owns everything below is the "arendse" org,
# identified by var.zitadel_org_id.
#
# NOTE: there is intentionally no `data "zitadel_org"` block here. That data
# source resolves the org through the Admin API, which is instance-scoped and
# rejects an ORG_OWNER token with:
#
#   error while getting org by id <id>: PermissionDenied ... (AUTH-5mWD2)
#
# We only ever need the org's ID, and we already have it, so the lookup buys us
# nothing but an extra permission requirement.

# Project grouping the OIDC applications. project_role_assertion adds the user's
# project roles to their tokens (useful for Grafana/ArgoCD RBAC later); the
# checks are relaxed so any org user can log in without explicit authorization —
# appropriate for a single-tenant homelab.
resource "zitadel_project" "homelab" {
  name                   = "homelab"
  org_id                 = var.zitadel_org_id
  project_role_assertion = true
  project_role_check     = false
  has_project_check      = false
}

# One confidential (client-secret) Web OIDC app per integration. Authorization
# Code + refresh token, OIDC 1.0 — exactly what oauth2-proxy, Grafana's generic
# OAuth, and ArgoCD's OIDC expect.
resource "zitadel_application_oidc" "app" {
  for_each = local.oidc_apps

  org_id     = var.zitadel_org_id
  project_id = zitadel_project.homelab.id

  name           = each.value.name
  redirect_uris  = each.value.redirect_uris
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types = [
    "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
    "OIDC_GRANT_TYPE_REFRESH_TOKEN",
  ]
  post_logout_redirect_uris = each.value.post_logout_redirect_uris

  app_type         = "OIDC_APP_TYPE_WEB"
  auth_method_type = "OIDC_AUTH_METHOD_TYPE_BASIC"
  version          = "OIDC_VERSION_1_0"

  # BEARER (opaque) access tokens; identity is carried in the ID token / userinfo,
  # which is what these clients read. Assert roles + userinfo into the ID token so
  # email/profile/roles are available without an extra userinfo call.
  access_token_type           = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = false
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true

  clock_skew         = "0s"
  dev_mode           = false
  additional_origins = []
}
