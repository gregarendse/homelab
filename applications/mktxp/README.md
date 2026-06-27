# mktxp — Mikrotik RouterOS Prometheus exporter

[akpw/mktxp](https://github.com/akpw/mktxp) exports RouterOS metrics for
Prometheus. It runs on the **OCI** cluster (where the kube-prometheus-stack lives)
and reaches the Mikrotik router at `192.168.1.1` over the existing IPsec link.
Only the mktxp → router API traffic crosses IPsec; Prometheus scrapes mktxp
in-cluster via a `ServiceMonitor`.

This is a **kubenix** app (like `pihole` / `unifi`), registered in
`clusters/oci/apps.yaml` as `type: rendered`. CI runs `nix build` to produce the
raw manifests under `clusters/oci/rendered/mktxp/`, which ArgoCD applies.

## Files

| File | Purpose |
|---|---|
| `flake.nix` | kubenix entrypoint (`nix build .#manifests`) |
| `mktxp.nix` | ConfigMap, Deployment, Service, ServiceMonitor |
| `mktxp.conf` | Router entries (no credentials) → ConfigMap |
| `_mktxp.conf` | System/runtime tuning → ConfigMap |
| `credentials.example.yaml` | Template for the manually-created Secret |

mktxp is **stateless** — no PVC/hostPath. The DHCP cache and connection pool are
in-memory and rebuilt on restart. `_mktxp.conf` is provided explicitly so mktxp
never needs to write to its read-only config mount.

It deploys into the **`monitoring`** namespace so the kube-prometheus-stack
Prometheus (Helm release `monitoring`) discovers the ServiceMonitor — which must
carry the `release: monitoring` label (it does).

## Prerequisites

### 1. Router API user (read-only)

On the RouterOS terminal:

```
/user group add name=mktxp_group policy=api,read
/user add name=mktxp_user group=mktxp_group password=<strong-password>
```

Ensure `/ip service` `api` (port 8728) is enabled and its allowed-address range
permits the OCI side of the IPsec tunnel.

### 2. Credentials Secret (NOT committed)

The router password lives only in a manually-created Secret. The ConfigMap holds
everything else, and `mktxp.conf` references the Secret via
`credentials_file = /etc/mktxp/credentials.yaml`.

```
kubectl -n monitoring create secret generic mktxp-credentials \
  --from-literal=credentials.yaml='username: mktxp_user
password: <strong-password>'
```

See `credentials.example.yaml`. To rotate, update the Secret and:

```
kubectl -n monitoring rollout restart deploy/mktxp
```

## Build / deploy

Render the manifests locally to inspect them:

```
cd applications/mktxp
nix build .#manifests        # outputs ./result (or result.json)
```

CI renders and commits `clusters/oci/rendered/mktxp/` automatically once the app
is registered in `clusters/oci/apps.yaml` (`type: rendered`). ArgoCD then applies
it from `master`.

## Verify

```
kubectl -n monitoring logs deploy/mktxp          # "Connection to router ... established"
kubectl -n monitoring port-forward deploy/mktxp 49090:49090
curl localhost:49090 | grep mktxp_               # metrics present
```

Then check Prometheus → Status → Targets for the `mktxp` job, and import the
mktxp Grafana dashboard (Dashboards → Import) selecting the Prometheus datasource.
