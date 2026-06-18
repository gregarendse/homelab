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
  longhorn_backup_secret_name = "longhorn-backup-b2"
}

# Credentials Longhorn uses to reach the Backblaze B2 (S3) backup target.
# AWS_ENDPOINTS points the S3 client at B2 instead of AWS.
resource "kubernetes_secret" "longhorn_backup" {
  metadata {
    name      = local.longhorn_backup_secret_name
    namespace = helm_release.longhorn.namespace
  }

  type = "Opaque"

  data = {
    AWS_ACCESS_KEY_ID     = var.longhorn_backup_access_key
    AWS_SECRET_ACCESS_KEY = var.longhorn_backup_secret_key
    AWS_ENDPOINTS         = var.longhorn_backup_endpoint
  }
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
