# Pi-hole Deployment with Kubenix

This directory contains kubenix configuration files to generate Kubernetes manifests for deploying Pi-hole.

## Files

- `flake.nix` - Nix flake configuration with kubenix inputs and build outputs
- `pihole.nix` - Main kubenix configuration defining all Kubernetes resources
- `pihole.toml` - Pi-hole FTL configuration mounted into the container
- `custom-dnsmasq.conf` - Custom dnsmasq rules mounted into the container
- `README.md` - This file

## Prerequisites

1. Install Nix with flakes enabled
2. Have kubectl configured for your cluster
3. Ensure your cluster has:
   - A storage class named `longhorn` (or update the `storageClassName` in `pihole.nix`)
   - An ingress controller (if using the ingress)
   - cert-manager (if using TLS)

## Configuration

### Storage Class
The PVC uses `storageClassName = "longhorn"`. Update this in `pihole.nix` if your cluster uses a different storage class.

### Password
The Pi-hole admin password is managed via a manually-created Kubernetes Secret to keep it out of Git.

```bash
kubectl create secret generic pihole-secret \
  --from-literal=password='YOUR_PASSWORD' \
  -n pihole
```

### DNS Settings
Modify the custom DNS settings in the ConfigMap to add your local domain mappings.

### Ingress and authentication
Pi-hole runs on **oci**, using Traefik. The user confirmed on 2026-09-27 that
`pihole-ingress` routes `pihole.arendse.nom.za/` directly to `pihole-web:80`,
Pi-hole is `1/1`, and the browser reaches Pi-hole's native login.

```text
browser -> Traefik -> pihole-web -> Pi-hole native login
```

**Zitadel integration skipped at the user's request.** Pi-hole has no native
OIDC/SAML integration; its [authentication](https://docs.pi-hole.net/api/auth/)
uses a local password, optional TOTP and sessions. An oauth2-proxy would only add
an edge login gate, not replace Pi-hole's login. Keep `pihole-secret` and native
authentication enabled. Do not run the previously proposed OAuth Secret-creation
command or publish the proxy/ingress changes.

**Cleanup prepared locally, not yet deployed:** the unused proxy entry and its
rendered Application have been removed from `clusters/oci/`; the real Pi-hole
entry and rendered workload are unchanged. The last live proxy Application
result was `ComparisonError`; no proxy Deployment, Service or OAuth Secret
existed at preflight. The user then verified that `oci-root` auto-sync is disabled
and the root-tracked proxy Application has no finalizers or reported managed
resources. After an approved commit/push, the user must remove only that abandoned
Application on **oci**; publication alone will not auto-prune it. Do not enable
root auto-sync or broadly sync/prune the root. Live removal is still pending.

The untracked proxy values and unpublished `pihole.nix` ingress switch are
preserved local work, not the desired deployment. Keep them out of the cleanup
commit/push. Retain the already-created Terraform project/client until an
explicit cleanup plan is reviewed. See
[`CP-5.1`](../zitadel/MIGRATION.md#cp-51--pi-hole-sso-skipped) for the decision and
cleanup boundaries. Pi-hole DNS, storage and live routing remain unchanged.

## Usage

### Build the manifests
```bash
nix build --out-link result.json
```

### Apply to cluster
```bash
kubectl apply --filename result.json
```

### Delete from cluster
```bash
kubectl delete --filename result.json
```

### View deployment status
```bash
kubectl get all --namespace pihole
```

### View generated manifests
```bash
cat result.json
```

### Show logs
```bash
kubectl logs --namespace pihole deployment/pihole
```

### Development shell
```bash
nix develop
```

## Customization

The configuration includes:

- **Namespace**: `pihole`
- **Storage**: 1Gi PVC for Pi-hole data persistence (storage class: `longhorn`)
- **Services**:
  - DNS service (`NodePort`) — DNS TCP on 30530, DNS UDP on 30053, DHCP on 30067, NTP on 30123
  - Web interface service (`ClusterIP`)
- **Ingress**: HTTPS access with Let's Encrypt certificates
- **ConfigMaps**: Custom dnsmasq rules (`custom-dnsmasq`) and Pi-hole FTL config (`pihole-config`)
- **Resources**: CPU request 500m / limit 1000m, memory request 320Mi / limit 768Mi

### DNS Configuration

The deployment includes:
- Custom DNS mappings via `custom-dnsmasq` ConfigMap (`custom-dnsmasq.conf`)
- Upstream DNS servers: `1.1.1.3` and `1.0.0.3` (Cloudflare for Families — blocks malware and adult content)
- FTL configuration via `pihole-config` ConfigMap (`pihole.toml`)

## Notes

- The deployment uses `strategy.type: Recreate` to avoid conflicts with persistent storage
- Pi-hole data persists across pod restarts via PVC
- Custom dnsmasq configuration is mounted from the `custom-dnsmasq` ConfigMap
- A `dshm` `emptyDir` volume (128Mi, `medium: Memory`) is mounted at `/dev/shm` to override the Kubernetes default of 64MB. Pi-hole FTL stores its DNS query database in shared memory and will crash with `No space left on device` if `/dev/shm` is too small. Note: tmpfs volumes count against the container memory limit, so the memory limit must account for both FTL process memory and `/dev/shm` usage.

## Troubleshooting

1. Check pod logs: `kubectl logs --namespace pihole deployment/pihole`
2. Verify PVC is bound: `kubectl get pvc --namespace pihole`
3. Check service endpoints: `kubectl get svc --namespace pihole`
4. Verify ingress: `kubectl get ingress --namespace pihole`

## Security Considerations

- Change the default admin password
- Consider using a more secure password storage method (e.g., external secrets)
- Review and adjust resource limits based on your usage
- Configure appropriate network policies if needed
