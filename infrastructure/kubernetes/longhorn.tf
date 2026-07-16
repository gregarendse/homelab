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
    # Configure the default Backblaze B2 backup target via the Longhorn chart's
    # defaultBackupStore block. The 3h poll interval keeps LIST/HEAD traffic far
    # below B2's free-tier Class B cap; Longhorn's chart default is 300s, and 0
    # disables polling entirely.
    {
      name  = "defaultBackupStore.backupTarget"
      value = "s3://${var.longhorn_backup_bucket}@${var.longhorn_backup_region}/"
    },
    {
      name  = "defaultBackupStore.backupTargetCredentialSecret"
      value = local.longhorn_backup_secret_name
    },
    # Disable polling entirely (0) to avoid LIST/HEAD traffic exceeding B2's free-tier Class B cap.
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
  for_each = local.longhorn_backup_days

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
