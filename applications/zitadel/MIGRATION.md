# Auth0 → Zitadel migration — resumable checklist

A step-by-step cutover from Auth0 to **Zitadel Cloud** as the single OIDC provider.
Each checkpoint is small, independently deployable, and **reversible**. Do one,
tick it off, and come back later — nothing here has to be done in one sitting.

- **Instance / issuer:** `https://homelab-jj4izt.eu1.zitadel.cloud` (referred to
  below as `<ISSUER>`).
- **Golden rule:** change **one integration at a time**, confirm login works,
  then move on. Auth0 stays fully intact until Phase 6, so any step rolls back by
  reverting the issuer + restoring the old client id/secret.
- ⚠️ **GitOps: pushing to `master` IS deploying.** Both clusters set
  `autoSync: true` in `clusters/*/apps.yaml`, which renders every app with
  `automated: {prune: true, selfHeal: true}`. Two consequences:
  1. **Update the Kubernetes Secret BEFORE you push the values change.** The
     Secrets are externally managed, so Argo never touches them — but if the new
     issuer lands while the old Auth0 credentials are still in the Secret, every
     app behind that proxy breaks until you fix it.
  2. **Do not deploy these with `helm upgrade` / `./upgrade.sh`.** `selfHeal`
     will revert laptop-side changes to whatever is on `master`. Commit + push
     instead.

  Not everything is auto-synced — **ArgoCD itself is not** (there is no `argocd`
  app in `clusters/*/rendered/`), so Phases 3 and 4 *do* deploy manually.
- **Zitadel OIDC endpoints** (needed for Grafana, which uses explicit URLs):
  - authorize: `<ISSUER>/oauth/v2/authorize`
  - token: `<ISSUER>/oauth/v2/token`
  - userinfo: `<ISSUER>/oidc/v1/userinfo`

## Progress tracker

Update this as you go so "future you" knows where to resume.

- **Last completed:** CP-0.2 — Phase 0 done. `homelab` project + 4 OIDC apps
  live in the `arendse` org, and their credentials are readable via
  `terraform output`.
- **Next up:** CP-1.1 — the edge-proxy cutover (moves every `*arr` app at once).

| # | Checkpoint | Done |
|---|---|:--:|
| 0.1 | Apply `zitadel.tf` (project + 4 OIDC apps) | ☑ |
| 0.2 | Capture the generated client ids/secrets | ☑ |
| 0.3 | (Optional) Dress-rehearse CP-1.1 on the PoC rig | ☐ |
| 1.1 | Cut over the edge proxy (all `*arr` apps) | ☐ |
| 1.2 | Burn-in: confirm the `*arr` apps for a few days | ☐ |
| 2.1 | Cut over Grafana | ☐ |
| 3.1 | Cut over ArgoCD (trinity) | ☐ |
| 4.1 | Cut over ArgoCD (OCI) | ☐ |
| 5.1 | (Optional) Fold Pi-hole into the central proxy | ☐ |
| 6.1 | Tear down the PoC rig | ☐ |
| 6.2 | Remove Auth0 runtime Secrets | ☐ |
| 6.3 | Retire the Auth0 Terraform + provider | ☐ |
| 6.4 | Clean up the old Zitadel console objects | ☐ |
| 6.5 | Update docs to make Zitadel the primary | ☐ |

## Decisions log

Context worth remembering between sessions.

- **Auth0 Terraform is commented out, not imported.** The `auth0_*` resources
  were only ever *pending* import and never entered state, so Terraform does not
  manage them and cannot destroy them. The live Auth0 tenant is untouched and
  remains the rollback path. `imports-pending.tf` was never completed on purpose
  (adopting the tenant/database connection would be throwaway work).
- **Zitadel layout: existing org, new project.** The console has a single org
  `arendse`, containing projects `ZITADEL` (built-in system project — do not
  touch) and `trinity` (hand-made, holds the working Pi-hole + PoC app
  registrations). `zitadel.tf` creates a new **`homelab` project** inside
  `arendse`. Creating a separate org was rejected because `zitadel_org` creation
  requires an instance-level **IAM_OWNER** PAT. Everything stays in one org,
  alongside your existing users; the old `trinity` project keeps Pi-hole running
  until Phase 6 cleanup.
- **The org is referenced by raw ID — there is deliberately no
  `data "zitadel_org"` block.** That data source resolves the org through
  ZITADEL's instance-level **Admin API** (`GetOrgByID` + `GetDefaultOrg`), so it
  demands IAM_OWNER and fails for an ORG_OWNER PAT with
  `error while getting org by id <id>: PermissionDenied ... (AUTH-5mWD2)`.
  Since we only ever need the ID and already have it, `var.zitadel_org_id` is
  passed straight to each resource's `org_id`.
- **PAT permissions:** the `terraform` service user holds **Org Owner** on
  `arendse`. That is sufficient to create projects and applications inside the
  org. No instance-level role is needed.
- **Known IDs** (identifiers, not secrets): org `arendse` =
  `380143417033860850`; project `homelab` = `389307350701388526`; instance
  domain / OIDC issuer = `https://homelab-jj4izt.eu1.zitadel.cloud`.
- **Client IDs are numeric, with no `@project` suffix.** The provider populates
  `client_id` straight from the API (`GetClientId()`), so paste the
  `terraform output` values verbatim into each Secret. For reference:
  `oauth2_proxy` = `389307350953112302`, `grafana` = `389307350969758446`,
  `argocd_trinity` = `389307350969838839`, `argocd_oci` = `389307350953061623`.
  The matching secrets stay in Terraform state only — never commit them.
- **Both clusters auto-sync.** `clusters/trinity/apps.yaml` and
  `clusters/oci/apps.yaml` both set `autoSync: true`, so every rendered app gets
  `prune: true, selfHeal: true`. Pushing to `master` deploys, and manual
  `helm upgrade` / `./upgrade.sh` gets reverted. `oauth2-proxy` (trinity) and
  `monitoring` (OCI) are both enrolled; **ArgoCD itself is not**, so its values
  files still need a manual apply.
- **Any org user can log in without a grant** because `zitadel.tf` sets
  `has_project_check = false` and `project_role_check = false`. No per-user
  project grants are needed for the initial cutover.

---

## Phase 0 — Provider groundwork (do once)

### CP-0.1 — Apply the Zitadel Terraform
Creates the `homelab` project and the 4 OIDC apps inside the **existing**
`arendse` org. Production redirect URIs are already registered in `zitadel.tf`,
so nothing to click in the console.

First set the instance domain and org ID in `.auto.tfvars` (git-ignored):

```hcl
# The INSTANCE domain — not the org name. Same host as the oidc-issuer-url the
# working Pi-hole/PoC proxies already use.
zitadel_domain = "homelab-jj4izt.eu1.zitadel.cloud"
zitadel_org_id = "380143417033860850"   # the "arendse" org
```

> Both variables have no default. If either is missing, Terraform silently
> *prompts* for it — which is how `arendse.eu1.zitadel.cloud` (org name + region)
> once got entered by mistake, producing a confusing
> `Instance not found` error on the first resource it tried to create.

```bash
cd infrastructure/identity
terraform init
terraform plan     # expect: 1 project + 4 OIDC apps = 5 to add, 0 to destroy
terraform apply
```
- **Verify:** `terraform plan` is clean afterward.
- **Permissions:** the PAT's service user needs **ORG_OWNER** on `arendse`. No
  instance-level IAM_OWNER is required (see Decisions log).
- Pi-hole keeps working throughout on its own app registration in the `trinity`
  project.

### CP-0.2 — Capture the generated credentials
You'll paste these into each app's Secret as you go. Read them on demand:

```bash
cd infrastructure/identity
terraform output -json zitadel_oidc_client_ids     | jq .
terraform output -json zitadel_oidc_client_secrets | jq .
# single app, e.g.:  terraform output -json zitadel_oidc_client_ids | jq -r .grafana
```
- **Verify:** you can read an id/secret for `oauth2_proxy`, `grafana`,
  `argocd_trinity`, `argocd_oci`.

---

### CP-0.3 — (Optional) Dress-rehearse the cutover on the PoC rig

A zero-risk rehearsal for CP-1.1. `zitadel.tf` registered **both** callbacks on
the `oauth2-proxy` app, including the PoC one
(`https://auth-zitadel.<base_domain>/oauth2/callback`). So you can point the
isolated PoC proxy at the **Terraform-managed** credentials and exercise the
exact same code path CP-1.1 will use — but against the throwaway `zitadel-echo`
app instead of every `*arr` app.

First confirm the PoC rig is still running (its rendered manifests were only
committed recently, so Argo may never have deployed it):

```bash
kubectl -n oauth2-proxy-zitadel get deploy,ingress
```

If it isn't there, skip this checkpoint and go straight to CP-1.1 — or deploy it
using the helm command in `applications/zitadel/README.md` §4.

If it is running, swap in the managed credentials:

```bash
cd infrastructure/identity
CID=$(terraform output -json zitadel_oidc_client_ids     | jq -r .oauth2_proxy)
SEC=$(terraform output -json zitadel_oidc_client_secrets | jq -r .oauth2_proxy)

kubectl -n oauth2-proxy-zitadel delete secret oauth2-proxy-zitadel
kubectl -n oauth2-proxy-zitadel create secret generic oauth2-proxy-zitadel \
  --from-literal=client-id="$CID" \
  --from-literal=client-secret="$SEC" \
  --from-literal=cookie-secret="$(openssl rand -base64 32 | tr -- '+/' '-_')"

kubectl -n oauth2-proxy-zitadel rollout restart deploy/oauth2-proxy-zitadel
```

- **Verify:** open `https://zitadel-echo.<base_domain>` → Zitadel login → the
  `http-echo` response. That proves the Terraform-created client, its secret,
  the issuer URL, and the whole oauth2-proxy flow all work together.
- **Blast radius:** none. Only the `oauth2-proxy-zitadel` namespace and the
  throwaway echo app are touched. Production `oauth2-proxy` (Auth0) and Pi-hole
  are untouched.
- **If it fails here**, CP-1.1 would have failed too — far better to find out
  now. Check the proxy logs:
  `kubectl -n oauth2-proxy-zitadel logs deploy/oauth2-proxy-zitadel`


## Phase 1 — Edge proxy (biggest win: every `*arr` app at once)
### CP-1.1 — Cut over `oauth2-proxy` (trinity)
1. Swap the runtime Secret to the Zitadel client (jot down the old Auth0 values
   first for rollback):
   ```bash
   CID=$(cd infrastructure/identity && terraform output -json zitadel_oidc_client_ids     | jq -r .oauth2_proxy)
   SEC=$(cd infrastructure/identity && terraform output -json zitadel_oidc_client_secrets | jq -r .oauth2_proxy)
   kubectl -n oauth2-proxy delete secret oauth2-proxy
   kubectl -n oauth2-proxy create secret generic oauth2-proxy \
     --from-literal=client-id="$CID" \
     --from-literal=client-secret="$SEC" \
     --from-literal=cookie-secret="$(openssl rand -base64 32 | tr -- '+/' '-_')"
   ```
2. In `applications/oauth2-proxy/values.yaml`, change:
   ```yaml
   oidc-issuer-url: https://homelab-jj4izt.eu1.zitadel.cloud
   ```
   (leave `redirect-url: https://auth.arendse.nom.za/oauth2/callback` as-is —
   it's already registered on the Zitadel app).
3. Commit and push — **this is the deploy.** Argo auto-syncs `oauth2-proxy`
   (it is enrolled in `clusters/trinity/apps.yaml`):
   ```bash
   git add applications/oauth2-proxy/values.yaml
   git commit -m "oauth2-proxy: authenticate against Zitadel instead of Auth0"
   git push
   ```
   Do **not** run `helm upgrade` here — `selfHeal` would revert it to `master`.
   Watch it land with `argocd app get oauth2-proxy`, or force it along with
   `argocd app sync oauth2-proxy`.
- **Verify:** open one protected app (e.g. `https://sonarr.arendse.nom.za`) →
  redirected to Zitadel → after login you reach the app.
- **Rollback:** `git revert` the commit and push (restores the Auth0 issuer),
  then put the Auth0 client id/secret back in the `oauth2-proxy` Secret.

### CP-1.2 — Burn-in
Leave it a few days. Confirm the shared cookie still gives single-sign-on across
the `*arr` apps and no one is locked out. Only then continue.

---

## Phase 2 — Grafana

> Grafana runs on the **OCI** cluster (`clusters/oci/rendered/monitoring.yaml`),
> which also has `autoSync: true`. Same rule as Phase 1: Secret first, then push.

### CP-2.1 — Cut over Grafana
1. Replace the credentials in the existing Secret (keeps `envFromSecret` intact):
   ```bash
   CID=$(cd infrastructure/identity && terraform output -json zitadel_oidc_client_ids     | jq -r .grafana)
   SEC=$(cd infrastructure/identity && terraform output -json zitadel_oidc_client_secrets | jq -r .grafana)
   kubectl -n monitoring delete secret grafana-auth0
   kubectl -n monitoring create secret generic grafana-auth0 \
     --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID="$CID" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="$SEC"
   ```
   (Keeping the `grafana-auth0` name avoids touching `values.yaml` here; you can
   rename it during cleanup in Phase 6.)
2. In `applications/monitoring/values.yaml` under `auth.generic_oauth`, repoint
   the three URLs and the display name:
   ```yaml
   name: Zitadel
   auth_url:  https://homelab-jj4izt.eu1.zitadel.cloud/oauth/v2/authorize
   token_url: https://homelab-jj4izt.eu1.zitadel.cloud/oauth/v2/token
   api_url:   https://homelab-jj4izt.eu1.zitadel.cloud/oidc/v1/userinfo
   ```
   Leave `scopes` and `role_attribute_path` as-is (Zitadel returns a verified
   `email` claim, which the admin mapping keys off).
3. Commit and push — Argo auto-syncs `monitoring`. Then restart Grafana so it
   re-reads the Secret:
   ```bash
   kubectl -n monitoring rollout restart deploy/monitoring-grafana
   ```
   Again, no `./upgrade.sh` — `selfHeal` would revert it.
- **Verify:** log in at `https://grafana.arendse.nom.za`; confirm your account
  still lands as **Admin** and others as Viewer.
- **Rollback:** `git revert` + push to restore the 3 Auth0 URLs, and put the
  Auth0 client id/secret back in the Secret.

---

## Phase 3 — ArgoCD (trinity)

> Unlike Phases 1–2, ArgoCD is **not** self-managed through GitOps — there is no
> `argocd` entry in `clusters/*/rendered/`. These values files are applied by
> hand (helm/terraform), so committing alone does **not** deploy them.

### CP-3.1 — Cut over trinity ArgoCD
> The built-in `admin` account is your break-glass login the whole time.
1. Replace creds in the `argocd-auth0` Secret (keep the label!):
   ```bash
   CID=$(cd infrastructure/identity && terraform output -json zitadel_oidc_client_ids     | jq -r .argocd_trinity)
   SEC=$(cd infrastructure/identity && terraform output -json zitadel_oidc_client_secrets | jq -r .argocd_trinity)
   kubectl -n argocd delete secret argocd-auth0
   kubectl -n argocd create secret generic argocd-auth0 \
     --from-literal=clientID="$CID" --from-literal=clientSecret="$SEC"
   kubectl -n argocd label secret argocd-auth0 app.kubernetes.io/part-of=argocd
   ```
2. In `clusters/trinity/argocd.yaml`, under `configs.cm.oidc.config`, change:
   ```yaml
   name: Zitadel
   issuer: https://homelab-jj4izt.eu1.zitadel.cloud
   ```
   (ArgoCD uses OIDC discovery, so only the issuer changes.)
3. Deploy the argocd release, then `kubectl -n argocd rollout restart deploy/argocd-server`.
- **Verify:** log in at `https://trinity.argocd.arendse.nom.za` via Zitadel and
  confirm you get `role:admin`. If SSO misbehaves, log in with `admin` and fix.
- **Rollback:** revert `issuer`/`name` and restore the Auth0 client id/secret.

---

## Phase 4 — ArgoCD (OCI)

### CP-4.1 — Cut over OCI ArgoCD
Same as CP-3.1 but for the OCI cluster:
- Secret creds come from `terraform output ... jq -r .argocd_oci`.
- Edit the issuer in `infrastructure/kubernetes/argocd.yaml`.
- Restart `argocd-server` in that cluster and verify at
  `https://argocd.arendse.nom.za`.

---

## Phase 5 — Pi-hole (optional consolidation)

Pi-hole already authenticates against Zitadel via
`pihole-zitadel-oauth2-proxy`, so **nothing is required**. Optional tidy-up only:

### CP-5.1 — (Optional) Fold Pi-hole into the central proxy
Decide whether to keep the dedicated per-app proxy or route Pi-hole through the
central `oauth2-proxy`. If it works today, feel free to skip this.

---

## Phase 6 — Decommission Auth0 (only after a solid burn-in)

### CP-6.1 — Tear down the PoC rig
Follow `applications/zitadel/README.md` §5: uninstall `oauth2-proxy-zitadel` and
`zitadel-echo`, delete their namespaces, remove their entries from
`clusters/trinity/apps.yaml`, delete `applications/oauth2-proxy-zitadel/` and
`applications/zitadel-echo/`, regenerate rendered manifests, and drop the
matching `clusters/trinity/rendered/*.yaml` files.

### CP-6.2 — Remove Auth0 runtime Secrets
Once every app has run on Zitadel for a while and you're confident, delete the
now-unused Auth0 client values. (If you reused Secret *names* like
`grafana-auth0` / `argocd-auth0`, they now hold Zitadel creds — leave them, or
rename to `-zitadel` and update the one referencing value file.)

### CP-6.3 — Retire the Auth0 Terraform + provider
The Auth0 resources were **never imported into state**, so this is purely a
file-deletion exercise — there is nothing for Terraform to destroy. Delete the
(already commented-out) `auth0.tf`, `generated.tf`, `imports-pending.tf`,
`list-auth0-ids.sh`, the `auth0_*` variables, and the `auth0` provider block in
`providers.tf`. Then `terraform plan` to confirm **0 to destroy**.
> This does not delete anything in the Auth0 tenant itself. Retire the tenant
> separately in the Auth0 dashboard once you're confident — it costs nothing to
> leave it as an emergency fallback for a while.

### CP-6.4 — Clean up the old Zitadel console objects
Once everything runs on the `homelab` org, remove the now-redundant hand-made
registrations in the `arendse` org's **`trinity`** project (the PoC app and, if
you folded Pi-hole into the central proxy at CP-5.1, the Pi-hole app too).
Leave the built-in **`ZITADEL`** project alone.

### CP-6.5 — Update docs
Refresh the READMEs (`applications/oauth2-proxy/`, `applications/monitoring/`,
`infrastructure/kubernetes/ARGOCD-SSO.md`, `AGENTS.md` if it mentions Auth0) so
Zitadel is described as the primary provider. Delete this file when done.

---

## Rollback cheat-sheet

Every app cutover is two knobs — flip both back. For the auto-synced apps
(`oauth2-proxy`, `monitoring`) reverting means **`git revert` + push**; for
ArgoCD it means editing the file and re-applying by hand.

| App | Revert issuer to | Restore secret |
|---|---|---|
| oauth2-proxy | `https://arendse.uk.auth0.com/` in `applications/oauth2-proxy/values.yaml` | `oauth2-proxy` |
| Grafana | the 3 `arendse.uk.auth0.com` URLs in `applications/monitoring/values.yaml` | `grafana-auth0` |
| ArgoCD trinity | `https://arendse.uk.auth0.com/` in `clusters/trinity/argocd.yaml` | `argocd-auth0` |
| ArgoCD OCI | `https://arendse.uk.auth0.com/` in `infrastructure/kubernetes/argocd.yaml` | `argocd-auth0` |

The Auth0 client ids live in `infrastructure/identity/auth0.tf`; the secrets are
in your password manager / Auth0 dashboard (never in Git).
