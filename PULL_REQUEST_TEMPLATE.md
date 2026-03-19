## Summary

Adds [n8n](https://github.com/n8n-io/n8n) workflow automation application following the existing kubenix pattern.

## Files Added

- `applications/n8n/flake.nix` - Nix flake entrypoint using kubenix
- `applications/n8n/n8n.nix` - KubeNix module defining all Kubernetes resources
- `applications/n8n/values.yaml` - Configuration values
- `applications/n8n/Makefile` - Standard deployment targets

## Resources Created

- `Namespace` - n8n
- `PersistentVolumeClaim` - 5Gi on longhorn
- `Deployment` - docker.n8n.io/n8nio/n8n:latest, strategy Recreate
- `Service` - ClusterIP on port 5678
- `Ingress` - n8n.arendse.nom.za with TLS via letsencrypt-prod

## Pre-deploy

Create the encryption key secret before deploying:

```sh
kubectl create secret generic n8n-secret \
  --namespace n8n \
  --from-literal=encryption-key=$(openssl rand -hex 32)
```