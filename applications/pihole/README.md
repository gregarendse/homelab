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
Change the default admin password in the secret configuration in `pihole.nix`.

### DNS Settings
Modify the custom DNS settings in the ConfigMap to add your local domain mappings.

### Ingress
Update the hostname in the ingress configuration to match your domain.

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
- **Resources**: CPU request 500m / limit 1000m, memory request 256Mi / limit 512Mi

### DNS Configuration

The deployment includes:
- Custom DNS mappings via `custom-dnsmasq` ConfigMap (`custom-dnsmasq.conf`)
- Upstream DNS servers: `1.1.1.3` and `1.0.0.3` (Cloudflare for Families — blocks malware and adult content)
- FTL configuration via `pihole-config` ConfigMap (`pihole.toml`)

## Notes

- The deployment uses `strategy.type: Recreate` to avoid conflicts with persistent storage
- Pi-hole data persists across pod restarts via PVC
- Custom dnsmasq configuration is mounted from the `custom-dnsmasq` ConfigMap
- A `dshm` `emptyDir` volume (256Mi, `medium: Memory`) is mounted at `/dev/shm` to override the Kubernetes default of 64MB. Pi-hole FTL stores its DNS query database in shared memory and will crash with `No space left on device` if `/dev/shm` is too small.

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