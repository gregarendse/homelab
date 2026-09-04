# # Auth0 tenant resources, imported from the existing tenant (arendse.uk.auth0.com).
# #
# # These `import` blocks let Terraform adopt the Auth0 applications that are
# # currently configured by hand in the dashboard. The Client / Secret used by
# # each app still live in externally-managed Kubernetes Secrets — Terraform only
# # manages the *application configuration* (callback/logout URLs, grant types,
# # app type, etc.), NOT the runtime secrets consumed by the workloads.
# #
# # ── One-time import workflow ────────────────────────────────────────────────
# # See README-auth0.md for the full walkthrough. In short:
# #
# #   1. Create an Auth0 Machine-to-Machine app authorized for the Management API
# #      and put its Client ID/Secret in .auto.tfvars (auth0_client_id/secret).
# #   2. Replace the `id = "..."` placeholders below with the real Client IDs
# #      (Auth0 Dashboard → Applications → <app> → Settings → Client ID).
# #   3. terraform init                       # download the auth0 provider
# #   4. terraform plan -generate-config-out=auth0_generated.tf
# #         └─ writes fully-populated resource blocks matching the live config
# #   5. Move the generated resources here (or keep auth0_generated.tf), then:
# #         terraform apply                   # records the resources in state
# #   6. Re-run `terraform plan` — it should show no changes.
# #
# # After a successful import you can delete the `import` blocks (state already
# # holds the resources); they are harmless if left in place.


# # ── Optional: other tenant objects you may also want under Terraform ─────────
# # Uncomment and fill IDs to import them, then re-run the generate-config step.
# #
# # Custom API (Resource Server) — only if you created one with "Allow Offline
# # Access" enabled for refresh tokens:
# # import {
# #   to = auth0_resource_server.api
# #   id = "REPLACE_WITH_RESOURCE_SERVER_ID"   # the API "Identifier"/id
# # }
# #
# # Database connection (Username-Password-Authentication):
# # import {
# #   to = auth0_connection.database
# #   id = "REPLACE_WITH_CONNECTION_ID"        # e.g. con_xxxxxxxxxxxxxxxx
# # }

# # ArgoCD OCI
# # Regular Web Application
# import {
#   to = auth0_client.argocd_oci
#   id = "9uAWOXkl1OuFoL20xxOKh5KHiLoxzyVE"
# }

# # ArgoCD Trinity
# # Regular Web Application
# import {
#   to = auth0_client.argocd_trinity
#   id = "yUhtOAKUT5TJdPQsGKmBmPqzMcmtoLmw"
# }

# # Default App
# # Generic
# import {
#   to = auth0_client.default_app
#   id = "r7n87ZX86czreuThfKgUsTs8r11YDoqg"
# }


# # ── Grafana — Regular Web Application (OIDC via [auth.generic_oauth]) ─────────
# # Callback:  https://grafana.<BASE_DOMAIN>/login/generic_oauth
# # Logout:    https://grafana.<BASE_DOMAIN>/login
# # Grafana
# # Regular Web Application
# import {
#   to = auth0_client.grafana
#   id = "qHbJv76uDYFuDcopk7yrBzwMhLMxF8TA"
# }


# # ── oauth2-proxy — Regular Web Application (forward-auth for the *arr apps) ───
# # Callback:  https://auth.<BASE_DOMAIN>/oauth2/callback
# # Logout:    https://auth.<BASE_DOMAIN>
# # OAuth2 Proxy
# # Regular Web Application
# import {
#   to = auth0_client.oauth2_proxy
#   id = "PuJ7IKOvjEAKMJaQ8qp0CAQzNmOglYvJ"
# }
