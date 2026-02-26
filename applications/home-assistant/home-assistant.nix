{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {
      # Namespace
      namespaces.home-assistant = {};

      # ConfigMap for Home Assistant configuration.yaml
      configMaps.home-assistant-config = {
        metadata = {
          name = "home-assistant-config";
          namespace = "home-assistant";
        };
        data = {
          "configuration.yaml" = builtins.readFile ./configuration.yaml;
        };
      };

      # PersistentVolumeClaim for Home Assistant config
      persistentVolumeClaims.home-assistant-config = {
        metadata = {
          name = "home-assistant-config";
          namespace = "home-assistant";
        };
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "5Gi";
          storageClassName = "longhorn"; # Adjust to your storage class
        };
      };

      # Deployment for Home Assistant
      deployments.home-assistant = {
        metadata = {
          name = "home-assistant";
          namespace = "home-assistant";
          labels = {
            app = "home-assistant";
          };
        };
        spec = {
          replicas = 1;
          strategy = {
            type = "Recreate";
          };
          selector.matchLabels = {
            app = "home-assistant";
          };
          template = {
            metadata.labels = {
              app = "home-assistant";
            };
            spec = {
              # Home Assistant may need privileged access for certain integrations
              # Uncomment if needed for hardware access (USB devices, Bluetooth, etc.)
              # hostNetwork = true;
              # dnsPolicy = "ClusterFirstWithHostNet";

              containers = [{
                name = "home-assistant";
                image = "ghcr.io/home-assistant/home-assistant:stable";
                ports = [
                  {
                    name = "http";
                    containerPort = 8123;
                    protocol = "TCP";
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
                    name = "config";
                    mountPath = "/config";
                  }
                  {
                    name = "config-yaml";
                    mountPath = "/config/configuration.yaml";
                    subPath = "configuration.yaml";
                  }
                ];
                resources = {
                  requests = {
                    memory = "512Mi";
                    cpu = "250m";
                  };
                  limits = {
                    memory = "2Gi";
                    cpu = "1000m";
                  };
                };
                # Home Assistant needs to be healthy before receiving traffic
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 8123;
                    scheme = "HTTP";
                  };
                  initialDelaySeconds = 60;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = 8123;
                    scheme = "HTTP";
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 5;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
              }];
              volumes = [
                {
                  name = "config";
                  persistentVolumeClaim.claimName = "home-assistant-config";
                }
                {
                  name = "config-yaml";
                  configMap.name = "home-assistant-config";
                }
              ];
            };
          };
        };
      };

      # Service for Home Assistant
      services.home-assistant = {
        metadata = {
          name = "home-assistant";
          namespace = "home-assistant";
          labels = {
            app = "home-assistant";
          };
        };
        spec = {
          type = "ClusterIP";
          selector = {
            app = "home-assistant";
          };
          ports = [
            {
              name = "http";
              port = 8123;
              targetPort = 8123;
              protocol = "TCP";
            }
          ];
        };
      };

      # Ingress for Home Assistant web interface
      ingresses.home-assistant-ingress = {
        metadata = {
          name = "home-assistant-ingress";
          namespace = "home-assistant";
          annotations = {

            # Optional: Enable if you have cert-manager
            # "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
          };
        };
        spec = {
          # Optional: Enable TLS
          # tls = [{
          #   hosts = ["home-assistant.lan"];
          #   secretName = "home-assistant-tls";
          # }];
          rules = [{
            host = "home-assistant.arendse.nom.za";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "home-assistant";
                port.number = 8123;
              };
            }];
          }];
        };
      };
    };
  };
}

