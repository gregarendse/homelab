# Loki Setup

Loki is configured to use OCI Object Storage via its S3-compatible API.

## Storage Configuration

The bucket name is `homelab-loki-logs`.

You need to provide OCI Customer Secret Keys via a Kubernetes Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: loki-s3-secret
  namespace: loki
type: Opaque
stringData:
  access_key: <OCI_ACCESS_KEY>
  secret_key: <OCI_SECRET_KEY>
```

## Retention

A 7-day retention period is configured to ensure storage usage remains within the OCI free tier (20GB).
