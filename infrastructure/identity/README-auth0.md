# Auth0 Terraform retired — live retirement pending

This root now configures only Zitadel. Follow [README-zitadel.md](README-zitadel.md)
for identity management and [Phase 6 of the migration checklist](../../applications/zitadel/MIGRATION.md#phase-6--decommission-auth0-only-after-a-solid-burn-in)
for retirement progress and approvals.

The user-supplied `terraform state list` contained only Zitadel resources;
Auth0 was never imported. The commented Auth0 imports/generated resources,
discovery script, provider requirement/configuration, lock entry and input
variables have been removed. The old import instructions remain in Git history,
not as a setup procedure to run again.

**This repository cleanup does not delete Auth0 clients, the tenant, runtime
Secrets or private credentials.** The user-run identity plan reported
**"No changes. Your infrastructure matches the configuration."** No apply is
needed; live removals still require separate approval. Do not run
`terraform destroy` or edit state for this cleanup.

Before planning, remove the obsolete `auth0_domain`, `auth0_client_id` and
`auth0_client_secret` assignments from private `.auto.tfvars`/other variable
files, and stop passing those variables via CLI or automation. Unset the matching
`TF_VAR_auth0_*` exports if present. Keep all Zitadel inputs and existing backend
settings unchanged. Never paste private variable files or secrets into chat.

The user deferred live cleanup to the next session (CP-6.2). All four Auth0
runtime Secrets, clients and the tenant remain untouched; recheck consumers and
obtain deletion approval when resuming. They remain the rollback path until
retirement. Grafana's optional automatic role-sync fix and
cleanup of unused Zitadel projects/PoC clients do not block Auth0 retirement.
