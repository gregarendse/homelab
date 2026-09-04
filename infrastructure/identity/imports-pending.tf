# ─────────────────────────────────────────────────────────────────────────────
# PENDING IMPORTS — the tenant objects not yet under Terraform.
#
# The application clients are already handled in auth0.tf / generated.tf. This
# file scaffolds the *remaining* pieces of the tenant so a single
# `-generate-config-out` run can adopt them too.
#
#   ⚠️  Import blocks need REAL resource IDs. Placeholders below WILL fail
#       `terraform plan`. Before generating config:
#
#         1. Run ./list-auth0-ids.sh   (prints every ID from your tenant)
#         2. Paste the real IDs into the blocks you want to manage
#         3. DELETE any block you don't need (e.g. a social connection you
#            don't use, or the system Management API resource server)
#         4. terraform plan -generate-config-out=generated-extra.tf
#
# ID formats (from the Auth0 provider docs):
#   auth0_connection          → con_XXXXXXXXXXXXXXXX
#   auth0_connection_clients  → con_XXXXXXXXXXXXXXXX   (the connection's ID)
#   auth0_resource_server     → opaque hex id (NOT the audience/identifier URL)
#   auth0_client_grant        → cgr_XXXXXXXXXXXXXXXX
#   auth0_tenant              → any random UUID (singleton; ID is ignored)
#
# ─────────────────────────────────────────────────────────────────────────────
# 🛑 ALL IMPORTS BELOW ARE INTENTIONALLY DISABLED.
#
# We are migrating off Auth0 onto Zitadel (see applications/zitadel/MIGRATION.md),
# so adopting the remaining Auth0 tenant objects into Terraform is throwaway work
# — they'd only be torn down again in Phase 6.
#
# They were also *blocking* `terraform plan`: an `import` block requires a
# matching `resource` block in the configuration, and none of these targets
# (auth0_tenant, auth0_connection, auth0_connection_clients) are defined
# anywhere. Two of them also still carry literal placeholder IDs. That produced:
#
#   Error: Configuration for import target does not exist
#
# If you ever abandon the Zitadel migration and DO want these under Terraform,
# follow the 4 steps above, uncomment the blocks, and generate config into a NEW
# file (generated.tf already exists, so `-generate-config-out=generated.tf`
# will fail):
#
#   terraform plan -generate-config-out=generated-extra.tf
# ─────────────────────────────────────────────────────────────────────────────


# ── Tenant-wide settings (singleton) ────────────────────────────────────────
# No discovery needed — the import ID is an arbitrary UUID that Auth0 ignores.
# Generating this captures friendly name, session lifetimes, flags, logout URLs,
# default_directory, etc. Optional: remove if you'd rather not track tenant flags.
# import {
#   to = auth0_tenant.tenant
#   id = "d94f3a1e-2b6c-4a58-9f0d-7c1e5b8a4f23"
# }


# ── Database connection (Username-Password-Authentication) ───────────────────
# Every tenant has this; it's what backs email/password login for the apps.
# import {
#   to = auth0_connection.username_password
#   id = "con_REPLACE_DATABASE_CONNECTION_ID"
# }

# Which clients the database connection is enabled for. Managing this is
# important: if the connection is in Terraform but this association is not,
# a later apply could disable logins for apps you didn't list.
# import {
#   to = auth0_connection_clients.username_password
#   id = "con_REPLACE_DATABASE_CONNECTION_ID"
# }


# ── Social connection: Google (delete if you don't use it) ───────────────────
# import {
#   to = auth0_connection.google
#   id = "con_REPLACE_GOOGLE_CONNECTION_ID"
# }
# import {
#   to = auth0_connection_clients.google
#   id = "con_REPLACE_GOOGLE_CONNECTION_ID"
# }


# ── Custom API / Resource Server (delete if you have no custom API) ──────────
# Only relevant if you created an API with "Allow Offline Access" for refresh
# tokens. Do NOT import the system "Auth0 Management API" (is_system = true) —
# it can't be modified and adds noise. Use the hex id from list-auth0-ids.sh.
# import {
#   to = auth0_resource_server.api
#   id = "REPLACE_RESOURCE_SERVER_HEX_ID"
# }


# ── Client grant: the Terraform M2M app → Management API ─────────────────────
# Captures the authorization that lets this Terraform project manage the tenant.
# Nice for completeness, but note the bootstrap chicken-and-egg: don't let a
# future apply revoke the grant this project depends on.
# import {
#   to = auth0_client_grant.terraform_management
#   id = "cgr_REPLACE_CLIENT_GRANT_ID"
# }
