# Loki S3 credentials bridge.
#
# The OCI bucket and the S3-compatible Customer Secret Key are provisioned in the
# `storage` stack (infrastructure/storage). Loki itself is deployed via ArgoCD
# (clusters/oci/apps.yaml -> applications/loki/values.yaml), NOT here. The only
# thing Terraform owns in-cluster is the Secret that the Loki Helm release
# consumes (loki-s3-secret).
#
# Cross-stack values are read from the storage stack's LOCAL state file. Both
# stacks are run from this repo on the same machine, so the relative path
# resolves. Run the storage stack first so these outputs exist.
data "terraform_remote_state" "storage" {
  backend = "local"

  config = {
    path = "${path.module}/../storage/terraform.tfstate"
  }
}

# ArgoCD's Loki Application also has CreateNamespace=true; Terraform owns the
# namespace here so the Secret has somewhere to live. Apply Terraform before
# ArgoCD first syncs Loki. Auto-prune is disabled on the Loki app, so ArgoCD
# will not delete this namespace.
#
# TODO (cleanup): the loki namespace and loki-s3-secret were created MANUALLY
# with kubectl while the Backblaze B2 remote state was rate-limited (Longhorn
# blew through the daily Class B transaction cap). Once B2 is reachable again,
# import the existing objects so Terraform adopts them instead of trying to
# recreate (and erroring on "already exists"):
#
#   cd infrastructure/kubernetes
#   terraform import kubernetes_namespace.loki loki
#   terraform import kubernetes_secret.loki_s3 loki/loki-s3-secret
#
# Then `terraform apply` should show no changes (or metadata-only). Remove this
# TODO once the imports are done and state is reconciled.
resource "kubernetes_namespace" "loki" {
  metadata {
    name = "loki"
    labels = {
      "name" = "loki"
    }
  }
}

resource "kubernetes_secret" "loki_s3" {
  metadata {
    name      = "loki-s3-secret"
    namespace = kubernetes_namespace.loki.metadata[0].name
  }

  type = "Opaque"

  data = {
    access_key = data.terraform_remote_state.storage.outputs.loki_s3_access_key
    secret_key = data.terraform_remote_state.storage.outputs.loki_s3_secret_key
  }
}
