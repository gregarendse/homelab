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
