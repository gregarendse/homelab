{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {
      namespaces.ollama = {};

      persistentVolumeClaims.ollama-models = {
        metadata = {
          name = "ollama-models";
          namespace = "ollama";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "20Gi";
          storageClassName = "longhorn";
        };
      };

      deployments.ollama = {
        metadata = {
          name = "ollama";
          namespace = "ollama";
          labels = {
            app = "ollama";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels = {
            app = "ollama";
          };
          template = {
            metadata.labels = {
              app = "ollama";
            };
            spec = {
              containers = [
                {
                  name = "ollama";
                  image = "ollama/ollama:latest";
                  imagePullPolicy = "IfNotPresent";
                  env = [
                    {
                      name = "OLLAMA_HOST";
                      value = "0.0.0.0";
                    }
                    {
                      name = "OLLAMA_KEEP_ALIVE";
                      value = "24h";
                    }
                    {
                        name = "OLLAMA_MAX_LOADED_MODELS";
                        value = "1";
                    }
                  ];
                  ports = [
                    {
                      name = "http";
                      containerPort = 11434;
                      protocol = "TCP";
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "models";
                      mountPath = "/root/.ollama";
                    }
                  ];
                  readinessProbe = {
                    tcpSocket.port = "http";
                    initialDelaySeconds = 5;
                    periodSeconds = 10;
                    timeoutSeconds = 2;
                    failureThreshold = 6;
                  };
                  livenessProbe = {
                    tcpSocket.port = "http";
                    initialDelaySeconds = 30;
                    periodSeconds = 20;
                    timeoutSeconds = 2;
                    failureThreshold = 3;
                  };
                  resources = {
                    requests = {
                      cpu = "1000m";
                      memory = "3Gi";
                    };
                    limits = {
                      cpu = "1800m";  # nodes have 2 cores each; leave headroom for system/other pods
                      memory = "5Gi";
                    };
                  };
                }
                {
                  name = "pull-model";
                  image = "ollama/ollama:latest";
                  imagePullPolicy = "IfNotPresent";
                  command = [
                    "/bin/sh"
                    "-c"
                    ''
                      # Wait for main ollama container to be ready
                      for i in $(seq 1 120); do
                        if nc -z localhost 11434 2>/dev/null; then
                          break
                        fi
                        sleep 5
                      done
                      # Pull the model
                      OLLAMA_HOST=http://localhost:11434 ollama pull llama3.2:3b
                      # Keep the sidecar alive
                      sleep infinity
                    ''
                  ];
                  volumeMounts = [
                    {
                      name = "models";
                      mountPath = "/root/.ollama";
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "10m";
                      memory = "128Mi";
                    };
                    limits = {
                      cpu = "10m";
                      memory = "128Mi";
                    };
                  };
                }
              ];
              volumes = [
                {
                  name = "models";
                  persistentVolumeClaim.claimName = "ollama-models";
                }
              ];
            };
          };
        };
      };

      services.ollama = {
        metadata = {
          name = "ollama";
          namespace = "ollama";
          labels = {
            app = "ollama";
          };
        };
        spec = {
          type = "ClusterIP";
          selector = {
            app = "ollama";
          };
          ports = [
            {
              name = "http";
              port = 11434;
              targetPort = "http";
              protocol = "TCP";
            }
          ];
        };
      };


    };
  };
}
