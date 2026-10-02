# Argo CD SSO (OCI cluster)

## Zitadel browser cutover complete — CP-4.1

Follow `applications/zitadel/MIGRATION.md` for the active checkpoint. The user
confirmed local-admin access, live chart `9.4.15` / ArgoCD `v3.3.4`, existing
email-based RBAC, context `oci`, and creation of the separate `argocd-zitadel`
Secret. `argocd-auth0` is retained for rollback. `argocd.yaml` pairs the Zitadel
issuer with both new Secret references. The user reported a successful Terraform
apply: **0 added, 1 changed, 0 destroyed**, followed by successful Zitadel login.
User Info shows username/group `greg.arendse@gmail.com` and issuer
`https://homelab-jj4izt.eu1.zitadel.cloud`. This matches the explicit email admin
mapping. The user also supplied `{"value":"yes"}` from the same-session
read-only `CanI` check for `applications/sync/*/*`, confirming that permission
without performing a sync. The user then replied "All looks good" to the
rollout-health, Applications-page and logout/re-login checks. **CP-4.1 is complete
for browser SSO on that confirmation**; raw rollout output was not supplied.
RBAC remains explicit, not everyone-admin.

**OCI ArgoCD is Terraform-managed** by `helm_release.argocd` in `argocd.tf`.
The previous direct Helm rollout advice is withdrawn. Being outside GitOps does
not remove Terraform ownership; trinity's manual Helm bootstrap is separate.
`argocd.tf` already reads `argocd.yaml`, so the prepared values are the desired
Terraform input. Pushing them alone does not deploy ArgoCD.

The user's targeted plan has passed review: **0 to add, 1 to change, 0 to
destroy**, only `helm_release.argocd` updated in place. Its values diff changes
the OIDC name/issuer and both Secret references, plus comments; RBAC, ingress and
chart version are unchanged. Computed release metadata becoming unknown after
apply is not removal of those settings.

The apply, browser SSO, permission check, rollout health and application
access/re-login are user-confirmed; **do not repeat the cutover or restart**.
Keep local admin and both provider Secrets. Local-admin access was verified
before cutover, not separately retested afterward. Private-window isolation,
non-admin/outside-org denial, CLI SSO and a separate live inspection of the
OIDC display name/Secret references remain unverified; see CP-4.1's test limits.
Do not treat them as passes or expand admission without reviewing the policy.

Targeting was an exceptional migration scope, not proof that the incomplete root
is consistent. A full plan is still required later before cleanup. The next
available migration is Pi-hole on OCI; trinity ArgoCD remains paused. The user
approved a local checkpoint commit; pushing requires separate approval.

Both providers explicitly select context `oci` from `var.kubeconfig_path`,
rather than inheriting an unrelated current-context. Only the user runs live
plans/applies or cluster commands; confirm the configured kubeconfig and context
before proceeding, and current context **oci** before writes. Keep local `admin`
and the original Auth0 Secret for rollback.

## Historical Auth0 reference — not the current migration procedure

Do not run the legacy setup/apply/restart commands below during CP-4.1; they are
retained as background only. Do not recreate the retained Secret or run a broad
Terraform apply. CLI SSO with the new Zitadel client remains unverified.

The OCI cluster installs Argo CD via Terraform (`argocd.tf`, values in
`argocd.yaml`). Argo CD authenticates users against Auth0 directly using its
**native OIDC** support (configured in `configs.cm.oidc.config` in `argocd.yaml`).

This mirrors the trinity install (`clusters/trinity/argocd.yaml` /
`clusters/trinity/README.md`); the only differences are the ingress class
(`traefik`) and the hostname (`argocd.arendse.nom.za`).

Argo CD is **not** put behind oauth2-proxy — forward-auth would break the Argo
CLI/API/gRPC, and native OIDC also gives RBAC role mapping. The built-in `admin`
account stays as a break-glass fallback.

> `<BASE_DOMAIN>` = your public base domain, `<AUTH0_DOMAIN>` = the Auth0 tenant
> domain. Real values live in `argocd.yaml`.

## 1. Auth0 application

Create a **Regular Web Application** in the Auth0 tenant (`<AUTH0_DOMAIN>`). Use a
**separate** application from the trinity ArgoCD one so the two clusters have
independent credentials/audit (or, if you prefer to reuse one app, add the OCI
URLs below to the existing application's lists):

- **Allowed Callback URLs:**
  `https://argocd.<BASE_DOMAIN>/auth/callback`, `http://localhost:8085/auth/callback`
  (the second one is for `argocd login --sso` from the CLI)
- **Allowed Logout URLs:** `https://argocd.<BASE_DOMAIN>`
- **Allowed Web Origins:** `https://argocd.<BASE_DOMAIN>`

Note the application's **Client ID** and **Client Secret** for the next step.

## 2. Secret

The client credentials are pulled from an externally-managed Secret (kept out of
Git — see `argocd-auth0.example.yaml`). It **must** carry the
`app.kubernetes.io/part-of: argocd` label for the `$argocd-auth0:clientID` /
`$argocd-auth0:clientSecret` references in `argocd.yaml` to resolve:

```bash
kubectl -n argocd create secret generic argocd-auth0 \
  --from-literal=clientID='<auth0-client-id>' \
  --from-literal=clientSecret='<auth0-client-secret>'
kubectl -n argocd label secret argocd-auth0 app.kubernetes.io/part-of=argocd
```

> The namespace must exist first. If you haven't applied the Terraform yet, run
> `kubectl create namespace argocd` (Terraform's `create_namespace = true` also
> creates it on first `terraform apply`).

## 3. Apply the Helm-values change

The OIDC config now lives in `argocd.yaml`. Roll it out via Terraform:

```bash
cd infrastructure/kubernetes
terraform plan
terraform apply
```

(Or, for a quick out-of-band test, `helm upgrade argocd argo/argo-cd -n argocd
--reuse-values -f argocd.yaml`.)

After creating/rotating the Secret, restart the server so it re-reads the values:

```bash
kubectl -n argocd rollout restart deploy/argocd-server
```

## 4. Log in

Open `https://argocd.<BASE_DOMAIN>` — you should now see a **LOG IN VIA AUTH0**
button alongside the username/password form. The Auth0 path drops you back into
Argo with whatever RBAC role your email maps to.

From the CLI:

```bash
argocd login argocd.<BASE_DOMAIN> --sso
```

## RBAC

`configs.rbac` in `argocd.yaml` matches on the `email` claim and grants
`role:admin` to a single email (`policy.default: ''` denies everyone else). Add
more lines to `policy.csv` to grant access to other users:

```yaml
policy.csv: |
  g, greg.arendse@gmail.com, role:admin
  g, someone.else@example.com, role:readonly
```

## Troubleshooting

- **`invalid_redirect_uri` from Auth0** — the callback URL in the Auth0
  application doesn't exactly match `https://argocd.<BASE_DOMAIN>/auth/callback`.
- **Login button missing / `oidc.config` errors** — the `argocd-auth0` Secret is
  missing the `app.kubernetes.io/part-of: argocd` label, so the `$name:key`
  substitution can't resolve. Check `kubectl -n argocd logs deploy/argocd-server`.
- **Redirect loop / TLS errors** — confirm `server.insecure: true` is set (it is)
  so Traefik terminates TLS and talks plain HTTP to the pod.
