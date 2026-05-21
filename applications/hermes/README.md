# Hermes Agent

Self-hosted autonomous AI agent by [Nous Research](https://nousresearch.com),
deployed as a Kubernetes workload on the OCI cluster.

- **Docs:** <https://hermes-agent.nousresearch.com/docs>
- **Image:** `nousresearch/hermes-agent:latest` (multi-arch, includes `linux/arm64`)
- **Ports:** `8642` (gateway / OpenAI-compatible API), `9119` (web dashboard)

---

## Prerequisites

### 1. Longhorn storage

This app requires Longhorn (`storageClassName: longhorn`). Confirm Longhorn is
enrolled and healthy in `clusters/oci/apps.yaml` before proceeding.

### 2. Secrets

All secret values are injected from the `hermes-secrets` Kubernetes Secret via
`envFrom`. Copy the example file, fill in your values, and apply it:

```bash
cp applications/hermes/hermes-secrets.example.yaml hermes-secrets.yaml
# edit hermes-secrets.yaml — do not commit the filled-in copy
kubectl apply -f hermes-secrets.yaml
```

The minimum required key is `API_SERVER_KEY` (gates the gateway API and
dashboard). Generate a strong value with:

```bash
openssl rand -hex 32
```

See `hermes-secrets.example.yaml` for the full list of supported keys
(cloud provider API keys, messaging platform bot tokens, etc.).

---

## Provider configuration

The LLM provider is controlled by which YAML file is inlined into the
`hermes-config` ConfigMap via `builtins.readFile` in `hermes.nix`.

| Variant | File | Extra secret key |
|---|---|---|
| **A — Local Ollama (default)** | `config-ollama.yaml` | *(none)* |
| **B — OpenAI** | `config-cloud.yaml` | `OPENAI_API_KEY` |
| **B — Gemini** | `config-cloud.yaml` | `GEMINI_API_KEY` |

To switch, change the one line in `hermes.nix`:

```nix
# from
data."config.yaml" = builtins.readFile ./config-ollama.yaml;
# to
data."config.yaml" = builtins.readFile ./config-cloud.yaml;
```

Then open `config-cloud.yaml` and uncomment the provider block you want.

The Ollama model name in `config-ollama.yaml` (`llama3.2:3b` by default) must
match a model that has been pulled in your Ollama deployment:

```bash
kubectl exec -n ollama deploy/ollama -- ollama list
```

---

## Enrolling in ArgoCD

Once the Secret is in place and the config file is correct, add to
`clusters/oci/apps.yaml`:

```yaml
- name: hermes
  type: rendered
  path: applications/hermes
```

---

## First-run behaviour

On the very first start the entrypoint bootstraps `/opt/data` (creates
directory structure, syncs bundled skills, copies default `SOUL.md`, etc.).
The pod will show `READY 0/1` for up to ~60 s — this is normal.

To customise the agent personality after the first run:

```bash
kubectl exec -it -n hermes deploy/hermes -- vi /opt/data/SOUL.md
```

---

## Resource usage

| | Requests | Limits |
|---|---|---|
| CPU | 250 m | 1000 m |
| Memory | 512 Mi | 1536 Mi |
| Storage | 5 Gi (Longhorn PVC) | — |
| `/dev/shm` | — | 1 Gi (Memory-backed emptyDir) |

Browser automation (Playwright/Chromium) is **disabled by default**. If you
enable it via `HERMES_BROWSER=1`, increase the memory limit to at least `3Gi`
and the `dshm` emptyDir `sizeLimit` accordingly.

OCI Always Free headroom consumed by this app:
- CPU: +250 m request / +1000 m limit
- RAM: +512 Mi request / +1536 Mi limit
- Block storage: +5 Gi

---

## Upgrading

Hermes uses a rolling `latest` tag. To redeploy with the newest image:

```bash
kubectl rollout restart -n hermes deployment/hermes
```

Once the app is stable, consider pinning to a specific digest to prevent
unexpected upgrades:

```nix
image = "nousresearch/hermes-agent@sha256:<digest>";
```
