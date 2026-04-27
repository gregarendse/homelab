# External DNS Configuration

This Terraform configuration deploys [External DNS](https://github.com/kubernetes-sigs/external-dns) to your Kubernetes cluster, enabling automatic DNS record management in Cloudflare based on Ingress resources.

## Overview

External DNS monitors your Kubernetes cluster for Ingress resources, automatically creating, updating, and deleting DNS records in Cloudflare. This replaces manual DNS record management via Terraform.

When you create a Kubernetes Ingress with a hostname, External DNS:
1. Reads the hostname from `spec.rules[].host`
2. Reads the target IP from `status.loadBalancer.ingress[].ip`
3. Creates an A record in Cloudflare pointing to that IP
4. Creates TXT ownership records (prefixed `external-dns-`) to track what it manages
5. Cleans up records when the Ingress is deleted (with `policy: sync`)

## Architecture Notes

This setup runs Traefik as a **DaemonSet with NodePort** behind an external firewall/NAT. The public IP is injected into ingress status via:

```hcl
# traefik.tf
additionalArguments = [
  "--providers.kubernetesingress.ingressendpoint.ip=YOUR_PUBLIC_IP"
]
```

This ensures every ingress gets a populated `status.loadBalancer` that External DNS can read, without requiring a cloud LoadBalancer service.

## Prerequisites

- Cloudflare account with API token (Zone:DNS:Edit permission)
- Domain managed by Cloudflare
- Kubernetes cluster with Traefik (or another ingress controller)
- `ingress_public_ip` and `domain_name` set in your Terraform variables

## Setup

### Step 1: Set Terraform Variables

Create a `terraform.tfvars` (git-ignored) file:

```hcl
domain_name       = "example.com"
ingress_public_ip = "1.2.3.4"   # Your firewall's public IP
```

### Step 2: Create the Cloudflare API Token Secret

Secrets are **not managed by Terraform**. Create the secret manually before applying.

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) → **Account Settings → API Tokens → Create Token**
2. Use the **Edit zone DNS** template, or set custom permissions:
   - Zone → **DNS:Edit**
   - Zone Resources → your specific zone
3. Copy the token

Create the namespace and secret:

```bash
kubectl create namespace external-dns

kubectl create secret generic cloudflare-credentials \
  --from-literal=cloudflare-api-token='YOUR_TOKEN' \
  -n external-dns
```

### Step 3: Deploy via Terraform

```bash
cd infrastructure/kubernetes
terraform plan
terraform apply
```

### Step 4: Verify

```bash
kubectl get pods -n external-dns
kubectl logs -n external-dns deployment/external-dns -f
```

You should see log lines like:

```
level=info msg="Changing record." action=CREATE record=myapp.example.com ttl=1 type=A
```

## Usage

DNS is managed automatically. Add these annotations to your Ingress to control Cloudflare behaviour:

```nix
# In your .nix / YAML ingress manifest:
annotations = {
  # Proxy traffic through Cloudflare (orange cloud). Omit for grey cloud (direct).
  "external-dns.alpha.kubernetes.io/cloudflare-proxied" = "true";

  # Optional: tag the record in Cloudflare for visibility
  "external-dns.alpha.kubernetes.io/cloudflare-tags" = "app=myapp,env=prod,owner=homelab";
};
```

External DNS reads `status.loadBalancer.ingress[].ip` as the A record target — there is no need to set a `target` annotation per-ingress when Traefik is configured with `ingressendpoint.ip`.

## Troubleshooting

### Records not being created

Check whether the ingress has a published IP in its status:

```bash
kubectl get ingress -A
kubectl get ingress -n NAMESPACE NAME -o jsonpath='{.status.loadBalancer}'
```

If the status is empty, Traefik is not publishing the ingress endpoint. Verify `ingress_public_ip` is set and Terraform has been applied.

### CNAME content cannot reference itself (Cloudflare error 9039)

This happens when External DNS computes a CNAME instead of an A record. Causes:

- **Stale `target` annotation on the ingress** — if `external-dns.alpha.kubernetes.io/target` is set to the hostname itself rather than an IP, External DNS creates a self-referencing CNAME. Remove the annotation:
  ```bash
  kubectl annotate ingress NAME -n NAMESPACE "external-dns.alpha.kubernetes.io/target-"
  ```
- **Empty ingress status** — no IP in `status.loadBalancer`. Fix Traefik config (see Architecture Notes above).

### Failed to update record: forbidden (1002)

Cloudflare rejects updates to proxied records when the ownership TXT records are inconsistent (e.g. from a previous deployment with different `txtOwnerId`/`txtPrefix` settings). Fix by deleting all External DNS TXT and A records for the affected hostname and letting External DNS recreate them:

```bash
# List all External DNS TXT records
TOKEN=your_token
ZONE_ID=your_zone_id

curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=TXT&per_page=100" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '.result[] | select(.content | test("heritage=external-dns")) | {id, name, content}'

# Delete each stale record (replace RECORD_ID)
curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/RECORD_ID" \
  -H "Authorization: Bearer ${TOKEN}"
```

> **Note:** The Cloudflare dashboard does **not** show TXT records associated with proxied hostnames. You must use the API to find and delete them.

After cleanup, restart External DNS:

```bash
kubectl rollout restart deployment/external-dns -n external-dns
kubectl logs -n external-dns deployment/external-dns -f
```

### An identical record already exists (Cloudflare error 81058)

Stale TXT ownership records from a previous run are blocking new ones. Use the API commands above to find and delete them — they are invisible in the dashboard when the parent record is proxied.

### Changing txtPrefix / txtOwnerId after initial deployment

**Do not change these values** once records exist in Cloudflare. Changing them causes ExternalDNS to lose track of existing records, leading to ownership conflicts and `forbidden (1002)` errors. If you must change them:

1. Set `policy = "upsert-only"` temporarily to stop deletions
2. Delete all External DNS TXT records via API
3. Delete all External DNS A records for managed hostnames
4. Restore the new config values
5. Apply and let External DNS recreate everything
6. Restore `policy = "sync"` once stable

### Enable debug logging temporarily

```bash
kubectl set env deployment/external-dns -n external-dns EXTERNAL_DNS_LOG_LEVEL=debug
kubectl logs -n external-dns deployment/external-dns -f

# Restore after debugging
kubectl set env deployment/external-dns -n external-dns EXTERNAL_DNS_LOG_LEVEL=info
```

## Security Considerations

- **Never commit API tokens** to version control — create the Kubernetes secret manually
- **Use least privilege**: only grant `Zone:DNS:Edit` to the API token
- **Rotate tokens periodically** and set expiration dates

## References

- [External DNS Documentation](https://kubernetes-sigs.github.io/external-dns/)
- [Cloudflare Provider Tutorial](https://kubernetes-sigs.github.io/external-dns/latest/tutorials/cloudflare/)
- [External DNS Helm Chart Values](https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns#values)
- [Cloudflare API Token Documentation](https://developers.cloudflare.com/api/tokens/create)

