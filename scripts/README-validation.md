# Manifest validation

Two scripts validate the cluster's Kubernetes manifests so that schema and
template errors are caught in CI instead of at deploy time. They run
automatically on pull requests via `.github/workflows/validate-manifests.yaml`,
and can also be run locally.

## What gets checked

| Script | Covers | How |
|---|---|---|
| `scripts/validate-helm.sh` | Every path-type Helm app in `clusters/*/apps.yaml` (the shared `server/` chart + per-app `values.yaml`) | `helm lint` + `helm template` piped through `kubeconform` |
| `scripts/validate-manifests.sh` | Every kubenix app (`applications/<app>/flake.nix`) | `nix build` → normalise the rendered `result.json` → `kubeconform` |

`kubeconform` validates each manifest against the Kubernetes API schema for the
version in `KUBE_VERSION` (default `1.28.0`, matching the cluster). Custom
resources are checked against the
[CRDs-catalog](https://github.com/datreeio/CRDs-catalog); CRDs that aren't in
the catalog are skipped (`-ignore-missing-schemas`) rather than failing.

## Requirements

- [`helm`](https://helm.sh/) (Helm script only)
- [`yq`](https://github.com/mikefarah/yq) v4
- [`kubeconform`](https://github.com/yannh/kubeconform)
- [`nix`](https://nixos.org/) (only when building kubenix apps with `--build`)

## Running locally

```bash
# Validate all Helm apps
scripts/validate-helm.sh

# Validate only specific Helm apps
scripts/validate-helm.sh plex sonarr

# Validate kubenix apps using their existing result.json
scripts/validate-manifests.sh

# Rebuild kubenix apps first (needed if result.json is missing — it's gitignored)
scripts/validate-manifests.sh --build

# Build + validate a single kubenix app
scripts/validate-manifests.sh --build pihole
```

Override the target Kubernetes version with the `KUBE_VERSION` environment
variable, e.g. `KUBE_VERSION=1.29.0 scripts/validate-helm.sh`.

## Notes

- `applications/*/result.json` is gitignored, so CI builds each kubenix app
  fresh with `nix build` (the `--build` flag) before validating it.
- `openclaw` has no committed `flake.nix`, so it is not auto-discovered by the
  kubenix validator. Add a `flake.nix` (as the other kubenix apps have) to bring
  it under validation.
