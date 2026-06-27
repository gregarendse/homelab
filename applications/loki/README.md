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
