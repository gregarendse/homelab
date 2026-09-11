# Monitoring Authentication

**Target cluster: oci.** Grafana is managed by ArgoCD Application `oci-monitoring`
with auto-sync. Only the user runs cluster commands; confirm
`kubectl config current-context` points to OCI before any write. Do not use a
work GKE context or a manual Helm upgrade that ArgoCD will revert.

Zitadel migration is tracked in `applications/zitadel/MIGRATION.md` (CP-2.1).
**Local values now prepare the approved temporary linking window; not deployed.**
The user confirmed OCI context and creation of the unused `grafana-zitadel`
Secret in `monitoring` and asked to complete the cutover. Documentation and
values will be committed separately; deployment and login verification remain
pending and only the user pushes.
Pushing to `master` deploys and enables global email lookup: complete the linking
and a second rollout disabling lookup in the same session. Do not push this
change as incidental work.

## Grafana admin credentials

Grafana's admin user/password are read from an externally-managed Secret
(`grafana.admin.existingSecret` in `values.yaml`), not templated by the chart.
This keeps the password out of Git and out of Helm's server-side-apply field
ownership (templating it caused `conflict with "kubectl-edit"` upgrade failures
when the password was edited manually).

Create the Secret before deploying the `monitoring` release:

```bash
kubectl --context=oci -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<strong-password>'
```

See `grafana-admin-credentials.example.yaml`. These credentials initialize an
empty Grafana user database. With persistence enabled, changing the Secret and
restarting **does not reset an existing user's password**. Use a supported
Grafana password-change/reset procedure if needed, then align the Secret.

Before changing SSO, test the existing local admin against `/api/user` using
HTTP Basic auth as documented in CP-2.1. The hidden login form does not itself
disable Basic auth. Do not share the password or assume the Secret proves that
it still matches the persisted account.

## Grafana SSO (Zitadel cutover prepared; live verification pending)

The last user-verified deployment uses Auth0. Local `values.yaml` now selects
Zitadel using `auth.generic_oauth` and `grafana.envFromSecret: grafana-zitadel`.
The new Secret uses the `grafana` entry in Terraform's `zitadel_sso_client_ids`
and `zitadel_sso_client_secrets` outputs; credentials stay out of Git. Follow
CP-2.1 section C to stage it without printing credentials or restarting Grafana.
Keep `grafana-auth0` and `grafana-admin-credentials` untouched.

### Legacy Auth0 credentials (retained for recovery)

The following documents the existing Auth0 Secret, not a migration step. Do not
recreate it or restart Grafana while merely staging the new Zitadel Secret.

Grafana auto-maps environment variables named `GF_<SECTION>_<KEY>` onto its
config, so the Secret keys must be named exactly as below — they populate
`[auth.generic_oauth] client_id` / `client_secret`:

```bash
kubectl --context=oci -n monitoring create secret generic grafana-auth0 \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID='<auth0-client-id>' \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET='<auth0-client-secret>'
```

Only when rotating credentials for the active provider, restart Grafana after
confirming context `oci` (not needed for staging an unused Secret):

```bash
kubectl --context=oci -n monitoring rollout restart deploy/monitoring-grafana
```

### Auth0 application setup

> `<BASE_DOMAIN>` is your public base domain; `<AUTH0_DOMAIN>` is the Auth0 tenant
> domain (e.g. `<tenant>.<region>.auth0.com`). Real values live in `values.yaml`.

Create a **Regular Web Application** in the Auth0 tenant (`<AUTH0_DOMAIN>`)
and configure:

- **Allowed Callback URLs:** `https://grafana.<BASE_DOMAIN>/login/generic_oauth`
- **Allowed Logout URLs:** `https://grafana.<BASE_DOMAIN>/login`
- **Allow Offline Access** (on the API): required because
  `use_refresh_token: true` / the `offline_access` scope are enabled in
  `values.yaml`.

The `client_id` / `client_secret` from this application populate the
`grafana-auth0` Secret above.

### Temporary linking restriction

The prepared values replace Auth0's substring rule with an exact email match
for `greg.arendse@gmail.com` **and boolean `email_verified: true`**. Only that
identity receives organization `Admin`; all others produce no role and are
rejected by `role_attribute_strict: true`. Signup is disabled, role sync stays
enabled, no `org_mapping` is configured, and `allow_assign_grafana_admin: false`
prevents this rule from granting server-wide GrafanaAdmin.

This deliberately restricts Grafana login to the migration user. Do not add a
Viewer fallback during linking. Broader org-user access is a later decision.

### Rollout flags

The last user-verified Auth0 configuration hides the login form and enables
OAuth auto-login. The prepared values set both `auth.disable_login_form` and
`auth.oauth_auto_login` to `false` so local login is available during migration.
The local admin API credentials have been confirmed; test the browser fallback
after the GitOps rollout. `/login?disableAutoLogin=true` alone cannot restore a
disabled form.

### Existing accounts and planned Secret handling

The new Zitadel `sub` differs from Auth0's. Grafana generic OAuth does not
normally link an existing account by email when
`oauth_allow_insecure_email_lookup` is off (the default in Grafana 11.4.x).
A same-email account can therefore collide rather than migrate automatically.
The user confirmed Grafana 11.4.1, existing SSO user `2` / org `1`, local
server-admin `1`, and the exact verified Zitadel email, and approved temporary
linking. Only Generic OAuth and Basic auth were enabled in the live inventory.

The prepared values enable `auth.oauth_allow_insecure_email_lookup` **only for
the linking window**. After fresh Zitadel login preserves user `2` / org `1`,
set it to `false` in a separate dedicated values commit and rollout. Confirm it
is off, revoke user `2`'s sessions using the admin API, and test fresh login
again. Keep the verified-email restriction and local login available. Do not
leave lookup enabled between sessions; see CP-2.1 section D for commands.

The user declined a database backup. Linking changes the existing generic-OAuth
binding: Secret/config rollback alone may not restore Auth0 login. If recovery
is needed, retain local admin access and separately review a restricted
reverse-linking window against Auth0. Do not delete user `2` or improvise DB
edits.

## Ingress basic auth (legacy)

To access Grafana, you need to populate the `grafana-basic-auth` secret in the `monitoring` namespace.

The secret should contain a `users` key with htpasswd formatted entries.

Example of generating the secret data:

```bash
echo -n "admin:$(openssl passwd -apr1 mypassword)" | base64
```

Then apply it manually or via your preferred secret management tool (SealedSecrets, etc):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-basic-auth
  namespace: monitoring
type: Opaque
data:
  users: <result-from-above>
```

**Note:** This is a temporary measure until a proper OIDC provider is integrated.

ToDo: Clean up, removed the `monitoring-auth` middleware helm chart, just apply it manually.
