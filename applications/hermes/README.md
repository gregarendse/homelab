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

## Home Assistant MCP

Hermes connects to Home Assistant's [MCP server](https://www.home-assistant.io/integrations/mcp_server/)
over the cluster network. This is separate from the native `platforms.homeassistant`
gateway (state-change events and `ha_*` tools). Both use `HASS_URL` and `HASS_TOKEN`.

OAuth is not used. Hermes runs headless, and Home Assistant's IndieAuth check
rejects Hermes' loopback callback. A long-lived access token is the supported
path for that.

### 1. Enable the integration in Home Assistant

Home Assistant is on **oci** (`https://home-assistant.arendse.nom.za`). The
`/api/mcp` endpoint 404s until the integration exists — it is a UI config entry,
not something this repo can declare.

1. **Settings → Devices & services → Add Integration → Model Context Protocol Server**
2. Allow clients to control Home Assistant
3. **Settings → Voice assistants → Expose** — expose only the entities Hermes should see or control

`/api/mcp` serves whichever LLM API you picked in that setup (Assist, unless you
changed it). Pin Assist explicitly by changing the URL in the config YAML to
`${HASS_URL}/api/mcp/assist`.

### 2. Add the token

Create a long-lived access token as an admin user (**Profile → Security →
Long-lived access tokens**) and put it in the untracked secret:

```yaml
HASS_TOKEN: "<token>"
```

`config.yaml` sends it as `Authorization: Bearer ${HASS_TOKEN}`. The URL is
`http://home-assistant.home-assistant:8123/api/mcp` via `HASS_URL`.

Apply against **oci**. Confirm the context first — the default kubeconfig also
has work GKE contexts.

```bash
kubectl config current-context
kubectl apply -f hermes-secrets.yaml
```

### 3. Restart Hermes after GitOps sync

`config.yaml` is a subPath ConfigMap mount, and `HASS_TOKEN` is injected at
process start. Neither hot-reloads. After this change is on `master` and ArgoCD
has synced `oci-hermes`, restart:

```bash
kubectl rollout restart -n hermes deployment/hermes
```

### 4. Verify

```bash
kubectl exec -n hermes deploy/hermes -- hermes mcp test homeassistant
```

A 404 means the integration is not added. A 401 means the token is wrong or
missing. Tools show up as `mcp__homeassistant__*`. Hermes can only control
entities exposed in step 1.

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
