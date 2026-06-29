# External DNS - Automatically manages DNS records in Cloudflare based on Kubernetes Ingress resources
# https://github.com/kubernetes-sigs/external-dns
# https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns

# Create namespace for External DNS
resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
  }
}

# NOTE: The Cloudflare API token secret must be created manually
# See EXTERNAL_DNS.md for instructions on creating the secret

# Deploy External DNS using Helm
resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = kubernetes_namespace.external_dns.metadata[0].name
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.15.1"

  atomic           = true
  cleanup_on_fail  = true
  create_namespace = false
  force_update     = true

  values = [
    yamlencode({
      # https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns#values
      provider = "cloudflare"

      # Cloudflare configuration
      env = [
        {
          name = "CF_API_TOKEN"
          valueFrom = {
            secretKeyRef = {
              name = "cloudflare-credentials" # Must be created manually - see EXTERNAL_DNS.md
              key  = "cloudflare-api-token"
            }
          }
        }
      ]

      # Prefer chart-native values and keep extraArgs only for provider-specific flags.
      registry      = "txt"
      txtOwnerId    = "external-dns-${var.domain_name}"
      txtPrefix     = "external-dns-"
      domainFilters = [var.domain_name]

      # Per-record proxying is controlled via the ingress annotation:
      # external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
      # Do not set --cloudflare-proxied globally here as it overrides per-record control.

      # RBAC
      rbac = {
        create = true
      }

      serviceAccount = {
        create = true
        name   = "external-dns"
      }

      # Resource limits
      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }

      # Enable logging
      logLevel = "info"

      # Watch ingresses only. This avoids extra noise when apps are exposed via Ingress.
      sources = ["ingress"]

      # Policy for managing DNS records
      policy = "sync" # sync, upsert-only

      # Metrics
      metrics = {
        enabled = true
        service = {
          annotations = {}
        }
      }

      # Replicas (for HA, set to 2 or more)
      replicas = 2

      # Node affinity (optional, for pinning to specific nodes)
      # affinity = {}

      # Tolerations (optional, for running on tainted nodes)
      # tolerations = []
    })
  ]

  depends_on = [kubernetes_namespace.external_dns]
}

