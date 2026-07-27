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
week so any single night only backs up 1-2 volumes. This keeps B2 Class B/C
(LIST/HEAD) transactions under the free-tier daily cap. Seven RecurringJobs
(`<day>-backup`) live in `infrastructure/kubernetes/longhorn.tf`, one per
weekday at 02:00.

> **Backups are currently DISABLED.** `local.longhorn_backups_enabled` in
> `infrastructure/kubernetes/longhorn.tf` is `false` (empties the backup target
> and skips the RecurringJobs) following a 2026-07-27 storage-cap incident. See
> the `TODO(backups)` there for the steps to re-enable.

Watch **two** separate B2 free-tier limits: the daily transaction caps
(2,500 Class B and 2,500 Class C) and the **10 GB stored-data cap**. Staggering
addresses transactions; total stored backup size is bounded separately by which
volumes we back up and by `retain`. Large, high-churn, reproducible volumes
(Prometheus metrics, Loki logs) are deliberately **not** backed up to keep the
stored total under 10 GB - Loki's logs already live in OCI Object Storage, and
Prometheus metrics are reproducible. Removing a backup label only stops future
backups; reclaim space by also deleting the existing backups from B2.

A volume joins a day's cycle via PVC labels. Longhorn only syncs PVC recurring
job labels when the PVC is also marked as a recurring-job label source:
`recurring-job.longhorn.io/source: enabled` plus
`recurring-job-group.longhorn.io/<day>-backup: enabled`. When you add a new PVC,
assign it a weekday group so backups stay spread (aim for 1-2 volumes per day) -
otherwise it won't be backed up. Set the labels durably where the PVC is defined
(the `.nix` PVC / `volumeClaimTemplate` for kubenix apps, or the chart's
PVC-labels field for Helm apps). Current split: Mon home-assistant, Tue mongo,
Wed unifi, Thu pihole, Fri hermes, Sat grafana. (Prometheus and Loki are
intentionally excluded; see above.)

## Longhorn: recovering from an unclean reboot

This is a single-node cluster with 1 replica per volume, so an unclean shutdown
(power loss, crash, or a reboot while volumes are attached) can leave every
volume `detached` + `faulted`: Longhorn marks the lone replica failed because
its process was killed mid-write. `defaultSettings.autoSalvage=true` (set in
`longhorn.tf`) makes Longhorn recover these automatically on the next attach, so
a quick reboot self-heals. If volumes are still stuck faulted afterwards, salvage
manually.

1. Confirm the node is back and healthy, and check the volumes:
   ```bash
   kubectl get nodes
   kubectl -n longhorn-system get volumes.longhorn.io \
     -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness
   ```
2. Each volume has a single intact replica; clear the failure marker so Longhorn
   treats it as healthy, then restart the workloads to re-attach:
   ```bash
   for r in $(kubectl -n longhorn-system get replicas.longhorn.io -o name); do
     kubectl -n longhorn-system patch "$r" --type=merge -p '{"spec":{"failedAt":""}}'
   done
   ```
   (Or use the Longhorn UI: each faulted volume -> **Salvage** -> attach.)
3. Volumes should progress `faulted -> detached -> attaching -> attached` with
   `robustness: degraded` (expected with 1 replica).
4. Keep the node disk below ~70%. Longhorn marks its disk unschedulable once free
   space drops under the 25% reserve (`schedulable=False`), which blocks replica
   rebuilds. Reclaim space with `sudo crictl rmi --prune` and
   `sudo journalctl --vacuum-size=200M`.

## Longhorn: emergency "disable all backups"

If failing backups start hammering B2 (e.g. a retry loop after exceeding the
10 GB storage cap), kill all backup activity immediately with these live patches
(reverted on the next `terraform apply`, so re-enabling is just an apply):

```bash
# Point the backup target at nothing -> zero B2 traffic
kubectl -n longhorn-system patch backuptargets.longhorn.io default --type=merge \
  -p '{"spec":{"backupTargetURL":"","pollInterval":"0"}}'
# Remove the scheduled jobs
kubectl -n longhorn-system delete recurringjobs.longhorn.io --all
# Clear stuck/in-progress backups that hold volumes and loop
kubectl -n longhorn-system delete backups.longhorn.io --all
```

To make this durable in Git, set `local.longhorn_backups_enabled = false` in
`infrastructure/kubernetes/longhorn.tf` and apply.

## What this repository is not

- It is not a polished starter template with one-click setup.
- It is not a guarantee that every legacy manifest is still actively deployed.
- It does not store secrets in Git; sensitive values are expected to be injected via variables/secrets tooling.

## Suggested reading

- `docs/gitops.md` for the cluster GitOps flow and Argo CD bootstrap pattern.
- `infrastructure/cloudflare/README.md` for Cloudflare-specific Terraform usage.
- `src/go/ci/README.md` for CI tooling used in this repository.
