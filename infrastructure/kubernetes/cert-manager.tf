
# https://cert-manager.io/docs/installation/helm/
# helm install \
# cert-manager oci://quay.io/jetstack/charts/cert-manager \
# --version v1.18.2 \
# --namespace cert-manager \
# --create-namespace \
# --set crds.enabled=true

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = "security"
  chart      = "cert-manager"
  repository = "oci://quay.io/jetstack/charts"
  version    = "v1.18.2"

  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  skip_crds        = false

  set = [{
    name  = "crds.enabled"
    value = "true"
  }]
}

# This resource must be created after the cert-manager Helm release, enable after the helm release has been installed
resource "kubernetes_manifest" "cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server : "https://acme-v02.api.letsencrypt.org/directory"
        # Email address used for ACME registration
        email : var.cert_manager_email
        # Name of a secret used to store the ACME account private key
        privateKeySecretRef = {
          name : "letsencrypt-prod"
        }
        # Enable the HTTP-01 challenge provider
        solvers = [{
          http01 = {
            ingress = {
              class : "traefik"
            }
          }
        }]
      }
    }
  }
  depends_on = [helm_release.cert_manager]
}
