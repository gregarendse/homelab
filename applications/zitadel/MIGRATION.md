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
  app in `clusters/*/rendered/`), so Phases 3 and 4 *do* deploy manually.
- **Zitadel OIDC endpoints** (needed for Grafana, which uses explicit URLs):
  - authorize: `<ISSUER>/oauth/v2/authorize`
  - token: `<ISSUER>/oauth/v2/token`
  - userinfo: `<ISSUER>/oidc/v1/userinfo`

## Progress tracker

Update this as you go so "future you" knows where to resume.

- **Last verified deployment:** CP-0.7 — user reported the isolated PoC rollout
  and fresh-browser login working on **trinity**, using the new `media_poc`
  client in the `media` project. This is user-reported, not an agent-run test.
- **Latest decision:** separate `media`, `pihole`, `argocd` and `grafana`
  projects inside `arendse`, initially allowing all org users without individual
  assignments. Self-registration is disabled **according to the user; not
  independently verified**. This remains approved untracked work.
- **Last completed:** CP-0.7 — PoC credential swap, rollout and fresh login
  passed per user. The user also confirmed normal Sonarr and Pi-hole access
  still works and explicitly accepted deferring the outside-org denial test
  for this single-user setup. That test is **deferred, not passed**; revisit it
  before adding users or changing registration/access policies.
- **In progress:** CP-1.1 preparation for the production media proxy on
  **trinity**. Local values now select a separate `oauth2-proxy-zitadel-media`
  Secret and the Zitadel issuer. User confirmed production preflight on
  `trinity`: one ready replica, Auth0 issuer `https://arendse.uk.auth0.com/`,
  and Secret `oauth2-proxy`. The user chose to skip the exported Auth0 backup;
  the original Secret stays untouched as the rollback path. The user reported
  `secret/oauth2-proxy-zitadel-media created` in namespace `oauth2-proxy`.
  The user approved separate local preparation/cutover commits. **Next
  deployment action after those commits:** a user-controlled push, followed by
  rollout and fresh-login verification. No values have deployed. The agent
  handles only the approved local commits, not live plan/apply, cluster commands,
  deployments or pushes.
- **Local commits approved; deployment not yet pushed.** The destination Secret is
  created. Retain the Auth0 Secret and switch the issuer/Secret reference
  together in a dedicated deployment commit. Commit the already-applied
  identity configuration and runbook separately; do not mix them or unrelated
  edits into the single-file cutover commit. The user controls the push.

| # | Checkpoint | Done |
|---|---|:--:|
| 0.1 | Apply `zitadel.tf` (project + 4 OIDC apps) | ☑ |
| 0.2 | Capture the generated client ids/secrets | ☑ |
| 0.3 | (Historical) Dress-rehearse the original `homelab` client | ☑ |
| 0.4 | Agree project boundaries and credential ownership | ☑ |
| 0.5 | Reviewed live plan: 10 additions, 0 changes/destroys (no apply) | ☑ |
| 0.6 | Applied 10 additions; post-apply checks confirmed by user | ☑ |
| 0.7 | PoC login and smoke checks passed; outside-org test deferral accepted | ☑ |
| 1.1 | Cut over the edge proxy (all `*arr` apps) | ☐ |
| 1.2 | Burn-in: confirm the `*arr` apps for a few days | ☐ |
| 2.1 | Cut over Grafana | ☐ |
| 3.1 | Cut over ArgoCD (trinity) | ☐ |
| 4.1 | Cut over ArgoCD (OCI) | ☐ |
| 5.1 | Move Pi-hole to its dedicated project/application (OCI) | ☐ |
| 6.1 | Tear down the PoC rig | ☐ |
| 6.2 | Remove Auth0 runtime Secrets | ☐ |
| 6.3 | Retire the Auth0 Terraform + provider | ☐ |
| 6.4 | Clean up superseded Zitadel projects/clients | ☐ |
| 6.5 | Update docs to make Zitadel the primary | ☐ |

## Decisions log

Context worth remembering between sessions.

- **Auth0 Terraform is commented out, not imported.** The `auth0_*` resources
  were only ever *pending* import and never entered state, so Terraform does not
  manage them and cannot destroy them. The live Auth0 tenant is untouched and
  remains the rollback path. `imports-pending.tf` was never completed on purpose
  (adopting the tenant/database connection would be throwaway work).
- **Existing layout (already applied):** the `arendse` org contains `ZITADEL`
  (built-in system project — do not touch), `trinity` (hand-made registrations,
  including the working Pi-hole client), and Terraform-managed `homelab`
  (four legacy clients; its `oauth2_proxy` client is now the PoC rollback path).
  Creating another org was rejected because it requires **IAM_OWNER**.
- **Target registrations created (CP-0.6 applied; only the PoC migrated so far):**
  keep `arendse`, but
  group projects by integration, not cluster: `media`, `pihole`, `argocd`,
  `grafana`. Each app/proxy deployment gets its own OIDC credentials, including
  separate media production/PoC clients and two native ArgoCD clients. See
  CP-0.4–0.7. Preserve all existing clients until their replacements are tested
  and their consumers migrated.
- **Pi-hole stays independent.** It gets its own project and application; it
  will not inherit the shared media access policy. Its eventual proxy layout
  is undecided. ArgoCD continues using native OIDC, not a proxy.
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
  `monitoring` (OCI) are both enrolled; **ArgoCD itself is not**, so its values
  files still need a manual apply.
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
  does not require project roles or per-user assignments. No roles, assignments,
  project grants, policy resources or Kubernetes providers are added.
- **Self-registration must remain disabled.** The user reports it is disabled;
  this has not been independently verified and Terraform does not manage it.
  Future users added to `arendse` automatically gain login to all four projects.
  **Follow-up: tighten access before adding users or re-enabling signup.** Defer
  per-project user restrictions until wanted, then design explicit assignments
  and role checks. Separate app RBAC still applies now: org-wide login does
  **not** mean everyone is a Grafana or ArgoCD administrator.

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
  Grafana and ArgoCD must still map identities/claims to local permissions;
  login alone must not grant admin. Per-project user restrictions are deferred
  until wanted, and must be revisited before onboarding users or opening signup.
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

**In progress: preflight and new Secret creation confirmed; commit/push and
rollout pending. Target cluster: trinity.** User output shows context `trinity`, one ready
production replica, `--oidc-issuer-url=https://arendse.uk.auth0.com/` and Secret
reference `oauth2-proxy`. **The user explicitly chose to skip the exported Auth0
backup.** Rollback relies on retaining the original Secret; if it is lost, its
credentials must be recovered separately. No staging command requires a backup
directory or writes credentials to disk. Only the user runs cluster commands.
Run from the repository root; stop on any error.

**Staging result:** the user reported `secret/oauth2-proxy-zitadel-media created`.
Steps 1–2 below are complete; do not repeat Secret creation. It is still unused
by the deployed values. The user approved the two separate local commits in
step 3; pushing and live verification remain user-controlled and pending.

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

**Completion gate (partially met):** the new Secret is created. Paired values
commit/push, correct live issuer/Secret, rollout and fresh production login are
still pending.

**Rollback:** revert the dedicated values commit and have the user push. This
restores both the Auth0 issuer and `existingSecret: oauth2-proxy`, whose original
credentials and cookie key were never changed. Wait for those references to
appear in the deployment and the rollout to finish on **trinity**. No Secret
rewrite is needed for normal rollback. The exported backup was explicitly
skipped, so this depends on the original Secret remaining available. Before the
deployment push, simply leave the new unused Secret in place and stop—there is
no runtime change to undo.

### CP-1.2 — Burn-in
Leave it a few days. Confirm the shared cookie still gives single-sign-on across
the `*arr` apps and no one is locked out. Only then continue.

---

## Phase 2 — Grafana

> Grafana runs on the **OCI** cluster (`clusters/oci/rendered/monitoring.yaml`),
> which also has `autoSync: true`. Same rule as Phase 1: Secret first, then push.

### CP-2.1 — Cut over Grafana

**Target cluster: oci.** Confirm the context before any write. Use the new
`grafana` project's client from CP-0.6, not the original `homelab` client.
Verify a local admin fallback before changing SSO.

1. Back up the current Secret securely, then replace its credentials (keeps
   `envFromSecret` intact):
   ```bash
   CID=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_ids | jq -er .grafana)
   SEC=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_secrets | jq -er .grafana)
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
   Review `scopes` and `role_attribute_path` against the new client's actual
   claims; no Zitadel project roles are created initially. Map intended admins
   explicitly and keep default permissions low. Do not assume the Auth0 mapping
   is correct for Zitadel or give every authenticated org user Admin.
3. Commit and push — Argo auto-syncs `monitoring`. Then restart Grafana so it
   re-reads the Secret:
   ```bash
   kubectl -n monitoring rollout restart deploy/monitoring-grafana
   ```
   Again, no `./upgrade.sh` — `selfHeal` would revert it.
- **Verify:** at `https://grafana.arendse.nom.za`, an `arendse` user can log in
  without project roles; unauthenticated access is challenged. The intended
  admin gets **Admin**, while a non-admin gets only intended lower permissions.
  Test outside-org denial when available; record unavailable outside-org or
  non-admin tests honestly. Use fresh sessions; org-wide login is not admin.
- **Rollback:** `git revert` + push to restore the 3 Auth0 URLs, and put the
  Auth0 client id/secret back in the Secret.

---

## Phase 3 — ArgoCD (trinity)

> Unlike Phases 1–2, ArgoCD is **not** self-managed through GitOps — there is no
> `argocd` entry in `clusters/*/rendered/`. These values files are applied by
> hand (helm/terraform), so committing alone does **not** deploy them.

### CP-3.1 — Cut over trinity ArgoCD

**Target cluster: trinity.** Confirm the context before any write. Use the new
`argocd` project's **trinity** client from CP-0.6, not the OCI or `homelab` client.

> Test the built-in `admin` break-glass login before changing SSO.

1. Back up the existing Secret securely, then replace creds in `argocd-auth0`
   (keep the label!):
   ```bash
   CID=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_ids | jq -er .argocd_trinity)
   SEC=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_secrets | jq -er .argocd_trinity)
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
   ArgoCD uses OIDC discovery. Check the requested claims and RBAC mapping
   against actual identities/claims; no project roles are created initially.
   Map intended administrators explicitly and keep default permissions minimal;
   successful org-wide login must not imply admin.
3. Deploy the argocd release, then `kubectl -n argocd rollout restart deploy/argocd-server`.
- **Verify:** at `https://trinity.argocd.arendse.nom.za`, an `arendse` user can
  log in without project roles and unauthenticated access is challenged. The
  intended admin gets `role:admin`; non-admins cannot perform admin operations.
  Test outside-org denial when available and record unavailable outside-org or
  non-admin tests honestly. Use fresh sessions. If SSO misbehaves, use the local
  `admin` fallback.
- **Rollback:** revert `issuer`/`name` and restore the Auth0 client id/secret.

---

## Phase 4 — ArgoCD (OCI)

### CP-4.1 — Cut over OCI ArgoCD
Same as CP-3.1 but for the **oci** cluster. Confirm its context and local admin
fallback separately before any write:
- Use the new `argocd` project's **OCI** client, never the trinity credentials.
  After the preparation gate, read the verified outputs:
  ```bash
  CID=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_ids | jq -er .argocd_oci)
  SEC=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_secrets | jq -er .argocd_oci)
  ```
- Edit the issuer in `infrastructure/kubernetes/argocd.yaml`.
- Apply manually, then restart `argocd-server` in that cluster and verify at
  `https://argocd.arendse.nom.za`, including the same allowed/denied and RBAC
  tests as CP-3.1. The two clients share the temporary org-wide login policy,
  but each ArgoCD instance enforces its own RBAC; no project roles are required.

---

## Phase 5 — Pi-hole (independent integration, OCI)

Pi-hole already uses Zitadel through `pihole-zitadel-oauth2-proxy`, with its
hand-made client in the `trinity` **Zitadel project** (not the hosting cluster).
It runs on **oci**. Leave it working until this checkpoint; do not fold it into
media's shared client or access policy.

### CP-5.1 — Move Pi-hole to its dedicated project/application

**Target cluster: oci.** Confirm the context before any write.

1. After the preparation gate, confirm the new `pihole` project's client,
   callback and temporary org-wide policy from CP-0.6 (no user assignments).
   Decide the proxy arrangement here; retaining the current per-app reverse
   proxy is the smallest change. Keep independent credentials and cookie/session
   configuration regardless of topology.
2. Back up the existing Secret securely. Read the verified new credentials:
   ```bash
   CID=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_ids | jq -er .pihole)
   SEC=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_secrets | jq -er .pihole)
   ```
   Update the Pi-hole integration's credentials and restart its proxy. If
   topology or values must change, prepare the exact GitOps rollout order before
   writing anything; do not combine an unplanned proxy redesign with the swap.
3. In fresh sessions, confirm an `arendse` user can reach
   `https://pihole.arendse.nom.za` without a Pi-hole project role, and that
   unauthenticated access is challenged. Test outside-org denial when available;
   record unavailable negative tests honestly. Retain any Pi-hole-local
   authentication; this is an edge access gate, not a local admin grant.

**Done:** Pi-hole uses its dedicated project/client with independently managed
credentials; org-wide login is temporary, per-project users are deferred.
**Rollback:** restore its previous Secret and any previous proxy configuration,
then restart on **oci**. The issuer stays Zitadel; retain the old client until
Phase 6.

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

### CP-6.4 — Clean up the superseded Zitadel objects
After every integration has moved to its target project inside **`arendse`**
and passed burn-in, inventory the remaining consumers before removing anything:
- Remove unused hand-made PoC/Pi-hole clients in the `trinity` project only
  after CP-5.1 and the PoC teardown. Keep the project if anything else uses it.
- Retire the original Terraform-managed `homelab` clients/project through
  Terraform, not console deletion. Review the exact planned deletions and
  retire their legacy outputs only when no consumer or rollback needs them.
- Remove the temporary media PoC client through Terraform after CP-6.1.

Keep the `arendse` organization, its users, and the built-in **`ZITADEL`**
project. These are not migration leftovers.

### CP-6.5 — Update docs
Refresh the READMEs (`applications/oauth2-proxy/`, `applications/monitoring/`,
`infrastructure/kubernetes/ARGOCD-SSO.md`, `AGENTS.md` if it mentions Auth0) so
Zitadel is described as the primary provider. Mark this checklist complete and
retain it as the migration/decision record.

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
| Pi-hole (oci) | Unchanged Zitadel issuer; restore previous proxy config if changed | `pihole-zitadel-oauth2-proxy` with original `trinity` project credentials |

The Auth0 client ids live in `infrastructure/identity/auth0.tf`; the secrets are
in your password manager / Auth0 dashboard (never in Git).
