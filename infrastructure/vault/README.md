# Vault

Always Free OCI Vault for the homelab. This stack creates the vault, the software key, and a read-only user. It does not create secret values, and it does not create the user's API key.

Applied by the `production`-gated Terraform workflow on merge to `master`. A push plans and, after approval, applies. Do not apply this against any other tenancy.

## What gets created

| Resource | Value |
|---|---|
| `oci_kms_vault.homelab` | `vault_type = DEFAULT` |
| `oci_kms_key.homelab` | AES-32, `protection_mode = SOFTWARE` |
| `oci_identity_user.external_secrets` | API keys only. No console password. |
| `oci_identity_policy.external_secrets` | `read secret-family` plus `use keys` on this key only |

`policy/free_tier.rego` rejects any other vault type or key protection mode. The provider's default key protection mode is `HSM`, so `SOFTWARE` is set explicitly.

Do not add `oci_vault_secret` here. The secret content would be stored in this stack's Backblaze state.

## Local init

Backend credentials are not committed. Copy another stack's gitignored `.config.s3.tfbackend` into this directory, then:

```bash
terraform -chdir=infrastructure/vault init -backend-config=.config.s3.tfbackend
```

## API key, after the first apply

Generate the key outside the repo. Terraform must not see the private key. CI must not see the public key either: a managed API key would be destroyed on the next CI apply, because that apply does not have the key.

```bash
openssl genrsa -out external-secrets.pem 2048
openssl rsa -pubout -in external-secrets.pem -out external-secrets.pub
chmod 600 external-secrets.pem
```

Upload the public key with the user OCID from `terraform output external_secrets_user_id`:

```bash
oci iam user api-key upload \
  --user-id "<external_secrets_user_id>" \
  --key-file external-secrets.pub
```

Keep `external-secrets.pem` and the fingerprint from that command. They become the one bootstrap Secret for External Secrets Operator. They do not go in Git.
