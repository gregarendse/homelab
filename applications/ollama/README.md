# Ollama Deployment with Kubenix

This directory contains a kubenix app for running Ollama on Kubernetes and pre-pulling one model.

## What gets deployed

- Namespace: `ollama`
- PVC: `ollama-models` (50Gi, ReadWriteOnce) mounted at `/root/.ollama`
- Deployment: `ollama` using `ollama/ollama:latest` with init container that pulls `llama3.2:3b` on startup
- Service: `ollama` on port `11434`

## Files

- `flake.nix` - Nix flake entrypoint for kubenix rendering
- `ollama.nix` - Kubernetes resources defined with kubenix
- `flake.lock` - Locked flake inputs

## Build and apply

```bash
cd applications/ollama
nix build
kubectl apply -f result/
```

## Verify

```bash
kubectl get all -n ollama
kubectl logs -n ollama deploy/ollama
```

## Quick test from inside cluster

```bash
kubectl run ollama-test --rm -it --restart=Never -n ollama --image=curlimages/curl -- \
  curl -sS http://ollama:11434/api/tags
```

## Notes

- The initial model download can take time depending on bandwidth.
- For GPU nodes, add node selectors, tolerations, and GPU resource limits to the deployment.
- To use a different model, update the `ollama pull llama3.2:3b` command in `ollama.nix`.

