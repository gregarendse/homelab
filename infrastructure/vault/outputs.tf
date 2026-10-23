output "vault_id" {
  description = "OCID of the Always Free DEFAULT vault. Safe to commit into a ClusterSecretStore."
  value       = oci_kms_vault.homelab.id
}

output "key_id" {
  description = "OCID of the software master encryption key. Not a secret."
  value       = oci_kms_key.homelab.id
}

output "management_endpoint" {
  description = "Vault management endpoint"
  value       = oci_kms_vault.homelab.management_endpoint
}

output "external_secrets_user_id" {
  description = "OCID of the read-only user. Use this when uploading an API key out of band."
  value       = oci_identity_user.external_secrets.id
}
