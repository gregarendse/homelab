{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    resources = {
      namespaces.mongo = { };

      configMaps."unifi" = {
        metadata = {
          name = "unifi";
          namespace = "mongo";
        };
        data = {
          "init-unifi.sh" = builtins.readFile ./init-unifi.sh;
        };
      };

      statefulSets."mongo" = {
        metadata = {
          name = "mongo";
          namespace = "mongo";
          labels = {
            app = "mongo";
          };
        };
        spec = {
          serviceName = "mongo";
          replicas = 1;
          selector.matchLabels = {
            app = "mongo";
          };
          template = {
            metadata.labels = {
              app = "mongo";
            };
            spec = {
              volumes = [
                {
                  name = "init-script";
                  configMap = {
                    name = "unifi";
                    items = [
                      {
                        key = "init-unifi.sh";
                        path = "init-unifi.sh";
                      }
                    ];
                  };
                }
              ];
              containers = [
                {
                  name = "mongo";
                  image = "mongo:8";
                  ports = [
                    {
                      name = "mongo";
                      containerPort = 27017;
                      protocol = "TCP";
                    }
                  ];
                  env = [
                    {
                      name = "MONGO_INITDB_ROOT_USERNAME";
                      valueFrom.secretKeyRef = {
                        name = "mongo-credentials";
                        key = "MONGO_INITDB_ROOT_USERNAME";
                      };
                    }
                    {
                      name = "MONGO_INITDB_ROOT_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "mongo-credentials";
                        key = "MONGO_INITDB_ROOT_PASSWORD";
                      };
                    }
                    {
                      name = "MONGO_UNIFI_USER";
                      valueFrom.secretKeyRef = {
                        name = "mongo-credentials";
                        key = "MONGO_UNIFI_USER";
                      };
                    }
                    {
                      name = "MONGO_UNIFI_PASS";
                      valueFrom.secretKeyRef = {
                        name = "mongo-credentials";
                        key = "MONGO_UNIFI_PASS";
                      };
                    }
                  ];
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/data/db";
                    }
                    {
                      name = "init-script";
                      mountPath = "/docker-entrypoint-initdb.d/init-unifi.sh";
                      subPath = "init-unifi.sh";
                      readOnly = true;
                    }
                  ];
                }
              ];
            };
          };
          volumeClaimTemplates = [
            {
              metadata = {
                name = "data";
                # Longhorn backup cycle: Tuesday (staggered to spread B2 traffic)
                labels."recurring-job-group.longhorn.io/tuesday-backup" = "enabled";
              };
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources.requests.storage = "10Gi";
              };
            }
          ];
        };
      };

      services."mongo" = {
        metadata = {
          name = "mongo";
          namespace = "mongo";
          labels = {
            app = "mongo";
          };
        };
        spec = {
          selector = {
            app = "mongo";
          };
          type = "ClusterIP";
          ports = [
            {
              name = "mongo";
              port = 27017;
              targetPort = "mongo";
              protocol = "TCP";
            }
          ];
        };
      };
    };
  };
}
