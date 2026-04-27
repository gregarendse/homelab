{ kubenix, ... }:
{
  imports = [ kubenix.modules.k8s ];

  kubernetes = {
    version = "1.28";

    # Traefik ServersTransport CRD for accepting self-signed certs
    objects = [
      {
        apiVersion = "traefik.io/v1alpha1";
        kind = "ServersTransport";
        metadata = {
          name = "unifi";
          namespace = "unifi";
        };
        spec = {
          insecureSkipVerify = true;
        };
      }
    ];

    resources = {
      namespaces.unifi = {};

      persistentVolumeClaims."unifi-controller-data" = {
        metadata = {
          name = "unifi-controller-data";
          namespace = "unifi";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."unifi-controller" = {
        metadata = {
          name = "unifi-controller";
          namespace = "unifi";
          labels = {
            app = "unifi-controller";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels = {
            app = "unifi-controller";
          };
          template = {
            metadata.labels = {
              app = "unifi-controller";
            };
            spec = {
              containers = [
                {
                  name = "unifi-controller";
                  image = "lscr.io/linuxserver/unifi-network-application:latest";
                  imagePullPolicy = "IfNotPresent";
                  env = [
                    { name = "PUID"; value = "1000"; }
                    { name = "PGID"; value = "1000"; }
                    { name = "TZ"; value = "Europe/London"; }
                    { name = "MEM_LIMIT"; value = "1024"; }
                    { name = "MEM_STARTUP"; value = "1024"; }
                    { name = "MONGO_HOST"; value = "mongo.mongo"; }
                    { name = "MONGO_PORT"; value = "27017"; }
                    { name = "MONGO_USER"; valueFrom.secretKeyRef = { name = "unifi-mongo-credentials"; key = "MONGO_USER"; }; }
                    { name = "MONGO_PASS"; valueFrom.secretKeyRef = { name = "unifi-mongo-credentials"; key = "MONGO_PASS"; }; }
                    { name = "MONGO_DBNAME"; valueFrom.secretKeyRef = { name = "unifi-mongo-credentials"; key = "MONGO_DBNAME"; }; }
                    { name = "MONGO_AUTHSOURCE"; valueFrom.secretKeyRef = { name = "unifi-mongo-credentials"; key = "MONGO_AUTHSOURCE"; }; }
                  ];
                  ports = [
                    { name = "https"; containerPort = 8443; protocol = "TCP"; }
                    { name = "stun"; containerPort = 3478; protocol = "UDP"; }
                    { name = "discovery"; containerPort = 10001; protocol = "UDP"; }
                    { name = "portal"; containerPort = 8080; protocol = "TCP"; }
                    { name = "mdns"; containerPort = 1900; protocol = "UDP"; }
                    { name = "https-redirect"; containerPort = 8843; protocol = "TCP"; }
                    { name = "http-redirect"; containerPort = 8880; protocol = "TCP"; }
                    { name = "speedtest"; containerPort = 6789; protocol = "TCP"; }
                    { name = "syslog"; containerPort = 5514; protocol = "UDP"; }
                  ];
                  volumeMounts = [
                    {
                      name = "unifi-controller-data";
                      mountPath = "/config";
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "200m";
                      memory = "1Gi";
                    };
                    limits = {
                      cpu = "1000m";
                      memory = "1Gi";
                    };
                  };
                }
              ];
              volumes = [
                {
                  name = "unifi-controller-data";
                  persistentVolumeClaim.claimName = "unifi-controller-data";
                }
              ];
            };
          };
        };
      };

      services."unifi-controller" = {
        metadata = {
          name = "unifi-controller";
          namespace = "unifi";
          annotations = {
            "traefik.ingress.kubernetes.io/service.serversscheme" = "https"; # Set backend is HTTPS
            "traefik.ingress.kubernetes.io/service.serverstransport" = "unifi-unifi@kubernetescrd"; # The value must be of form namespace-name@kubernetescrd
          };
          labels = {
            app = "unifi-controller";
          };
        };
        spec = {
          type = "ClusterIP";
          selector = {
            app = "unifi-controller";
          };
          ports = [
            # Application GUI/API (on UniFi Console)
            { name = "https"; port = 8443; targetPort = "https"; protocol = "TCP"; }
          ];
        };
      };

      services."unifi" = {
        metadata = {
          name = "unifi";
          namespace = "unifi";
          labels = {
            app = "unifi-controller";
          };
        };
        spec = {
          type = "NodePort";
          selector = {
            app = "unifi-controller";
          };
          ports = [
            # STUN for device adoption and communication (also required for Remote Management)
            { name = "stun"; port = 3478; targetPort = "stun"; protocol = "UDP"; nodePort = 30478;}
            # Device discovery during adoption
            { name = "discovery"; port = 10001; targetPort = "discovery"; protocol = "UDP"; nodePort = 31001;}
            # Device and application communication
            { name = "portal"; port = 8080; targetPort = "portal"; protocol = "TCP"; nodePort = 30808;}
            # L2 discovery (“Make application discoverable on L2 network”)
            { name = "mdns"; port = 1900; targetPort = "mdns"; protocol = "UDP"; nodePort = 31900;}
            # UniFi mobile speed test
            { name = "speedtest"; port = 6789; targetPort = "speedtest"; protocol = "TCP"; nodePort = 30678;}
          ];
      };
      };

      ingresses."unifi-controller" = {
        metadata = {
          name = "unifi-controller";
          namespace = "unifi";
          annotations = {
            "external-dns.alpha.kubernetes.io/cloudflare-proxied" = "true";
            "external-dns.alpha.kubernetes.io/cloudflare-tags"   = "app=unifi,env=prod,owner=homelab";
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
            "traefik.ingress.kubernetes.io/router.tls" = "true";
          };
        };
        spec = {
          tls = [{
            hosts = [ "unifi.arendse.nom.za" ];
            secretName = "unifi-tls";
          }];
          rules = [{
            host = "unifi.arendse.nom.za";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "unifi-controller";
                port.name = "https";
              };
            }];
          }];
        };
      };
    };
  };
}
