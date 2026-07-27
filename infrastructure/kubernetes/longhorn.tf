resource "helm_release" "longhorn" {
  name             = "longhorn"
  namespace        = "longhorn-system"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = "1.10.0"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  force_update     = true

  set = [
    {
      name  = "defaultSettings.defaultReplicaCount"
      value = "\"1\""
    },
    # Single-node cluster: make the default `longhorn` StorageClass provision
    # 1 replica so volumes don't sit permanently degraded (the chart otherwise
    # bakes numberOfReplicas=3 into the default class, overriding the setting
    # above for any PVC using it).
    {
      name  = "persistence.defaultClassReplicaCount"
      value = "1"
    },
    # Reboot resilience (single-node cluster). An unclean shutdown kills the
    # replica process mid-write, so on the next boot Longhorn marks the lone
    # replica failed and the volume goes `faulted`. auto-salvage lets Longhorn
    # automatically clear that and bring the volume back on re-attach, so a
    # reboot self-heals with only the reboot's worth of downtime instead of
    # needing a manual salvage. See the "unclean reboot" runbook in README.md.
    {
      name  = "defaultSettings.autoSalvage"
      value = "true"
    },
    # Delete the workload pod when its volume detaches unexpectedly so the pod is
    # rescheduled and re-attaches (triggering auto-salvage) instead of getting
    # stuck on a stale mount.
    {
      name  = "defaultSettings.autoDeletePodWhenVolumeDetachedUnexpectedly"
      value = "true"
    },
    # Configure the default Backblaze B2 backup target via the Longhorn chart's
    # defaultBackupStore block. pollInterval is 0 (polling disabled) to avoid
    # LIST/HEAD traffic exceeding B2's free-tier Class B/C caps.
    #
    # NOTE: backupTarget is gated on local.longhorn_backups_enabled. While that
    # is false the target renders empty (""), which disables all backup activity
    # and stops Longhorn talking to B2 at all. See the TODO on that local below.
    {
      name  = "defaultBackupStore.backupTarget"
      value = local.longhorn_backups_enabled ? "s3://${var.longhorn_backup_bucket}@${var.longhorn_backup_region}/" : ""
    },
    {
      name  = "defaultBackupStore.backupTargetCredentialSecret"
      value = local.longhorn_backup_secret_name
    },
    {
      name  = "defaultBackupStore.pollInterval"
      value = "0"
    }
  ]
}

locals {
  # The credential Secret is applied out-of-band (see
  # longhorn-backup-secret.example.yaml) so the B2 keys never enter Terraform
  # state. Terraform only references it by name.
  longhorn_backup_secret_name = "longhorn-backup-b2"

  # TODO(backups): re-enable Longhorn -> Backblaze B2 backups.
  #
  # Backups were disabled 2026-07-27 during a storage-cap + faulted-volume
  # incident: total stored data had exceeded B2's free-tier 10 GB cap, which put
  # failing backups into a retry loop that exhausted the daily Class C
  # (LIST) transaction cap. While this is false the backup target renders empty
  # and no weekday RecurringJobs are created, so `terraform apply` can ship other
  # Longhorn changes (e.g. auto-salvage) without re-triggering backups.
  #
  # Before flipping this back to true:
  #   1. Delete the oversized Prometheus + Loki backup sets from B2 so stored
  #      data drops back under 10 GB (see applications/loki/README.md and the
  #      README "Longhorn Backups" section).
  #   2. Confirm B2 storage < 10 GB and daily transactions are back to baseline.
  #   3. Set this to true and `terraform apply`.
  longhorn_backups_enabled = false
}

# Backups are staggered across the week to stay under Backblaze B2's free-tier
# Class B (LIST/HEAD) transaction cap. Instead of one job that backs up the
# whole `default` group every night, each weekday has its own group + job, so
# only the volumes assigned to that day's group are backed up. Spread your
# volumes across these groups (1-2 per day) by adding the PVC source label plus
# the matching group label:
#
#   recurring-job.longhorn.io/source: enabled
#   recurring-job-group.longhorn.io/<day>-backup: enabled
#
# e.g. label two volumes with `recurring-job-group.longhorn.io/monday-backup`,
# two with `tuesday-backup`, etc. Volumes left in `default` are no longer
# backed up automatically, so make sure every volume gets a weekday group.
locals {
  # Cron day-of-week field: 0=Sun .. 6=Sat. All jobs run at 02:00.
  longhorn_backup_days = {
    monday    = 1
    tuesday   = 2
    wednesday = 3
    thursday  = 4
    friday    = 5
    saturday  = 6
    sunday    = 0
  }
}

resource "kubernetes_manifest" "longhorn_staggered_backup" {
  # Gated on the backups toggle: while backups are disabled we skip the weekday
  # RecurringJobs entirely so nothing is scheduled against the (empty) target.
  for_each = local.longhorn_backups_enabled ? local.longhorn_backup_days : {}

  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "${each.key}-backup"
      namespace = helm_release.longhorn.namespace
    }
    spec = {
      cron        = "0 2 * * ${each.value}" # 02:00 on the assigned weekday
      task        = "backup"
      groups      = ["${each.key}-backup"]
      retain      = var.longhorn_backup_retain
      concurrency = 1
    }
  }

  depends_on = [helm_release.longhorn]
}
