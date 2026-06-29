{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {
      # Namespace
      namespaces.pihole = { };

      # ConfigMap for Pi-hole custom DNS settings
      configMaps.custom-dnsmasq = {
        metadata = {
          name = "custom-dnsmasq";
          namespace = "pihole";
        };
        data = {
          "50-custom.conf" = builtins.readFile ./custom-dnsmasq.conf;
        };
      };

      # ConfigMap for Pi-hole TOML configuration
      configMaps.pihole-config = {
        metadata = {
          name = "pihole-config";
          namespace = "pihole";
        };
        data = {
          "pihole.toml" = builtins.readFile ./pihole.toml;
        };
      };

      # Secret for Pi-hole admin password
      secrets.pihole-secret = {
        metadata = {
          name = "pihole-secret";
          namespace = "pihole";
        };
        type = "Opaque";
        stringData = {
          password = "admin123"; # Change this to your desired password
        };
      };

      # PersistentVolumeClaim for Pi-hole data
      persistentVolumeClaims.pihole-data = {
        metadata = {
          name = "pihole-data";
          namespace = "pihole";
          # Longhorn backup cycle: Thursday (staggered to spread B2 traffic)
          labels."recurring-job-group.longhorn.io/thursday-backup" = "enabled";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
          storageClassName = "longhorn"; # Adjust to your storage class
        };
      };

      # Deployment for Pi-hole
      deployments.pihole = {
        metadata = {
          name = "pihole";
          namespace = "pihole";
          labels = {
            app = "pihole";
          };
        };
        spec = {
          replicas = 1;
          strategy = {
            type = "Recreate";
          };
          selector.matchLabels = {
            app = "pihole";
          };
          template = {
            metadata.labels = {
              app = "pihole";
            };
            spec = {
              containers = [
                {
                  name = "pihole";
                  image = "pihole/pihole:2026.04.1";
                  ports = [
                    {
                      name = "dns-tcp";
                      containerPort = 53;
                      protocol = "TCP";
                    }
                    {
                      name = "dns-udp";
                      containerPort = 53;
                      protocol = "UDP";
                    }
                    {
                      name = "http";
                      containerPort = 80;
                      protocol = "TCP";
                    }
                    {
                      name = "https";
                      containerPort = 443;
                      protocol = "TCP";
                    }
                    {
                      name = "dhcp";
                      containerPort = 67;
                      protocol = "UDP";
                    }
                    {
                      name = "ntp";
                      containerPort = 123;
                      protocol = "UDP";
                    }
                  ];
                  env = [
                    {
                      name = "TZ";
                      value = "Europe/London";
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "pihole-data";
                      mountPath = "/etc/pihole";
                      subPath = "pihole";
                    }
                    {
                      name = "pihole-data";
                      mountPath = "/etc/dnsmasq.d";
                      subPath = "dnsmasq.d";
                    }
                    {
                      name = "custom-dnsmasq";
                      mountPath = "/etc/dnsmasq.d/50-custom.conf";
                      subPath = "50-custom.conf";
                    }
                    {
                      name = "pihole-config";
                      mountPath = "/etc/pihole/pihole.toml";
                      subPath = "pihole.toml";
                    }
                    {
                      # Override the default 64MB /dev/shm limit so FTL doesn't OOM
                      name = "dshm";
                      mountPath = "/dev/shm";
                    }
                  ];
                  resources = {
                    requests = {
                      # /dev/shm 128Mi + 256Mi
                      memory = "384Mi";
                      cpu = "500m";
                    };
                    limits = {
                      # /dev/shm 128Mi + 512Mi
                      memory = "640Mi";
                      cpu = "1000m";
                    };
                  };
                }
              ];
              volumes = [
                {
                  name = "pihole-data";
                  persistentVolumeClaim.claimName = "pihole-data";
                }
                {
                  name = "custom-dnsmasq";
                  configMap.name = "custom-dnsmasq";
                }
                {
                  name = "pihole-config";
                  configMap.name = "pihole-config";
                }
                {
                  # tmpfs-backed volume to replace the 64MB /dev/shm default
                  name = "dshm";
                  emptyDir = {
                    medium = "Memory";
                    sizeLimit = "128Mi";
                  };
                }
              ];
            };
          };
        };
      };

      # Service for Pi-hole DNS (UDP/TCP)
      services.pihole-dns = {
        metadata = {
          name = "pihole-dns";
          namespace = "pihole";
          labels = {
            app = "pihole";
            service = "dns";
          };
        };
        spec = {
          type = "NodePort";
          # Preserve the real client IP instead of SNAT-ing to the node's
          # Cilium internal IP. Without this, all home network clients appear
          # as internal node IPs, causing Pi-hole to rate-limit them.
          externalTrafficPolicy = "Local";
          selector = {
            app = "pihole";
          };
          ports = [
            {
              name = "dns-tcp";
              port = 53;
              targetPort = 53;
              protocol = "TCP";
              nodePort = 30530; # Optional: specify NodePort if needed
            }
            {
              name = "dns-udp";
              port = 53;
              targetPort = 53;
              protocol = "UDP";
              nodePort = 30053; # Optional: specify NodePort if needed
            }
            {
              name = "dhcp-udp";
              port = 67;
              targetPort = 67;
              protocol = "UDP";
              nodePort = 30067; # Optional: specify NodePort if needed
            }
            {
              name = "ntp-udp";
              port = 123;
              targetPort = 123;
              protocol = "UDP";
              nodePort = 30123; # Optional: specify NodePort if needed
            }
          ];
        };
      };

      # Service for Pi-hole web interface
      services.pihole-web = {
        metadata = {
          name = "pihole-web";
          namespace = "pihole";
          labels = {
            app = "pihole";
            service = "web";
          };
        };
        spec = {
          type = "ClusterIP";
          selector = {
            app = "pihole";
          };
          ports = [
            {
              name = "http";
              port = 80;
              targetPort = 80;
              protocol = "TCP";
            }
            {
              name = "https";
              port = 443;
              targetPort = 443;
              protocol = "TCP";
            }
          ];
        };
      };

      # Ingress for Pi-hole web interface
      ingresses.pihole-ingress = {
        metadata = {
          name = "pihole-ingress";
          namespace = "pihole";
          annotations = {
            "external-dns.alpha.kubernetes.io/cloudflare-proxied" = "true";
            "external-dns.alpha.kubernetes.io/cloudflare-tags" = "app=pihole,env=prod,owner=homelab";
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
          };
        };
        spec = {
          tls = [
            {
              hosts = [ "pihole.arendse.nom.za" ];
              secretName = "pihole-tls";
            }
          ];
          rules = [
            {
              host = "pihole.arendse.nom.za";
              http.paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                  backend.service = {
                    name = "pihole-web";
                    port.number = 80;
                  };
                }
              ];
            }
          ];
        };
      };
    };
  };
}
