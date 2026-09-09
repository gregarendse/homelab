# AGENTS.md — Home Lab Codebase Guide

## Architecture Overview

This repo manages a personal **home lab** Kubernetes cluster ("trinity") running media and automation services. There are two distinct deployment paradigms:

1. **Helm (primary)** — Most apps use the shared `server/` Helm chart. Each app has `applications/<app>/values.yaml` that overrides defaults. Deployed via `upgrade.sh` or ArgoCD.
2. **Nix/kubenix** — Some apps (pihole, ollama, open-webui, openclaw, mongo) define full Kubernetes manifests in Nix using the `kubenix` flake. These produce raw YAML via `nix build`.

## Key Directories

| Path | Purpose |
|---|---|
| `server/` | Shared Helm chart used by all standard apps |
| `applications/<app>/values.yaml` | Per-app Helm value overrides |
| `applications/<app>/flake.nix` + `<app>.nix` | Nix-managed apps with full manifests |
| `clusters/trinity/apps.yaml` | Declares all apps and their deployment type |
| `clusters/trinity/rendered/` | Pre-rendered ArgoCD Application YAMLs (committed) |
| `clusters/trinity/root.yaml` | ArgoCD root app pointing to `rendered/` |
| `infrastructure/` | Terraform for OCI cloud resources |
| `src/go/ci/` | Go CI helper tool (`make && ./bin/ci`) |

## Deployment Workflows

### Working with the clusters (agent rules)

- **Never run `kubectl` / `helm` against a cluster yourself.** The agent has no
  access to either cluster. Print the command and ask the user to run it.
- **Always state which cluster a command targets** (`trinity` or `oci`). The
  user's default kubeconfig contains unrelated *work* GKE contexts
  (`standin-production`, `standin-staging`), so an unlabelled command risks being
  run against the wrong — possibly production — cluster.
- Ask the user to confirm `kubectl config current-context` before any command
  that writes to a cluster.

### Which cluster runs what

| Cluster | Ingress | Notable apps |
|---|---|---|
| `trinity` | ingress-nginx | the `*arr` apps, `oauth2-proxy` (edge SSO), `zitadel-echo` + `oauth2-proxy-zitadel` (PoC rig), ArgoCD at `trinity.argocd.arendse.nom.za` |
| `oci` | Traefik | `monitoring`/Grafana, `pihole` + `pihole-zitadel-oauth2-proxy`, `home-assistant`, `loki`, ArgoCD at `argocd.arendse.nom.za` |

### Deploy/upgrade a Helm app
```bash
./upgrade.sh <app>           # e.g. ./upgrade.sh plex
# Runs: helm upgrade --install <app> server --values=applications/<app>/values.yaml --namespace=<app> --create-namespace --atomic
```

### Add a new Helm app
1. Create `applications/<app>/values.yaml` (copy an existing one, e.g. `applications/echo/values.yaml`)
2. Add an entry in `clusters/trinity/apps.yaml` pointing `path: server` and `valueFiles: [applications/<app>/values.yaml]`
3. Render and commit to `clusters/trinity/rendered/`

### Build a Nix-managed app manifest
```bash
cd applications/<app>
nix build .#manifests      # outputs to ./result or ./result.json
```

## Helm Chart Conventions (`server/`)

- All apps share the single `server/` chart — **do not create per-app charts**
- `keel:` block in values.yaml controls auto-update policy (default: `policy: force`, poll `@midnight`)
- Standard env vars `PUID`, `PGID`, `TZ` are set in every `values.yaml`
- Host-path volumes are named and follow pattern: `source: /mnt/data/docker/<app>/config`
- Ingress hosts use `.lan` suffix for internal services (e.g. `home-assistant.lan`)
- External (internet-facing) services use `arendse.nom.za` with cert-manager + Cloudflare (`cert-manager.io/cluster-issuer: letsencrypt-prod`)

## Nix/kubenix Conventions

- All Nix apps target `kubernetes.version = "1.28"`
- Secrets that contain sensitive values are **never committed** — create manually with `kubectl create secret`; the `.nix` file documents the exact `kubectl` command in a comment (see `applications/openclaw/openclaw.nix`)
- Storage uses `storageClassName: longhorn`
- DNS services use `externalTrafficPolicy: Local` to preserve client IPs

## ArgoCD / GitOps

- `clusters/trinity/root.yaml` bootstraps ArgoCD by pointing to `clusters/trinity/rendered/`
- Rendered Application manifests must be committed — ArgoCD reads them from `master` branch of `github.com/gregarendse/homelab.git`
- Auto-sync is **enabled**: both `clusters/trinity/apps.yaml` and
  `clusters/oci/apps.yaml` set `autoSync: true`, so every rendered app gets
  `automated: {prune: true, selfHeal: true}`. **Pushing to `master` deploys**,
  and `selfHeal` reverts manual `helm`/`kubectl` changes to managed apps. Opt a
  single app out with `autoSync: false` on its entry in `apps.yaml`.
- ArgoCD itself is **not** self-managed (no `argocd` app in `clusters/*/rendered/`);
  its values files are applied manually via helm/terraform.

## Infrastructure (Terraform / OCI)

- Provider config in `infrastructure/providers.tf`, resources split across focused files (`compute.tf`, `network/vcn.tf`, etc.)
- Cloudflare DNS managed separately under `infrastructure/cloudflare/`

## Go CI Tool

```bash
cd src/go/ci
make          # builds ./bin/ci
make test     # runs tests
```

## Manifest Validation (CI)

Pull requests run `.github/workflows/validate-manifests.yaml`, which schema-checks
all Kubernetes manifests with `kubeconform` so errors are caught before deploy:

- `scripts/validate-helm.sh` — `helm lint` + `helm template` every path-type Helm
  app in `clusters/*/apps.yaml`, then `kubeconform` the output.
- `scripts/validate-manifests.sh [--build]` — build each kubenix app
  (`applications/<app>/flake.nix`) and `kubeconform` the rendered manifests.

Both validate against `KUBE_VERSION` (default `1.28.0`) and skip CRDs not in the
[CRDs-catalog](https://github.com/datreeio/CRDs-catalog). Run them locally before
opening a PR; see `scripts/README-validation.md` for details.

