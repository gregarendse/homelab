# actual-sync

A scheduled Kubernetes `CronJob` that keeps [Actual Budget](https://actualbudget.org/)
accounts bank-synced by running [`actual-ctl`](https://github.com/gregarendse/actual-ctl)'s
`sync-due` command, staying within the GoCardless free-tier rate limit no matter
how many accounts you have.

Modelled on the upstream
[`cronjob.example.yaml`](https://github.com/gregarendse/actual-ctl/blob/master/manifests/cronjob.example.yaml).

- **Image:** `ghcr.io/gregarendse/actual-ctl:latest`
- **Namespace:** `actual-sync`
- **Actual endpoint:** `http://actual.actual.svc.cluster.local:5006` (in-cluster)
- **Command:** `actual-ctl sync-due --limit 4 --min-age 20`

## How it works

Each run, `sync-due` bank-syncs the **least-recently-synced accounts first** and
**skips any account synced within the last `--min-age` hours** (it reads each
account's own `last_sync` timestamp). `--limit` caps how many accounts a single
run will touch.

Because eligibility is decided per account from its `last_sync` time, the
rotation is **stateless** and stays under GoCardless' per-account daily rate
limit regardless of how frequently the CronJob fires. The account list is read
on every run, so it **adapts automatically to a variable number of accounts** —
add or remove accounts in Actual and nothing here needs to change.

## Cadence and the GoCardless free tier

GoCardless' free tier allows roughly **4 syncs per account per day**. With the
committed defaults — `--min-age 20` on a 6-hour schedule — each account becomes
eligible again ~20 hours after its last sync, so it is synced roughly **once per
day**, well under the limit. `--min-age` is the real protection here, so a
frequent schedule is safe: recently-synced accounts are simply skipped.

## Tuning the knobs

All knobs live in a single `let` block at the top of
[`actual-sync.nix`](./actual-sync.nix):

```nix
limit = 4;          # max accounts synced per run
minAgeHours = 20;   # skip accounts synced within this many hours
intervalHours = 6;  # hours between runs (must divide 24)
```

`intervalHours` drives the CronJob `schedule`. To sync each account less often,
raise `minAgeHours` (e.g. `44` for roughly every other day). To handle more
accounts falling due in the same run, raise `limit`. After changing any value,
rebuild and re-apply (see Deploy).

## Prerequisites

Create the namespace and the required Secret before the first deploy. The Secret
is named `actual-ctl` and is consumed via `envFrom`; it is **never committed**
(per repo convention). It carries the in-cluster server URL plus the sensitive
Sync ID and password:

```bash
kubectl create namespace actual-sync

kubectl create secret generic actual-ctl \
  --namespace actual-sync \
  --from-literal=SERVER_URL="http://actual.actual.svc.cluster.local:5006" \
  --from-literal=SYNC_ID="your-budget-sync-id" \
  --from-literal=PASSWORD="your-actual-server-password"
```

> `SYNC_ID` is the budget's **Sync ID** (Actual → Settings → Show advanced
> settings → Sync ID). `PASSWORD` is the Actual server login password.

## Deploy

```bash
cd applications/actual-sync
nix build .#manifests
kubectl apply -f result
```

## Verify / run on demand

```bash
# Inspect the CronJob and recent runs
kubectl get cronjob,jobs -n actual-sync

# Trigger an immediate run without waiting for the schedule
kubectl create job -n actual-sync --from=cronjob/actual-sync actual-sync-manual

# Follow the logs of the most recent run
kubectl logs -n actual-sync -l app.kubernetes.io/name=actual-ctl --tail=100 -f
```

Preview which accounts are due without syncing anything by running the CLI with
`sync-due --dry-run` (e.g. locally, or in a one-off pod).

## Notes

- The container runs from the distroless `actual-ctl` image; `args` include
  `dist/index.js` because the image entrypoint is bare `node` (the upstream
  example omits it).
- The local budget cache lives in an ephemeral `emptyDir` at `/data`; it is
  re-downloaded from the Actual server on every run. Swap for a PVC to persist.
- `sync-due` covers GoCardless-linked accounts; closed accounts are ignored.
