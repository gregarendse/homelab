# Monitoring Authentication

## Grafana admin credentials

Grafana's admin user/password are read from an externally-managed Secret
(`grafana.admin.existingSecret` in `values.yaml`), not templated by the chart.
This keeps the password out of Git and out of Helm's server-side-apply field
ownership (templating it caused `conflict with "kubectl-edit"` upgrade failures
when the password was edited manually).

Create the Secret before deploying the `monitoring` release:

```bash
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<strong-password>'
```

See `grafana-admin-credentials.example.yaml`. To rotate the password, update the
Secret and restart Grafana:

```bash
kubectl -n monitoring rollout restart deploy/monitoring-grafana
```

## Ingress basic auth (legacy)

To access Grafana, you need to populate the `grafana-basic-auth` secret in the `monitoring` namespace.

The secret should contain a `users` key with htpasswd formatted entries.

Example of generating the secret data:

```bash
echo -n "admin:$(openssl passwd -apr1 mypassword)" | base64
```

Then apply it manually or via your preferred secret management tool (SealedSecrets, etc):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-basic-auth
  namespace: monitoring
type: Opaque
data:
  users: <result-from-above>
```

**Note:** This is a temporary measure until a proper OIDC provider is integrated.

ToDo: Clean up, removed the `monitoring-auth` middleware helm chart, just apply it manually.
