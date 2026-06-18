# Runbook: migrate OCI compute from 2 nodes to 1

Consolidates the OCI k3s cluster from **2 instances → 1** to fit Oracle's reduced
Always Free Ampere allocation (2 OCPU / 12 GB total). Done carelessly this causes
a **cluster outage** (etcd quorum loss) and **permanent data loss** (Longhorn
single-replica volumes on the terminated node). This runbook sequences the work so
neither happens.

## Why this is risky (read first)

- **Both OCI nodes are k3s control-plane servers** sharing an embedded etcd
  (`scripts/k3s.sh:196` `--cluster`, `scripts/k3s.sh:210` `--server`). A 2-member
  etcd needs both members for quorum, so removing one stops the API server until
  etcd is reset.
- **Longhorn uses a single replica** (`infrastructure/kubernetes/longhorn.tf:15`,
  `defaultReplicaCount = "1"`). Each volume lives on exactly one node; if that node
  is terminated, the data is gone. Affected apps: pihole, home-assistant, hermes,
  mongo. UniFi uses OCI block storage (`storageClassName = "oci"`) and is safe.
- **An instance-pool scale-in terminates an arbitrary instance with no draining.**
  We therefore remove a *specific*, already-drained node manually rather than
  letting Terraform pick.

## Prerequisites

- `kubectl` pointed at the OCI cluster (`~/.kube/config` from `scripts/k3s.sh`).
- SSH access to both nodes over Tailscale (`tailscale status`).
- OCI Console access (or `oci` CLI) for the instance pool.
- Terraform set up for `infrastructure/compute` (see the CI/CD PR).
- A maintenance window — pihole DNS and home-assistant will blip during cutover.
- **Decide which node survives** and record both Tailscale IPs / node names:
  ```bash
  kubectl get nodes -o wide
  tailscale status --peers --json | jq -r '.Peer[] | select(.HostName|startswith("ubuntu")) | "\(.HostName) \(.TailscaleIPs[0])"'
  ```
  Below, `KEEP_NODE` = the survivor, `DRAIN_NODE` = the one to remove.

---

## Phase 1 — Back up data (do not skip)

Two independent safety nets. Do at least #1; #2 is strongly recommended.

### 1. Replicate every Longhorn volume onto both nodes

So the survivor holds a full copy of all data before the other node leaves.

1. Open the Longhorn UI (`kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80`, then http://localhost:8080).
2. **Volume → select all → Update Replica Count → `2`.**
3. Wait until **every volume shows 2 healthy replicas** and is `Healthy` (one replica per node). Do not proceed until this is true.

   ```bash
   kubectl -n longhorn-system get volumes.longhorn.io \
     -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,REPLICAS:.spec.numberOfReplicas
   ```

### 2. Off-cluster backup (recommended)

Point Longhorn at an S3 backup target — you already have Backblaze B2 (used for
Terraform state). In Longhorn UI **Setting → General → Backup Target** (e.g.
`s3://<bucket>@<region>/`) with a credentials secret, then **Volume → select all →
Create Backup**. Verify backups complete before continuing.

---

## Phase 2 — Drain and remove the node from Kubernetes

1. **Cordon + drain** the node to remove (evicts pods to the survivor):
   ```bash
   kubectl cordon "$DRAIN_NODE"
   kubectl drain "$DRAIN_NODE" --ignore-daemonsets --delete-emptydir-data --timeout=10m
   ```
2. Confirm workloads rescheduled onto `KEEP_NODE` and are `Running`:
   ```bash
   kubectl get pods -A -o wide | grep -v Running || true
   kubectl get pods -A -o wide | grep "$DRAIN_NODE" || echo "no pods left on drain node"
   ```
3. **Uninstall k3s on the drained node** (cleanly stops its etcd member), over SSH:
   ```bash
   ssh "$USER@$DRAIN_NODE_IP" sudo /usr/local/bin/k3s-uninstall.sh || \
   ssh "$USER@$DRAIN_NODE_IP" sudo /usr/local/bin/k3s-server-uninstall.sh
   ```
4. **Delete the node object:**
   ```bash
   kubectl delete node "$DRAIN_NODE"
   ```

> At this point etcd has likely lost quorum (1 of 2 members). The API server may go
> read-only / unavailable — expected. Phase 4 restores it.

---

## Phase 3 — Remove the specific instance from the OCI pool

Terminate the **drained** instance and shrink the pool so it is not relaunched.
This guarantees the survivor is the node we kept.

**OCI Console:** Compute → Instance Pools → `ubuntu` → Instances → select the
**drained** instance → **Terminate**, and tick **"Decrement the instance pool
size"** (and "Permanently delete the attached boot volume" only for the drained
node).

**or CLI:**
```bash
oci compute-management instance-pool-instance detach \
  --instance-pool-id <POOL_OCID> \
  --instance-id <DRAINED_INSTANCE_OCID> \
  --is-decrement-size true \
  --is-auto-terminate true
```

The pool is now size 1, holding `KEEP_NODE`.

---

## Phase 4 — Restore single-node etcd

On the **surviving** node, reset etcd to a healthy single member:

```bash
ssh "$USER@$KEEP_NODE_IP"
sudo systemctl stop k3s
sudo k3s server --cluster-reset
# wait for "Managed etcd cluster membership has been reset" then Ctrl-C if it stays foreground
sudo systemctl start k3s
```

Verify the control plane is healthy with one node:
```bash
kubectl get nodes                       # only KEEP_NODE, Ready
kubectl get pods -A | grep -v Running   # nothing stuck
```

---

## Phase 5 — Apply the Terraform change

The PR sets `instance_count = 1` and pins the boot volume to 100 GB. Because the
pool is already size 1, the `size` change is a no-op; this mainly reconciles the
instance configuration.

```bash
cd infrastructure/compute
terraform plan -input=false   # confirm: pool size unchanged, NO instance destroy
terraform apply
```

If the plan shows the instance pool trying to **destroy/recreate** an instance,
**stop** — the pool state is out of sync with Phase 3; reconcile before applying.

---

## Phase 6 — Reset Longhorn to single replica

One node can only host one replica, so return to the default:

1. Longhorn UI → **Volume → select all → Update Replica Count → `1`** (clears the
   now-unschedulable second replicas).
2. Keep `infrastructure/kubernetes/longhorn.tf` at `defaultReplicaCount = "1"`
   (already correct) for new volumes.

---

## Phase 7 — Downstream cleanup

- **Network module:** with one instance, the second node's NLB backends disappear
  and the hard-coded `import` blocks for it in `infrastructure/network/nlb.tf`
  (`backend["ubuntu-6-*"]`) now reference for-each keys that no longer exist —
  delete those stale `import` blocks, then `terraform plan` the network module to
  confirm it's clean.
- Verify the public NLB has the surviving node as a healthy backend.

---

## Verification checklist

- [ ] `kubectl get nodes` → exactly one `Ready` node.
- [ ] `kubectl get pods -A` → all `Running`; none `Pending` for lack of resources.
- [ ] etcd healthy single member; API server stable across a survivor reboot.
- [ ] Longhorn volumes `Healthy` with 1 replica.
- [ ] pihole resolving DNS; home-assistant, unifi, mongo reachable with their data.
- [ ] NLB backend healthy; ingress (http/https) works.
- [ ] `network` module plan is clean after import-block cleanup.

## Rollback

- **Before Phase 3:** uncordon the drained node (`kubectl uncordon "$DRAIN_NODE"`);
  set Longhorn replicas back to 1. No change made to the pool.
- **After data loss:** restore volumes from the Phase 1.2 backups onto the single
  node (Longhorn → Backup → Restore). This is why the off-cluster backup matters.
- A single node has **no HA**: any reboot (incl. the cloud-init unattended-upgrades
  auto-reboot) is a full outage. Accept this or keep DNS resilient another way.
