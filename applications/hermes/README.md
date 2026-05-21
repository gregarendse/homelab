# Hermes Agent

Self-hosted autonomous AI agent by [Nous Research](https://nousresearch.com),
deployed as a Kubernetes workload on the OCI cluster.

- **Docs:** <https://hermes-agent.nousresearch.com/docs>
- **Image:** `nousresearch/hermes-agent:latest`
- **Ports:** `8642` (gateway / OpenAI-compatible API), `9119` (web dashboard)

---

## ⚠️ ARM64 Check — do this before enrolling

The OCI nodes are `aarch64` (ARM64).  Confirm the official image ships a
`linux/arm64` layer **before** adding this app to `clusters/oci/apps.yaml`:

```bash
docker manifest inspect nousresearch/hermes-agent:latest \
  | jq '.manifests[].platform'
```

You need to see `"architecture": "arm64"` in the output.  If it is absent:

- Check the [GitHub releases](https://github.com/NousResearch/hermes-agent/releases)
  for an ARM-specific tag.
- Open an issue on the upstream repo requesting multi-arch builds.
- As a workaround, deploy on the `trinity` cluster (if that is x86) instead.

---

## Prerequisites

### 1. Secrets

Create the `hermes-secrets` Secret in the `hermes` namespace **before** the
pod starts.  The minimum required key is `API_SERVER_KEY`.

```bash
# Generate a strong API server key
API_SERVER_KEY=$(openssl rand -hex 32)

kubectl create secret generic hermes-secrets \
  --namespace hermes \
  --from-literal=API_SERVER_KEY="${API_SERVER_KEY}"
```

#### Variant A — Local Ollama (no extra keys needed)

The Ollama endpoint does not require an API key.  The secret above is
sufficient.

#### Variant B — Cloud provider

Add the provider key to the same secret:

```bash
# OpenAI
kubectl create secret generic hermes-secrets \
  --namespace hermes \
  --from-literal=API_SERVER_KEY="${API_SERVER_KEY}" \
  --from-literal=OPENAI_API_KEY="sk-..."

# --- OR Gemini ---
kubectl create secret generic hermes-secrets \
  --namespace hermes \
  --from-literal=API_SERVER_KEY="${API_SERVER_KEY}" \
  --from-literal=GEMINI_API_KEY="AIza..."
```

#### Optional — messaging platform tokens

Add any gateway bot tokens to the same secret and uncomment the corresponding
env vars in `hermes.nix`:

```bash
# Re-create (or patch) the secret with additional keys:
kubectl create secret generic hermes-secrets \
  --namespace hermes \
  --from-literal=API_SERVER_KEY="${API_SERVER_KEY}" \
  --from-literal=TELEGRAM_BOT_TOKEN="..."
  # --from-literal=DISCORD_BOT_TOKEN="..."
```

### 2. Longhorn storage

This app requires Longhorn (`storageClassName: longhorn`).  Enroll Longhorn in
`clusters/oci/apps.yaml` first if it is not already active.

---

## Provider configuration

The `hermes-config` ConfigMap in `hermes.nix` controls which LLM provider
Hermes uses.  Two variants are included as comments; switch between them by
changing the `config.yaml` key in the ConfigMap and the corresponding env var
in the Deployment.

| Variant | `config.yaml` `provider` | Required secret key |
|---------|--------------------------|---------------------|
| A — Local Ollama | `custom` → Ollama ClusterIP | *(none)* |
| B — OpenAI | `openai` | `OPENAI_API_KEY` |
| B — Gemini | `google` | `GEMINI_API_KEY` |

The Ollama model name in the ConfigMap (`llama3.2:3b` by default) must match
a model that has been pulled in your Ollama deployment.  Check available
models with:

```bash
kubectl exec -n ollama deploy/ollama -- ollama list
```

---

## Enrolling in ArgoCD

Once the ARM64 check passes and secrets are in place, add to
`clusters/oci/apps.yaml`:

```yaml
- name: hermes
  type: rendered
  path: applications/hermes
```

---

## First-run setup

On the very first start the entrypoint bootstraps `/opt/data` (creates
directory structure, copies default `SOUL.md`, etc.).  The pod will show
`READY 0/1` for up to ~60 s while this completes — this is normal.

If you want to customise the agent personality, edit `SOUL.md` in the PVC
after the first run:

```bash
kubectl exec -n hermes deploy/hermes -- \
  vi /opt/data/SOUL.md
```

---

## Resource usage

| | Requests | Limits |
|---|---|---|
| CPU | 250 m | 1000 m |
| Memory | 512 Mi | 1536 Mi |
| Storage | 5 Gi (Longhorn PVC) | — |
| `/dev/shm` | — | 1 Gi (Memory-backed) |

Browser automation (Playwright/Chromium) is the most memory-hungry feature.
It is **disabled by default** in this deployment.  If you enable it via
`HERMES_BROWSER=1`, increase the memory limit to at least `3Gi`.

Always Free headroom check before changing limits:
- Total A1 OCPUs across all instances ≤ 4
- Total A1 RAM across all instances ≤ 24 GB
- Total block storage ≤ 200 GB

---

## Upgrading

Hermes uses a rolling `latest` tag.  To trigger a redeploy with the newest
image, cycle the pod:

```bash
kubectl rollout restart -n hermes deployment/hermes
```

Consider pinning to a specific release digest once the app is stable:

```nix
image = "nousresearch/hermes-agent@sha256:<digest>";
```
