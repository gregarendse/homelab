{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {
      namespaces."open-webui" = {};

      persistentVolumeClaims."open-webui-data" = {
        metadata = {
          name = "open-webui-data";
          namespace = "open-webui";
          labels.app = "open-webui";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "10Gi";
          storageClassName = "longhorn";
        };
      };

      deployments."open-webui" = {
        metadata = {
          name = "open-webui";
          namespace = "open-webui";
          labels.app = "open-webui";
        };
        spec = {
          replicas = 1;
          strategy.type = "Recreate";
          selector.matchLabels.app = "open-webui";
          template = {
            metadata.labels.app = "open-webui";
            spec = {
              automountServiceAccountToken = false;

              securityContext = {
                fsGroup = 1000;
                seccompProfile.type = "RuntimeDefault";
              };

              containers = [
                {
                  name = "open-webui";
                  image = "ghcr.io/open-webui/open-webui:main";
                  imagePullPolicy = "IfNotPresent";

                  ports = [
                    {
                      name = "http";
                      containerPort = 8080;
                      protocol = "TCP";
                    }
                  ];

                  env = [
                    {
                      name = "OLLAMA_BASE_URL";
                      value = "http://ollama.ollama.svc.cluster.local:11434";
                    }
                    {
                      name = "WEBUI_SECRET_KEY";
                      valueFrom.secretKeyRef = {
                        name = "open-webui-secrets";
                        key = "WEBUI_SECRET_KEY";
                      };
                    }
                    {
                      name = "WEBUI_AUTH";
                      value = "True";
                    }
                    {
                      # Disable open registration once an admin user has been created.
                      name = "ENABLE_SIGNUP";
                      value = "True";
                    }
                  ];

                  startupProbe = {
                    tcpSocket.port = "http";
                    periodSeconds = 5;
                    timeoutSeconds = 2;
                    failureThreshold = 60;
                  };
                  readinessProbe = {
                    tcpSocket.port = "http";
                    periodSeconds = 10;
                    timeoutSeconds = 2;
                    failureThreshold = 6;
                  };
                  livenessProbe = {
                    tcpSocket.port = "http";
                    periodSeconds = 20;
                    timeoutSeconds = 2;
                    failureThreshold = 6;
                  };

                  resources = {
                    requests = {
                      cpu = "200m";
                      memory = "512Mi";
                    };
                    limits = {
                      cpu = "1";
                      memory = "2Gi";
                    };
                  };

                  volumeMounts = [
                    {
                      name = "open-webui-data";
                      mountPath = "/app/backend/data";
                    }
                    {
                      name = "tmp-volume";
                      mountPath = "/tmp";
                    }
                  ];

                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = 1000;
                    runAsGroup = 1000;
                    allowPrivilegeEscalation = false;
                    capabilities.drop = [ "ALL" ];
                  };
                }
              ];

              volumes = [
                {
                  name = "open-webui-data";
                  persistentVolumeClaim.claimName = "open-webui-data";
                }
                {
                  name = "tmp-volume";
                  emptyDir = {};
                }
              ];
            };
          };
        };
      };

      services."open-webui" = {
        metadata = {
          name = "open-webui";
          namespace = "open-webui";
          labels.app = "open-webui";
        };
        spec = {
          type = "ClusterIP";
          selector.app = "open-webui";
          ports = [
            {
              name = "http";
              port = 80;
              targetPort = "http";
              protocol = "TCP";
            }
          ];
        };
      };

      ingresses."open-webui-ingress" = {
        metadata = {
          name = "open-webui-ingress";
          namespace = "open-webui";
          annotations = {
            "external-dns.alpha.kubernetes.io/cloudflare-proxied" = "true";
            "external-dns.alpha.kubernetes.io/cloudflare-tags" = "app=open-webui,env=prod,owner=homelab";
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
            "traefik.ingress.kubernetes.io/router.tls" = "true";
          };
        };
        spec = {
          ingressClassName = "traefik";
          tls = [
            {
              hosts = [ "openwebui.arendse.nom.za" ];
              secretName = "open-webui-tls";
            }
          ];
          rules = [
            {
              host = "openwebui.arendse.nom.za";
              http.paths = [
                {
                  path = "/";
                  pathType = "Prefix";
                  backend.service = {
                    name = "open-webui";
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

