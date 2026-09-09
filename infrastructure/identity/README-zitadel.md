# Configuring Zitadel Cloud with Terraform

This manages the Zitadel Cloud identity config as code, mirroring the Auth0 apps
in `generated.tf` so a future migration off Auth0 is a like-for-like swap.

| Zitadel app (`zitadel.tf`) | Replaces Auth0 app | Used by |
|---|---|---|
| `oauth2-proxy` | `oauth2_proxy` | Edge SSO for the `*arr` apps + the PoC proxy |
| `grafana` | `grafana` | Grafana OIDC (`applications/monitoring`) |
| `argocd-trinity` | `argocd_trinity` | ArgoCD (trinity) OIDC |
| `argocd-oci` | `argocd_oci` | ArgoCD (OCI) OIDC |

Unlike Auth0 (imported from a hand-built tenant), this is a **greenfield** config
— it *creates* the org, project and OIDC apps. Terraform generates each app's
`client_id`/`client_secret`; you copy those into the externally-managed
Kubernetes Secrets. Terraform never stores them in Git (only in the S3 state).

## 1. Create a Zitadel service user + PAT

Terraform talks to the Zitadel management API as a service (machine) user:

1. Zitadel Console → your instance → **Users → Service Users → New**. Name it
   e.g. `terraform`.
2. Give it **ORG_OWNER** on the org that will hold the project (`arendse`):
   Console → Organization → **Managers** → New. That is all this module needs —
   it creates a project and applications *inside* an existing org and never
   touches instance-level resources.
3. On the service user → **Personal Access Tokens → New** → copy the token.
4. Put the instance domain + token in `.auto.tfvars` (git-ignored by the
   repo-wide `*.tfvars` rule):

   ```hcl
   # INSTANCE domain — not an org name. Same host as the OIDC issuer.
   zitadel_domain       = "homelab-jj4izt.eu1.zitadel.cloud"
   zitadel_access_token = "<personal-access-token>"
   # ID of the existing org to create the project in (from the Console URL).
   zitadel_org_id       = "380143417033860850"
   # base_domain defaults to arendse.nom.za; override if needed.
   ```

   > None of these have defaults. If one is missing, Terraform silently
   > *prompts* for it — which makes a typo look like an authentication failure.
   > A wrong `zitadel_domain` reports `Instance not found`, not a bad token.

   Or export `TF_VAR_zitadel_domain` / `TF_VAR_zitadel_access_token`.

> This module also configures the `auth0` provider, so `terraform plan` expects
> the `auth0_*` variables to be present too. Keep them in `.auto.tfvars` (they're
> already required for the Auth0 side).

## 2. Plan & apply

```bash
cd infrastructure/identity
terraform init          # pulls the zitadel provider (>= 3)
terraform plan          # review: 1 project + 4 OIDC apps = 5 to add
terraform apply
```

## 3. Wire the generated credentials into Kubernetes

`terraform apply` creates the apps and computes their secrets. Feed the PoC proxy
its credentials (see `applications/zitadel/README.md`):

```bash
CID=$(terraform output -json zitadel_oidc_client_ids     | jq -r .oauth2_proxy)
SEC=$(terraform output -json zitadel_oidc_client_secrets | jq -r .oauth2_proxy)

kubectl -n oauth2-proxy-zitadel create secret generic oauth2-proxy-zitadel \
  --from-literal=client-id="$CID" \
  --from-literal=client-secret="$SEC" \
  --from-literal=cookie-secret="$(openssl rand -base64 32 | tr -- '+/' '-_')"
```

The same outputs (`grafana`, `argocd_trinity`, `argocd_oci`) feed the other apps'
Secrets when you migrate them.

## 4. Migrating off Auth0 (later)

The redirect URIs for the production hosts are already registered, so cutover per
app is just: point the app's `oidc-issuer-url` at
`https://<zitadel_domain>` and replace the client id/secret in its Secret. See
the "Promote to production" section of `applications/zitadel/README.md`.

Roll back by reverting the issuer/secret to the Auth0 values — the Auth0 apps in
`generated.tf` stay intact throughout.

## Why there is no zitadel_org resource *or* data source

`zitadel.tf` never declares the organization — neither way works with an
org-scoped token, because both go through instance-level APIs:

| Block | Underlying API | Requires |
|---|---|---|
| `resource "zitadel_org"` | `AddOrganization` (org v2) | IAM_OWNER |
| `data "zitadel_org"` | Admin API `GetOrgByID` + `GetDefaultOrg` | IAM_OWNER |

The data source is the surprising one: merely *reading* an org uses the
instance-scoped Admin API, so an ORG_OWNER token fails with

```
error while getting org by id <id>: PermissionDenied ... (AUTH-5mWD2)
```

The only thing actually needed is the org's ID, and we already have it, so the
org is referenced directly as `org_id = var.zitadel_org_id`. Creating projects
and applications inside an org uses the Management API, which ORG_OWNER covers.
Do not reintroduce the data source “for validation” — it only adds a permission
requirement.

## Notes

- `.auto.tfvars` and `*.tfbackend` are git-ignored — never commit the PAT.
- State (including the generated client secrets) lives in the Backblaze S3
  backend (`.config.s3.tfbackend`), not in Git.
- Changing a callback/logout URL later is a Terraform edit + `apply`, no console
  clicking.
