# Monitoring Authentication

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
