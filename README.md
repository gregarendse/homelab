# Home Lab

This repository is the source of truth for a personal homelab that is operated with **Infrastructure as Code** and **GitOps**.

## Purpose

The project has two goals:

1. Keep infrastructure and application state reproducible and reviewable in Git.
2. Serve as a practical reference for building and operating a small multi-cluster homelab on Oracle Cloud Infrastructure (OCI) and local/on-prem resources.

In practice, this means:
- Infrastructure is provisioned with Terraform (`infrastructure/`).
- Kubernetes apps are managed through Argo CD inventories (`clusters/<cluster>/apps.yaml`).
- App configuration lives in `applications/` and generated manifests are committed under `clusters/<cluster>/rendered/`.

## Current State (as represented in this repo)

- **Clusters**
  - `clusters/oci`: primary cloud cluster inventory and rendered outputs.
  - `clusters/trinity`: secondary cluster inventory and rendered outputs.
- **GitOps model**
  - Per-cluster app inventories define Helm and rendered applications.
  - Argo CD bootstrap patterns and root app definitions are included in-cluster folders and Terraform.
- **Infrastructure**
  - OCI-focused Terraform for networking, compute, Kubernetes bootstrap, and supporting services.
  - Cloudflare DNS/Tunnel Terraform in `infrastructure/cloudflare/`.
- **Operations**
  - Utility scripts under `scripts/` for maintenance and backups.
  - Legacy Kubernetes-era Docker manifests kept for reference in `docker-scripts/`.

## Longhorn Backups (staggered)

Volumes are backed up to Backblaze B2 once a week each, staggered across the
week so any single night only backs up 1-2 volumes. This keeps B2 Class B
(LIST/HEAD) transactions under the free-tier daily cap. Seven RecurringJobs
(`<day>-backup`) live in `infrastructure/kubernetes/longhorn.tf`, one per
weekday at 02:00.

A volume joins a day's cycle via the label
`recurring-job-group.longhorn.io/<day>-backup: enabled` on its PVC. When you
add a new PVC, assign it a weekday group so backups stay spread (aim for 1-2
volumes per day) - otherwise it won't be backed up. Set the label durably where
the PVC is defined (the `.nix` PVC / `volumeClaimTemplate` for kubenix apps, or
the chart's PVC-labels field for Helm apps). Current split: Mon home-assistant,
Tue mongo, Wed unifi, Thu pihole, Fri hermes, Sat grafana+prometheus, Sun loki.

## What this repository is not

- It is not a polished starter template with one-click setup.
- It is not a guarantee that every legacy manifest is still actively deployed.
- It does not store secrets in Git; sensitive values are expected to be injected via variables/secrets tooling.

## Suggested reading

- `docs/gitops.md` for the cluster GitOps flow and Argo CD bootstrap pattern.
- `infrastructure/cloudflare/README.md` for Cloudflare-specific Terraform usage.
- `src/go/ci/README.md` for CI tooling used in this repository.
