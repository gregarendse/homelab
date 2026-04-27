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
    }
  ]
}
