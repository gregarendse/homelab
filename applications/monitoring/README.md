# Monitoring Authentication

## Grafana admin credentials

Grafana's admin user/password are read from an externally-managed Secret
(`grafana.admin.existingSecret` in `values.yaml`), not templated by the chart.
This keeps the password out of Git and out of Helm's server-side-apply field
ownership (templating it caused `conflict with "kubectl-edit"` upgrade failures
when the password was edited manually).

Create the Secret before deploying the `monitoring` release:

```bash
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<strong-password>'
```

See `grafana-admin-credentials.example.yaml`. To rotate the password, update the
Secret and restart Grafana:

```bash
kubectl -n monitoring rollout restart deploy/monitoring-grafana
```

## Grafana SSO (Auth0)

Grafana authenticates users via Auth0 using OpenID Connect (Grafana's
`auth.generic_oauth`). The OAuth config lives in `values.yaml`, but the
`client_id` / `client_secret` are injected from an externally-managed Secret
(`grafana.envFromSecret: grafana-auth0`) so they stay out of Git.

Grafana auto-maps environment variables named `GF_<SECTION>_<KEY>` onto its
config, so the Secret keys must be named exactly as below — they populate
`[auth.generic_oauth] client_id` / `client_secret`:

```bash
kubectl -n monitoring create secret generic grafana-auth0 \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID='<auth0-client-id>' \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET='<auth0-client-secret>'
```

After creating/rotating the Secret, restart Grafana:

```bash
kubectl -n monitoring rollout restart deploy/monitoring-grafana
```

### Auth0 application setup

Create a **Regular Web Application** in the Auth0 tenant (`arendse.auth0.com`)
and configure:

- **Allowed Callback URLs:** `https://grafana.arendse.nom.za/login/generic_oauth`
- **Allowed Logout URLs:** `https://grafana.arendse.nom.za/login`
- **Allow Offline Access** (on the API): required because
  `use_refresh_token: true` / the `offline_access` scope are enabled in
  `values.yaml`.

The `client_id` / `client_secret` from this application populate the
`grafana-auth0` Secret above.

### Admin role mapping

`role_attribute_path` in `values.yaml` grants the `Admin` role to a single
hardcoded email and `Viewer` to everyone else. To change who is an admin,
update that expression (or, longer term, map an Auth0 role/claim into the
token and key off that instead).

### Rollout flags

During initial rollout the Grafana login form is intentionally left enabled so
you can still log in if OAuth misbehaves:

- `auth.disable_login_form: false` — set `true` once Auth0 login is confirmed.
- `auth.oauth_auto_login: false` — set `true` to skip the Grafana login page and
  redirect straight to Auth0.

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
