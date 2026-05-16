---
name: terraform-nix
trigger:
  type: keyword
  keywords: ["terraform", "hcl", "nix", "nixos", "flake", "infrastructure",
             "OCI resource", "provision", "nix-shell", "derivation"]
---
# Terraform / Nix Infrastructure

## Repository layout
- `infrastructure/` — Terraform/HCL for OCI resources (VCN, compute, storage)
- `server/` — NixOS system configuration
- `applications/` — kubenix application manifests (Nix flakes → K8s YAML)
- `scripts/` — cluster bootstrapping

## Terraform workflow
```bash
cd infrastructure/
terraform plan
terraform apply
```
Provider: oracle/oci

## kubenix workflow
```bash
cd applications/<app>/
nix build              # generates result/ with K8s manifests
kubectl apply -f result/
```

## OCI free tier limits — never exceed these
- Compute: 4 OCPU + 24 GB RAM (Ampere A1 Flex)
- Block Storage: 200 GB total
- Object Storage: 20 GB
- Networks: 2 VCNs, 1 internet gateway
- Load Balancers: 1 (10 Mbps)

## Critical: do not delete
- VCN, subnet, or internet gateway — will tear down the entire cluster
- Longhorn storage class — all PVCs depend on it

## Nix guidance
- Prefer flakes over legacy channels
- Keep derivations reproducible — no impure fetchurl without hashes
- For services: use systemd service modules where possible
- ARM64: verify aarch64-linux support for any fetched binaries
