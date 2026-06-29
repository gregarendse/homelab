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
    # NOTE (2026-06-19) — backup-store poll interval is a known loose end.
    # It is currently set to 3h DIRECTLY on the live BackupTarget CR via
    #   kubectl -n longhorn-system patch backuptargets.longhorn.io default \
    #     --type=merge -p '{"spec":{"pollInterval":"3h0m0s"}}'
    # and is intentionally NOT yet managed here.
    #
    # Why 3h: Longhorn's default 5-minute backup-store polling issues B2
    # LIST/HEAD calls that pushed our Backblaze account past its daily Class B
    # transaction cap (2,500/day). Once exceeded, B2 returns 403, which locked
    # Terraform out of its remote state entirely. 3h cuts that recurring traffic
    # ~36x while keeping the backup list reasonably fresh.
    #
    # Why it's not fixed in code yet: on Longhorn 1.10 the poll interval lives on
    # the BackupTarget CR (spec.pollInterval); the old `backupstore-poll-interval`
    # setting no longer exists, so it isn't covered by the defaultSettings below.
    # The live 3h value survives `terraform apply` (apply doesn't touch
    # pollInterval), but a from-scratch reinstall would revert to the 5m default.
    #
    # TODO (cleanup later, once the B2 cap clears and `terraform plan` works
    # again): encode the poll interval properly — likely via the chart's
    # `defaultBackupStore` block — and verify on apply. Deferred until the
    # backend is reachable and everything is green again.
    {
      name  = "defaultSettings.backupTarget"
      value = "s3://${var.longhorn_backup_bucket}@${var.longhorn_backup_region}/"
    },
    {
      name  = "defaultSettings.backupTargetCredentialSecret"
      value = local.longhorn_backup_secret_name
    }
  ]
}

locals {
  # The credential Secret is applied out-of-band (see
  # longhorn-backup-secret.example.yaml) so the B2 keys never enter Terraform
  # state. Terraform only references it by name.
  longhorn_backup_secret_name = "longhorn-backup-b2"
}

# Single-replica StorageClass for volumes that don't need Longhorn redundancy.
# The cluster is single-node, so anything requesting >1 replica sits permanently
# degraded (anti-affinity can't place replicas on a second node). The built-in
# `longhorn` class carries numberOfReplicas=3, so charts that pin to it (loki,
# grafana, prometheus) need this class to stay healthy.
resource "kubernetes_manifest" "longhorn_r1_storageclass" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "longhorn-r1"
    }
    provisioner          = "driver.longhorn.io"
    allowVolumeExpansion = true
    reclaimPolicy        = "Delete"
    volumeBindingMode    = "Immediate"
    parameters = {
      numberOfReplicas    = "1"
      staleReplicaTimeout = "30"
    }
  }

  depends_on = [helm_release.longhorn]
}

# Backups are staggered across the week to stay under Backblaze B2's free-tier
# Class B (LIST/HEAD) transaction cap. Instead of one job that backs up the
# whole `default` group every night, each weekday has its own group + job, so
# only the volumes assigned to that day's group are backed up. Spread your
# volumes across these groups (1-2 per day) by adding the matching label to
# each volume:
#
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
