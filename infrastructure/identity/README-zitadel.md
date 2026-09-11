# Configuring Zitadel Cloud with Terraform

This manages Zitadel Cloud projects and OIDC apps inside the **existing
`arendse` organization**, referenced by `var.zitadel_org_id`. It does not create
or look up the org. Auth0 resources are commented out and were **never imported
into state**; the live Auth0 tenant remains untouched for rollback.

**CP-0.5–0.6 are complete based on user confirmation:** the user reported
**10 added, 0 changed, 0 destroyed** and confirmed the requested post-apply
checks look good. **CP-0.7 rollout and fresh login passed on trinity**, also
reported by the user. The PoC now uses `media_poc` in the `media` project.
The user confirmed normal Sonarr/Pi-hole access and explicitly accepted deferring
outside-org denial testing in this single-user setup. **CP-0.7 is complete with
that deferral; CP-1.1 on trinity is being prepared, not deployed.** Outside-org denial is
not proven; revisit it before adding users or changing access policies.
Project IDs and results are recorded in `applications/zitadel/MIGRATION.md`.
The existing `zitadel_project.homelab` and `zitadel_application_oidc.app` (four
legacy clients) remain intact, including the previous PoC rollback credentials.
Pi-hole keeps its hand-made client in the `trinity` Zitadel project until its
later cutover on the **oci** cluster.

New `zitadel_project.sso` has `for_each` keys `media`, `pihole`, `argocd`,
`grafana`. New `zitadel_application_oidc.sso` has these six client keys:

| Client/output key | Project | Consumer / cluster | Callback (default `base_domain`) |
|---|---|---|---|
| `media` | `media` | Production edge SSO for the `*arr` apps / **trinity** | `https://auth.arendse.nom.za/oauth2/callback` |
| `media_poc` | `media` | Separate isolated PoC proxy / **trinity** | `https://auth-zitadel.arendse.nom.za/oauth2/callback` |
| `pihole` | `pihole` | Dedicated Pi-hole proxy / **oci** | `https://pihole.arendse.nom.za/oauth2/callback` |
| `grafana` | `grafana` | Grafana OIDC (`applications/monitoring`) / **oci** | `https://grafana.arendse.nom.za/login/generic_oauth` |
| `argocd_trinity` | `argocd` | Native ArgoCD OIDC / **trinity** | `https://trinity.argocd.arendse.nom.za/auth/callback` |
| `argocd_oci` | `argocd` | Native ArgoCD OIDC / **oci** | `https://argocd.arendse.nom.za/auth/callback`, `https://oci.argocd.arendse.nom.za/auth/callback` |

Existing Grafana/ArgoCD callback and logout URLs are unchanged. Each deployment
gets separate client credentials; production media and PoC no longer share a
client in the new layout. Terraform generates `client_id`/`client_secret` at
apply; runtime copies belong in externally-managed Kubernetes Secrets, never
Git. The management PAT is not a workload secret.

### Temporary access policy

All four new projects use `org_id = var.zitadel_org_id`,
`has_project_check = true`, `project_role_check = false` and
`project_role_assertion = true`. With **no project grants to external orgs**, all
users in `arendse` may log in initially, without roles or per-user assignments.
No project grants, roles, assignments, policy resources or Kubernetes providers
are added. Role assertion does not itself grant app permissions.

**Self-registration must remain disabled.** The user reports it is disabled;
this has not been independently verified, and Terraform does not manage that
policy. Future users added to `arendse` automatically gain login to all four
projects. **Tighten access before adding users or re-enabling signup**; defer
per-project users/role checks until wanted. App RBAC remains separate: org-wide
login does **not** mean everyone is a Grafana or ArgoCD admin.

The legacy `homelab` project keeps both checks disabled; its existing behavior
is not evidence of the new org boundary. Follow `applications/zitadel/MIGRATION.md`
for fresh-session tests: allowed org login, unauthenticated challenge, outside-org
denial when an account is available, and separate app RBAC. Record any unavailable
negative test honestly, not as a pass; a within-org user without a role is allowed.

## 1. Create a Zitadel service user + PAT

Terraform talks to the Zitadel management API as a service (machine) user:

1. Zitadel Console → your instance → **Users → Service Users → New**. Name it
   e.g. `terraform`.
2. Give it **ORG_OWNER** on the org that will hold the projects (`arendse`):
   Console → Organization → **Managers** → New. That is all this module needs —
   it creates projects and applications *inside* an existing org and never
   touches instance-level resources.
3. On the service user → **Personal Access Tokens → New** → copy the token.
4. Put the instance domain + token in `.auto.tfvars` (git-ignored by the
   repo-wide `*.tfvars` rule):

   ```hcl
   # INSTANCE domain — not an org name. Same host as the OIDC issuer.
   zitadel_domain       = "homelab-jj4izt.eu1.zitadel.cloud"
   zitadel_access_token = "<personal-access-token>"
   # ID of the existing org to create the projects in (from the Console URL).
   zitadel_org_id       = "380143417033860850"
   # base_domain defaults to arendse.nom.za; override if needed.
   ```

   > None of these have defaults. If one is missing, Terraform silently
   > *prompts* for it — which makes a typo look like an authentication failure.
   > A wrong `zitadel_domain` reports `Instance not found`, not a bad token.

   Or export `TF_VAR_zitadel_domain` / `TF_VAR_zitadel_access_token`.

> This module also configures the `auth0` provider, so `terraform plan` expects
> the `auth0_*` variables to be present too. Keep them in `.auto.tfvars` (they're
> already required for the Auth0 side).

## 2. CP-0.5–0.6 complete; preparation reference

The agent does not run a live plan or apply. **User commands, targeting Zitadel
Cloud only** (run from the repository root, using the existing backend/state):

```bash
terraform -chdir=infrastructure/identity init -input=false -backend-config=.config.s3.tfbackend
terraform -chdir=infrastructure/identity plan -input=false
```

The user supplied a live plan showing **10 to add (4 projects and 6 clients),
0 to change, 0 to destroy**, matching CP-0.5. The original 1-project/4-client
apply is historical CP-0.1, not the current plan. Stop and investigate any later
changes/replacements/deletions of legacy resources or Kubernetes resources.
Do not commit plan files or expose secrets.

**The user reported a successful CP-0.6 apply: 10 added, 0 changed, 0 destroyed**
and confirmed the requested post-apply checks look good. CP-0.6 is complete on
that basis; the agent did not independently run those checks. Do not repeat the
creation step. A subsequent plan should report **No changes**. This apply did
not switch workloads. No initial roles/assignments are required;
self-registration must remain disabled and no external project grants should
exist. CP-0.7 has now verified the new `media_poc` rollout/login on **trinity**;
normal Sonarr/Pi-hole access and deferral of outside-org testing are confirmed
by the user. Production cutovers remain separate, deliberate checkpoints.

## 3. Verify outputs after apply; wire credentials only at the matching checkpoint

**CP-0.7 is complete on user confirmation, with outside-org testing explicitly
deferred.** Do not repeat the PoC swap below. Start CP-1.1 separately with the
original Auth0 Secret retained and a coordinated rollout. The user declined an
exported production backup. Successful login alone does not prove outside-org
denial.

| Output | Keys / purpose |
|---|---|
| `zitadel_sso_project_ids` | `media`, `pihole`, `argocd`, `grafana` project IDs |
| `zitadel_sso_client_ids` | Six client keys from the table above; sensitive |
| `zitadel_sso_client_secrets` | Same six keys; sensitive |
| `zitadel_project_id` | Unchanged legacy `homelab` project ID |
| `zitadel_oidc_client_ids` / `zitadel_oidc_client_secrets` | Unchanged legacy keys `oauth2_proxy`, `grafana`, `argocd_trinity`, `argocd_oci`; sensitive |

At CP-0.6, compare project/client IDs with the console and verify both new client
maps have all six keys. Never copy secrets into docs or Git;
`terraform output -json` reveals sensitive values. CP-0.1–0.3 keep legacy output
recipes for the historical setup and rollback.

At CP-0.7, read **only the PoC** credentials (from the repository root):

```bash
CID=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_ids | jq -er .media_poc)
SEC=$(terraform -chdir=infrastructure/identity output -json zitadel_sso_client_secrets | jq -er .media_poc)
```

Stop if either output is missing/empty. **Target cluster: trinity.** Only the user
runs cluster commands; confirm `kubectl config current-context` against the
homelab kubeconfig before any write, never a default work GKE context. Back up the
complete existing PoC Secret securely outside Git and follow CP-0.7 to replace
its credentials and restart only that proxy. Keep the issuer unchanged; restore
the backup with legacy `homelab` credentials if the rehearsal fails.

Later production recipes use these same new client outputs with key `media`
(**trinity**, production proxy), `pihole` (**oci**), `grafana` (**oci**),
`argocd_trinity` (**trinity**) or `argocd_oci` (**oci**). Confirm the named cluster's
context before every write. Never use `media` for the PoC or `media_poc` for
production; identical Grafana/ArgoCD keys in the legacy maps still select the old
`homelab` clients. Preserve Pi-hole's current client and all rollback credentials.

## 4. Migrating off Auth0 (later)

Follow `applications/zitadel/MIGRATION.md`, not a direct issuer-only promotion.
**CP-1.1 preparation is in progress on trinity:** CP-0.5–0.7 are complete, with
the outside-org denial test explicitly deferred by the user. Local production
values now select `oauth2-proxy-zitadel-media` and the Zitadel issuer together.
The user confirmed production preflight: context `trinity`, one ready replica,
Auth0 issuer and the existing `oauth2-proxy` Secret. The user explicitly chose
to skip the exported backup; rollback relies on preserving that original Secret.
The user has now reported `secret/oauth2-proxy-zitadel-media created` in
namespace `oauth2-proxy`, not the PoC namespace. Do not repeat its creation.
Leave the existing Auth0 `oauth2-proxy` Secret intact. The destination Secret is
ready, and the user approved separate local commits for the already-applied
identity code/docs and the single-file cutover. After those commits, the next
deployment action is the user's push; rollout and fresh production login still
need verification. Preparation can safely pause before that push. The agent
handles only local commits, not production deployments or pushes.

Callbacks are prepared in code; apply must register the new clients first.
Cut over one integration at a time with matching issuer/Secret changes and fresh
login/access tests. Grafana and ArgoCD also need explicit app-RBAC review. Pushing
to `master` deploys auto-synced workloads; coordinate Secret/config changes in
one session, and do not use manual Helm upgrades that `selfHeal` would revert.
ArgoCD itself is manually managed; see the checklist for its separate rollout.

For the production media proxy, rollback reverts the paired values change to the
Auth0 issuer and original `existingSecret: oauth2-proxy`; that Secret is never
overwritten during staging. For other Auth0 integrations, restore the previous
configuration and complete Secret. The live Auth0 apps stay intact, outside
Terraform state. PoC and Pi-hole
rollback keeps the Zitadel issuer and restores their previous client credentials;
keep all legacy registrations until migration and burn-in are complete.

## Why there is no zitadel_org resource *or* data source

`zitadel.tf` never declares the organization — neither way works with an
org-scoped token, because both go through instance-level APIs:

| Block | Underlying API | Requires |
|---|---|---|
| `resource "zitadel_org"` | `AddOrganization` (org v2) | IAM_OWNER |
| `data "zitadel_org"` | Admin API `GetOrgByID` + `GetDefaultOrg` | IAM_OWNER |

The data source is the surprising one: merely *reading* an org uses the
instance-scoped Admin API, so an ORG_OWNER token fails with

```
error while getting org by id <id>: PermissionDenied ... (AUTH-5mWD2)
```

The only thing actually needed is the org's ID, and we already have it, so the
org is referenced directly as `org_id = var.zitadel_org_id`. Creating projects
and applications inside an org uses the Management API, which ORG_OWNER covers.
Do not reintroduce the data source “for validation” — it only adds a permission
requirement.

## Notes

- `.auto.tfvars` and `*.tfbackend` are git-ignored — never commit the PAT.
- State (including the generated client secrets) lives in the Backblaze S3
  backend (`.config.s3.tfbackend`), not in Git.
- Changing a callback/logout URL later is a Terraform edit + `apply`, no console
  clicking.
