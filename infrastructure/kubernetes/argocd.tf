# https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
# helm install argocd argo/argo-cd --namespace argocd --create-namespace
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.4.15"

  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true

  values = [
    file("${path.module}/argocd.yaml")
  ]
}

# Root Application — bootstraps Argo CD to watch the rendered directory
resource "kubernetes_manifest" "argocd_root" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "oci-root"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/gregarendse/homelab.git"
        targetRevision = "master"
        path           = "clusters/oci/rendered"
        directory = {
          include = "*.yaml"
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
    }
  }
  depends_on = [helm_release.argocd]
}
