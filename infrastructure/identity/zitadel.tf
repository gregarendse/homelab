# ─────────────────────────────────────────────────────────────────────────────
# Zitadel Cloud — homelab identity configuration (Terraform).
#
# Creates projects and OIDC applications inside the EXISTING "arendse" org.
# Auth0 remains outside Terraform state as the rollback path.
#
# What Terraform manages here:
#   • the original "homelab" project/clients, preserved for the working PoC
#   • separate media, pihole, argocd and grafana projects (CP-0.5)
#   • separate OIDC credentials per app/proxy deployment, including the media PoC
#
# New clients are additive: creating them does not switch any workload. Follow
# applications/zitadel/MIGRATION.md for the per-integration cutover.
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
  # Legacy registrations: keep their keys, settings and resource addresses
  # intact until every consumer has migrated and rollback is no longer needed.
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

# Legacy project used by the working PoC. Both checks remain disabled to avoid
# changing its behavior during preparation; this is NOT an org-only boundary.
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

# New access boundaries. Do not repurpose the legacy resources above: changing
# a client's project can replace it and invalidate working credentials.
locals {
  sso_projects = toset(["media", "pihole", "argocd", "grafana"])

  sso_apps = {
    media = {
      project                   = "media"
      name                      = "media-proxy-trinity"
      redirect_uris             = ["https://auth.${var.base_domain}/oauth2/callback"]
      post_logout_redirect_uris = ["https://auth.${var.base_domain}"]
    }

    media_poc = {
      project                   = "media"
      name                      = "media-proxy-poc-trinity"
      redirect_uris             = ["https://auth-zitadel.${var.base_domain}/oauth2/callback"]
      post_logout_redirect_uris = ["https://auth-zitadel.${var.base_domain}"]
    }

    pihole = {
      project                   = "pihole"
      name                      = "pihole-proxy-oci"
      redirect_uris             = ["https://pihole.${var.base_domain}/oauth2/callback"]
      post_logout_redirect_uris = ["https://pihole.${var.base_domain}"]
    }

    grafana = {
      project                   = "grafana"
      name                      = "grafana"
      redirect_uris             = ["https://grafana.${var.base_domain}/login/generic_oauth"]
      post_logout_redirect_uris = ["https://grafana.${var.base_domain}/login"]
    }

    argocd_trinity = {
      project                   = "argocd"
      name                      = "argocd-trinity"
      redirect_uris             = ["https://trinity.argocd.${var.base_domain}/auth/callback"]
      post_logout_redirect_uris = ["https://trinity.argocd.${var.base_domain}"]
    }

    argocd_oci = {
      project = "argocd"
      name    = "argocd-oci"
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

# Initially admit all users in the owning org, without individual assignments.
# No external org receives a project grant. Self-registration must stay disabled
# in the console; Terraform does not manage that policy. New org users will also
# be admitted, so revisit role checks before onboarding them. App RBAC is separate.
resource "zitadel_project" "sso" {
  for_each = local.sso_projects

  name                   = each.key
  org_id                 = var.zitadel_org_id
  project_role_assertion = true
  project_role_check     = false
  has_project_check      = true
}

resource "zitadel_application_oidc" "sso" {
  for_each = local.sso_apps

  org_id     = var.zitadel_org_id
  project_id = zitadel_project.sso[each.value.project].id

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

  access_token_type           = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = false
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true

  clock_skew         = "0s"
  dev_mode           = false
  additional_origins = []
}
