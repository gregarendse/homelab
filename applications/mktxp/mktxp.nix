{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    # ServiceMonitor is a kube-prometheus-stack CRD not modelled by the upstream
    # k8s module, so it is declared as a raw object (same technique unifi uses
    # for the Traefik ServersTransport CRD).
    objects = [
      {
        apiVersion = "monitoring.coreos.com/v1";
        kind = "ServiceMonitor";
        metadata = {
          name = "mktxp";
          namespace = "monitoring";
          labels = {
            app = "mktxp";
            # kube-prometheus-stack's Prometheus only selects ServiceMonitors
            # carrying its Helm release label ("monitoring"). Without this the
            # target is silently ignored.
            release = "monitoring";
          };
        };
        spec = {
          selector.matchLabels = {
            app = "mktxp";
          };
          namespaceSelector.matchNames = [ "monitoring" ];
          endpoints = [
            {
              port = "metrics";
              path = "/metrics";
              interval = "60s";
              scrapeTimeout = "30s";
            }
          ];
        };
      }
    ];

    resources = {
      # Deploy into the monitoring namespace so the kube-prometheus-stack
      # Prometheus (same release) discovers the ServiceMonitor. The namespace is
      # created/owned by the monitoring release; do not redeclare it here.

      # Non-sensitive mktxp configuration. _mktxp.conf is provided explicitly so
      # mktxp never needs to write to its read-only config mount.
      configMaps.mktxp-config = {
        metadata = {
          name = "mktxp-config";
          namespace = "monitoring";
        };
        data = {
          "mktxp.conf" = builtins.readFile ./mktxp.conf;
          "_mktxp.conf" = builtins.readFile ./_mktxp.conf;
        };
      };

      deployments.mktxp = {
        metadata = {
          name = "mktxp";
          namespace = "monitoring";
          labels = {
            app = "mktxp";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels = {
            app = "mktxp";
          };
          template = {
            metadata.labels = {
              app = "mktxp";
            };
            spec = {
              securityContext = {
                runAsUser = 1000;
                runAsGroup = 1000;
                fsGroup = 1000;
              };
              containers = [
                {
                  name = "mktxp";
                  image = "ghcr.io/akpw/mktxp:latest";
                  imagePullPolicy = "Always";
                  # The image has no ENTRYPOINT (only CMD), so `command` must be
                  # set explicitly — otherwise args[0] ("--cfg-dir") is execed as
                  # the binary and the container fails with StartError.
                  command = [ "mktxp" ];
                  args = [
                    "--cfg-dir"
                    "/etc/mktxp"
                    "export"
                  ];
                  ports = [
                    {
                      name = "metrics";
                      containerPort = 49090;
                      protocol = "TCP";
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "config";
                      mountPath = "/etc/mktxp";
                      readOnly = true;
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "50m";
                      memory = "64Mi";
                    };
                    limits = {
                      cpu = "250m";
                      memory = "256Mi";
                    };
                  };
                }
              ];
              volumes = [
                {
                  # Merge the ConfigMap-provided .conf files and the manually
                  # created credentials Secret into one /etc/mktxp directory.
                  name = "config";
                  projected.sources = [
                    {
                      configMap = {
                        name = "mktxp-config";
                        items = [
                          {
                            key = "mktxp.conf";
                            path = "mktxp.conf";
                          }
                          {
                            key = "_mktxp.conf";
                            path = "_mktxp.conf";
                          }
                        ];
                      };
                    }
                    {
                      secret = {
                        name = "mktxp-credentials";
                        items = [
                          {
                            key = "credentials.yaml";
                            path = "credentials.yaml";
                          }
                        ];
                      };
                    }
                  ];
                }
              ];
            };
          };
        };
      };

      services.mktxp = {
        metadata = {
          name = "mktxp";
          namespace = "monitoring";
          labels = {
            app = "mktxp";
          };
        };
        spec = {
          type = "ClusterIP";
          selector = {
            app = "mktxp";
          };
          ports = [
            {
              name = "metrics";
              port = 49090;
              targetPort = "metrics";
              protocol = "TCP";
            }
          ];
        };
      };
    };
  };
}
