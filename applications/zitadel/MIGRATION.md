# Auth0 → Zitadel migration — resumable checklist

A step-by-step cutover from Auth0 to **Zitadel Cloud** as the single OIDC provider.
Each checkpoint is small, independently deployable, and **reversible**. Do one,
tick it off, and come back later — nothing here has to be done in one sitting.

- **Instance / issuer:** `https://homelab-jj4izt.eu1.zitadel.cloud` (referred to
  below as `<ISSUER>`).
- **Golden rule:** change **one integration at a time**, verify allowed login
  and unauthenticated challenge, and test outside-org denial when an account is
  available. Record unavailable negative tests honestly, never as passes. Keep
  Auth0 and the working Zitadel clients intact until Phase 6; rollback restores
  the previous configuration and Secret.
- **Cluster safety:** only the user runs cluster commands. Before any write,
  select the homelab kubeconfig and confirm `kubectl config current-context`
  matches the checkpoint's named cluster (**trinity** or **oci**). Never use the
  default work GKE contexts.
- ⚠️ **GitOps: pushing to `master` IS deploying.** Both clusters set
  `autoSync: true` in `clusters/*/apps.yaml`, which renders every app with
  `automated: {prune: true, selfHeal: true}`. Two consequences:
  1. **Prepare the destination Secret BEFORE pushing the values change.** For
     CP-1.1, create a separate Zitadel Secret and switch `existingSecret` and the
     issuer together. Keep the Auth0 Secret intact: preparation can safely pause
     before the GitOps rollout. Other checkpoints that replace a Secret in place
     still risk an issuer/credential mismatch if a pod restarts early; do not
     leave those mixed states between sessions.
  2. **Do not deploy these with `helm upgrade` / `./upgrade.sh`.** `selfHeal`
     will revert laptop-side changes to whatever is on `master`. Commit + push
     instead.

  Not everything is auto-synced — **ArgoCD itself is not** (there is no `argocd`
  app in `clusters/*/rendered/`). Ownership still matters: **trinity** is
  bootstrapped manually with Helm (Phase 3); **OCI** is Terraform-managed via
  `infrastructure/kubernetes/argocd.tf` (Phase 4). Do not bypass OCI Terraform
  with a direct Helm upgrade.
- **Zitadel OIDC endpoints** (needed for Grafana, which uses explicit URLs):
  - authorize: `<ISSUER>/oauth/v2/authorize`
  - token: `<ISSUER>/oauth/v2/token`
  - userinfo: `<ISSUER>/oidc/v1/userinfo`

## Progress tracker

Update this as you go so "future you" knows where to resume.

- **Last verified deployment:** CP-3.1 — ArgoCD browser SSO on **trinity**.
  Zitadel login, API-session issuer/email and concrete Application permission
  checks are user-confirmed. The user then replied "all looks good" to the
  application-details, logout/re-login and rollout-success checks. Browser
  cutover is complete on that confirmation; raw Helm/rollout output was not
  supplied. The upgrade command retained chart `9.4.15` / ArgoCD `v3.3.4`.
- **Retirement scope:** finish removing Auth0 before taking up Grafana's optional
  role-sync fix. Its working Zitadel login/manual Admin workaround is accepted;
  general Terraform tidying and unused Zitadel/PoC cleanup are also separate.
- **Latest decision:** trinity ArgoCD browser SSO (CP-3.1) is complete with the
  existing explicit email-admin policy; no new Zitadel roles or broader RBAC
  were needed. OCI ArgoCD browser SSO (CP-4.1) is also complete. Accept working
  Grafana login with the manual Admin workaround. Grafana's configuration mismatch
  and remaining verification stay deferred; do not mark them passed.
  The constant Admin policy remains in code; role mapping and Terraform adoption
  are also deferred. Separate `media`, `pihole`, `argocd` and
  `grafana` projects still admit eligible `arendse` users without individual
  assignments. Self-registration is disabled **according to the user; not
  independently verified**. This remains approved untracked work.
- **Completed:** CP-1.2 — trinity media operational burn-in accepted with
  the evidence limits below. CP-3.1 (trinity ArgoCD), CP-4.1 (OCI ArgoCD)
  and CP-1.1 (production media proxy) are also complete.
  Outside-org denial remains **explicitly deferred, not passed** for this
  single-user setup; revisit it before adding users or changing access policies.
- **Accepted with caveats (trinity / CP-1.2):** current proxy health and fresh
  Sonarr login passed. Asked about stable use/older sessions over the last few
  days, the user replied "I believe so"; stability is based on that recollection,
  not a measured observation period. Session refresh and cross-app SSO were not
  separately verified. Retain Auth0 rollback credentials and the PoC.
  Grafana on **oci** remains usable with manual Admin assignment; CP-2.1's
  automatic role sync and remaining checks are still deferred, not passed.
- **Completed (trinity / CP-3.1):** local-admin fallback, separate
  `argocd-zitadel` Secret, Zitadel login and matching API-session identity are
  user-confirmed. Live RBAC retains the email-admin mapping, empty default,
  `glob` matching and `[email]` scope, with no additional policy CSV entries.
  The initial wildcard CanI request returned `no`; concrete checks for
  `default/trinity-oauth2-proxy` were then reported as `yes`, without RBAC changes.
  The wildcard discrepancy remains unexplained, not a diagnosed role-sync bug.
  Application details, re-login and rollout success are user-confirmed.
  Keep local admin and both Secrets; do not repeat the upgrade or restart.
- **Last completed (CP-6.3):** repository-only Auth0 Terraform retirement. Both
  cluster reference scans returned `[]`; the user-supplied identity state list
  contains only Zitadel. The user assesses the remaining console checks as
  clear; no detailed tenant log/provider inventory was supplied. See Phase 6
  for scope and evidence limits. Auth0 provider/variables/lock entry and obsolete
  import files/script are removed locally; all Zitadel resources remain intact.
  The user reported **"No changes. Your infrastructure matches the configuration."**
  from the full identity plan. No Terraform apply is needed.
- **Paused at the user's request:** create a local Git checkpoint for CP-6.3;
  resume live cleanup next session at CP-6.2. All four retained Auth0 Secrets,
  clients and the tenant remain untouched. Before deleting anything, recheck
  consumers, obtain explicit approval and confirm the target cluster context.
  Verify migrated logins after Secret cleanup; retire Auth0 clients/tenant only
  with separate approval afterward. No push or live deletion is authorized.
- **Completed (oci / CP-4.1):** local-admin login, deployment/OIDC/RBAC
  preflight, context `oci` and creation of `argocd-zitadel` are user-confirmed.
  `argocd-auth0` is retained. Local values now pair the Zitadel issuer/name with
  both new Secret references; RBAC is unchanged. OCI ArgoCD is Terraform-owned:
  the prior direct Helm command is withdrawn. The user's targeted plan passed
  review: **0 to add, 1 to change, 0 to destroy**, only `helm_release.argocd`
  in place. The values diff changes OIDC name/issuer and both Secret references
  plus comments; RBAC, ingress and chart version are unchanged. The user then
  reported **Apply complete: 0 added, 1 changed, 0 destroyed**, followed by a
  successful Zitadel login. User Info shows username/group
  `greg.arendse@gmail.com` and the expected Zitadel issuer, matching the explicit
  admin mapping. The user then supplied `{"value":"yes"}` from the same-session
  read-only `CanI` check for `applications/sync/*/*`, confirming that permission
  without performing a sync. The user subsequently confirmed rollout health,
  application access and re-login with "All looks good". Do not repeat apply or
  restart. Keep local admin and both Secrets. The user approved a local checkpoint
  commit; no push is authorized.
- **Skipped by user (oci / CP-5.1):** Pi-hole has no native OIDC/SAML integration;
  the proposed proxy would add an edge gate, not replace its local login.
  Preflight on 2026-09-27 confirmed Pi-hole `1/1`, direct ingress to
  `pihole-web:80`, native login, and no proxy Deployment, Service or credentials
  Secret. No subsequent Secret creation or deployment has been reported.
  Keep that working setup and DNS unchanged; the Secret-creation command and
  proxy/ingress rollout are withdrawn. OCI's in-scope login cutovers are finished
  with Grafana's accepted manual-Admin workaround, not a fully verified role sync.
  **Enrollment cleanup complete:** commit `7a84e65` was pushed with approval,
  removing only the proxy enrollment/generated Application and updating two docs.
  The user then confirmed context **oci**, deleted only
  `oci-pihole-zitadel-oauth2-proxy`, and supplied successful deletion output.
  Post-cleanup: `oci-pihole` is **Synced/Healthy**, deployment `pihole` is **1/1**,
  and the user reports Pi-hole is working. No root sync/prune was needed.
  These are user-supplied checks, not agent cluster access. Unpublished
  proxy/ingress work and unused Terraform identity objects remain separate
  cleanup candidates; do not accidentally publish them.
- **Deferred Grafana follow-up:** diagnose the discrepancy between
  `applications/monitoring/values.yaml`, ArgoCD's rendered configuration and
  effective Grafana settings, including environment overrides and role sync.
  The user suspects incomplete `infrastructure/identity/` and `kubernetes/`
  configuration and wants cleanup after migration; this is a hypothesis, not a
  confirmed cause or fix. The constant Admin rule is a Grafana Helm setting,
  not a Zitadel role assignment. Manual Admin may be overwritten on a later
  OAuth login if role sync takes effect. Keep the local admin fallback.
  Live settings, automatic Admin assignment, dashboard/re-login/refresh checks
  remain deferred, not passed; see CP-2.1. Deleted/current SSO numeric IDs are
  unknown; do not assume user `2`'s fate.
- **Current commit IDs:** `0fc08bd` (identity/docs) and `884fc5f` (single-file
  cutover) in the current Git history. Their earlier local IDs were `e6eeabc`
  and `fb35bde`. The agent compared the production values at `884fc5f` and
  `fb35bde`: identical. The synced revision has the Zitadel issuer and
  `existingSecret: oauth2-proxy-zitadel-media`.
- **Media rollback:** retain the original Auth0 `oauth2-proxy` Secret; revert only
  current cutover commit `884fc5f` if needed, with a user-controlled push. An
  exported backup was explicitly declined. The agent made the two approved
  local media commits; the user pushed them. For Grafana, the agent committed
  and pushed `caa05c9` (docs) and `6cced05` (values) with explicit approval.
  The agent ran no cluster commands or live Terraform plan/apply.

| # | Checkpoint | Done |
|---|---|:--:|
| 0.1 | Apply `zitadel.tf` (project + 4 OIDC apps) | ☑ |
| 0.2 | Capture the generated client ids/secrets | ☑ |
| 0.3 | (Historical) Dress-rehearse the original `homelab` client | ☑ |
| 0.4 | Agree project boundaries and credential ownership | ☑ |
| 0.5 | Reviewed live plan: 10 additions, 0 changes/destroys (no apply) | ☑ |
| 0.6 | Applied 10 additions; post-apply checks confirmed by user | ☑ |
| 0.7 | PoC login and smoke checks passed; outside-org test deferral accepted | ☑ |
| 1.1 | Production Zitadel login, ArgoCD health and rollout verified | ☑ |
| 1.2 | Operational burn-in accepted: current health/Sonarr login passed; stability based on user recollection; refresh/cross-app tests unverified; retain rollback | ☑ |
| 2.1 | Grafana on OCI: login works; manual Admin workaround accepted; automatic role sync/config mismatch and remaining verification deferred | ☐ |
| 3.1 | Complete: trinity Zitadel browser login/identity, concrete Application permissions, application details/re-login/rollout user-confirmed; RBAC unchanged | ☑ |
| 4.1 | Complete: OCI Terraform apply, Zitadel browser login/issuer/email, CanI sync permission, rollout/application access/re-login user-confirmed; test gaps recorded below | ☑ |
| 5.1 | SSO skipped; enrollment cleanup published in `7a84e65`, live Application deleted, Pi-hole health/access user-confirmed | — |
| 6.1 | Optional later cleanup: tear down the Zitadel PoC rig (not an Auth0-retirement blocker) | ☐ |
| 6.2 | Deferred to next cleanup session: four Auth0 runtime Secrets retained; deletion approval still required | ☐ |
| 6.3 | Auth0 Terraform/provider removed; local validation passed and user-run plan reports No changes; repository checkpoint | ☑ |
| 6.4 | Optional later cleanup: superseded Zitadel projects/clients (not an Auth0-retirement blocker) | ☐ |
| 6.5 | Update docs to make Zitadel the primary | ☐ |

## Decisions log

Context worth remembering between sessions.

- **Auth0 Terraform is commented out, not imported.** The `auth0_*` resources
  were only ever *pending* import and never entered state, so Terraform does not
  manage them and cannot destroy them. The live Auth0 tenant is untouched and
  remains the rollback path. `imports-pending.tf` was never completed on purpose
  (adopting the tenant/database connection would be throwaway work).
- **Existing layout (already applied):** the `arendse` org contains `ZITADEL`
  (built-in system project — do not touch), `trinity` (hand-made registrations;
  the presumed Pi-hole consumer was not present at CP-5.1 preflight), and Terraform-managed `homelab`
  (four legacy clients; its `oauth2_proxy` client is now the PoC rollback path).
  Creating another org was rejected because it requires **IAM_OWNER**.
- **Target registrations created (CP-0.6 applied; only the PoC migrated so far):**
  keep `arendse`, but
  group projects by integration, not cluster: `media`, `pihole`, `argocd`,
  `grafana`. Each app/proxy deployment gets its own OIDC credentials, including
  separate media production/PoC clients and two native ArgoCD clients. See
  CP-0.4–0.7. Preserve all existing clients until their replacements are tested
  and their consumers migrated.
- **Pi-hole SSO skipped (2026-09-27).** The user does not want a proxy-only
  login gate because Pi-hole lacks native OIDC/SAML integration. Keep Pi-hole's
  native authentication and direct ingress; do not deploy the prepared proxy.
  The already-created Terraform `pihole` project/client is a cleanup candidate,
  not authorization for a destroy. ArgoCD continues using native OIDC.
- **Secret provisioning remains undecided.** This design does not add Terraform
  management of Kubernetes Secrets. A project defines the access boundary (and
  can own roles/assignments later); an OIDC application owns client credentials;
  a Kubernetes Secret stores those credentials for its consumer. The management
  PAT is never a workload secret.
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
- **New project IDs** from the user's successful CP-0.6 apply output:

  | Project | ID |
  |---|---|
  | `argocd` | `390167990911547596` |
  | `grafana` | `390167990928259276` |
  | `media` | `390167990911482060` |
  | `pihole` | `390167990911416524` |

  New client IDs/secrets remain in the `zitadel_sso_*` outputs. The user
  confirmed the output-key and console-grouping checks; no client secrets are
  stored here.
- **Client IDs are numeric, with no `@project` suffix.** The provider populates
  `client_id` straight from the API (`GetClientId()`), so use output values
  verbatim. These are the **original `homelab` clients**, not the planned
  replacement clients:
  `oauth2_proxy` = `389307350953112302`, `grafana` = `389307350969758446`,
  `argocd_trinity` = `389307350969838839`, `argocd_oci` = `389307350953061623`.
  Read the matching secrets from Terraform state; never commit them or include
  them in this checklist. Workload copies belong in Kubernetes Secrets.
- **Both clusters auto-sync.** `clusters/trinity/apps.yaml` and
  `clusters/oci/apps.yaml` both set `autoSync: true`, so every rendered app gets
  `prune: true, selfHeal: true`. Pushing to `master` deploys, and manual
  `helm upgrade` / `./upgrade.sh` gets reverted. `oauth2-proxy` (trinity) and
  `monitoring` (OCI) are both enrolled; **ArgoCD itself is not**. OCI ArgoCD
  changes go through Terraform; trinity ArgoCD uses its manual Helm workflow.
- **CP-0.3 verified the original credentials; CP-0.7 now verifies the new client.**
  The PoC on **trinity** has moved from the `homelab` client to `media_poc` in
  the `media` project. Rollout and fresh login passed per the user; outside-org
  denial is not yet demonstrated. Keep the `homelab` client for rollback.
  The hand-made PoC app in the `trinity` project is no longer used by that rig;
  retain it until CP-6.4. Its previous Secret backup was written to
  `/tmp/oauth2-proxy-zitadel.bak.yaml` (ephemeral; do not rely on it).
- **Legacy access stays unchanged.** `zitadel_project.homelab` keeps
  `has_project_check = false` and `project_role_check = false`; both proxies
  allow all email domains. Those legacy settings are not an org-only boundary.
- **Temporary org-wide login is approved for the new projects.** All use
  `org_id = var.zitadel_org_id`, `has_project_check = true`,
  `project_role_check = false` and `project_role_assertion = true`. With no
  project grants to external orgs, login is limited to users in `arendse`, but
  does not require project roles or per-user assignments. The initial rollout
  added no role/assignment, project-grant, policy or Kubernetes-provider resources.
  CP-2.1 defers Grafana role/grant adoption again; console roles/grants remain
  untouched and roles are not a login requirement. Outside-org denial remains
  deferred and unverified, not a demonstrated access-boundary test.
- **Self-registration must remain disabled.** The user reports it is disabled;
  this has not been independently verified and Terraform does not manage it.
  Future users added to `arendse` automatically gain login to all four projects.
  **Follow-up: tighten access before adding users, re-enabling signup or granting
  external orgs access.** CP-2.1's temporary Grafana policy will make **all current
  and future admitted users Main Org Admin** on login. This is not server
  GrafanaAdmin and does not change ArgoCD RBAC. Replace the constant with narrower
  mapping and review per-project admission before expanding access.
- **Grafana: login works; manual Admin workaround accepted, role-sync fix deferred.** The
  user chose “making everyone admin for now” instead of role mapping. Minimal
  Viewer provisioning (`66ed660`) and the intermediate native-role mapping plan
  are superseded by `role_attribute_path: "'Admin'"` under generic OAuth.
  Publication and rollout at `6cced05` are user-confirmed, but the user reports
  the Admin configuration has not taken effect and manually assigned Admin.
  They explicitly chose to defer investigation and continue migration.
  The intended expression ignores role claims: all admitted users should get
  Main Org Admin on login when effective, never a server-admin grant. That
  behavior has not been demonstrated in the live deployment.
  Standard scopes, OAuth signup on, local signup off, lookup off and local
  `auto_assign_org_role=Viewer` stay unchanged; OAuth overrides Viewer.
  Role sync overwrites manual org roles; local admin and anonymous access are
  unaffected. No account aliases, hardcoded email or personal `sub`.
  Role mapping and Terraform adoption are **deferred again**; no grant ID or
  Terraform action is needed. Cleanup is only the agent's untracked, unapplied
  `grafana-roles.tf` draft and its header reference; no live plan/import/apply
  was ever run for that draft, and console roles/grants are untouched.
  The user deleted a conflicting account themselves; the agent deleted none.
  Deleted/current SSO IDs are unknown, including whether user `2` still exists.
  Keep local admin `1` and old Secrets. No further deletion, automatic merging
  or DB surgery. The declined DB backup is settled; rollback cannot recover
  deleted metadata. Local-admin browser login is confirmed; automatic Admin-role
  verification, dashboard access and fresh re-login/refresh are deferred, not
  passed. See CP-2.1 for the configuration/role-sync investigation and later
  least-privilege mapping/adoption follow-up.

---

## Phase 0 — Provider groundwork

> CP-0.1–0.3 are completed historical steps for the original `homelab` layout.
> Do not replay them to implement the new design; resume at CP-0.5.

### CP-0.1 — Apply the Zitadel Terraform
Creates the `homelab` project and the 4 OIDC apps inside the **existing**
`arendse` org. Production redirect URIs are already registered in `zitadel.tf`,
so nothing to click in the console.

First set the instance domain and org ID in `.auto.tfvars` (git-ignored):

```hcl
# The INSTANCE domain — not the org name. Same host as the oidc-issuer-url the
# working media PoC proxy uses.
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
- Pi-hole stays unchanged. CP-5.1 later confirmed it was serving its own login
  directly, not using the presumed `trinity` project client.

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

### CP-0.3 — (Historical) Dress-rehearse the original client (trinity)

This completed rehearsal tested the original credentials only. `zitadel.tf`
registered **both** callbacks on the `oauth2-proxy` app, including the PoC one
(`https://auth-zitadel.<base_domain>/oauth2/callback`). So you can point the
isolated PoC proxy at the **Terraform-managed** credentials and exercise the
exact same code path CP-1.1 will use — but against the throwaway `zitadel-echo`
app instead of every `*arr` app.

First confirm the PoC rig is still running (its rendered manifests were only
committed recently, so Argo may never have deployed it):

```bash
kubectl -n oauth2-proxy-zitadel get deploy,ingress
```

For the new design, CP-0.7 is required before CP-1.1. If the rig is absent,
restore it through trinity's GitOps configuration, not a manual Helm install.

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


### CP-0.4 — Agree project boundaries and credential ownership ✅

**Agreed target inside the existing `arendse` organization:**

| Project | OIDC applications / consumers | Initial access boundary |
|---|---|---|
| `media` | Shared media proxy on **trinity**; a separate temporary PoC client | All `arendse` users; same proxy policy for protected media apps |
| `pihole` | Dedicated Pi-hole integration on **oci** | All `arendse` users initially; independent project/client for later restrictions |
| `argocd` | Separate native OIDC clients for **trinity** and **oci** | All `arendse` users may log in; each ArgoCD instance enforces its own RBAC |
| `grafana` | Grafana on **oci** | All `arendse` users may log in; Grafana permissions remain separate |

- A **project is not a secret**: applications in a project share its access
  policy and any future roles/assignments. Each OIDC application has its own
  client ID/secret, stored only where its consumer needs them. Do not share one
  credential across a cluster.
- Initial policy: `has_project_check = true`, no external-org project grants,
  `project_role_check = false`, `project_role_assertion = true`. All org users
  are allowed without initial roles or assignments; role assertion does not
  grant permissions or require a role. Self-registration must stay disabled.
  The initial decision kept app permissions separate from login. CP-2.1 now
  proposes a temporary Grafana-only exception: Main Org Admin for every admitted
  login; ArgoCD RBAC is unchanged. Per-project restrictions and narrower Grafana
  mapping must be revisited before onboarding, opening signup or external grants.
- Sonarr and its peers currently share one proxy policy. Per-media-app access
  would require separate enforcement, not just more Zitadel registrations.
  Proxy protection applies only to requests routed through it, not direct
  access to the underlying services.
- Separate projects/clients still share Zitadel SSO. They do not need shared
  client secrets or shared proxy cookies to avoid repeated password entry.

**Done:** architecture agreed and documented. CP-0.4 itself made no Terraform
or live changes; additive implementation and plan review are complete in CP-0.5.

### CP-0.5 — Prepare the additive Terraform plan (no apply)

**Complete:** reviewed the live plan supplied by the user. The subsequent
apply is recorded under CP-0.6. **Target:** Zitadel Cloud only; no writes to
**trinity** or **oci**.

**Local validation:** `terraform fmt -check`, `terraform validate` and the scoped
`git diff --check` passed. These do not verify the live plan or login behavior.

1. The additive code in `infrastructure/identity/zitadel.tf` preserves
   `zitadel_project.homelab` and `zitadel_application_oidc.app` at their current
   addresses with their existing settings. New `zitadel_project.sso` uses
   `for_each` keys `media`, `pihole`, `argocd`, `grafana`, all owned by
   `var.zitadel_org_id`. Each sets `has_project_check = true`,
   `project_role_check = false`, `project_role_assertion = true`. No external-org
   project grants, roles, per-user assignments, policy resources or Kubernetes
   providers are added.
2. New `zitadel_application_oidc.sso` has six keys. Callbacks below use the
   default `base_domain = arendse.nom.za`; existing Grafana/ArgoCD callbacks and
   logout URLs are retained. Production media and PoC have separate credentials
   and callbacks:

   | Client/output key | Project | Consumer / cluster | Callback |
   |---|---|---|---|
   | `media` | `media` | Production media proxy / **trinity** | `https://auth.arendse.nom.za/oauth2/callback` |
   | `media_poc` | `media` | Isolated PoC proxy / **trinity** | `https://auth-zitadel.arendse.nom.za/oauth2/callback` |
   | `pihole` | `pihole` | Pi-hole proxy / **oci** | `https://pihole.arendse.nom.za/oauth2/callback` |
   | `grafana` | `grafana` | Grafana / **oci** | `https://grafana.arendse.nom.za/login/generic_oauth` |
   | `argocd_trinity` | `argocd` | Native ArgoCD OIDC / **trinity** | `https://trinity.argocd.arendse.nom.za/auth/callback` |
   | `argocd_oci` | `argocd` | Native ArgoCD OIDC / **oci** | `https://argocd.arendse.nom.za/auth/callback`, `https://oci.argocd.arendse.nom.za/auth/callback` |

3. `outputs.tf` adds `zitadel_sso_project_ids` (four project keys),
   `zitadel_sso_client_ids` and `zitadel_sso_client_secrets` (six client keys
   above). Both client outputs are sensitive. Legacy `zitadel_project_id`,
   `zitadel_oidc_client_ids` and `zitadel_oidc_client_secrets` remain unchanged
   and still refer to `homelab`; CP-0.1–0.3 intentionally retain those recipes.
4. **Reviewed:** the user ran the live plan using the existing backend/state.
   To recheck from the repository root before proceeding:

   ```bash
   terraform -chdir=infrastructure/identity plan -input=false
   ```

   The supplied plan matches: **10 to add (4 projects + 6 clients), 0 to change,
   0 to destroy**, all in org `380143417033860850`. The three `zitadel_sso_*`
   outputs are additions; legacy resources and outputs are unchanged. If a later
   plan differs, review it again before applying. Do not share secrets or commit
   plan files. The agent does not run a live plan or apply.

**Completion gate passed:** additions-only live plan and client/consumer mapping
reviewed. CP-0.6 is now available. No apply, issuer push or Secret swap has been
performed as part of CP-0.5.

### CP-0.6 — User applies new projects/clients and verifies outputs (no cutover)

**Complete based on user confirmation:** apply succeeded, and the user replied
“Looks good” after the post-apply plan, output-key and console-grouping checks
were requested. The agent did not independently run them. **Target:** Zitadel
Cloud only; this checkpoint did not switch workloads on **trinity** or **oci**.

1. **Applied:** the user reported `Apply complete! Resources: 10 added,
   0 changed, 0 destroyed.` All four project IDs were returned (see Decisions
   log), along with sensitive client outputs. Do not repeat the creation step.
   Keep the temporary org-wide policy: no external project grants, roles or
   initial assignments. Self-registration must remain disabled; Terraform does
   not enforce it. Leave all workload Secrets unchanged.
2. Confirm each new client belongs to its intended project, with the correct
   redirect URIs. Verify `zitadel_sso_project_ids` against the console and check
   both new client output maps contain all six keys listed in CP-0.5:

   ```bash
   terraform -chdir=infrastructure/identity output -json zitadel_sso_project_ids
   terraform -chdir=infrastructure/identity output -json zitadel_sso_client_ids | jq 'keys'
   terraform -chdir=infrastructure/identity output -json zitadel_sso_client_secrets | jq 'keys'
   ```

   Read individual IDs/secrets privately when needed and verify the client IDs
   against the console. `-json` exposes sensitive output values; never paste
   secrets into this checklist, logs or Git.
3. Verify the future credential recipes below against those applied outputs.
   They now use `zitadel_sso_client_ids` / `zitadel_sso_client_secrets`; they are
   **prepared recipes, not evidence of apply or permission to cut over**. Keep
   legacy outputs available for rollback. Do not change live Secrets yet.
4. From the repository root, confirm the post-apply plan is clean:

   ```bash
   terraform -chdir=infrastructure/identity plan -input=false
   ```

   Expected: **No changes.** Share any differences/errors before proceeding;
   do not apply unexpected changes.

**Completion gate passed on user confirmation:** the new registrations and
post-apply checks are accepted. No workload Secret swaps have been reported;
CP-0.7 comes next, not production cutover.
**Rollback:** leave the new unused resources in place and continue on the old
clients; no workload rollback is needed.

### CP-0.7 — Rehearse the media access policy (trinity)

**Complete with an accepted test deferral. Target cluster: trinity.**
The user confirmed context `trinity` and the healthy PoC preflight, then reported
“Done, and its working” after the backup, `media_poc` credential patch, restart
and fresh-browser login instructions. The new client is now in use by the PoC;
no production or OCI credential changes were part of these steps.

**Recorded results:**
- Preflight: deployment `1/1`, Ingress `auth-zitadel.arendse.nom.za` at `192.168.0.50`.
- PoC rollout and fresh-browser Zitadel login to the echo response: passed per user.
- Outside-org denial: **not tested**; no outside-org test account identified in
  this single-user setup. The user explicitly accepted deferring this test for
  now. Revisit it before adding users or changing registration/access policies.
- Normal Sonarr and Pi-hole access: confirmed working by the user.
- Rollback backup: keep the private `zitadel-poc-backup.*` directory created
  locally. Its exact path and contents have not been shared; do not commit it.

The completed swap instructions below remain as a reference, **not a request to
repeat the swap**. Only the user runs cluster commands; re-confirm the context
if resuming in another session. Commands run from the repository root in the
same terminal and explicitly target `trinity`. **Stop on any error.**

1. Back up the complete working Secret to a private directory outside Git:

   ```bash
   umask 077
   BACKUP_DIR=$(mktemp -d "$HOME/zitadel-poc-backup.XXXXXX")
   kubectl --context=trinity -n oauth2-proxy-zitadel get secret oauth2-proxy-zitadel -o json > "$BACKUP_DIR/secret.json"
   ```

   Note the directory path (`printf '%s\n' "$BACKUP_DIR"`) for rollback. The
   backup contains credentials: do not paste its contents or commit it. Keep
   it until the rehearsal passes; it is not in an automatically cleaned temp dir.
2. Read Terraform outputs privately through a pipe and patch only the PoC
   client ID/secret. This rejects missing/empty credentials, keeps the existing
   cookie secret and other Secret fields, and does not delete the Secret:

   ```bash
   terraform -chdir=infrastructure/identity output -json |
     jq -e '{stringData: {
       "client-id": .zitadel_sso_client_ids.value.media_poc,
       "client-secret": .zitadel_sso_client_secrets.value.media_poc
     }} | if all(.stringData[]; type == "string" and length > 0)
          then . else error("Missing media_poc credentials") end' |
     kubectl --context=trinity -n oauth2-proxy-zitadel patch secret oauth2-proxy-zitadel --type=merge --patch-file=/dev/stdin
   ```

   The pipe must stay intact; do not print the raw Terraform output or enable
   shell tracing. Use `media_poc`, never `media` or legacy `oauth2_proxy`.
3. Only after the patch succeeds, restart and wait for the PoC deployment:

   ```bash
   kubectl --context=trinity -n oauth2-proxy-zitadel rollout restart deployment/oauth2-proxy-zitadel
   kubectl --context=trinity -n oauth2-proxy-zitadel rollout status deployment/oauth2-proxy-zitadel --timeout=120s
   ```

   The issuer stays unchanged. No production `oauth2-proxy` or OCI changes.
4. Test `https://zitadel-echo.arendse.nom.za` in fresh browser sessions:
   - A user in `arendse` reaches the echo app, without project role assignments.
   - An unauthenticated visitor is challenged for login, not given the echo app.
   - A user outside `arendse` is denied when an outside-org account is available
     to test. Do not add an external project grant to make the test possible.
   Existing cookies are not proof. A within-org user without a media role is
   **allowed**, not a negative test under this temporary policy.
5. Record actual results here, including any unavailable negative test and why;
   do not call an unrun test a pass. Confirm no external grants and that
   self-registration remains disabled. Confirm production media/Pi-hole still
   work. The PoC verifies the project policy and proxy flow; the separate
   production client's end-to-end login is verified during CP-1.1.

**Completion gate passed with accepted deferral:** rollout, fresh login and
normal Sonarr/Pi-hole access are confirmed by the user. Outside-org denial is
explicitly deferred, not demonstrated. CP-1.1 is now available as a separate
checkpoint; this confirmation does not itself change production credentials or
authorize a commit/push. Retain the rollback credentials and record any future
unavailable app-RBAC tests just as explicitly.
**Rollback (trinity):** with `BACKUP_DIR` set to the directory created above,
restore its data and restart only the PoC proxy. Stop if restoring the data fails:

```bash
jq '{data: .data}' "$BACKUP_DIR/secret.json" |
  kubectl --context=trinity -n oauth2-proxy-zitadel patch secret oauth2-proxy-zitadel --type=merge --patch-file=/dev/stdin
kubectl --context=trinity -n oauth2-proxy-zitadel rollout restart deployment/oauth2-proxy-zitadel
kubectl --context=trinity -n oauth2-proxy-zitadel rollout status deployment/oauth2-proxy-zitadel --timeout=120s
```

Keep the old `homelab` client available for this rollback.

---

## Phase 1 — Edge proxy (biggest win: every `*arr` app at once)

> **Preparation complete:** CP-0.5–0.7 are complete on the recorded user
> confirmations, including accepted deferral of the outside-org denial test.
> The recipes below use the new `zitadel_sso_*` outputs. Start with CP-1.1 on
> **trinity**, one integration at a time; production-client login still needs
> its own verification. No production Secret swap, commit or push has been
> performed by completing the PoC. Coordinate each rollout explicitly.

### CP-1.1 — Cut over `oauth2-proxy` (trinity)

**Complete. Target cluster: trinity.** Before cutover, the user confirmed one
ready replica, the Auth0 issuer and Secret `oauth2-proxy`. The new Secret was
created and the paired values change was committed/pushed. Current Git history
identifies preparation commit `0fc08bd` and single-file cutover `884fc5f`.

**Recorded verification:**
- Fresh incognito Zitadel login returning to Sonarr: working per user.
- ArgoCD `trinity-oauth2-proxy`: `Synced`, `Healthy`, revisions `10.7.0` and
  `884fc5f0428c8f6d580b4e944d3257c08d2fd6ed`, from the user's command output.
- Deployment: `deployment "oauth2-proxy" successfully rolled out`, from user output.
- Values at the synced Git revision: agent verified the Zitadel issuer and
  `existingSecret: oauth2-proxy-zitadel-media`. They are identical to the values
  in the original local cutover commit `fb35bde`; the different hash is not a
  configuration mismatch. Use current commit `884fc5f` for rollback.
- Outside-org denial: explicitly deferred by the user, not tested.

**The user explicitly chose to skip the exported Auth0 backup.** Rollback relies
on retaining the original Secret; if it is lost, its credentials must be
recovered separately. The agent did not run cluster commands or push.

The steps below are the completed cutover record, **not instructions to repeat
it**. CP-1.2's acceptance and evidence limits are recorded below. Only the user
runs cluster commands; confirm the context
again if troubleshooting or rolling back in another session.

**Safer rollout:** do not overwrite or delete the Auth0 `oauth2-proxy` Secret.
Create `oauth2-proxy-zitadel-media` in namespace **`oauth2-proxy`**, then switch
both `config.existingSecret` and the issuer through GitOps. This is separate
from the PoC namespace `oauth2-proxy-zitadel`. The running production pod keeps
using Auth0 until the rollout; an early pod restart still uses matching Auth0
settings. It is safe to pause after staging the new Secret, before pushing.

1. **Production preflight is confirmed; retain Auth0's Secret.** When resuming
   in a new session, confirm the current context is `trinity` before any write:

   ```bash
   kubectl config current-context
   kubectl --context=trinity -n oauth2-proxy get deploy,ingress
   ```

   Inspect the production deployment without printing credential values:

   ```bash
   kubectl --context=trinity -n oauth2-proxy get deployment oauth2-proxy -o json |
     jq '{ready: .status.readyReplicas,
       issuer: [.spec.template.spec.containers[].args[]? | select(startswith("--oidc-issuer-url="))],
       secrets: ([.spec.template.spec.containers[].env[]?.valueFrom.secretKeyRef.name // empty] | unique)}'
   ```

   Expect a healthy deployment, the Auth0 issuer and Secret `oauth2-proxy`.
   If anything differs, stop and inspect before proceeding. The exported backup
   was declined; **do not delete or overwrite the existing Secret**.
2. **Stage the new Secret; do not restart the deployment.** Use the production
   output key `media`, not `media_poc` or legacy `oauth2_proxy`. Generate a new
   cookie key so Auth0 sessions will not be carried into the Zitadel rollout:

   ```bash
   {
     terraform -chdir=infrastructure/identity output -json
     openssl rand -base64 32 | tr -- '+/' '-_' | jq -R '{cookie_secret: .}'
   } |
     jq -se 'if length != 2 then error("Expected Terraform outputs and cookie key") else {
       apiVersion: "v1", kind: "Secret", type: "Opaque",
       metadata: {name: "oauth2-proxy-zitadel-media", namespace: "oauth2-proxy"},
       stringData: {
         "client-id": .[0].zitadel_sso_client_ids.value.media,
         "client-secret": .[0].zitadel_sso_client_secrets.value.media,
         "cookie-secret": .[1].cookie_secret
       }
     } end | if all(.stringData[]; type == "string" and length > 0)
                and (.stringData["cookie-secret"] | length == 44)
              then . else error("Missing media credentials or invalid cookie key") end' |
     kubectl --context=trinity -n oauth2-proxy create -f -
   ```

   The two JSON inputs stay in the pipe, not files or command-line arguments.
   Missing inputs/credentials or an invalid cookie-key length abort the filter.
   Keep the pipeline intact and shell tracing off. `create` deliberately fails
   if the Secret already exists: investigate rather than overwrite it blindly.
   Confirm creation before authorizing a commit/push. **Safe stopping point:**
   the new Secret is unused and Auth0's Secret remains untouched.
3. **Deploy the paired values change only when ready.** Local
   `applications/oauth2-proxy/values.yaml` already selects:

   ```yaml
   config:
     existingSecret: oauth2-proxy-zitadel-media
   extraArgs:
     oidc-issuer-url: https://homelab-jj4izt.eu1.zitadel.cloud
   ```

   Keep the production callback `https://auth.arendse.nom.za/oauth2/callback`.
   With the new Secret confirmed, review the values diff and the entire unpushed
   commit set. Keep unrelated working-tree changes out; do not use `git add -A`.
   Obtain explicit approval before the agent commits anything; the user pushes.
   Record the already-applied identity Terraform and migration docs in a separate
   preparation commit so a fresh checkout retains the new resource definitions.
   The deployment commit should contain only this values file, so it can be
   reverted independently. **Pushing to master deploys.**

   ArgoCD Application **`trinity-oauth2-proxy`** uses chart `10.7.0` with these
   values from `master`. Do not run a manual Helm upgrade: `selfHeal` reverts it.
   After pushing, the user checks on **trinity**:

   ```bash
   kubectl --context=trinity -n argocd get application trinity-oauth2-proxy
   ```

   Re-run the deployment summary from step 1. Wait until it shows the **Zitadel
   issuer and `oauth2-proxy-zitadel-media` Secret** before checking rollout:

   ```bash
   kubectl --context=trinity -n oauth2-proxy rollout status deployment/oauth2-proxy --timeout=120s
   ```

   Checking rollout too early can report the old Auth0 deployment as healthy.
   The paired pod-template change triggers the rollout; no early manual restart.
4. **Verify:** a fresh browser session at `https://sonarr.arendse.nom.za` should
   require Zitadel authentication, then reach Sonarr. Confirm other protected
   media apps still work. The new cookie key requires users to log in again.
   No project role is required; outside-org denial remains explicitly deferred
   for the single-user setup, not passed. Pi-hole/OCI are not part of this change.

**Completion gate passed:** staging, paired values commit/push, fresh production
login, ArgoCD `Synced` / `Healthy` at the verified cutover revision and successful
rollout are confirmed. Subsequent CP-1.2 acceptance is recorded below; no
further auth changes are needed for this checkpoint.

**Rollback:** revert dedicated values commit `884fc5f` and have the user push. This
restores both the Auth0 issuer and `existingSecret: oauth2-proxy`, whose original
credentials and cookie key were never changed. Wait for those references to
appear in the deployment and the rollout to finish on **trinity**. No Secret
rewrite is needed for normal rollback. The exported backup was explicitly
skipped, so this depends on the original Secret remaining available. Before the
deployment push, simply leave the new unused Secret in place and stop—there is
no runtime change to undo.

### CP-1.2 — Burn-in

**Operational burn-in accepted with caveats. Target cluster: trinity.** No
rollout or configuration change was made for this checkpoint.

**Current checks — user-supplied evidence:**

- ArgoCD Application `trinity-oauth2-proxy`: **Synced / Healthy**.
- Deployment `oauth2-proxy`: **1/1** ready, up-to-date `1`, available `1`.
  Deployment age alone does not establish the duration of Zitadel stability.
- Sonarr redirects to Zitadel, then to Sonarr's own login page. The user
  confirmed "Yes, login works" after signing in with Sonarr credentials.
  This verifies the fresh-login flow through both layers; the proxy protects
  access but does not replace Sonarr's native authentication. Both stay enabled.
- Asked whether existing sessions had remained usable over the last few days
  without login loops or unexpected failures, the user replied **"I believe so"**.
  Accept this as the user's recollection for operational sign-off, not as a
  controlled multi-day test or direct observation of token/session refresh.

**Remaining evidence gaps:** a separate session-refresh test, cross-app SSO
check and precise observation interval were not supplied. These are not marked
passed. Outside-org denial remains explicitly deferred for the single-user
setup. Continue normal use and revisit this checkpoint if failures appear.

Keep the original Auth0 `oauth2-proxy` Secret, registrations and PoC intact.
Closing this operational checkpoint does **not** authorize decommissioning;
consumer/rollback review and remaining verification are separate follow-ups.

---

## Phase 2 — Grafana

> Grafana runs on **oci**, managed by ArgoCD Application `oci-monitoring`
> (`clusters/oci/rendered/monitoring.yaml`), using `kube-prometheus-stack`
> **69.0.0** with auto-sync. Stage a separate Secret before a paired values
> change, as in CP-1.1. Keep the existing `grafana-auth0` Secret intact.

### CP-2.1 — Cut over Grafana

**Login usable with manual Admin; role-sync fix deferred. Target cluster: oci.**
After removing a conflicting Grafana account themselves, the user confirmed SSO
and local-admin browser login. The pre-policy SSO profile was **Main Org
Viewer; Grafana Admin No**. The approved policy is intended to grant every
admitted Zitadel login **Main Org Admin**, with mapping deferred. Documentation (`caa05c9`) and
values (`6cced05`) were committed separately and pushed with approval. User
output confirms `oci-monitoring` is `Synced` / `Healthy` at chart `69.0.0`, Git
revision `6cced051b786fac7125b2085ab28db911b1aac1c`, and a successful
`monitoring-grafana` rollout. Subsequently, the user reported working login but
that the Admin configuration had not taken effect; they manually set their user
to Admin. **The user accepts this workaround and defers the fix to continue
with CP-3.1.** Automatic role sync and remaining checks are not passed; this
checkpoint is not fully verified. Media burn-in is separately accepted with
caveats in CP-1.2; that does not resolve these Grafana follow-ups.

#### A. Verified preflight and short history

- User output confirmed Grafana `11.4.1`, one ready replica on OCI; the original
  Auth0 deployment used `grafana-auth0` and separate `grafana-admin-credentials`.
- HTTP Basic `GET /api/user` verified local admin **user `1`**, login `admin`,
  `isGrafanaAdmin: true`. **Local-admin browser login is now user-confirmed**;
  do not reset its password or assume the Secret resets a persisted password.
- The earlier strict email-based rule failed with “IdP did not return a role
  attribute”. User `2` alias/linking plans are superseded; lookup stays off.
- The user removed a conflicting Grafana account and login now works. They
  inspected the personal SSO profile: **Gregory Arendse**, email/login
  **`greg.arendse@gmail.com`**, synced by **Generic OAuth**, **Main Org Viewer**,
  **Grafana Admin No**. Neither the deleted user's numeric ID nor the current
  SSO numeric ID is known; do not infer user `2` was retained, deleted or replaced.
- User confirmed OCI context and creation of `monitoring/grafana-zitadel` with
  the dedicated Grafana client credentials. Staging is done: do not recreate it
  or print credentials. Retain `grafana-auth0` and `grafana-admin-credentials`.
- The agent deleted no users. Retain local admin `1`, remaining accounts and
  Secrets; do not delete/change accounts to force association. A Grafana DB
  backup was **explicitly declined**; none was taken and that decision is settled.

#### B. Intended code-controlled Admin policy (live mismatch unresolved)

The following describes intended behavior, not verified live role sync. The
manual Admin assignment is a workaround and does not prove this policy works.

Keep `grafana.envFromSecret: grafana-zitadel` and the provider endpoints unchanged.
Under `grafana.grafana.ini.auth.generic_oauth`, use the constant role expression:

```yaml
name: Zitadel
auth_url: https://homelab-jj4izt.eu1.zitadel.cloud/oauth/v2/authorize
token_url: https://homelab-jj4izt.eu1.zitadel.cloud/oauth/v2/token
api_url: https://homelab-jj4izt.eu1.zitadel.cloud/oidc/v1/userinfo
role_attribute_path: "'Admin'"
```

- `[auth.generic_oauth]`: only standard scopes `openid profile email offline_access`,
  `use_pkce=true`, `use_refresh_token=true`, `allow_sign_up=true`,
  `skip_org_role_sync=false`, `role_attribute_strict=false`,
  `allow_assign_grafana_admin=false`; no `org_mapping`. Use standard profile/email
  claims, without account aliases, hardcoded email or personal `sub`.
- YAML `"'Admin'"` is the JMESPath literal `'Admin'`, not a claim lookup. Every
  successful Zitadel login gets Main Org **Admin** on next login after deployment,
  including no-role users and a user labelled `ZITADEL Admin`. No project role,
  grant, admin claim, extra scope or custom Action is required; existing role
  assertion settings are unchanged and do not control this constant policy.
- Organization **Admin** is not server **GrafanaAdmin**; server-admin grants
  remain disabled. `skip_org_role_sync=false` overwrites manual Grafana org
  assignments on login. Removing Zitadel roles does not downgrade users under
  this policy. Local admin is unaffected; anonymous visitors gain no access.
- `[users]`: `allow_sign_up=false` disables **local self-signup only**;
  `auto_assign_org=true`, `auto_assign_org_role=Viewer`, default org ID `1`.
  OAuth signup independently auto-provisions IdP-authenticated users; the constant
  OAuth expression overrides Viewer for Zitadel users, including no-role users.
- `[auth]`: `oauth_allow_insecure_email_lookup=false`,
  `disable_login_form=false`, `oauth_auto_login=false`; keep Basic auth enabled
  and generic OAuth `auto_login=false`. No temporary email-lookup window.
- Do not assume a new or retained SSO account ID. Preferences/permissions are
  not automatically migrated; role sync no longer preserves manual org roles.
  **Stop on further email/login uniqueness collisions**: no deletion, DB
  surgery, automatic alias/merge, email changes or enabling lookup to associate.
- Login admission relies on Zitadel's existing Grafana project
  `390167990928259276` in `arendse` (`380143417033860850`):
  `has_project_check=true`, `project_role_check=false`, no external project grants
  reported, self-registration disabled **per the user, not independently verified**.
  **All current and future admitted users receive Main Org Admin. Narrow the
  policy before onboarding, enabling registration or granting external orgs
  access.** Outside-org denial remains **deferred, not passed**.
- **Role mapping and Terraform adoption are deferred again.** No Terraform action
  or `grafana_greg_user_grant_id` is required now. Cleanup is limited to the
  agent's untracked, **unapplied** `infrastructure/identity/grafana-roles.tf` draft
  and its header reference. No live plan, import or apply was ever run for that
  draft; console roles/grants remain untouched.
- **Later follow-up:** replace the constant with least-privilege, org-scoped
  Admin/Editor/Viewer mapping; decide no-role behavior and verify actual claims
  and role removal/downgrade. Separately review Terraform adoption of existing
  roles/grants, tighten admission and test outside-org denial before expanding
  access. None of this is a prerequisite for the temporary constant policy.

#### C. Deployment confirmed — remaining OCI checks deferred

The user chose to move on with manual Admin access. Retain the checks below for
the follow-up, not as prerequisites to starting CP-3.1. Deployment steps 1–2
are complete; do not repeat them to diagnose the unresolved configuration.

1. **Completed:** separate documentation (`caa05c9`) and values (`6cced05`)
   commits were pushed with approval. **No grant ID or Terraform action is
   needed.** Auto-sync deploys `master`; only the user runs cluster commands.
   Confirm `kubectl config current-context` is `oci` before any cluster write.
   Do not manually Helm-upgrade or restart ahead of GitOps.
2. **Completed by the user:** `Synced` / `Healthy`, chart `69.0.0`, Git revision
   `6cced051b786fac7125b2085ab28db911b1aac1c`, and successful rollout. Commands
   retained for reference; no repeat check is needed for this deployment:

   ```bash
   kubectl --context=oci -n argocd get application oci-monitoring -o json |
     jq '{sync: .status.sync.status, health: .status.health.status,
       revision: .status.sync.revision, revisions: .status.sync.revisions}'
   kubectl --context=oci -n monitoring rollout status deployment/monitoring-grafana --timeout=120s
   ```

3. Check live settings using the local admin on **OCI**. Keep this filter intact;
   the raw response can contain sensitive settings. Curl prompts for the password:

   ```bash
   curl -q --basic --user admin --fail --silent --show-error \
     --connect-timeout 10 --max-time 20 \
     https://grafana.arendse.nom.za/api/admin/settings |
     jq '{auth: (.auth | {oauth_allow_insecure_email_lookup,
         disable_login_form, oauth_auto_login}),
       basic: (."auth.basic" | {enabled}),
       genericOAuth: (."auth.generic_oauth" | {
         enabled, name, auth_url, token_url, api_url, scopes,
         use_pkce, use_refresh_token, auto_login, allow_sign_up,
         skip_org_role_sync, role_attribute_path, role_attribute_strict,
         allow_assign_grafana_admin, org_mapping,
         email_attribute_path, login_attribute_path, name_attribute_path
       }),
       users: (.users | {allow_sign_up, auto_assign_org,
         auto_assign_org_id, auto_assign_org_role})}'
   ```

   Require section B's standard scopes and constant `role_attribute_path` value
   `'Admin'` (YAML `"'Admin'"`): OAuth signup `true`; skip-role-sync/local signup/
   insecure lookup/strict roles/server-admin assignment `false`; default org
   `1`/Viewer unchanged but overridden by OAuth Admin, no alias/org mappings,
   local form on and auto-login off.
   If settings differ, stop before testing SSO. Share no passwords, tokens,
   cookies, raw settings/logs or callback URLs.
4. Keep the **user-confirmed local admin `1` browser login** available in a
   separate session; recheck fallback after rollout.
5. In a fresh private browser, choose Zitadel and log in. At `/api/user`, record
   the account ID/login/email; require **not local admin `1`**, `orgId: 1`,
   `isGrafanaAdmin: false`, and the actual Zitadel email (observed profile:
   `greg.arendse@gmail.com`). Do not assume the SSO numeric ID. At
   `/api/user/orgs`, require org `1` (**Main Org**) **Admin**, while **Grafana
   Admin remains No**, regardless of Zitadel roles. When an eligible no-role
   user is available, expect Admin too, not Viewer. No role-claim evidence is
   needed for the constant. Stop on any collision or unexpected access.
6. Verify intended dashboards load. Log out of the test session and perform a
   fresh Zitadel re-login; verify the same account, email and expected org/role.
   Exercise session/token refresh and record the result; a surviving old
   session alone is not proof.

**Deferred with user approval:** live settings, automatic Main Org Admin
assignment with Grafana Admin No, dashboards and re-login/refresh; no-role Admin
test when an account is available. Login works and the user manually assigned
Admin; this does not demonstrate automatic role sync or persistence across
logins. Role mapping/Terraform adoption and outside-org testing also remain
**deferred, not passed**. CP-2.1 retains these follow-ups independently of the
completed CP-3.1 browser cutover and CP-1.2's qualified operational acceptance.

**Configuration/role-sync follow-up (after migration):** trace
`applications/monitoring/values.yaml` through `oci-monitoring` to rendered
Grafana configuration and effective settings, checking environment overrides
and OAuth role sync without exposing credentials. Reconcile ownership across
Helm/GitOps and Terraform before applying cleanup. Incomplete
`infrastructure/identity/` and `kubernetes/` configuration is the user's suspected
contributor, not a confirmed diagnosis; cleanup alone is not a proven fix.
Retain local admin access: OAuth role sync may overwrite the manual org role
on subsequent login. Then repeat the deferred checks above.

**Rollback:** review reverting provider URLs and `envFromSecret` to the retained
`grafana-auth0`, then user-controlled push. Retain remaining accounts and Secrets;
review any binding recovery separately. Provider/config rollback **cannot restore
the deleted user's metadata** or automatically migrate preferences/permissions.
The deleted/current SSO IDs remain unknown; do not assume user `2`'s state.

---

## Phase 3 — ArgoCD (trinity)

> Unlike Phases 1–2, ArgoCD is **not** self-managed through GitOps — there is no
> `argocd` entry in `clusters/*/rendered/`. These values files are applied by
> hand (helm/terraform), so committing alone does **not** deploy them.

### CP-3.1 — Cut over trinity ArgoCD

**Complete for browser SSO, based on user confirmation.** Zitadel login,
API-session identity and concrete Application permission checks succeeded per
user-supplied results. The user then confirmed application details, logout/
re-login and rollout success with "all looks good". Raw Helm/rollout output was
not supplied. Do not repeat the cutover or restart. Keep local `admin`,
`argocd-auth0` and `argocd-zitadel` for recovery.

**Target cluster: trinity.** Manually Helm-managed, not OCI Terraform or GitOps.
Uses the new `argocd` project's **trinity** client from CP-0.6, not the OCI or
`homelab` client. Only the user runs cluster commands; reconfirm context before
any future writes.

**Preflight completed — user-supplied evidence:**

- `argocd-server`: one ready replica, chart `argo-cd-9.4.15`, ArgoCD `v3.3.4`.
- Public URL: `https://trinity.argocd.arendse.nom.za`.
- Before cutover, live OIDC was Auth0 (`https://arendse.uk.auth0.com/`).
- `admin.enabled: "true"`; built-in `admin` login works per the user.
- RBAC: scopes `[email]`, empty default policy, and
  `g, greg.arendse@gmail.com, role:admin`.
- Existing `argocd-auth0` Secret retained untouched. The user subsequently
  reported `secret/argocd-zitadel created` using the `zitadel_sso_*` outputs'
  `argocd_trinity` entry, keys `clientID` / `clientSecret` and label
  `app.kubernetes.io/part-of: argocd`. No credential values were shared.

**Secret staging is complete; do not repeat it.** The old instructions to delete
or overwrite `argocd-auth0` are withdrawn. Creating `argocd-zitadel` alone does
not switch SSO. No standalone context output was supplied in this resumed
preflight; reconfirm it before any future write.

**Applied cutover — user-confirmed:** `clusters/trinity/argocd.yaml` switches
these four OIDC fields together:

```yaml
name: Zitadel
issuer: https://homelab-jj4izt.eu1.zitadel.cloud
clientID: $argocd-zitadel:clientID
clientSecret: $argocd-zitadel:clientSecret
```

Requested scopes/email claim, email-admin RBAC, ingress and chart version stay
unchanged. Org-wide login is not an admin grant. No project-role mapping is
required for the existing explicit email policy. Committing or pushing this
values file alone does **not** deploy ArgoCD itself.

**Completed user-run upgrade recipe — reference only; do not repeat.** From the
repository root:

```bash
kubectl config current-context
# Continue only when this reports trinity.
helm upgrade argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 9.4.15 \
  --kube-context trinity \
  --namespace argocd \
  --reuse-values \
  --values clusters/trinity/argocd.yaml \
  --rollback-on-failure \
  --timeout 5m
```

The locally checked Helm CLI is `v4.3.0`; `--rollback-on-failure` waits for
readiness and rolls back a failed upgrade (Helm 3 uses `--atomic` instead).
`--reuse-values` preserves release overrides absent from this file; values
present in the file take precedence. This is a same-chart-version SSO change,
not a chart upgrade or a new installation. Stop on errors rather than forcing
resource replacement. Helm readiness does not verify browser SSO.

**Rollout check — user-confirmed, trinity; reference only:**

```bash
kubectl --context=trinity -n argocd rollout status deployment/argocd-server --timeout=120s
```

**Browser and authorization evidence — user-supplied:**

- Zitadel login works. User Info and `/api/v1/session/userinfo` show
  `greg.arendse@gmail.com` as username and group, issuer
  `https://homelab-jj4izt.eu1.zitadel.cloud`, and `loggedIn: true`.
- Live `argocd-rbac-cm` has `g, greg.arendse@gmail.com, role:admin`, empty
  `policy.default`, `policy.matchMode: glob`, scopes `[email]`, and no additional
  `policy.*.csv` entries. No role or RBAC changes were made during diagnosis.
- The initial `/api/v1/account/can-i/applications/sync/*/*` check returned
  `{"value":"no"}`. Its cause was not established; do not infer an email mismatch
  or a Grafana-style role-sync problem from that result.
- The checks were repeated against the concrete Application
  `default/trinity-oauth2-proxy` using the two read-only URLs below. The user
  replied "Its returning yse" (yes); separate JSON responses were not supplied.
  These checks do not perform a sync:
  - `https://trinity.argocd.arendse.nom.za/api/v1/account/can-i/applications/get/default/trinity-oauth2-proxy`
  - `https://trinity.argocd.arendse.nom.za/api/v1/account/can-i/applications/sync/default/trinity-oauth2-proxy`
- The user subsequently replied "all looks good" to application-details access,
  logout/fresh Zitadel login and successful rollout checks. Browser SSO is
  complete on that confirmation; do not repeat deployment to fix the unexplained
  wildcard result.

These permission checks do not prove every admin operation. Outside-org denial
remains explicitly deferred; non-admin authorization, CLI SSO and a separate
post-cutover local-admin retest remain unverified, not implied by browser login.

**Rollback:** restore only the four OIDC fields below in
`clusters/trinity/argocd.yaml` and repeat the same user-run Helm upgrade after
confirming context `trinity`. Keep both Secrets and RBAC unchanged; do not revert
unrelated work or delete/recreate credentials.

```yaml
name: Auth0
issuer: https://arendse.uk.auth0.com/
clientID: $argocd-auth0:clientID
clientSecret: $argocd-auth0:clientSecret
```

---

## Phase 4 — ArgoCD (OCI)

### CP-4.1 — Cut over OCI ArgoCD

**Complete for browser SSO, based on user confirmation.** Following the
successful Terraform apply, Zitadel User Info and `CanI` response, the user
replied "All looks good" to the rollout-health, Applications-page and
logout/re-login checks. Record those as user-confirmed; raw rollout output was
not supplied. Do not repeat the cutover. Keep local `admin`, `argocd-auth0` and
`argocd-zitadel` for recovery. Remaining test gaps are listed below.

The user supplied these read-only preflight results:

- Deployment `argocd-server`: one ready replica, chart label `argo-cd-9.4.15`,
  image `quay.io/argoproj/argocd:v3.3.4`. The chart label matches the version in
  `infrastructure/kubernetes/argocd.tf`.
- `argocd-cm`: `admin.enabled: "true"`, URL `https://argocd.arendse.nom.za`,
  provider `Auth0`, issuer `https://arendse.uk.auth0.com/`.
- `argocd-rbac-cm`: `scopes: "[email]"`, empty `policy.default`, and
  `g, greg.arendse@gmail.com, role:admin`. These inspected fields match the
  repository values before cutover; subsequent Zitadel login/email and sync
  permission checks are recorded below.

**Secret staging completed (user-confirmed):** context `oci` and initial
Secret-existence checks passed (`argocd-auth0` existed, `argocd-zitadel` did not).
The user then confirmed creating `argocd-zitadel` with the recipe below, using
`clientID` / `clientSecret` from the new `zitadel_sso_*` outputs' `argocd_oci`
entry and the required `app.kubernetes.io/part-of: argocd` label. Secret values
were not exposed; `argocd-auth0` is retained for rollback. Subsequent Terraform
apply and browser verification are user-confirmed below.

**OCI ArgoCD is owned by Terraform** (`helm_release.argocd` in
`infrastructure/kubernetes/argocd.tf`), not GitOps. The earlier direct Helm
rollout advice is withdrawn; do not use it. Trinity's manual Helm bootstrap is
a different workflow. The chart remains pinned to `9.4.15`. Both Helm and
Kubernetes providers in this OCI-only root explicitly select context `oci`
(`config_context = "oci"`) while retaining `var.kubeconfig_path`; Terraform must
find that context in the configured file. Confirm the intended kubeconfig and context before
planning, and `kubectl config current-context` before any cluster write.

**Completed Secret staging — reference only; do not repeat.**
Context `oci` was confirmed for this step; reconfirm if returning in a later
session. Keep the pipeline intact: `terraform output -json` exposes sensitive
outputs if run alone. Do not print, tee, log or save the intermediate JSON.
Only the OCI client's two values are sent to Kubernetes; no Terraform apply is
needed. `create` refuses to overwrite an existing Secret. If any command fails,
stop and investigate rather than deleting or replacing a Secret.

```bash
terraform -chdir=infrastructure/identity output -json |
  jq -e '{
    clientID: .zitadel_sso_client_ids.value.argocd_oci,
    clientSecret: .zitadel_sso_client_secrets.value.argocd_oci
  } | if all(.[]; type == "string" and length > 0) then {
    apiVersion: "v1",
    kind: "Secret",
    metadata: {
      name: "argocd-zitadel",
      namespace: "argocd",
      labels: {"app.kubernetes.io/part-of": "argocd"}
    },
    type: "Opaque",
    stringData: .
  } else error("Missing or empty argocd_oci credentials") end' |
  kubectl --context=oci -n argocd create -f -
```

The user confirmed completion of this creation step. Creating the separate
Secret alone does not switch SSO.

**Applied through Terraform — browser cutover verified by the user:**
`infrastructure/kubernetes/argocd.yaml` uses name `Zitadel`, issuer
`https://homelab-jj4izt.eu1.zitadel.cloud`, and
`$argocd-zitadel:clientID` / `$argocd-zitadel:clientSecret`. Requested scopes and
email claim, explicit email admin mapping, default permissions, ingress and
chart version are unchanged. Existing unrelated work in that file is preserved.
Do not commit or push without approval; pushing this file alone does not deploy
ArgoCD itself.

**Completed plan review — OCI, user-supplied output.** The plan command below
is retained as reference. Run from the repository
root with the existing backend/workspace and the usual private variable inputs
for `infrastructure/kubernetes`; do not initialize new state or migrate/reset
the backend. The file change is already consumed by `helm_release.argocd` via
`file("${path.module}/argocd.yaml")`, so no resource rewrite is required.
The Helm provider has its own implementation; local Helm CLI version/flags do
not determine the Terraform resource arguments.

```bash
terraform -chdir=infrastructure/kubernetes plan -input=false \
  -target=helm_release.argocd
```

`-target` is an exceptional migration scope while the root is incomplete, not
normal ongoing practice. It includes dependencies and **all pending changes to
the ArgoCD release**, not just OIDC. Terraform still loads/validates the root and
may require unrelated input variables. If initialization, inputs or configuration
fail, share the non-sensitive error and stop; do not fall back to direct Helm,
new state or an unreviewed broad apply.

**Plan review passed:** the user supplied **0 to add, 1 to change, 0 to destroy**,
with only `helm_release.argocd` updated in place. The `values` diff switches
name/issuer and both Secret references together, plus comments. Requested scopes,
email claim, explicit email admin mapping, ingress and chart version are unchanged.
The apparent removals under `metadata.values -> (known after apply)` are computed
release metadata being refreshed, not deletion of live RBAC or ingress. No
replacement or unrelated resource change is shown.

**Completed apply — OCI, reference only; do not repeat.** The user reported
**Apply complete! Resources: 0 added, 1 changed, 0 destroyed.** The reviewed
plan and user-run command targeted `helm_release.argocd`, using the existing
backend/workspace and private inputs. No saved plan was supplied; the command
required confirmation of a fresh plan, without automatic approval.

```bash
kubectl config current-context
# Continue only when this reports oci.
terraform -chdir=infrastructure/kubernetes apply -target=helm_release.argocd
```

**Apply and Zitadel sign-in succeeded per the user.** User Info shows:

- Username: `greg.arendse@gmail.com`
- Issuer: `https://homelab-jj4izt.eu1.zitadel.cloud`
- Groups: `greg.arendse@gmail.com`

This demonstrates sign-in through the intended issuer. The email matches the
unchanged `g, greg.arendse@gmail.com, role:admin` policy with scopes `[email]`;
no new Zitadel project role is required. The Groups display is not evidence of
a separate Zitadel project-role assignment. The subsequent read-only `CanI`
response confirms application-sync permission for this SSO session (below).
Rollout health, application access and logout/re-login were subsequently
confirmed by the user. Private-window isolation was not separately confirmed.
Share only non-sensitive results/errors, never
raw state, credential outputs, saved plan files or secret-bearing values. A
targeted apply does not prove the rest of the root is consistent; review a full
plan after migration before cleanup.

**Permission check passed — user-supplied `{"value":"yes"}`.** The requested
read-only check used the same browser/profile that showed the Zitadel User Info,
not the separate local-admin session:

`https://argocd.arendse.nom.za/api/v1/account/can-i/applications/sync/*/*`

Actual user response: `{"value":"yes"}`. This confirms the SSO session is allowed
`applications/sync` for `*/*`, consistent with the intended admin mapping; it
does not perform a sync or change applications. It is not a test of every admin
operation or negative-access behavior. Endpoint and response behavior were checked
against upstream ArgoCD `v3.3.4` `server/account/account.proto` and
`server/account/account.go`; no live request was made by the agent.

**Rollout health confirmed by the user.** In response to the read-only rollout
status, Applications-page and logout/re-login checks, the user replied "All looks
good". No raw rollout output was supplied; the agent ran no cluster commands.
The commands below are retained as reference only, **not a request to restart
again**. Any future restart requires confirming current context `oci` and may
briefly interrupt the ArgoCD UI/API, not managed workloads.

```bash
kubectl --context=oci -n argocd rollout restart deployment/argocd-server
kubectl --context=oci -n argocd rollout status deployment/argocd-server --timeout=120s
```

**Completion and test limits:** browser sign-in with the expected issuer/email,
application-sync permission, rollout health, application access and re-login are
user-confirmed. These close the browser cutover; do not broaden RBAC or perform
an actual sync merely to test it. Local-admin access was verified before cutover,
not separately retested afterward. Private-window isolation and a separate live
inspection of OIDC display name/Secret references were not supplied; the paired
configuration was reviewed in the Terraform plan and the apply succeeded.
Non-admin/outside-org denial and CLI SSO remain unverified follow-ups, never
passes. Do not assume the historical Auth0 localhost callback is registered in
the new client. Revisit access-boundary tests before onboarding users or expanding
admission. A full Terraform plan and repository cleanup remain separate work;
this targeted apply does not establish that the rest of the root is consistent.

**Rollback:** keep local admin and `argocd-auth0`. Restore the four OIDC values
in the source file together: `name: Auth0`, issuer `https://arendse.uk.auth0.com/`,
`$argocd-auth0:clientID`, `$argocd-auth0:clientSecret`; then review a Terraform
plan, apply only the approved rollback and restart the server on OCI. Do not
use direct Helm rollback or revert the whole checkpoint: the earlier Auth0
OIDC/RBAC additions were uncommitted before this work, so a wholesale revert
would remove them rather than restore the working Auth0 baseline. Restore only
the four provider fields above. Retain both Secrets and all Zitadel registrations
until migration and burn-in complete.

---

## Phase 5 — Pi-hole (independent integration, OCI)

**Corrected baseline (user-supplied OCI checks, 2026-09-27):** Pi-hole is NOT
currently behind Zitadel. `pihole` is `1/1`; Traefik's `pihole-ingress` routes
`pihole.arendse.nom.za/` directly to `pihole-web:80`. The browser reaches
Pi-hole's own login. The namespace has no proxy Deployment, Service or OAuth
Secret. The original assumption of a working hand-made `trinity` project
integration was incorrect; retain those registrations until consumers are
inventoried, but do not treat them as a verified rollback path.

### CP-5.1 — Pi-hole SSO (skipped)

**Decision (2026-09-27): skipped at the user's request, not a successful SSO
cutover.** Pi-hole's [native authentication](https://docs.pi-hole.net/api/auth/)
uses a local password (optionally TOTP) and sessions, not OIDC/SAML. The proposed
oauth2-proxy would challenge users with Zitadel before Pi-hole's own login; it
would not map Zitadel identities into Pi-hole or replace local authentication.
Do not disable Pi-hole's password to simulate native SSO.

**Keep:** the direct Traefik route to `pihole-web:80`, `pihole-secret`, native
login, TLS, DNS and storage. No cluster changes were made by the agent. The user
has not reported running the now-withdrawn Secret-creation command or either
rollout stage. No SSO verification is claimed and no live rollback is needed
based on the supplied preflight.

**Abandoned proxy enrollment — published and live cleanup complete (2026-09-27):**

- The user approved removal of the unused enrollment. Removed only the proxy
  entry from `clusters/oci/apps.yaml` and
  `clusters/oci/rendered/pihole-zitadel-oauth2-proxy.yaml`. The generator does not
  remove stale files, so deleting the generated Application is necessary too.
  The separate `oci-pihole` enrollment, its generated Application and Pi-hole
  workload manifests remain unchanged.
- Before cleanup, `oci-pihole-zitadel-oauth2-proxy` reported `ComparisonError`
  because its values were missing from Git. The abandoned Application has now
  been deleted, rather than repaired/deployed. Do not publish the untracked
  proxy values or re-enroll it.
- **Pre-deletion safety check supplied by the user:** `oci-root` had
  `automated: {enabled: false}`, no finalizers/owner references, and listed the
  proxy Application among its resources. The proxy's tracking annotation was
  `oci-root:argoproj.io/Application:argocd/oci-pihole-zitadel-oauth2-proxy`;
  its finalizers and owner references were empty and `status.resources` was empty.
  Its own automated prune/self-heal did not make the parent remove it.
- The repository has conflicting root definitions: `clusters/oci/root.yaml`
  enables automated prune/self-heal, while Terraform's
  `kubernetes_manifest.argocd_root` in `infrastructure/kubernetes/argocd.tf`
  has no `syncPolicy`. Neither was changed here. The live root had auto-sync
  disabled, so publication alone did not auto-prune the abandoned Application.
- With explicit approval, commit `7a84e65` published the inventory removal,
  generated Application deletion and two updated docs (four files only).
  Pre-commit hooks, including Application generation, passed. Unrelated work,
  including `pihole.nix`, was preserved and excluded from the commit.
- **User-confirmed live cleanup:** context was `oci`; the targeted delete
  returned `application.argoproj.io "oci-pihole-zitadel-oauth2-proxy" deleted`.
  The follow-up checks showed `oci-pihole` **Synced/Healthy** and deployment
  `pihole` **1/1**, up-to-date `1`, available `1`. The user reported
  "PiHole appears to be working". No broad root sync/prune, Pi-hole restart,
  DNS change or Secret deletion was part of this cleanup. Do not repeat it.
  A separate DNS-query test and a post-deletion root-status check were not
  supplied; do not claim those tests passed.
- The unpublished `pihole.nix` ingress switch and untracked proxy values still
  exist. Do not include them in a commit/push. Review/reconcile this existing
  user work explicitly rather than discarding it or accidentally deploying it.
- The Terraform-managed `pihole` project (`390167990911416524`) and OIDC client
  were already created. Leave them for an explicit, reviewed Terraform cleanup
  after checking consumers; do not destroy them as part of this decision.
- If the user did create the proxy Secret after preflight, inventory it during
  cleanup; do not assume it exists or delete it blindly.

OCI's intended login cutovers are now complete within the revised scope:
ArgoCD is on Zitadel and Grafana login works with the accepted manual-Admin
workaround. Grafana role sync, review of unpublished proxy/ingress work and unused
Terraform identity objects, and other recorded test gaps remain follow-ups.
Trinity ArgoCD browser SSO is also complete (CP-3.1), and media operational
burn-in is accepted with caveats (CP-1.2). Global Auth0 retirement still requires
review of remaining consumers, verification gaps and rollback needs.

---

## Phase 6 — Decommission Auth0 (only after a solid burn-in)

**Current scope:** remove Auth0 dependencies and retire Auth0, without waiting
for Grafana's optional role-sync fix, general Terraform tidying or cleanup of
unused Zitadel projects/PoC clients. The user accepts the existing Grafana
Zitadel login/manual Admin workaround. Those deferred checks are not marked
passed by this scope decision.

**Read-only dependency audit — user-supplied results:**

- Both **trinity** and **oci** scans returned `[]`. They inspected specs of
  Deployments, StatefulSets, DaemonSets, Jobs, CronJobs and Pods, plus ConfigMap
  data, for `auth0` strings and supported Secret-reference paths to the legacy
  `oauth2-proxy` Secret. This is a scoped negative result, not a complete audit
  of Secret contents, custom resources, external clients or tenant activity.
- `terraform -chdir=infrastructure/identity state list` returned only the ten
  Zitadel OIDC apps and five projects. No Auth0 resources are in this state.
  The legacy `homelab`, `media_poc` and unused `pihole` objects are **Zitadel**
  resources; leave them unchanged during this Auth0-only cleanup.
- Asked to check Zitadel's upstream identity providers and Auth0's clients/APIs
  and recent activity (including M2M), the user replied **"I think we are clear"**.
  Record this as the user's assessment, not independently verified evidence:
  no detailed provider inventory or log review results were supplied. A working
  Zitadel console alone does not prove independence from an upstream provider.

**CP-6.3's zero-change plan passed per the user.** The user requested a local
Git checkpoint and deferred live cleanup to the next session. Resume at CP-6.2
with a consumer recheck and explicit deletion approval; live Auth0 client/tenant
retirement remains a separate later approval. No live removals have happened
in this phase. Grafana role sync remains optional, not a retirement blocker.

### CP-6.1 — Tear down the PoC rig

**Optional later Zitadel cleanup, not a blocker for Auth0 retirement.** Leave
`oauth2-proxy-zitadel`, `zitadel-echo`, their Secrets and Terraform clients intact
for now. If teardown is requested, first inspect GitOps ownership, finalizers
and consumers. Remove the inventory entries and stale rendered Applications
through an approved publication, then review the exact user-run trinity cleanup.
Do not blindly Helm-uninstall GitOps-managed apps or delete their namespaces.
The old uninstall-first recipe is withdrawn.

### CP-6.2 — Remove Auth0 runtime Secrets

**Deferred to the next cleanup session at the user's request.** The zero-change
identity plan passed, but deletion is not approved. The migrated workloads use
separate Zitadel Secrets; all four retained Auth0 candidates remain untouched:

| Cluster | Namespace | Secret |
|---|---|---|
| trinity | oauth2-proxy | oauth2-proxy |
| trinity | argocd | argocd-auth0 |
| oci | monitoring | grafana-auth0 |
| oci | argocd | argocd-auth0 |

Do not delete by name alone. Use the consumer audit above and recheck if runtime
configuration changes or cleanup is delayed. The user must confirm the named
cluster context before each cluster's writes. Keep Zitadel Secrets, local-admin
credentials and Pi-hole's native Secret. Removing old Secrets ends the quick
Auth0 rollback recipe, even if the tenant still exists.

### CP-6.3 — Retire the Auth0 Terraform + provider

**Complete: repository checkpoint and user-confirmed zero-change plan.** No
apply or live Auth0 deletion was performed. Removed the commented-out
`auth0.tf`, `generated.tf`, `imports-pending.tf`, `list-auth0-ids.sh`, the three
`auth0_*` variables, and the Auth0 provider/configuration/lock entry. The old
Auth0 import guide now points to this retirement record rather than instructing
a new import. No Zitadel resource, output, provider version or backend changed.
Local `terraform validate`, formatting checks for the edited `.tf` files and
`git diff --check` passed. The agent did not run a live plan/apply or cluster
command. The user subsequently reported the full plan result below.

Before planning, the user removes `auth0_domain`, `auth0_client_id` and
`auth0_client_secret` assignments from private `.auto.tfvars`/other variable
files and stops passing them via CLI/automation. Unset corresponding
`TF_VAR_auth0_*` exports if present. Keep all Zitadel and backend settings. The
agent did not inspect or modify private inputs; do not paste their contents.

**Completed user-run plan — reference only; no apply needed.** Target was the
Zitadel Cloud identity root, not either Kubernetes cluster, using the existing
initialized backend/workspace from the repository root:

```bash
terraform -chdir=infrastructure/identity plan -input=false
```

User-reported result: **"No changes. Your infrastructure matches the configuration."**
This passes the CP-6.3 gate without removing any Zitadel objects.

For subsequent checks, require **No changes**, not merely zero destroys. Any addition, update,
replacement or deletion is outside this cleanup: stop and investigate. Do not
use `-target`, `terraform destroy`, state edits, a new backend/workspace or an
unreviewed apply to make the plan pass. If initialization is required, preserve
the existing backend and locked Zitadel version; do not upgrade or migrate it.

Removing Terraform configuration does **not** delete any live Auth0 object.
After the zero-change plan and explicit approval, retire unused Auth0 clients
and Management API credentials through Auth0, then the tenant/subscription last.
Confirm independent Zitadel/local-admin access before ending rollback. Do not
assume there is no billing/subscription to cancel. Runtime example files and
historical rollback docs remain to reconcile when live retirement is completed.

### CP-6.4 — Clean up the superseded Zitadel objects
After every in-scope integration has moved to its target project inside
**`arendse`** and passed burn-in, inventory consumers before removing anything:
- Pi-hole SSO was skipped. Review the unused Terraform `pihole` project/client
  for removal through a separately approved plan; leave it until that review.
- Remove unused hand-made PoC/Pi-hole clients in the `trinity` project only
  after checking consumers and completing the PoC teardown. Keep the project
  if anything else uses it.
- Retire the original Terraform-managed `homelab` clients/project through
  Terraform, not console deletion. Review the exact planned deletions and
  retire their legacy outputs only when no consumer or rollback needs them.
- Remove the temporary media PoC client through Terraform after CP-6.1.

Keep the `arendse` organization, its users, and the built-in **`ZITADEL`**
project. These are not migration leftovers.

### CP-6.5 — Update docs
Refresh the READMEs (`applications/oauth2-proxy/`, `applications/monitoring/`,
`infrastructure/kubernetes/ARGOCD-SSO.md`, `AGENTS.md` if it mentions Auth0) so
Zitadel is described as the primary provider. Mark Auth0 retirement complete
only after the live cleanup is user-confirmed; optional Grafana/PoC/Zitadel
cleanup can remain open. Retain this checklist as the migration/decision record.

---

## Rollback cheat-sheet

For the production media proxy, revert the paired issuer/Secret-reference
values change: its original Auth0 Secret remains intact. For other integrations,
restore both the previous configuration (including any changed RBAC) and the
complete Secret. For auto-synced apps, restore Git configuration with
**`git revert` + push**; for ArgoCD, re-apply the old configuration manually.
Coordinate Secret/config changes in one session, then restart only after they
match. The user confirms the named cluster's context before any write.

| App | Revert issuer to | Restore secret |
|---|---|---|
| oauth2-proxy (trinity) | `https://arendse.uk.auth0.com/` in `applications/oauth2-proxy/values.yaml` | Revert `existingSecret` to the untouched `oauth2-proxy` Secret |
| Grafana (oci) | the 3 `arendse.uk.auth0.com` URLs in `applications/monitoring/values.yaml` | `grafana-auth0` |
| ArgoCD trinity | `https://arendse.uk.auth0.com/` in `clusters/trinity/argocd.yaml` | `argocd-auth0` |
| ArgoCD OCI | `https://arendse.uk.auth0.com/` in `infrastructure/kubernetes/argocd.yaml` | `argocd-auth0` |
| Media PoC (trinity) | Unchanged Zitadel issuer; restore previous proxy config if changed | `oauth2-proxy-zitadel` with original `homelab` credentials |
| Pi-hole (oci) | SSO skipped; keep the existing direct route to `pihole-web:80` | Keep native `pihole-secret`; no OAuth Secret creation reported |

The removed `infrastructure/identity/auth0.tf` client-ID inventory is retained
in Git history; live values remain in the Auth0 dashboard until retirement.
Secrets belong in the password manager / Auth0 dashboard, never Git. These
rollback recipes cease to be usable once the old credentials/tenant are removed.
