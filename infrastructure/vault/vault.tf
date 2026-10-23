# Always Free secret store.
#
# Secret values are not Terraform resources. An `oci_vault_secret` would copy
# the plaintext into this stack's Backblaze state. Create secrets with the OCI
# CLI or console after apply. See README.md.
#
# vault_type and protection_mode are hardcoded. policy/free_tier.rego rejects
# any other value, including an omitted protection_mode (the provider default
# is HSM).

resource "oci_kms_vault" "homelab" {
  compartment_id = data.oci_identity_compartment.homelab.id
  display_name   = "homelab"
  vault_type     = "DEFAULT"

  freeform_tags = var.tags
}

resource "oci_kms_key" "homelab" {
  compartment_id      = data.oci_identity_compartment.homelab.id
  display_name        = "homelab-software"
  management_endpoint = oci_kms_vault.homelab.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }

  freeform_tags = var.tags
}
