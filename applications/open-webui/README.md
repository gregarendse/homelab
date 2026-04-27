# Open WebUI

Open WebUI is deployed in Kubernetes as a secure chat entry point to the in-cluster Ollama service.

- **Image:** `ghcr.io/open-webui/open-webui:main`
- **Namespace:** `open-webui`
- **Ollama endpoint:** `http://ollama.ollama.svc.cluster.local:11434`

## Security baseline

- TLS ingress via Traefik + cert-manager
- Authentication enabled (`WEBUI_AUTH=True`)
- Public signups disabled (`ENABLE_SIGNUP=False`)
- Secret-managed signing key (`WEBUI_SECRET_KEY`)
- Pod hardening (`runAsNonRoot`, seccomp `RuntimeDefault`, dropped Linux capabilities)

## Prerequisites

Create the namespace and required secret before first deploy:

```bash
kubectl create namespace open-webui
kubectl create secret generic open-webui-secrets \
  --namespace open-webui \
  --from-literal=WEBUI_SECRET_KEY="$(openssl rand -hex 32)"
```

## Deploy

```bash
cd applications/open-webui
nix build .#manifests
kubectl apply -f result
kubectl rollout status deployment/open-webui -n open-webui
```

## Bootstrap admin user

If this is a fresh install and no admin exists yet, you may need a one-time bootstrap:

1. Set `ENABLE_SIGNUP=True` in `open-webui.nix` and redeploy.
2. Create the first admin account in the UI.
3. Set `ENABLE_SIGNUP=False` again and redeploy.

## Access

- URL: `https://openwebui.arendse.nom.za`
- Ensure DNS points this hostname to your Traefik ingress endpoint.

