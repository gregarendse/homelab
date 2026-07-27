# Loki Setup

Loki is configured to use OCI Object Storage via its S3-compatible API.

## Storage Configuration

The bucket name is `homelab-loki-logs`.

Loki authenticates to OCI Object Storage via its S3-compatible API using an OCI
Customer Secret Key. Both the bucket and the credentials are provisioned by
Terraform:

- **`infrastructure/storage`** creates the bucket
  (`oci_objectstorage_bucket.loki_storage`) and the S3 credential
  (`oci_identity_customer_secret_key.loki_s3`), exposing them as outputs.
- **`infrastructure/kubernetes`** reads those outputs via `terraform_remote_state`
  and creates the `loki-s3-secret` Secret in the `loki` namespace
  (`loki.tf`).

Loki itself is still deployed via ArgoCD (`clusters/oci/apps.yaml` ->
`applications/loki/values.yaml`); only the credential Secret is managed by
Terraform.

### Apply order

1. `cd infrastructure/storage && terraform apply` (creates bucket + credential)
2. `cd infrastructure/kubernetes && terraform apply` (creates the Secret)
3. ArgoCD syncs the Loki Helm release, which consumes the Secret.

> Note: the credential's secret key is returned by OCI only at creation time and
> is therefore stored in both stacks' Terraform state. OCI permits a maximum of
> 2 customer secret keys per user.

## Retention

A 7-day retention period is configured to ensure storage usage remains within the OCI free tier (20GB).

## Longhorn / Backblaze backups

Loki's Longhorn PV is **intentionally excluded** from the staggered Backblaze B2
backups (see the repo-root `README.md` "Longhorn Backups" section). The volume is
large and high-churn, and — more importantly — the log data it holds already
lives durably in OCI Object Storage (`homelab-loki-logs`), so backing the PV up to
B2 would double-store reproducible data and push total B2 usage past the
free-tier 10 GB storage cap.

Concretely, the `storage-loki-0` PVC carries **no** `recurring-job.longhorn.io/source`
or `recurring-job-group.longhorn.io/<day>-backup` labels, so no RecurringJob picks
it up. Because the PVC is created from an immutable StatefulSet
`volumeClaimTemplate`, this exclusion cannot be enforced purely from Git on an
already-provisioned volume — if the labels ever reappear on the live PVC/Volume,
strip them by hand:

```bash
kubectl -n loki label pvc storage-loki-0 \
  recurring-job.longhorn.io/source- recurring-job-group.longhorn.io/sunday-backup-
# and the matching Longhorn Volume CR (find its pvc-... name via `kubectl -n loki get pvc`)
kubectl -n longhorn-system label volumes.longhorn.io <loki-pv-name> \
  recurring-job.longhorn.io/source- recurring-job-group.longhorn.io/sunday-backup-
```

The `sunday-backup` RecurringJob is deliberately kept in
`infrastructure/kubernetes/longhorn.tf` (empty group) so a future volume can be
assigned to Sunday without redefining the job.
