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

- **Last verified deployment:** CP-1.1 — production `oauth2-proxy` on **trinity**.
  The user confirmed fresh Zitadel login back to Sonarr, ArgoCD `Synced` /
  `Healthy` at Git revision `884fc5f0428c8f6d580b4e944d3257c08d2fd6ed` (chart
  `10.7.0`), and a successful deployment rollout. The agent verified the values
  at that Git revision; runtime results are user-supplied.
- **Latest decision:** separate `media`, `pihole`, `argocd` and `grafana`
  projects inside `arendse`, initially allowing all org users without individual
  assignments. Self-registration is disabled **according to the user; not
  independently verified**. This remains approved untracked work.
- **Last completed:** CP-1.1 — production media proxy cutover and verification.
  Outside-org denial remains **explicitly deferred, not passed** for this
  single-user setup; revisit it before adding users or changing access policies.
- **In progress:** CP-1.2 — a few days of normal media-app use on **trinity**.
  Make no further auth changes during burn-in. Check login/session refresh and
  access across the protected media apps; keep Auth0's original Secret intact.
  The user asked to keep going, so CP-2.1 **preparation** for Grafana on **oci**
  is proceeding alongside burn-in. This does not mark CP-1.2 complete or deploy
  another cutover.
- **Next action (OCI / CP-2.1):** the user confirmed context OCI and creation of
  `monitoring/grafana-zitadel`, and asked to complete Grafana. The unused Secret
  is staged and the cutover is prepared, **not yet deployed**. Proceed with
  separate documentation and Grafana-only cutover commits; the user pushes and
  verifies the OCI rollout. Link user `2`, then disable email lookup in a second
  rollout during the same session. Do not mark CP-2.1 complete before those checks.
- **Current commit IDs:** `0fc08bd` (identity/docs) and `884fc5f` (single-file
  cutover) in the current Git history. Their earlier local IDs were `e6eeabc`
  and `fb35bde`. The agent compared the production values at `884fc5f` and
  `fb35bde`: identical. The synced revision has the Zitadel issuer and
  `existingSecret: oauth2-proxy-zitadel-media`.
- **Rollback:** retain the original Auth0 `oauth2-proxy` Secret; revert only
  current cutover commit `884fc5f` if needed, with a user-controlled push. An
  exported backup was explicitly declined. The agent made the two approved
  local commits but ran no cluster commands, live Terraform plan/apply or push.

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
| 1.2 | In progress: normal `*arr` use for a few days; retain Auth0 rollback | ☐ |
| 2.1 | Grafana on OCI: Secret staged per user; cutover ready, deployment/linking pending | ☐ |
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
it**. Resume at CP-1.2. Only the user runs cluster commands; confirm the context
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
rollout are confirmed. CP-1.2 burn-in starts now; no further auth changes needed.

**Rollback:** revert dedicated values commit `884fc5f` and have the user push. This
restores both the Auth0 issuer and `existingSecret: oauth2-proxy`, whose original
credentials and cookie key were never changed. Wait for those references to
appear in the deployment and the rollout to finish on **trinity**. No Secret
rewrite is needed for normal rollback. The exported backup was explicitly
skipped, so this depends on the original Secret remaining available. Before the
deployment push, simply leave the new unused Secret in place and stop—there is
no runtime change to undo.

### CP-1.2 — Burn-in

**In progress after CP-1.1 verification. Target cluster: trinity.** No rollout
or configuration change is needed for this checkpoint.

Use the protected media apps normally for a few days. Check:
- Fresh login and returning sessions work, including after session refresh.
- Moving between Sonarr and the other protected media apps works as expected.
- No login loops or unexpected authorization failures appear.

Keep the original Auth0 `oauth2-proxy` Secret and registrations for rollback;
do not remove them or the PoC during burn-in. Outside-org denial remains a
recorded, accepted test gap rather than a pass.

**Done when:** the user confirms normal use has stayed stable for a few days.
CP-2.1 preparation is proceeding on **oci** at the user's request, but media
burn-in remains open. Do not infer stability just because preparation continues.

---

## Phase 2 — Grafana

> Grafana runs on **oci**, managed by ArgoCD Application `oci-monitoring`
> (`clusters/oci/rendered/monitoring.yaml`), using `kube-prometheus-stack`
> **69.0.0** with auto-sync. Stage a separate Secret before a paired values
> change, as in CP-1.1. Keep the existing `grafana-auth0` Secret intact.

### CP-2.1 — Cut over Grafana

**Approved cutover prepared; deployment and verification pending. Target cluster:
oci, not trinity.** Media burn-in remains open. Use the new `grafana` project's
client from CP-0.6, not the original `homelab` client. User confirmation of the
exact verified Zitadel email and approval of the restricted linking window are
recorded below. The user confirmed OCI context and creation of the unused
`monitoring/grafana-zitadel` Secret. Actual claim delivery and account linking
remain untested. **Pushing the values to master deploys the temporary window.**
The user asked to complete Grafana: proceed with separate documentation and
cutover commits. Only the user pushes and runs the OCI rollout/login checks;
then close the temporary window in section D before stopping.

#### A. Confirm the OCI deployment and local admin fallback ✅

**Confirmed by user output:**
- OCI Grafana deployment has one ready replica and image
  `docker.io/grafana/grafana:11.4.1`.
- OAuth environment Secret is `grafana-auth0`.
- HTTP Basic `GET /api/user` returned local user `id: 1`, `login: admin`,
  `isGrafanaAdmin: true`. Credentials work for the admin API; no password was
  shared. This does not enable or test the currently hidden browser login form.

The commands below are completed checks, not a request to reset any
credentials. Account-preservation approval is recorded in section B; Secret
staging in section C is now user-confirmed.
Only the user runs cluster commands. Select the OCI kubeconfig and confirm
`kubectl config current-context` before any write. Read the deployment without
printing credential values:

```bash
kubectl --context=oci -n monitoring get deployment monitoring-grafana -o json |
  jq '{ready: .status.readyReplicas,
    containers: [.spec.template.spec.containers[] | {
      name, image,
      envSecrets: [.envFrom[]?.secretRef.name // empty],
      credentialSecrets: ([.env[]?.valueFrom.secretKeyRef.name // empty] | unique)
    }]}'
```

Expect the Grafana container to reference `grafana-auth0` and the separate
`grafana-admin-credentials` Secret. Record its actual image/version before
planning account migration; the pinned parent chart uses Grafana chart `8.8.*`.

**The last user-verified Auth0 deployment hides the login form and enables
OAuth auto-login; prepared local values reverse both settings.** The
admin Secret's existence does not prove the persisted password is current.
With the existing local admin username (`admin` if unchanged), the user can
check HTTP Basic authentication against Grafana on **oci**:

```bash
curl -q --basic --user admin --fail --silent --show-error \
  --connect-timeout 10 --max-time 20 \
  https://grafana.arendse.nom.za/api/user |
  jq '{id, login, isGrafanaAdmin}'
```

Curl prompts for the local password; do not put it in command history or share
it. Do not follow redirects, disable TLS verification, or use a service token.
Pass: the expected local user and `isGrafanaAdmin: true`, not an error/HTML or an
SSO cookie. Basic auth is separate from the hidden login form, but must be
confirmed live. If this fails, stop; do not reset credentials blindly. Updating
the Secret and restarting does **not** reset an existing persisted Grafana
password. `/login?disableAutoLogin=true` also does not unhide a disabled form.

#### B. Preserve the existing Grafana account (approved; not yet executed)

**Account inventory confirmed by user:**

| Purpose | Grafana ID | Login / email | Organization |
|---|---|---|---|
| Local server-admin fallback | `1` | Login `admin`; server-admin API access verified | Not part of the OAuth migration |
| Existing Auth0-backed account | `2` | `greg.arendse@gmail.com` for both login and email | `orgId: 1` |

Preserve user `2` and its organization membership/permissions; do not recreate
it or merge it with local admin `1`. The inventory came from `/api/user` in the
existing Auth0 browser session, separately from the local-admin Basic-auth test.

Grafana's generic OAuth identity uses the external `sub`; Zitadel supplies a
new subject even when the email matches Auth0. In Grafana `11.4.x`, insecure
email lookup is off by default, so an existing email/login can produce a user
collision rather than automatic linking. Do not enable
`oauth_allow_insecure_email_lookup` as an automatic workaround or delete users.

**Approved by the user:** a short, restricted email-linking window, rather than
deleting user `2` or editing the Grafana database directly. The user also
confirmed the Zitadel email is exactly `greg.arendse@gmail.com` and marked
verified. This is a user-reported console check, not a captured token/claim test.
Local values now prepare this restriction; no runtime setting has changed.

1. **Grafana database backup explicitly declined by the user.** Keep local
   server-admin `1` and the Auth0 Secret available. Recovery will need a
   separately reviewed reverse-linking procedure, not restoration from a new
   pre-cutover backup. The exact verified Zitadel email is user-confirmed; the
   login gate will require boolean `email_verified` true in the claims.

   **Provider inventory confirmed by user output on OCI:** email lookup is
   `false`; only `auth.basic` and `auth.generic_oauth` are enabled. Generic OAuth
   currently allows signup and uses the substring Admin/Viewer rule, with strict
   role checking off. `org_mapping` is empty, role sync is enabled, and granting
   server-admin privileges is disabled. No second OAuth provider was reported.
   The user subsequently confirmed the exact verified Zitadel email and approved
   the linking window. No second provider may be enabled during that window.

   The completed read-only check is retained below. Keep the filter intact: the
   unfiltered settings response may contain sensitive configuration.

   ```bash
   curl -q --basic --user admin --fail --silent --show-error \
     --connect-timeout 10 --max-time 20 \
     https://grafana.arendse.nom.za/api/admin/settings |
     jq '{emailLookup: .auth.oauth_allow_insecure_email_lookup,
       enabledAuthSections: [to_entries[] |
         select(.key | startswith("auth.")) |
         select(.value.enabled == "true" or .value.enabled == true) | .key],
       genericOAuth: (."auth.generic_oauth" | {
         allow_sign_up, role_attribute_path, role_attribute_strict,
         org_mapping, skip_org_role_sync, allow_assign_grafana_admin
       })}'
   ```

   This is read-only. The API password prompt is expected; do not share the
   password or raw settings. The provider inventory check and linking approval
   are complete, and Secret staging is user-confirmed. The reviewed deployment
   remains pending.
2. Temporarily enable global `[auth] oauth_allow_insecure_email_lookup` for the
   provider cutover. Gate generic OAuth login to that **exact verified email**:
   strict role checking, no alternative org mapping, role sync enabled, and an
   expression returning organization `Admin` only for the match and no role
   otherwise. Disable OAuth user creation (`allow_sign_up: false`) and do not
   grant Grafana server-admin privileges. The current inventory shows no other
   enabled OAuth provider; recheck if authentication configuration changes before
   the linking window, since the email-lookup switch is global.
3. Log in through Zitadel and verify `/api/user` still reports **user `2`, org
   `1`** and the expected organization Admin permissions. Keep local admin `1`
   available; its browser form must be restored for the cutover.
4. In a separate follow-up rollout, disable insecure email lookup again.
   Revoke user `2`'s old sessions using Grafana's supported admin logout API,
   then repeat fresh Zitadel login with lookup **off**. Verify user ID and
   permissions again and test refresh. Leave email lookup off long-term.
   Complete linking and disabling lookup in the same session; do not leave the
   temporary setting enabled between work sessions.

**Security tradeoff (accepted for this window):** email lookup is disabled by
default for a reason; a matching address alone must not become a general
account-adoption rule. The strict verified-email gate is evaluated before user
linking in Grafana 11.4.1. Self-registration being disabled reduces exposure but
is not a substitute for that gate or the approval recorded above. This
temporarily admits only the migration user, not every org user; broader access
can be restored after safe role mapping is reviewed, with email lookup still off.

**Rollback is not just a Secret revert:** Grafana 11.4.1 updates the existing
`oauth_generic_oauth` binding for user `2` to the Zitadel subject and OAuth-token
data. Restoring Auth0 settings alone may then fail to find the old subject.
The user chose not to take a pre-cutover database backup. If the binding has
changed and rollback is needed, separately approve a restricted reverse-linking
window against Auth0, verify user `2` is restored, then disable lookup again.
Do not assume merely restoring Auth0 URLs/credentials reverses the database write.
A failed later login step can still follow a successful binding update; inspect
before retrying. Old sessions or cached auth lookups are not rollback proof.

The backup decision is settled: **skip it**, as requested. The temporary
email-linking window is approved and prepared in local values. Only the new,
unused Secret has been created, per the user; no live security setting or user
mapping has changed. Recovery via reverse linking, if needed, still requires
its own reviewed procedure; do not improvise a rollback.
Sources: [Grafana email lookup guidance](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/#enable-email-lookup),
[11.4.1 user linking](https://github.com/grafana/grafana/blob/v11.4.1/pkg/services/authn/authnimpl/sync/user_sync.go),
[11.4.1 auth binding updates](https://github.com/grafana/grafana/blob/v11.4.1/pkg/services/login/authinfoimpl/store.go).

#### C. Secret staged; review the paired cutover (next)

**Staging complete according to the user:** OCI context was confirmed, then the
user reported the creation command completed. The original Auth0/admin Secrets
were not targeted by that command. No restart or deployment was requested.
Step 1 is retained for reference; do not repeat it. Resume at commit review.

1. **User only, target OCI.** Confirm `kubectl config current-context` prints
   `oci` before writing. From the repository root, keep this pipeline intact
   and shell tracing off; do not print or save Terraform's credential outputs:

   ```bash
   terraform -chdir=infrastructure/identity output -json |
     jq -se 'if length != 1 then error("Expected one Terraform output object") else .[0] | {
       apiVersion: "v1", kind: "Secret", type: "Opaque",
       metadata: {name: "grafana-zitadel", namespace: "monitoring"},
       stringData: {
         GF_AUTH_GENERIC_OAUTH_CLIENT_ID: .zitadel_sso_client_ids.value.grafana,
         GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: .zitadel_sso_client_secrets.value.grafana
       }
     } | if all(.stringData[]; type == "string" and length > 0)
         then . else error("Missing Grafana credentials") end end' |
     kubectl --context=oci -n monitoring create -f -
   ```

   Missing/empty credentials abort the filter. `create` deliberately fails if
   the Secret exists; inspect rather than overwrite it. **Safe stopping point:**
   the Secret is unused until the values deploy. Do not restart Grafana. Keep
   `grafana-auth0` and `grafana-admin-credentials` untouched.
2. **Review local `applications/monitoring/values.yaml`.** It now selects
   `grafana.envFromSecret: grafana-zitadel` and the provider name/URLs under
   `grafana.grafana.ini.auth.generic_oauth`:

   ```yaml
   name: Zitadel
   auth_url: https://homelab-jj4izt.eu1.zitadel.cloud/oauth/v2/authorize
   token_url: https://homelab-jj4izt.eu1.zitadel.cloud/oauth/v2/token
   api_url: https://homelab-jj4izt.eu1.zitadel.cloud/oidc/v1/userinfo
   ```

   PKCE, refresh tokens and `openid profile email offline_access` are preserved.
   Local login is exposed and auto-login disabled. Global email lookup is
   temporarily enabled with this exact Generic OAuth restriction:

   ```yaml
   allow_sign_up: false
   role_attribute_path: >-
     (email == 'greg.arendse@gmail.com' && email_verified == `true`) && 'Admin' || ''
   role_attribute_strict: true
   skip_org_role_sync: false
   allow_assign_grafana_admin: false
   ```

   Leave `org_mapping` unset and do not introduce a Viewer fallback. This grants
   organization Admin only, not server GrafanaAdmin.
3. **Only deploy when there is time to finish section D in the same session.**
   Confirm Secret creation, review the entire unpushed commit set, and obtain
   approval for a dedicated commit containing only the monitoring values. Keep
   migration docs separate and unrelated working-tree changes out. The user
   pushes; auto-sync deploys. No commit or push is authorized by preparation alone.
   A changed Secret reference triggers a rollout; do not restart early or run a
   manual Helm upgrade that self-healing would undo.

#### D. Verify linking, then close the temporary window (not yet started)

1. **OCI, read-only:** verify `oci-monitoring` is `Synced` / `Healthy` at the
   intended Git revision, then check rollout:

   ```bash
   kubectl --context=oci -n argocd get application oci-monitoring -o json |
     jq '{sync: .status.sync.status, health: .status.health.status, revisions: .status.sync.revisions}'
   kubectl --context=oci -n monitoring rollout status deployment/monitoring-grafana --timeout=120s
   ```

   Re-run the filtered settings request from section B. Expect email lookup
   `true`, signup `false`, strict roles `true`, the exact verified-email rule,
   no org mapping, role sync enabled and server-admin assignment disabled.
   Do not test linking if these differ. Verify local admin browser login in a
   separate session and keep it available.
2. In a fresh private browser, choose Zitadel and log in. Visit `/api/user` on
   Grafana: require `id: 2`, `orgId: 1`, expected email, and no server-admin grant.
   Visit `/api/user/orgs`: require organization `1` has role `Admin`. If anything
   differs, stop and inspect without deleting users or weakening the gate.
3. **Immediately close the window:** set only
   `grafana.grafana.ini.auth.oauth_allow_insecure_email_lookup` to `false`, then
   review/approve a second dedicated values commit and user push. Do not combine
   the two rollouts; the first fresh login must link before lookup is disabled.
   Leave the strict gate and local login form intact. Repeat rollout/health and
   the filtered settings check; require email lookup `false` on the live server.
4. **User-run Grafana API write on OCI:** after confirming lookup is off,
   invalidate all sessions for migrated user `2` (not local admin `1`):

   ```bash
   curl -q --basic --user admin --request POST --fail --silent --show-error \
     --connect-timeout 10 --max-time 20 \
     https://grafana.arendse.nom.za/api/admin/users/2/logout
   ```

   Enter the local admin password at the prompt; share no credentials/cookies.
   Log in through Zitadel in a new private session with lookup off and verify
   user `2`, org `1` and organization Admin again. Test session refresh and
   record results; an existing session alone does not prove linking succeeded.
   If linking fails, close the lookup window rather than leaving it enabled
   between sessions, retain local admin access and review recovery separately.

**Done when:** fresh Zitadel login works, the intended existing account/permissions
are preserved as agreed, the intended admin has organization Admin, local
break-glass access works, and refresh/session behavior is verified. Record any
unavailable non-admin/outside-org test honestly; no automatic admin for all users.

**Rollback:** revert only the paired values change and have the user push,
restoring Auth0 URLs and `envFromSecret: grafana-auth0`. The old Secret stays
intact. Follow the separately agreed restoration procedure if account mappings
were changed. Local values are prepared; no rollout or account changes have
been reported yet.

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
