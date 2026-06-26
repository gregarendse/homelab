resource "oci_objectstorage_bucket" "loki_storage" {
  compartment_id = oci_identity_compartment.homelab.id
  name           = var.loki_storage_bucket_name
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  storage_tier   = "Standard"
  versioning     = "Disabled"

  freeform_tags = var.tags
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = oci_identity_compartment.homelab.id
}

variable "loki_storage_bucket_name" {
  description = "Name of the OCI Object Storage bucket for Loki logs"
  type        = string
  default     = "homelab-loki-logs"
}
