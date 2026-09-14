# Monitoring Authentication

**Target cluster: oci.** Grafana is managed by ArgoCD Application `oci-monitoring`
with auto-sync. Only the user runs cluster commands; confirm
`kubectl config current-context` points to OCI before any write. Do not use a
work GKE context or a manual Helm upgrade that ArgoCD will revert.

Zitadel migration is tracked in `applications/zitadel/MIGRATION.md` (CP-2.1).
**Minimal Zitadel login is in values commit `66ed660`; publication is approved,
but deployment and login verification are pending.** The user chose working
SSO first and role mapping later. The new configuration
provisions authenticated Zitadel users as Viewer, reads standard profile/email
claims and disables insecure email lookup. No custom roles or account aliases
are required. Last verified live settings still had the failing email-role rule
and lookup enabled; only a user-controlled push/OCI rollout changes that.

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

## Grafana SSO (minimal configuration prepared; login verification pending)

The live provider is Zitadel via `auth.generic_oauth` and
`grafana.envFromSecret: grafana-zitadel`; successful login is still unverified.
The Secret uses the `grafana` entry in Terraform's `zitadel_sso_client_ids` and
`zitadel_sso_client_secrets` outputs; credentials stay out of Git.
Keep `grafana-auth0`, `grafana-admin-credentials`, and local server-admin user
`1` intact.

### Legacy Auth0 credentials (retained for recovery)

The following is **historical Auth0 setup**, not the current deployment or a
migration step. Preserve the existing Secret; do not recreate it. Restoring
Auth0 requires a reviewed rollback using its known-good settings. The new
minimal flow does not deliberately rebind the existing Auth0 account.

Grafana auto-maps environment variables named `GF_<SECTION>_<KEY>` onto its
config, so the Secret keys must be named exactly as below — they populate
`[auth.generic_oauth] client_id` / `client_secret`:

```bash
kubectl --context=oci -n monitoring create secret generic grafana-auth0 \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID='<auth0-client-id>' \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET='<auth0-client-secret>'
```

Historical restart command for active-provider credential rotation only;
confirm context `oci` first. Do not run it for the retained, inactive Auth0 Secret:

```bash
kubectl --context=oci -n monitoring rollout restart deploy/monitoring-grafana
```

### Historical Auth0 application setup

> `<BASE_DOMAIN>` is the public base domain; `<AUTH0_DOMAIN>` is the former Auth0
> tenant domain (e.g. `<tenant>.<region>.auth0.com`). Current values select Zitadel.

The former Auth0 setup used a **Regular Web Application** with:

- **Allowed Callback URLs:** `https://grafana.<BASE_DOMAIN>/login/generic_oauth`
- **Allowed Logout URLs:** `https://grafana.<BASE_DOMAIN>/login`
- **Allow Offline Access** (on the API): used with refresh tokens and the
  `offline_access` scope.

Its `client_id` / `client_secret` populate the retained `grafana-auth0` Secret.

### Minimal behavior

- Use standard `openid profile email offline_access` claims, with PKCE and
  refresh tokens. No personal IDs, custom attribute aliases or role expressions.
- `auth.generic_oauth.allow_sign_up: true` lets an authenticated Zitadel identity
  provision a Grafana account. This is separate from Zitadel self-registration.
- `[users] allow_sign_up: false` blocks local Grafana self-signup. New OAuth
  accounts join the default organization (`1`) as **Viewer**.
- `skip_org_role_sync: true` defers IdP role mapping. A local administrator can
  adjust organization roles in Grafana without subsequent SSO logins resetting
  them. `allow_assign_grafana_admin: false` prevents SSO server-admin grants.
- `oauth_allow_insecure_email_lookup: false` stays off. No temporary linking
  window or extra lookup-off rollout is needed for this approach.
- Keep the local login form enabled and OAuth auto-login off for recovery.

The Zitadel project currently admits eligible `arendse` users without individual
role assignments. Self-registration is disabled according to the user; external
project grants are not configured. Any identity admitted by that project can
provision a Viewer account. Outside-org denial is deferred, not demonstrated.
Revisit these controls before onboarding users or enabling self-registration.

### Existing accounts and verification

The first successful Zitadel login normally creates a **separate Grafana user**
with the actual Zitadel email. Preserving Auth0 user `2` as the SSO account is no
longer a prerequisite; keep it and local admin `1` untouched. Old preferences,
stars and permissions are not automatically migrated. Viewer access to existing
organization dashboards depends on their permissions; use local admin to adjust
access if needed.

After the reviewed values commit and user push, verify `oci-monitoring` is
Synced/Healthy at the intended revision and the Grafana rollout completes. Then:

1. Confirm local admin browser login works (Basic-auth API access already did).
2. Use a fresh private Zitadel login; check `/api/user` has the actual Zitadel
   email and `isGrafanaAdmin: false`. Do not require user ID `2`.
3. Check `/api/user/orgs` reports org `1` and Viewer for a newly provisioned user;
   confirm dashboard access, sign out/in again and verify session refresh.

Stop on an email/login uniqueness collision rather than enabling insecure
lookup, deleting users or changing either existing email. See CP-2.1 for commands
and progress. No successful minimal-login result has been reported yet.

### Deferred roles and recovery

The user created `admin`, `editor`, `viewer` roles in the Zitadel Grafana project;
their user assignment is tentative. Leave those roles alone; they are not needed
for this minimal flow. Later, review project-role mapping as its own checkpoint.

The database backup was declined. Retain the Auth0 Secret and existing accounts.
For rollback, restore known-good Auth0 settings and its Secret reference—not
merely the previous failing Zitadel role rule. A new Zitadel account's preferences
do not migrate back automatically. If any earlier attempt altered a binding,
inspect it using local admin before separately reviewing recovery; no DB surgery.

## Ingress basic auth (legacy)

Historical ingress basic-auth setup only; this is not required for the current
Zitadel flow. The former setup used the `grafana-basic-auth` Secret in the
`monitoring` namespace.

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

The `monitoring-auth` middleware Helm chart was removed. These legacy notes are
not instructions to re-enable ingress basic auth during the Zitadel migration.
