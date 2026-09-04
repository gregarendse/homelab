# Importing Auth0 into Terraform

The Auth0 tenant (`arendse.uk.auth0.com`) backs two SSO integrations that were
originally configured by hand in the dashboard:

| App | Type | Used by |
|---|---|---|
| `grafana` | Regular Web Application | Grafana OIDC (`applications/monitoring`) |
| `oauth2-proxy` | Regular Web Application | Edge SSO for the `*arr` apps (`applications/oauth2-proxy`) |

This brings those objects under Terraform so their config (callback/logout URLs,
grant types, app type) is version-controlled. The **runtime** Client ID/Secret
each workload consumes still live in externally-managed Kubernetes Secrets
(`grafana-auth0`, `oauth2-proxy`) — Terraform does not touch those.

## 1. Create a Management API M2M application

Terraform talks to the Auth0 Management API, so it needs its own credentials:

1. Auth0 Dashboard → **Applications → Applications → Create Application**
   → *Machine to Machine Applications*. Name it e.g. `terraform`.
2. Authorize it for the **Auth0 Management API** and grant at least:
   - `read:clients`, `update:clients`, `create:clients`, `delete:clients`
   - `read:client_keys`
   - `read:resource_servers`, `update:resource_servers` (if importing an API)
   - `read:connections`, `update:connections` (if importing connections)
   - (or simply `read:*` / `update:*` for full management)
3. Copy its **Client ID** and **Client Secret** into `.auto.tfvars`
   (git-ignored via the repo-wide `*.tfvars` rule):

   ```hcl
   auth0_domain        = "arendse.uk.auth0.com"
   auth0_client_id     = "<m2m-client-id>"
   auth0_client_secret = "<m2m-client-secret>"
   ```

   Or export them as `TF_VAR_auth0_client_id` / `TF_VAR_auth0_client_secret`.

## 2. Find the Client IDs of the apps to import

Dashboard → **Applications → <app> → Settings → Client ID** for both `grafana`
and `oauth2-proxy`. Paste them into the `import` blocks in `auth0.tf`, replacing
`REPLACE_WITH_GRAFANA_CLIENT_ID` / `REPLACE_WITH_OAUTH2_PROXY_CLIENT_ID`.

## 3. Init, generate config, import

```bash
cd infrastructure/identity
terraform init                                       # pulls the auth0 provider

# Auto-generate resource blocks matching the LIVE Auth0 config:
terraform plan -generate-config-out=auth0_generated.tf

# Review auth0_generated.tf, then record the resources in state:
terraform apply
```

`-generate-config-out` writes `auth0_client.grafana` / `auth0_client.oauth2_proxy`
(and any other imported objects) fully populated from the tenant, so you don't
have to hand-write every attribute. Review the generated file — trim any
read-only/computed attributes Terraform flags — then `apply`.

## 4. Verify

```bash
terraform plan
```

A clean import shows **no changes**. Once confirmed, the `import` blocks in
`auth0.tf` can be deleted (state already holds the resources); leaving them is
harmless.

## 5. Import the rest of the tenant (connections, APIs, tenant settings)

The application clients are only part of the tenant. `imports-pending.tf`
scaffolds the remaining objects — the database connection and its enabled-client
association, optional social connections, custom APIs (resource servers), the
tenant-wide settings singleton, and the Terraform M2M client grant.

These need **real resource IDs**, so first list them:

```bash
cd infrastructure/identity
AUTH0_DOMAIN=arendse.uk.auth0.com \
AUTH0_CLIENT_ID=<m2m-client-id> \
AUTH0_CLIENT_SECRET=<m2m-client-secret> \
  ./list-auth0-ids.sh
```

That prints every client, connection, resource server, and client grant with its
ID. Then, in `imports-pending.tf`:

1. Paste the real IDs into the blocks you want to manage.
2. **Delete** any block you don't need (unused social connections, the
   `is_system` Management API resource server, etc.).
3. Regenerate and apply:

   ```bash
   terraform plan -generate-config-out=generated-extra.tf
   terraform apply
   terraform plan   # confirm no drift
   ```

> The M2M app needs read scopes for the discovery script and generation:
> `read:clients`, `read:connections`, `read:resource_servers`,
> `read:client_grants`.

### Watch out for

- **`auth0_connection_clients`** manages the *complete* set of clients enabled on
  a connection. Importing it alongside `auth0_connection` keeps logins working;
  managing the connection without it risks a later apply disabling apps you
  didn't list. Don't also use `auth0_connection_client` (singular) for the same
  connection.
- **Tenant settings** (`auth0_tenant`) is a singleton — the import ID is a
  throwaway UUID. Generation pulls in every tenant flag, so review before apply.
- **The M2M client grant** is what lets this project talk to Auth0. Managing it
  is fine, but never let an apply revoke the grant Terraform itself depends on.

## Notes

- `.auto.tfvars` and `*.tfbackend` are git-ignored — never commit the M2M secret.
- Terraform state lives in the Backblaze S3 backend (`.config.s3.tfbackend`);
  imported client secrets that Auth0 returns are stored there, not in Git.
- Changing an app's callback/logout URLs later is now a Terraform edit + `apply`,
  no dashboard clicking required.
