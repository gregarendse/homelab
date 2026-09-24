# Monitoring Authentication

**Target cluster: oci.** Grafana is managed by ArgoCD Application `oci-monitoring`
with auto-sync. Only the user runs cluster commands; confirm
`kubectl config current-context` points to OCI before any write. Do not use a
work GKE context or a manual Helm upgrade that ArgoCD will revert.

Zitadel migration is tracked in `applications/zitadel/MIGRATION.md` (CP-2.1).
**Zitadel login and local-admin browser access are user-confirmed.** After the
user removed a conflicting Grafana account, their SSO profile showed Gregory
Arendse (`greg.arendse@gmail.com` as email/login), synced by Generic OAuth,
**Main Org Viewer; Grafana Admin No**. The latest decision is temporary **Main Org
Admin for every successful Zitadel login**, with role mapping deferred again.
The user **approved separate documentation/values commits and a push to master**;
no Terraform action is needed. Publication does not confirm deployment: exact
synced Git revision, health, rollout, live settings, fresh Admin login and
session refresh evidence remain pending.

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

Local admin access was verified using both HTTP Basic `/api/user` and browser
login (user-confirmed; see CP-2.1). Keep this fallback available during SSO
changes. Do not share the password or assume the Secret proves that it still
matches the persisted account.

## Grafana SSO (login confirmed; Admin-policy rollout verification pending)

The live provider is Zitadel via `auth.generic_oauth` and
`grafana.envFromSecret: grafana-zitadel`; successful login is user-confirmed.
The Secret uses the `grafana` entry in Terraform's `zitadel_sso_client_ids` and
`zitadel_sso_client_secrets` outputs; credentials stay out of Git.
Keep `grafana-auth0`, `grafana-admin-credentials`, and local server-admin user
`1` intact.

### Legacy Auth0 credentials (retained for recovery)

The following is **historical Auth0 setup**, not the current deployment or a
migration step. Preserve the existing Secret; do not recreate it. Restoring
Auth0 requires a reviewed rollback using its known-good settings. The new
flow does not deliberately rebind an Auth0 account or restore deleted metadata.

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

### Temporary constant Admin policy (publication approved; live checks pending)

Under `grafana.grafana.ini.auth.generic_oauth` in `values.yaml`:

```yaml
role_attribute_path: "'Admin'"
skip_org_role_sync: false
role_attribute_strict: false
allow_assign_grafana_admin: false
```

- `"'Admin'"` is the YAML spelling of the JMESPath literal `'Admin'`, not a
  claim lookup. After deployment, every successful Zitadel login gets org `1`
  (**Main Org**) **Admin** on next login, including no-role users and a user
  labelled `ZITADEL Admin`. No Zitadel role, grant or admin claim is required.
- `skip_org_role_sync: false` overwrites manual Grafana org roles on login;
  removing Zitadel roles does not downgrade users under this constant policy.
  No `org_mapping` is configured.
- Only standard scopes: `openid profile email offline_access`, with PKCE and
  refresh tokens. `auth.generic_oauth.allow_sign_up: true` permits OAuth
  provisioning. `[users] allow_sign_up: false`, `auto_assign_org: true` and
  `auto_assign_org_role: Viewer` stay unchanged; the OAuth expression overrides
  Viewer for Zitadel users, including those without project roles.
- Organization **Admin** is not server **GrafanaAdmin**:
  `allow_assign_grafana_admin: false` prevents SSO server-admin grants. This
  policy grants nothing to anonymous visitors and does not change local admin.
- `oauth_allow_insecure_email_lookup: false` stays off. No account aliases,
  hardcoded email or personal `sub`; standard profile/email claims are used.
  Keep the local login form enabled and OAuth auto-login off for recovery.

Login admission still relies on the existing dedicated Zitadel Grafana project
(`390167990928259276`) in `arendse` (`380143417033860850`):
`has_project_check=true`, `project_role_check=false`, no external project grants
reported. Self-registration is disabled per the user, not independently verified.
**All current and future admitted users receive Main Org Admin under this
policy. Narrow it before onboarding users, enabling registration or granting
external orgs access.** Outside-org denial remains **deferred, not passed**.

### Existing accounts and verification

The user removed the conflicting Grafana account themselves; the agent deleted
no users. Neither the deleted account's numeric ID nor the current SSO numeric
ID is known: do not infer user `2` was retained, deleted or replaced. Keep local
admin `1` intact. Old preferences, stars and permissions are not automatically
migrated.

The user approved committing and pushing this constant policy. **No grant ID
or Terraform action is required.** After publication, the user verifies
`oci-monitoring` is Synced/Healthy at the intended revision and the Grafana
rollout completes. Pushing to `master` auto-deploys; the agent runs no cluster
commands. Then:

1. Keep the confirmed local-admin browser fallback available; verify live
   settings match the constant policy above, including lookup remaining off.
2. Use a fresh private Zitadel login; record `/api/user` ID/login/email and
   require the actual Zitadel email and `isGrafanaAdmin: false`. Do not assume
   an SSO account ID or associate it with local admin `1`.
3. Require `/api/user/orgs` to show org `1` (**Main Org**) **Admin**, while
   **Grafana Admin stays No**, regardless of Zitadel roles. An eligible no-role
   user must also receive Admin when one is available to test, not Viewer.
4. Confirm dashboard access, sign out/in again, verify the same account and
   expected role, then exercise session refresh. These checks remain pending.

Stop on further email/login collisions or unexpected access; do not enable
insecure lookup, delete users or change account emails to force association.
See CP-2.1 for commands and progress; outside-org testing remains deferred.

### Deferred role mapping and recovery

**Role mapping and Terraform role/grant adoption are deferred again.** The
constant is code-controlled in `values.yaml`; existing console roles/grants are
untouched. Cleanup is limited to the agent's untracked, **unapplied**
`infrastructure/identity/grafana-roles.tf` draft and its header reference. No
live plan, import or apply was ever run for that draft; no Terraform action or
`grafana_greg_user_grant_id` is needed now.

**Later follow-up:** replace the constant with least-privilege, org-scoped
Admin/Editor/Viewer mapping, decide no-role behavior, verify actual claims and
role removal/downgrade, and separately review Terraform adoption of existing
roles/grants. Narrow admission and test outside-org denial before expanding
access; do not treat mapping/adoption or those tests as complete.

The database backup was declined; that decision is settled. Retain the Auth0
Secret and remaining accounts. For rollback, restore known-good Auth0 settings
and its Secret reference—not merely the previous failing Zitadel role rule.
Rollback cannot restore the deleted user's metadata or automatically migrate
preferences/permissions. Review any binding recovery separately; no DB surgery.

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
