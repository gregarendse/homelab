resource "oci_objectstorage_bucket" "loki_storage" {
  compartment_id = data.oci_identity_compartment.homelab.id
  name           = var.loki_storage_bucket_name
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  storage_tier   = "Standard"
  versioning     = "Disabled"

  freeform_tags = var.tags
}

output "loke_storage_uri" {
  value = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
}

# S3-compatible (Customer Secret Key) credentials used by Loki to talk to the
# bucket above via the OCI Object Storage S3-compatibility endpoint.
#
# NOTE: the secret_key is only returned by OCI at creation time and is stored in
# this stack's Terraform state. OCI allows at most 2 customer secret keys per
# user. The Kubernetes Secret itself is created in the `kubernetes` stack, which
# reads the outputs below via terraform_remote_state.
resource "oci_identity_customer_secret_key" "loki_s3" {
  display_name = "loki-s3"
  user_id      = var.user_ocid
}

output "loki_storage_bucket_name" {
  description = "Name of the OCI Object Storage bucket backing Loki"
  value       = oci_objectstorage_bucket.loki_storage.name
}

output "loki_s3_access_key" {
  description = "OCI S3-compatible access key (Customer Secret Key OCID) for the Loki bucket"
  value       = oci_identity_customer_secret_key.loki_s3.id
}

output "loki_s3_secret_key" {
  description = "OCI S3-compatible secret key for the Loki bucket"
  value       = oci_identity_customer_secret_key.loki_s3.key
  sensitive   = true
}
