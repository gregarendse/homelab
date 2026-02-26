# Home Assistant Deployment with Kubenix

This directory contains kubenix configuration files to generate Kubernetes manifests for deploying Home Assistant.

## Migration Notice

This deployment has been migrated from Helm/values.yaml to kubenix. The `values.yaml` file is kept for reference but is no longer used.

## Files

- `flake.nix` - Nix flake configuration with kubenix inputs and build outputs
- `home-assistant.nix` - Main kubenix configuration defining all Kubernetes resources
- `configuration.yaml` - Home Assistant configuration file (mounted via ConfigMap)
- `Makefile` - Convenient commands for building and deploying
- `values.yaml` - **DEPRECATED** - Legacy Helm values, kept for reference only
- `README.md` - This file

## Configuration Management

Home Assistant's `configuration.yaml` is managed via a Kubernetes ConfigMap, similar to how pihole manages its configuration. The file is:

1. **Stored in this directory** as `configuration.yaml`
2. **Read by kubenix** using `builtins.readFile`
3. **Deployed as a ConfigMap** to the cluster
4. **Mounted into the container** at `/config/configuration.yaml`

**To modify the configuration:**
1. Edit `configuration.yaml` in this directory
2. Run `make build` to rebuild manifests
3. Run `make apply` to update the cluster
4. Restart Home Assistant: `make restart`

**Important:** The ConfigMap mount will override any changes made to `configuration.yaml` through the Home Assistant UI. Other files (automations.yaml, scripts.yaml, etc.) are stored on the PVC and can be edited normally.

## Prerequisites

1. Install Nix with flakes enabled
2. Have kubectl configured for your cluster
3. Ensure your cluster has:
   - A storage class (default: `longhorn`, or update the PVC configuration)
   - An ingress controller (if using the ingress)
   - cert-manager (optional, for TLS)

## Configuration

### Storage Class
Update the `storageClassName` in the PVC configuration in `home-assistant.nix` to match your cluster's available storage classes.

### Timezone
The default timezone is set to `Africa/Johannesburg`. Update the `TZ` environment variable in `home-assistant.nix` if needed.

### Ingress
Update the hostname in the ingress configuration to match your domain (default: `home-assistant.lan`).

### Hardware Access (Optional)
If you need Home Assistant to access USB devices (Zigbee, Z-Wave, etc.) or Bluetooth:
1. Uncomment `hostNetwork = true;` in the deployment spec
2. Uncomment `dnsPolicy = "ClusterFirstWithHostNet";`
3. Consider adding device mounts for specific hardware

## Usage

### Build the manifests
```bash
nix build
```

### View generated manifests
```bash
# After building, manifests are in the result directory
ls -la result/
cat result/*.yaml
```

### Apply to cluster
```bash
kubectl apply -f result/
```

### Delete from cluster
```bash
kubectl delete -f result/
```

### View deployment status
```bash
kubectl get all -n home-assistant
```

### Show logs
```bash
kubectl logs -n home-assistant -l app=home-assistant -f
```

### Development shell
```bash
nix develop
```

## Customization

The configuration includes:

- **Namespace**: `home-assistant`
- **Storage**: 5Gi PVC for Home Assistant configuration persistence
- **Service**: ClusterIP service exposing port 8123
- **Ingress**: HTTP(S) access via ingress controller
- **Resources**: 
  - Requests: 512Mi RAM, 250m CPU
  - Limits: 2Gi RAM, 1000m CPU
- **Health Checks**: Liveness and readiness probes configured

### Image

Uses the official Home Assistant container image from GitHub Container Registry:
- Image: `ghcr.io/home-assistant/home-assistant:stable`
- Auto-updates to the latest stable release

### WebSocket Support

The ingress is configured with:
- Extended proxy timeouts (3600s)
- WebSocket upgrade headers
- Required for Home Assistant's real-time features

### Initial Setup

On first deployment:
1. Access Home Assistant via the ingress URL
2. Complete the onboarding wizard
3. Create your admin account
4. Configure integrations as needed

### Migration from Docker/Helm

If migrating from an existing Docker or Helm deployment:
1. Backup your existing `/config` directory
2. Copy the backup to the PVC mount point after deployment
3. Restart the pod to load the existing configuration

## Troubleshooting

### Pod not starting
```bash
kubectl describe pod -n home-assistant -l app=home-assistant
kubectl logs -n home-assistant -l app=home-assistant
```

### Cannot access via ingress
- Verify ingress controller is running
- Check ingress configuration: `kubectl get ingress -n home-assistant`
- Ensure DNS resolves to your ingress controller

### USB device not detected
- Enable `hostNetwork: true` in the deployment
- Add device mounts to the container spec
- Ensure the node has the required hardware

## Security Considerations

1. **TLS**: Enable TLS in the ingress for secure access
2. **Network Policies**: Consider implementing network policies to restrict traffic
3. **Authentication**: Home Assistant has built-in authentication
4. **Secrets**: Store sensitive data (API keys, etc.) in Kubernetes Secrets

## Resources

- [Home Assistant Documentation](https://www.home-assistant.io/)
- [Home Assistant Container Installation](https://www.home-assistant.io/installation/alternative#docker-compose)
- [Kubenix Documentation](https://github.com/hall/kubenix)


