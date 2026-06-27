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
