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
2. Give it the right manager role:
   - **IAM_OWNER** (instance-level) if Terraform should create the `homelab`
     org (the default in `zitadel.tf`), or
   - **ORG_OWNER** on an existing org if you reuse it (see step 4).
3. On the service user → **Personal Access Tokens → New** → copy the token.
4. Put the instance domain + token in `.auto.tfvars` (git-ignored by the
   repo-wide `*.tfvars` rule):

   ```hcl
   zitadel_domain       = "my-instance-abc123.zitadel.cloud"
   zitadel_access_token = "<personal-access-token>"
   # base_domain defaults to arendse.nom.za; override if needed.
   ```

   Or export `TF_VAR_zitadel_domain` / `TF_VAR_zitadel_access_token`.

> This module also configures the `auth0` provider, so `terraform plan` expects
> the `auth0_*` variables to be present too. Keep them in `.auto.tfvars` (they're
> already required for the Auth0 side).

## 2. Plan & apply

```bash
cd infrastructure/identity
terraform init          # pulls the zitadel provider (>= 3)
terraform plan          # review: 1 org + 1 project + 4 OIDC apps
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

## Reusing the instance's default org instead of creating one

If your service user only has `ORG_OWNER` (not `IAM_OWNER`), don't create a new
org. Replace `resource "zitadel_org" "homelab"` with a data source that looks the
org up by ID (find it in the Console URL, or via `terraform output`/the API), and
repoint the `org_id` references from `zitadel_org.homelab.id` to
`data.zitadel_org.homelab.id`:

```hcl
variable "zitadel_org_id" {
  description = "ID of an existing Zitadel org to use instead of creating one"
  type        = string
}

data "zitadel_org" "homelab" {
  id = var.zitadel_org_id
}
```

## Notes

- `.auto.tfvars` and `*.tfbackend` are git-ignored — never commit the PAT.
- State (including the generated client secrets) lives in the Backblaze S3
  backend (`.config.s3.tfbackend`), not in Git.
- Changing a callback/logout URL later is a Terraform edit + `apply`, no console
  clicking.
