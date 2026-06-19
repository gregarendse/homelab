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

# Daily backup of all volumes in the default group, keeping var.longhorn_backup_retain.
resource "kubernetes_manifest" "longhorn_daily_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "daily-backup"
      namespace = helm_release.longhorn.namespace
    }
    spec = {
      cron        = "0 2 * * *" # 02:00 daily
      task        = "backup"
      groups      = ["default"]
      retain      = var.longhorn_backup_retain
      concurrency = 1
    }
  }

  depends_on = [helm_release.longhorn]
}
