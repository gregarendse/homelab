# Read-only principal for External Secrets Operator.
#
# The API key is deliberately not a Terraform resource. CI applies this stack
# without that public key, so a managed api-key resource would be destroyed on
# the next apply. Upload the public key out of band after the user exists.
# The private key never enters Terraform.

resource "oci_identity_user" "external_secrets" {
  compartment_id = var.tenancy_ocid
  name           = "external-secrets"
  description    = "Read-only OCI Vault client for External Secrets Operator"

  freeform_tags = var.tags
}

resource "oci_identity_user_capabilities_management" "external_secrets" {
  user_id = oci_identity_user.external_secrets.id

  can_use_api_keys             = true
  can_use_auth_tokens          = false
  can_use_console_password     = false
  can_use_customer_secret_keys = false
  can_use_smtp_credentials     = false
}

resource "oci_identity_group" "external_secrets" {
  compartment_id = var.tenancy_ocid
  name           = "external-secrets"
  description    = "Read-only OCI Vault access for External Secrets Operator"

  freeform_tags = var.tags
}

resource "oci_identity_user_group_membership" "external_secrets" {
  group_id = oci_identity_group.external_secrets.id
  user_id  = oci_identity_user.external_secrets.id
}

resource "oci_identity_policy" "external_secrets" {
  compartment_id = data.oci_identity_compartment.homelab.id
  name           = "external-secrets"
  description    = "Allow External Secrets Operator to read Vault secrets and decrypt them with the software key"

  statements = [
    "Allow group ${oci_identity_group.external_secrets.name} to read secret-family in compartment ${data.oci_identity_compartment.homelab.name}",
    "Allow group ${oci_identity_group.external_secrets.name} to use keys in compartment ${data.oci_identity_compartment.homelab.name} where target.key.id = '${oci_kms_key.homelab.id}'",
  ]

  freeform_tags = var.tags
}
