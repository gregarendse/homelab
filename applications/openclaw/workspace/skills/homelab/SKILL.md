---
name: homelab
trigger:
  type: keyword
  keywords: ["kubernetes", "k8s", "cluster", "pod", "server", "homelab",
             "deploy", "ollama", "oracle", "OCI", "restart", "down", "broken",
             "namespace", "helm", "kubectl", "manifest"]
---
# Homelab

Self-hosted setup on Oracle Cloud free tier.

## Cluster
- OCI Kubernetes Engine, ARM64 (Ampere A1), 4 OCPU, 24 GB RAM total
- No GPU — never suggest GPU workloads
- Namespaces: openclaw, ollama, monitoring, default
- Manifests: github.com/gregarendse/homelab (kubenix / Nix flakes)
- Longhorn for persistent storage

## Key services
- Ollama: http://ollama.ollama.svc.cluster.local:11434
- OpenClaw (me): openclaw namespace, port 18789
- Home Assistant: home-assistant namespace
- Plex: plex namespace

## Common requests
- "is X running" → describe what you know; note that live kubectl needs the tool enabled
- "restart X" → provide the kubectl rollout restart command
- "what model is ollama running" → curl the ollama API tags endpoint

## ARM64 constraint
Always verify linux/arm64 image support before recommending any container image.
Check with: docker manifest inspect <image> | grep -i arm64

## Free tier constraints
- 200 GB total block storage — be conservative with PVC sizes
- 10 TB/month outbound bandwidth free
- Never suggest paid OCI resources
