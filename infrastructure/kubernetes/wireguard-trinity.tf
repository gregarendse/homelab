# Direct OCI <-> Trinity WireGuard tunnel — cluster side.
#
# Manual, one-time steps required before/after `terraform apply` here — see
# docs/wireguard-trinity.md. In short:
#   1. Label the node backing var.wireguard_gateway_instance_name:
#        kubectl --context oci label node <node-name> homelab.arendse.nom.za/wireguard-gateway=true
#   2. Create the private-key Secret out of band (never committed, matching
#      the existing convention in infrastructure/kubernetes/EXTERNAL_DNS.md /
#      applications/openclaw/openclaw.nix):
#        kubectl --context oci create secret generic wireguard-trinity-keys \
#          --namespace wireguard-trinity \
#          --from-literal=wg0.conf="$(cat wg0.conf)"
#
# Why hostNetwork + a pinned node instead of a normal Service: reaching
# Trinity has to work for *any* pod in the cluster, not just this one, which
# means some node has to hold the wg0 interface and do real IP forwarding
# other nodes can route through. That's unavoidably a single pinned node —
# see infrastructure/network/wireguard-trinity.tf for the matching NLB side.

resource "kubernetes_namespace_v1" "wireguard_trinity" {
  metadata {
    name = "wireguard-trinity"
    labels = {
      "app.kubernetes.io/part-of" = "wireguard-trinity"
    }
  }
}

# Non-secret half of the config: everything except the private key, which
# lives in the manually-created wireguard-trinity-keys Secret instead.
resource "kubernetes_config_map_v1" "wireguard_trinity_gateway_info" {
  metadata {
    name      = "wireguard-trinity-gateway-info"
    namespace = kubernetes_namespace_v1.wireguard_trinity.metadata[0].name
  }

  data = {
    gateway_private_ip = var.wireguard_gateway_private_ip
    trinity_pod_cidr   = var.trinity_pod_cidr
    trinity_svc_cidr   = var.trinity_svc_cidr
  }
}

resource "kubernetes_deployment_v1" "wireguard_trinity" {
  metadata {
    name      = "wireguard-trinity"
    namespace = kubernetes_namespace_v1.wireguard_trinity.metadata[0].name
    labels = {
      app = "wireguard-trinity"
    }
  }

  spec {
    replicas = 1

    strategy {
      # hostNetwork + a single replica means the old and new pod would race
      # for the same UDP port on the same node during a rolling update.
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "wireguard-trinity"
      }
    }

    template {
      metadata {
        labels = {
          app = "wireguard-trinity"
        }
      }

      spec {
        host_network = true
        dns_policy   = "ClusterFirstWithHostNet"

        # Pinned to whichever node backs var.wireguard_gateway_instance_name
        # (infrastructure/variables.tf) — see docs/wireguard-trinity.md for
        # the one-time `kubectl label node` step.
        node_selector = {
          "homelab.arendse.nom.za/wireguard-gateway" = "true"
        }

        container {
          name  = "wireguard"
          image = "linuxserver/wireguard:latest" # multi-arch, arm64 included

          env {
            name  = "PUID"
            value = "1000"
          }
          env {
            name  = "PGID"
            value = "1000"
          }
          env {
            name  = "TZ"
            value = "Africa/Johannesburg"
          }

          security_context {
            capabilities {
              add = ["NET_ADMIN"]
            }
          }

          volume_mount {
            name       = "wg-config"
            mount_path = "/config/wg_confs/wg0.conf"
            sub_path   = "wg0.conf"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "wg-config"
          secret {
            # Created manually, out of band — see header comment and
            # docs/wireguard-trinity.md. Not managed by Terraform so the
            # private key never touches TF state.
            secret_name = "wireguard-trinity-keys"
          }
        }
      }
    }
  }
}

# Installs a route to Trinity's pod/service CIDRs, via the gateway node, on
# every *other* node — so pods scheduled anywhere in the cluster can reach
# Trinity, not just pods on the gateway node itself. Cilium's default
# masquerade (SNAT pod egress to the node IP) means this one host route per
# node is sufficient; no per-pod routing is needed.
resource "kubernetes_daemon_set_v1" "wireguard_trinity_routes" {
  metadata {
    name      = "wireguard-trinity-routes"
    namespace = kubernetes_namespace_v1.wireguard_trinity.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = "wireguard-trinity-routes"
      }
    }

    template {
      metadata {
        labels = {
          app = "wireguard-trinity-routes"
        }
      }

      spec {
        host_network = true

        # Don't also run this on the gateway node: wg-quick's own PostUp
        # already owns these routes there via the tunnel interface directly.
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "homelab.arendse.nom.za/wireguard-gateway"
                  operator = "NotIn"
                  values   = ["true"]
                }
              }
            }
          }
        }

        container {
          name  = "route-sync"
          image = "docker.io/library/alpine:3.20" # multi-arch, arm64 included

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              apk add --no-cache iproute2 >/dev/null
              while true; do
                ip route replace "$TRINITY_POD_CIDR" via "$GATEWAY_PRIVATE_IP"
                ip route replace "$TRINITY_SVC_CIDR" via "$GATEWAY_PRIVATE_IP"
                sleep 60
              done
            EOT
          ]

          env {
            name = "GATEWAY_PRIVATE_IP"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.wireguard_trinity_gateway_info.metadata[0].name
                key  = "gateway_private_ip"
              }
            }
          }
          env {
            name = "TRINITY_POD_CIDR"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.wireguard_trinity_gateway_info.metadata[0].name
                key  = "trinity_pod_cidr"
              }
            }
          }
          env {
            name = "TRINITY_SVC_CIDR"
            value_from {
              config_map_key_ref {
                name = kubernetes_config_map_v1.wireguard_trinity_gateway_info.metadata[0].name
                key  = "trinity_svc_cidr"
              }
            }
          }

          security_context {
            capabilities {
              add = ["NET_ADMIN"]
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "50m"
              memory = "32Mi"
            }
          }
        }
      }
    }
  }
}
