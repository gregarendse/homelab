# OpenClaw Deployment with Kubenix

Personal AI assistant gateway — connects to WhatsApp, Telegram, and Discord and answers via a configurable LLM backend.

## What gets deployed

- **Namespace**: `openclaw`
- **PVC**: `openclaw-home` (5Gi, Longhorn) — persists config, sessions, and workspace
- **ConfigMap**: `openclaw-workspace-seed` — seeds SOUL.md and skills on first run
- **Deployment**: `openclaw` using `ghcr.io/openclaw/openclaw:latest`
  - Init container seeds workspace files from ConfigMap (skips if files already exist)
  - Runs as uid 1000 (node user)
  - `strategy: Recreate` — required for single-instance RWO volume
- **Service**: `openclaw` on port 18789 (ClusterIP)

## Files

```
applications/openclaw/
├── flake.nix                              # Nix flake entrypoint
├── flake.lock                             # Locked inputs (shared with ollama)
├── openclaw.nix                           # Kubernetes resources via kubenix
├── README.md                              # This file
└── workspace/
    ├── SOUL.md                            # Assistant personality & context
    └── skills/
        ├── homelab/SKILL.md               # Homelab keyword skill
        ├── personal-context/SKILL.md      # Always-active personal context
        ├── security/SKILL.md              # Access boundary enforcement
        └── terraform-nix/SKILL.md         # Terraform/Nix keyword skill
```

## Before deploying

### 1. Fill in placeholders

Edit `workspace/SOUL.md` and `workspace/skills/personal-context/SKILL.md` — replace every `[PLACEHOLDER]` with your actual values. These files are seeded into the PVC on first deployment.

### 2. Create the secret

```bash
kubectl create secret generic openclaw-secrets \
  --namespace openclaw \
  --from-literal=OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32) \
  --from-literal=GEMINI_API_KEY='...'       # optional: cloud LLM
  --from-literal=GROQ_API_KEY='...'         # optional: cloud LLM
  --from-literal=TELEGRAM_BOT_TOKEN='...'   # optional: messaging channel
  --from-literal=DISCORD_BOT_TOKEN='...'    # optional: messaging channel
```

> **Note**: Do not commit secrets to the repo.

### 3. Choose a LLM backend

In `openclaw.nix`, the default is **Option A (Ollama)**. If you want a cloud provider, comment out Option A and uncomment Option B (Gemini) or Option C (Groq).

## Build and apply

```bash
cd applications/openclaw
nix build
kubectl apply -f result/
```

## Add messaging channels (after first deploy)

```bash
# Telegram
kubectl exec -n openclaw -it deploy/openclaw -- \
  openclaw channels add --channel telegram --token "<your-bot-token>"

# WhatsApp (interactive QR scan)
kubectl exec -n openclaw -it deploy/openclaw -- \
  openclaw channels login

# Discord
kubectl exec -n openclaw -it deploy/openclaw -- \
  openclaw channels add --channel discord --token "<your-bot-token>"
```

## Access the control UI

```bash
# Port-forward to your local machine
kubectl port-forward -n openclaw svc/openclaw 18789:18789

# Get the dashboard URL with auth token
kubectl exec -n openclaw -it deploy/openclaw -- openclaw dashboard --no-open
# Open the URL shown (swap host to localhost:18789)
```

## Updating workspace files

The init container seeds files only if they don't already exist in the PVC. To push an update from the repo:

```bash
# Delete the file from the PVC so the init container re-seeds it on next restart
kubectl exec -n openclaw -it deploy/openclaw -- rm /home/node/.openclaw/workspace/SOUL.md
kubectl rollout restart deployment/openclaw -n openclaw
```

## Verify

```bash
kubectl get all -n openclaw
kubectl logs -n openclaw deploy/openclaw -c init-workspace
kubectl logs -n openclaw deploy/openclaw -c openclaw
```

## Notes

- OpenClaw is a single-user, stateful application — `replicas: 1` is intentional.
- The `Recreate` deployment strategy prevents two pods from holding the RWO volume simultaneously.
- SOUL.md and skills live in the repo under `workspace/` but are written to the PVC — the PVC copy is live; the repo copy is the source of truth.
- To reset a skill to defaults: delete it from the PVC and restart the pod.
