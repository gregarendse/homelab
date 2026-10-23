data "oci_identity_compartments" "compartments" {
  compartment_id            = var.tenancy_ocid
  compartment_id_in_subtree = true
  name                      = var.compartment_name
  state                     = "ACTIVE"
}

data "oci_identity_compartment" "homelab" {
  id = data.oci_identity_compartments.compartments.compartments[0].id
}
