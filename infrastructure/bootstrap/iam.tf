# One-time bootstrap. Apply LOCALLY with an admin identity, never from CI
# (CI must not be able to edit its own permissions).
# Legacy IAM resources below target the Default identity domain.

variable "tenancy_ocid" { type = string }
variable "compartment_ocid" { type = string }
variable "compartment_name" { type = string }
variable "state_bucket_name" { type = string }
variable "ci_group_name" { type = string }
variable "ci_user_name" { type = string }
variable "ci_user_email" { type = string }

locals {
  tags = {
    terraform   = "true"
    environment = "homelab"
    project     = "homelab"
  }
}

resource "oci_identity_group" "ci" {
  compartment_id = var.tenancy_ocid
  name           = var.ci_group_name
  description    = "GitHub Actions Terraform deployer"
  freeform_tags  = local.tags
}

resource "oci_identity_user" "ci" {
  compartment_id = var.tenancy_ocid
  name           = var.ci_user_name
  description    = "GitHub Actions Terraform deployer"
  email          = var.ci_user_email
  freeform_tags  = local.tags
}

resource "oci_identity_user_group_membership" "ci" {
  group_id = oci_identity_group.ci.id
  user_id  = oci_identity_user.ci.id
}

resource "oci_identity_policy" "ci" {
  compartment_id = var.tenancy_ocid
  name           = "${var.ci_group_name}-policy"
  description    = "Least-privilege Terraform CI access, scoped to one compartment"
  freeform_tags  = local.tags

  statements = [
    "Allow group ${oci_identity_group.ci.name} to manage instance-family in compartment ${var.compartment_name}",
    "Allow group ${oci_identity_group.ci.name} to manage virtual-network-family in compartment ${var.compartment_name}",
    "Allow group ${oci_identity_group.ci.name} to manage volume-family in compartment ${var.compartment_name}",
    "Allow group ${oci_identity_group.ci.name} to read compartments in tenancy",
    "Allow group ${oci_identity_group.ci.name} to read buckets in compartment ${var.compartment_name}",
    "Allow group ${oci_identity_group.ci.name} to manage objects in compartment ${var.compartment_name} where target.bucket.name = '${var.state_bucket_name}'",
  ]
}
